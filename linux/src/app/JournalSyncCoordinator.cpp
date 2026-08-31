#include "JournalSyncCoordinator.h"

#include "AppSettings.h"
#include "DropboxAuthSession.h"
#include "DropboxSyncBackend.h"
#include "JournalLibrary.h"
#include "JournalModels.h"
#include "JournalPaths.h"
#include "SyncWorker.h"

#include <QCoreApplication>
#include <QDebug>
#include <QEventLoop>
#include <QMetaObject>
#include <QSettings>
#include <QThread>
#include <QTimer>
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
    connect(&m_debounce, &QTimer::timeout, this, &JournalSyncCoordinator::requestSync);

    m_periodic.setInterval(60000);
    connect(&m_periodic, &QTimer::timeout, this, &JournalSyncCoordinator::requestSync);

    if (m_library) {
        connect(m_library, &JournalLibrary::journalContentChanged, this, [this]() {
            if (connected())
                m_debounce.start();
        });
        connect(m_library, &JournalLibrary::activeJournalChanged, this, [this]() {
            if (connected())
                requestSync();
        });
        connect(m_library, &JournalLibrary::journalDeletedLocally, this, [this](const wick::Uuid &id) {
            if (m_worker && connected()) {
                const QString str = QString::fromStdString(id.toString());
                QMetaObject::invokeMethod(m_worker, "queueJournalDeletion", Qt::QueuedConnection,
                                          Q_ARG(QString, str));
            }
        });
    }
    if (m_settings) {
        connect(m_settings, &AppSettings::syncChanged, this, [this]() {
            if (m_settings->syncEnabled() && connected()) {
                m_periodic.start();
                requestSync();
            } else {
                m_periodic.stop();
            }
        });
    }

    m_thread = new QThread(this);
    m_worker = new SyncWorker(m_library, m_fakeAvailable, deviceID(), stateDirectory());
    m_worker->moveToThread(m_thread);
    connect(m_thread, &QThread::finished, m_worker, &QObject::deleteLater);
    connect(m_thread, &QThread::started, m_worker, &SyncWorker::startEngine);
    connect(m_worker, &SyncWorker::statusTextChanged, this, [this](const QString &text) {
        m_statusText = text;
        emit statusChanged();
    });
    connect(m_worker, &SyncWorker::syncingChanged, this, [this](bool s) {
        if (m_syncing != s) {
            m_syncing = s;
            emit syncingChanged();
        }
    });
    connect(m_worker, &SyncWorker::authorizedChanged, this, [this](bool ok, const QString &email) {
        m_connected = ok;
        if (!email.isEmpty())
            m_accountEmail = email;
        if (!ok)
            m_accountEmail.clear();
        emit connectedChanged();
        if (ok) {
            startPeriodicIfEnabled();
            requestSync();
        }
    });
    m_thread->start();
}

JournalSyncCoordinator::~JournalSyncCoordinator()
{
    m_periodic.stop();
    if (m_thread) {
        m_thread->quit();
        if (!m_thread->wait(1500)) {
            m_thread->terminate();
            m_thread->wait(1000);
        }
    }
}

void JournalSyncCoordinator::startPeriodicIfEnabled()
{
    if (m_settings && m_settings->syncEnabled() && connected())
        m_periodic.start();
}

void JournalSyncCoordinator::requestSync()
{
    if (!m_worker || !connected())
        return;
    QMetaObject::invokeMethod(m_worker, "syncActive", Qt::QueuedConnection);
}

std::string JournalSyncCoordinator::deviceID() const
{
    AppSettings::migrateLegacySettings();
    QSettings s(QStringLiteral("wick"), QStringLiteral("wick"));
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
    m_authorizing = true;
    emit syncingChanged();
    m_statusText = m_settings && m_settings->isChinese()
        ? QStringLiteral("正在登录…")
        : QStringLiteral("Signing in…");
    emit statusChanged();
    try {
        wick::DropboxSyncBackend oauth;
        oauth.setAuthSession([](const QUrl &url, const QString &scheme) {
            return DropboxAuthSession::run(url, scheme);
        });
        const std::string email = oauth.authorize();
        m_accountEmail = QString::fromStdString(email);
        m_connected = true;
        if (m_settings)
            m_settings->setSyncEnabled(true);
        m_periodic.start();
        emit connectedChanged();
        m_authorizing = false;
        emit syncingChanged();
        if (m_worker)
            QMetaObject::invokeMethod(m_worker, "syncActive", Qt::QueuedConnection);
    } catch (const wick::SyncBackendError &e) {
        m_authorizing = false;
        emit syncingChanged();
        if (e.kind == wick::SyncBackendError::Kind::authorizationCancelled) {
            m_statusText = m_settings && m_settings->isChinese()
                ? QStringLiteral("已取消登录")
                : QStringLiteral("Sign-in cancelled");
        } else {
            m_statusText = QString::fromStdString(e.what());
        }
        emit statusChanged();
        qWarning("wick: Dropbox connect failed: %s", e.what());
    } catch (const std::exception &e) {
        m_authorizing = false;
        emit syncingChanged();
        m_statusText = QString::fromStdString(e.what());
        emit statusChanged();
        qWarning("wick: Dropbox connect failed: %s", e.what());
    }
}

void JournalSyncCoordinator::signOut()
{
    if (m_settings)
        m_settings->setSyncEnabled(false);
    m_periodic.stop();
    m_connected = false;
    m_accountEmail.clear();
    m_statusText.clear();
    emit connectedChanged();
    emit statusChanged();
    if (m_worker)
        QMetaObject::invokeMethod(m_worker, "signOut", Qt::QueuedConnection);
}

void JournalSyncCoordinator::syncNow()
{
    requestSync();
}

void JournalSyncCoordinator::syncOnceBeforeQuit(std::chrono::milliseconds timeout)
{
    if (!m_worker || !connected())
        return;
    QEventLoop loop;
    QTimer limiter;
    limiter.setSingleShot(true);
    QObject::connect(&limiter, &QTimer::timeout, &loop, &QEventLoop::quit);
    QObject::connect(m_worker, &SyncWorker::statusTextChanged, &loop, &QEventLoop::quit);
    limiter.start(static_cast<int>(timeout.count()));
    QMetaObject::invokeMethod(m_worker, "syncActive", Qt::QueuedConnection);
    loop.exec();
}
