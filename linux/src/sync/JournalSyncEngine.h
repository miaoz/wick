#pragma once

#include "JournalDayMerge.h"
#include "JournalLocalSource.h"
#include "JournalSyncBackend.h"
#include "JournalSyncState.h"

#include <map>
#include <optional>
#include <set>
#include <string>
#include <utility>
#include <vector>

namespace wick {

class JournalSyncError : public std::runtime_error {
public:
    enum class Kind {
        unsupportedRemoteFormat,
        journalSwitched,
        unsupportedTradingSnapshotFormat,
        invalidRemoteEntryIdentity
    };
    Kind kind;
    int formatVersion = 0;
    std::string path;

    explicit JournalSyncError(Kind k, std::string message, int version = 0, std::string p = {})
        : std::runtime_error(std::move(message))
        , kind(k)
        , formatVersion(version)
        , path(std::move(p)) {}

    static JournalSyncError unsupportedRemoteFormat(int v) {
        return JournalSyncError(Kind::unsupportedRemoteFormat,
                                "remote format v" + std::to_string(v) + " is newer than this app supports",
                                v);
    }
    static JournalSyncError journalSwitched() {
        return JournalSyncError(Kind::journalSwitched, "journal switched");
    }
    static JournalSyncError invalidRemoteEntryIdentity(std::string p) {
        return JournalSyncError(Kind::invalidRemoteEntryIdentity,
                                "remote entry identity does not match its path: " + p, 0, std::move(p));
    }
};

class JournalSyncEngine {
public:
    enum class Status { idle, syncing, needsAuth, offline, error };
    enum class SyncErrorKind { remoteFormatTooNew, server, other };
    enum class SyncConflictResolution { local, remote, merged };

    static constexpr int pushedHashHistoryLimit = 5;

    JournalSyncEngine(JournalSyncBackend& backend,
                      JournalLocalSource& localSource,
                      std::string deviceID,
                      JournalSyncStateStore stateStore);

    void syncOnce();
    void performSyncCycle();

    Status status() const { return status_; }
    SyncErrorKind errorKind() const { return errorKind_; }
    const std::string& errorDetail() const { return errorDetail_; }
    std::optional<TimePoint> lastSyncAt() const { return lastSyncAt_; }
    const std::vector<SyncConflictRecord>& pendingConflicts() const { return pendingConflicts_; }
    const std::vector<JournalSyncManifest>& discoveredJournals() const { return discoveredJournals_; }
    const std::vector<Uuid>& remoteJournalDeletions() const { return remoteJournalDeletions_; }

    void queueJournalDeletion(const Uuid& journalID);
    void acknowledgeRemoteJournalDeletion(const Uuid& journalID);
    bool isJournalTombstoned(const Uuid& journalID) const;
    void resetSyncState(const Uuid& journalID);
    void dismissConflict(const Uuid& id);
    void resolveConflict(const Uuid& id, SyncConflictResolution resolution);

    JournalSyncState& debugState() { return state_; }
    const JournalSyncState& debugState() const { return state_; }

private:
    struct PendingEntryMutation {
        JournalSyncMutation mutation;
        std::optional<EntrySyncState> baseline;
    };
    struct LocalSnap {
        JournalEntry entry;
        std::string hash;
    };
    enum class SettlementOutcome { executed, continueMatrix, superseded };

