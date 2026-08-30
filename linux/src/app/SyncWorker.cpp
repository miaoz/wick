#include "SyncWorker.h"
#include "AppSettings.h"

#include "DropboxSyncBackend.h"
#include "FakeSyncBackend.h"
#include "JournalLibrary.h"
#include "JournalLocalSource.h"
#include "JournalSyncEngine.h"

#include <QDebug>
#include <QMetaObject>
#include <QThread>
#include <QUrl>

#include <optional>
#include <utility>

class LocalSourceProxy final : public wick::JournalLocalSource
{
public:
    explicit LocalSourceProxy(JournalLibrary *library)
        : m_library(library)
    {
    }

    void setForcedJournal(std::optional<wick::Uuid> id) { m_forced = std::move(id); }

    std::optional<wick::Uuid> syncJournalID() const override
    {
        if (m_forced)
            return m_forced;
        return blocking([this] { return m_library->syncJournalID(); });
    }

    std::string syncJournalName() const override
    {
        const auto id = syncJournalID();
        if (!id)
            return {};
        return blocking([this, id] { return m_library->journalNameFor(*id); });
    }

    bool syncIsWritable() const override
    {
        const auto id = syncJournalID();
        if (!id)
            return false;
        return blocking([this, id] { return m_library->journalWritable(*id); });
    }

    std::map<wick::Uuid, wick::JournalEntry> syncEntrySnapshots() override
    {
        const auto id = syncJournalID();
        if (!id)
            return {};
        return blocking([this, id] { return m_library->entrySnapshotsFor(*id); });
    }

    std::optional<wick::JournalEntry> syncEntrySnapshot(const wick::Uuid &entryID) override
    {
        const auto id = syncJournalID();
        if (!id)
            return std::nullopt;
        return blocking([this, id, entryID] { return m_library->entrySnapshotFor(*id, entryID); });
    }

    void prepareForRemoteApply(const wick::Uuid &entryID) override
    {
        const auto forced = m_forced;
        blocking([this, entryID, forced] {
            const auto live = m_library->syncJournalID();
            if (!forced || (live && *live == *forced))
                m_library->prepareForRemoteApply(entryID);
        });
    }

    std::set<wick::Uuid> applySyncedChanges(const std::vector<wick::JournalSyncMutation> &changes,
                                            const wick::Uuid &journalID) override
    {
        return blocking([this, changes, journalID] {
            return m_library->applySyncedChanges(changes, journalID);
        });
    }

    void applySyncedEntry(const wick::JournalEntry &entry, const wick::Uuid &journalID) override
    {
        blocking([this, entry, journalID] { m_library->applySyncedEntry(entry, journalID); });
    }

    void removeSyncedEntry(const wick::Uuid &entryID, const wick::Uuid &journalID) override
    {
        blocking([this, entryID, journalID] { m_library->removeSyncedEntry(entryID, journalID); });
    }

    std::string applySyncedJournalName(const std::string &name, const wick::Uuid &journalID) override
    {
        return blocking([this, name, journalID] {
            return m_library->applySyncedJournalName(name, journalID);
        });
    }

    std::set<std::string> syncedImageFilenames() override
    {
        const auto id = syncJournalID();
        if (!id)
            return {};
        return blocking([this, id] { return m_library->imageFilenamesFor(*id); });
    }

    std::optional<std::string> syncedImageData(const std::string &filename) override
    {
        const auto id = syncJournalID();
        if (!id)
            return std::nullopt;
        return blocking([this, id, filename] { return m_library->imageDataFor(*id, filename); });
    }

    bool hasSyncedImage(const std::string &filename) override
    {
        const auto id = syncJournalID();
        if (!id)
            return false;
        return blocking([this, id, filename] { return m_library->hasImageFor(*id, filename); });
    }

    void storeSyncedImage(const std::string &filename, std::string_view data,
                          const wick::Uuid &journalID) override
    {
        const std::string copy(data);
        blocking([this, filename, copy, journalID] {
            m_library->storeSyncedImage(filename, copy, journalID);
        });
    }

    bool syncTradingSnapshotEnabled() const override
    {
        return blocking([this] { return m_library->syncTradingSnapshotEnabled(); });
    }

    std::optional<wick::JournalTradingSnapshotDocument> syncedTradingSnapshot(const wick::Uuid &journalID) override
    {
        return blocking([this, journalID] { return m_library->syncedTradingSnapshot(journalID); });
    }

    void applySyncedTradingSnapshot(const wick::JournalTradingSnapshotDocument &document,
                                    const wick::Uuid &journalID) override
    {
        blocking([this, document, journalID] {
            m_library->applySyncedTradingSnapshot(document, journalID);
        });
    }

    void removeSyncedTradingSnapshot(const wick::Uuid &journalID) override
    {
        blocking([this, journalID] {
            m_library->removeSyncedTradingSnapshot(journalID);
        });
    }

private:
    template <typename Fn>
    auto blocking(Fn &&fn) const -> decltype(fn())
    {
        using R = decltype(fn());
        if (QThread::currentThread() == m_library->thread())
            return fn();
        if constexpr (std::is_void_v<R>) {
            QMetaObject::invokeMethod(m_library, std::forward<Fn>(fn), Qt::BlockingQueuedConnection);
        } else {
            std::optional<R> result;
            QMetaObject::invokeMethod(
                m_library, [&]() { result = fn(); }, Qt::BlockingQueuedConnection);
            return std::move(*result);
        }
    }

