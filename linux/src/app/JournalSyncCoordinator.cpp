#include "JournalSyncCoordinator.h"

#include "AppSettings.h"
#include "DropboxAuthSession.h"
#include "DropboxSyncBackend.h"
#include "FakeSyncBackend.h"
#include "JournalLibrary.h"
#include "JournalPaths.h"

#include <QCoreApplication>
#include <QDeadlineTimer>
#include <QDebug>
#include <QSettings>
#include <QUrl>

#include <cstdlib>

JournalSyncCoordinator::JournalSyncCoordinator(JournalLibrary *library,
                                               AppSettings *settings,
                                               QObject *parent)
    : QObject(parent)
    , m_library(library)
    , m_settings(settings)
{
    const char *env = std::getenv("WICK_FAKE_SYNC");
    m_fakeAvailable = env && env[0] == '1';

    m_debounce.setSingleShot(true);
    m_debounce.setInterval(15000);
    connect(&m_debounce, &QTimer::timeout, this, &JournalSyncCoordinator::syncNow);

    m_periodic.setInterval(60000);
    connect(&m_periodic, &QTimer::timeout, this, &JournalSyncCoordinator::syncNow);

    if (m_library) {
        connect(m_library, &JournalLibrary::journalContentChanged, this, [this]() {
            if (connected())
                m_debounce.start();
        });
    }
    if (m_settings) {
        connect(m_settings, &AppSettings::syncChanged, this, [this]() {
            if (m_settings->syncEnabled() && connected()) {
                m_periodic.start();
                syncNow();
            } else {
                m_periodic.stop();
            }
        });
    }

    ensureEngine();
    if (m_fakeAvailable && m_settings && m_settings->syncEnabled()) {
        if (auto *fake = dynamic_cast<wick::FakeSyncBackend *>(m_backend.get()))
            fake->authorized = true;
        startPeriodicIfEnabled();
        refreshStatus();
        QTimer::singleShot(0, this, &JournalSyncCoordinator::syncNow);
    } else if (!m_fakeAvailable && connected()) {
        startPeriodicIfEnabled();
        refreshStatus();
        if (m_settings && m_settings->syncEnabled())
            QTimer::singleShot(0, this, &JournalSyncCoordinator::syncNow);
    } else {
        refreshStatus();
    }
}

void JournalSyncCoordinator::startPeriodicIfEnabled()
{
    if (m_settings && m_settings->syncEnabled() && connected())
        m_periodic.start();
}

bool JournalSyncCoordinator::connected() const
{
    return m_backend && m_backend->isAuthorized();
}

QString JournalSyncCoordinator::accountEmail() const
{
    if (!m_backend)
        return {};
    auto email = m_backend->accountEmail();
    return email ? QString::fromStdString(*email) : QString();
}

void JournalSyncCoordinator::ensureEngine()
{
    if (m_engine)
        return;
    if (!m_library)
        return;

    if (m_fakeAvailable) {
        m_backend = std::make_unique<wick::FakeSyncBackend>();
    } else {
        auto dropbox = std::make_unique<wick::DropboxSyncBackend>();
        dropbox->setAuthSession([](const QUrl &url, const QString &scheme) {
            return DropboxAuthSession::run(url, scheme);
        });
        m_backend = std::move(dropbox);
    }
    wick::JournalSyncStateStore store(stateDirectory());
    m_engine = std::make_unique<wick::JournalSyncEngine>(*m_backend, *m_library, deviceID(), store);
}

std::string JournalSyncCoordinator::deviceID() const
{
    QSettings s(QStringLiteral("wick"), QStringLiteral("秉烛"));
    QString id = s.value(QStringLiteral("sync.deviceID")).toString();
    if (id.isEmpty()) {
        id = QString::fromStdString(wick::Uuid::generate().toString());
        s.setValue(QStringLiteral("sync.deviceID"), id);
    }
    return id.toStdString();
}

std::filesystem::path JournalSyncCoordinator::stateDirectory() const
{
    auto root = wick::JournalPaths::defaultPaths().librariesRoot;
    return root.parent_path() / "sync";
}

void JournalSyncCoordinator::connectDropbox()
{
    if (m_authorizing)
        return;
    ensureEngine();
    if (!m_backend || !m_engine)
        return;
    m_authorizing = true;
    m_statusText = m_settings && m_settings->isChinese()
        ? QStringLiteral("正在登录…")
        : QStringLiteral("Signing in…");
    emit statusChanged();
    try {
        m_backend->authorize();
        if (m_settings)
            m_settings->setSyncEnabled(true);
        m_periodic.start();
        emit connectedChanged();
        m_engine->syncOnce();
        refreshStatus();
    } catch (const wick::SyncBackendError &e) {
        if (e.kind == wick::SyncBackendError::Kind::authorizationCancelled) {
            m_statusText = m_settings && m_settings->isChinese()
                ? QStringLiteral("已取消登录")
                : QStringLiteral("Sign-in cancelled");
        } else {
            m_statusText = QString::fromStdString(e.what());
        }
        emit statusChanged();
        qWarning("秉烛: Dropbox connect failed: %s", e.what());
    } catch (const std::exception &e) {
        m_statusText = QString::fromStdString(e.what());
        emit statusChanged();
        qWarning("秉烛: Dropbox connect failed: %s", e.what());
    }
    m_authorizing = false;
}

void JournalSyncCoordinator::signOut()
{
    if (m_backend)
        m_backend->signOut();
    if (m_settings)
        m_settings->setSyncEnabled(false);
    m_periodic.stop();
    emit connectedChanged();
    refreshStatus();
}

void JournalSyncCoordinator::syncNow()
{
    if (!m_engine || !connected())
        return;
    try {
        m_engine->syncOnce();
        refreshStatus();
    } catch (const std::exception &e) {
        qWarning("秉烛: sync failed: %s", e.what());
        refreshStatus();
    }
}

void JournalSyncCoordinator::syncOnceBeforeQuit(std::chrono::milliseconds timeout)
{
    if (!m_engine || !connected())
        return;
    QDeadlineTimer deadline(timeout);
    try {
        m_engine->syncOnce();
        refreshStatus();
    } catch (const std::exception &e) {
        qWarning("秉烛: quit-time sync failed: %s", e.what());
    }
    if (deadline.hasExpired())
        qWarning("秉烛: quit-time sync hit timeout, continuing quit");
}

void JournalSyncCoordinator::refreshStatus()
{
    if (!m_engine || !connected()) {
        if (!m_authorizing)
            m_statusText.clear();
        emit statusChanged();
        return;
    }
    using S = wick::JournalSyncEngine::Status;
    switch (m_engine->status()) {
    case S::idle:
        m_statusText = m_settings && m_settings->isChinese()
            ? QStringLiteral("已同步")
            : QStringLiteral("Synced");
        break;
    case S::syncing:
        m_statusText = m_settings && m_settings->isChinese()
            ? QStringLiteral("同步中…")
            : QStringLiteral("Syncing…");
        break;
    case S::needsAuth:
        m_statusText = m_settings && m_settings->isChinese()
            ? QStringLiteral("需要登录")
            : QStringLiteral("Needs sign-in");
        break;
    case S::offline:
        m_statusText = m_settings && m_settings->isChinese()
            ? QStringLiteral("离线")
            : QStringLiteral("Offline");
        break;
    case S::error:
        m_statusText = QString::fromStdString(m_engine->errorDetail());
        break;
    }
    emit statusChanged();
}