    void syncCycleBody(const Uuid& journalID);
    void reconcileEntry(const Uuid& entryID,
                        const Uuid& journalID,
                        const std::map<Uuid, LocalSnap>& localEntries,
                        std::vector<PendingEntryMutation>& mutations,
                        std::set<Uuid>& supersededEntries);
    SettlementOutcome executeSettlement(const EntrySettlement& settlement,
                                        const Uuid& entryID,
                                        const Uuid& journalID,
                                        const std::map<Uuid, LocalSnap>& localEntries,
                                        const std::optional<RemoteFileRecord>& remoteFile,
                                        std::vector<PendingEntryMutation>& mutations);
    void authoritativePush(const LocalSnap& local,
                           const Uuid& entryID,
                           const Uuid& journalID,
                           const std::optional<RemoteFileRecord>& remoteFile);
    void recordPushedEntry(const LocalSnap& local,
                           const Uuid& entryID,
                           const std::string& entryPath,
                           const std::string& rev);
    void pushEntry(const LocalSnap& local,
                   const Uuid& journalID,
                   const std::optional<std::string>& currentRemoteRev,
                   std::vector<PendingEntryMutation>& mutations);
    std::pair<bool, std::optional<std::string>> pullEntry(
        const RemoteFileRecord& remoteFile,
        const std::string& entryPath,
        const Uuid& entryID,
        const Uuid& journalID,
        const std::optional<LocalSnap>& snapshot,
        std::vector<PendingEntryMutation>& mutations);
    void mergeEntry(const LocalSnap& local,
                    const Uuid& entryID,
                    const Uuid& journalID,
                    const std::string& entryPath,
                    std::vector<PendingEntryMutation>& mutations);
    bool localEntryMatchesSnapshot(const Uuid& entryID, const std::optional<LocalSnap>& snapshot);
    std::string archiveConflict(const JournalEntryMergeResult& result,
                                const Uuid& entryID,
                                const Uuid& journalID);
    void recordConflict(const Uuid& entryID,
                        const std::string& summary,
                        const std::string& remotePath,
                        const std::optional<JournalEntry>& local = std::nullopt,
                        const std::optional<JournalEntry>& remote = std::nullopt,
                        const std::optional<JournalEntry>& merged = std::nullopt);
    void removeConflicts(const Uuid& entryID);
    void uploadSettlementMarker(const Uuid& entryID, const std::string& settledHash, const Uuid& journalID);
    bool hasSettlingMarker(const Uuid& entryID, const Uuid& journalID, const std::string& hash);
    void reconcileImages(const Uuid& journalID);
    void migrateLegacyRemoteIfNeeded(const Uuid& journalID, const std::string& localName);
    void ensureManifest(const Uuid& journalID, const std::string& localName);
    JournalSyncManifest downloadManifest(const std::string& path);
    void adoptJournalName(const std::string& name, const Uuid& journalID);
    JournalTombstone downloadTombstone(const std::string& path);
    void refreshDiscoveredJournals(const Uuid& currentJournalID);
    static std::optional<Uuid> manifestJournalID(const std::string& path);
    std::optional<Uuid> tombstoneEntryID(const std::string& path, const Uuid& journalID);
    void collectGarbageTombstones(const Uuid& journalID);
    void requireJournal(const Uuid& journalID);
    void handleBackendError(const SyncBackendError& error);
    void publishFromState();
    void saveAndPublish();
    void flushPendingJournalDeletions();
    void detectPeerJournalTombstones();
    void pruneRemoteFiles(const std::string& root);
    void saveDeviceStateAndPublish();
    void queueConflictArchiveCleanup(const SyncConflictRecord& record);
    void flushConflictArchiveCleanups();
    void flushPendingTradingSnapshotDeletions() {}
    void reconcileTradingSnapshot(const Uuid&) {}

    JournalSyncBackend& backend_;
    JournalLocalSource& localSource_;
    std::string deviceID_;
    JournalSyncStateStore stateStore_;

    JournalSyncState state_;
    std::optional<Uuid> stateJournalID_;
    JournalDeviceSyncState deviceState_;

    bool isSyncing_ = false;
    bool pendingSync_ = false;
    Status status_ = Status::idle;
    SyncErrorKind errorKind_ = SyncErrorKind::other;
    std::string errorDetail_;
    std::optional<TimePoint> lastSyncAt_;
    std::vector<SyncConflictRecord> pendingConflicts_;
    std::vector<JournalSyncManifest> discoveredJournals_;
    std::vector<Uuid> remoteJournalDeletions_;
};

} // namespace wick