    JournalLibrary *m_library = nullptr;
    std::optional<wick::Uuid> m_forced;
};

SyncWorker::SyncWorker(JournalLibrary *library,
                       bool fake,
                       std::string deviceId,
                       std::filesystem::path stateDir,
                       QObject *parent)
    : QObject(parent)
    , m_library(library)
    , m_fake(fake)
    , m_deviceId(std::move(deviceId))
    , m_stateDir(std::move(stateDir))
{
}

SyncWorker::~SyncWorker() = default;

void SyncWorker::startEngine()
{
    if (m_engine)
        return;
    m_proxy = std::make_unique<LocalSourceProxy>(m_library);
    if (m_fake)
        m_backend = std::make_unique<wick::FakeSyncBackend>();
    else
        m_backend = std::make_unique<wick::DropboxSyncBackend>();
    wick::JournalSyncStateStore store(m_stateDir);
    m_engine = std::make_unique<wick::JournalSyncEngine>(*m_backend, *m_proxy, m_deviceId, store);
    emit authorizedChanged(m_backend->isAuthorized(),
                           m_backend->accountEmail() ? QString::fromStdString(*m_backend->accountEmail())
                                                     : QString());
}

void SyncWorker::syncActive()
{
    if (!m_engine || !m_backend)
        return;
    if (auto *dropbox = dynamic_cast<wick::DropboxSyncBackend *>(m_backend.get()))
        dropbox->reloadFromStore();
    if (!m_backend->isAuthorized())
        return;
    m_proxy->setForcedJournal(std::nullopt);
    try {
        m_engine->syncOnce();
        if (autoImport() > 0)
            pullAll();
        else
            emitStatus();
    } catch (const std::exception &e) {
        qWarning("秉烛: sync failed: %s", e.what());
        emitStatus();
    }
}

void SyncWorker::pullAll()
{
    if (!m_engine || !m_backend || !m_backend->isAuthorized() || !m_library)
        return;
    const bool zh = AppSettings::instance() ? AppSettings::instance()->isChinese() : true;
    emit statusTextChanged(zh ? QStringLiteral("正在拉取日记…") : QStringLiteral("Pulling journals…"));
    std::vector<wick::Uuid> ids;
    QMetaObject::invokeMethod(
        m_library, [this, &ids]() { ids = m_library->journalIds(); }, Qt::BlockingQueuedConnection);
    for (const auto &id : ids) {
        if (m_engine->isJournalTombstoned(id))
            continue;
        m_proxy->setForcedJournal(id);
        try {
            m_engine->syncOnce();
        } catch (const std::exception &e) {
            qWarning("秉烛: pull %s failed: %s", id.toString().c_str(), e.what());
        }
    }
    m_proxy->setForcedJournal(std::nullopt);
    emitStatus();
}

void SyncWorker::signOut()
{
    if (m_backend)
        m_backend->signOut();
    emit authorizedChanged(false, {});
    emit statusTextChanged({});
}

void SyncWorker::emitStatus()
{
    if (!m_engine || !m_backend || !m_backend->isAuthorized()) {
        emit statusTextChanged({});
        return;
    }
    using S = wick::JournalSyncEngine::Status;
    const bool zh = AppSettings::instance() ? AppSettings::instance()->isChinese() : true;
    QString text;
    switch (m_engine->status()) {
    case S::idle:
        text = zh ? QStringLiteral("已同步") : QStringLiteral("Synced");
        break;
    case S::syncing:
        text = zh ? QStringLiteral("同步中…") : QStringLiteral("Syncing…");
        break;
    case S::needsAuth:
        text = zh ? QStringLiteral("需要登录") : QStringLiteral("Login Required");
        break;
    case S::offline:
        text = zh ? QStringLiteral("离线") : QStringLiteral("Offline");
        break;
    case S::error:
        text = QString::fromStdString(m_engine->errorDetail());
        break;
    }
    emit statusTextChanged(text);
    emit authorizedChanged(true,
                           m_backend->accountEmail() ? QString::fromStdString(*m_backend->accountEmail())
                                                     : QString());
}

int SyncWorker::autoImport()
{
    if (!m_engine || !m_library)
        return 0;
    int imported = 0;
    const auto manifests = m_engine->discoveredJournals();
    for (const auto &manifest : manifests) {
        if (m_engine->isJournalTombstoned(manifest.journalID))
            continue;
        bool exists = false;
        QMetaObject::invokeMethod(
            m_library,
            [this, &exists, id = manifest.journalID]() { exists = m_library->hasJournal(id); },
            Qt::BlockingQueuedConnection);
        if (exists)
            continue;
        m_engine->resetSyncState(manifest.journalID);
        QMetaObject::invokeMethod(
            m_library,
            [this, manifest]() {
                m_library->registerRemoteJournal(manifest.journalID,
                                                 QString::fromStdString(manifest.journalName));
            },
            Qt::BlockingQueuedConnection);
        ++imported;
        qInfo("秉烛: auto-imported remote journal \"%s\"", manifest.journalName.c_str());
    }
    return imported;
}
