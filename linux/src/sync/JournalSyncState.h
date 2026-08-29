#pragma once

#include "JournalModels.h"

#include <filesystem>
#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace wick {

struct JournalSyncLayout {
    static constexpr int formatVersion = 2;
    static constexpr double tombstoneRetention = 30.0 * 24 * 3600;

    static std::string journalRoot(const Uuid& journalID);
    static std::string manifestPath(const Uuid& journalID);
    static std::string entryPath(const Uuid& journalID, const Uuid& entryID);
    static std::string imagePath(const Uuid& journalID, const std::string& filename);
    static std::string tradingSnapshotPath(const Uuid& journalID);
    static std::string tradingSnapshotTombstonePath(const Uuid& journalID);
    static std::string entryTombstonePath(const Uuid& journalID, const Uuid& entryID);
    static std::string journalTombstonePath(const Uuid& journalID);
    static std::optional<Uuid> journalTombstoneID(const std::string& path);
    static std::string settlementPath(const Uuid& journalID, const Uuid& entryID,
                                      TimePoint stamp, const Uuid& uniqueID);
    static std::optional<Uuid> settlementEntryID(const std::string& path, const Uuid& journalID);
    static bool isSettlementPath(const std::string& path, const Uuid& journalID);
    static std::string conflictPath(const Uuid& journalID, const Uuid& entryID,
                                    TimePoint stamp, const Uuid& uniqueID);
    static std::optional<Uuid> entryIDFromEntryPath(const std::string& path, const Uuid& journalID);
    static std::string formatUtcStamp(TimePoint tp);
};

std::string asciiLower(std::string s);

struct JournalSyncManifest {
    int formatVersion = JournalSyncLayout::formatVersion;
    Uuid journalID{};
    std::string journalName;
    TimePoint createdAt{};
    std::string deviceID;
};

struct JournalTombstone {
    int formatVersion = JournalSyncLayout::formatVersion;
    Uuid entryID{};
    TimePoint deletedAt{};
    std::string deviceID;
};

struct JournalDeletionTombstone {
    int schemaVersion = 1;
    Uuid journalID{};
    TimePoint deletedAt{};
    std::string deviceID;
};

struct JournalSettlementMarker {
    Uuid entryID{};
    std::string settledHash;
    std::string deviceID;
    TimePoint stamp{};
};

struct JournalConflictPayload {
    Uuid entryID{};
    TimePoint detectedAt{};
    std::string deviceID;
    std::string reason;
    std::vector<JournalItem> losingItems;
    std::optional<std::string> losingTitle;
};

enum class EntrySettlementKind { none, pushSettled, adoptRemote, markSettled };

struct EntrySettlement {
    EntrySettlementKind kind = EntrySettlementKind::none;
    std::string hash;
    static EntrySettlement pushSettled(std::string h) {
        return {EntrySettlementKind::pushSettled, std::move(h)};
    }
    static EntrySettlement adoptRemote() { return {EntrySettlementKind::adoptRemote, {}}; }
    static EntrySettlement markSettled(std::string h) {
        return {EntrySettlementKind::markSettled, std::move(h)};
    }
};

struct EntrySyncState {
    std::optional<std::string> localHash;
    std::optional<std::string> remoteRev;
    std::optional<std::string> remoteContentHash;
    std::optional<std::string> tombstoneRev;
    std::optional<TimePoint> tombstoneDeletedAt;
    std::vector<std::string> pushedHashes;
    std::optional<EntrySettlement> settlement;
};

struct RemoteFileRecord {
    std::string rev;
    std::optional<std::string> contentHash;
};

struct SyncConflictRecord {
    Uuid id = Uuid::generate();
    Uuid entryID{};
    std::string displayDay;
    std::string remotePath;
    std::string summary;
    TimePoint detectedAt{};
    std::optional<JournalEntry> localEntry;
    std::optional<JournalEntry> remoteEntry;
    std::optional<JournalEntry> mergedEntry;
};

struct DiscoveredJournalRecord {
    JournalSyncManifest manifest;
    std::string manifestRev;
};

struct JournalSyncState {
    std::optional<std::string> cursor;
    std::map<std::string, RemoteFileRecord> remoteFiles;
    std::map<Uuid, EntrySyncState> entries;
    std::vector<SyncConflictRecord> pendingConflicts;
    std::vector<std::string> pendingConflictCleanups;
    std::optional<std::string> manifestRev;
    std::optional<int> manifestFormatVersion;
    std::optional<std::string> manifestName;
    std::optional<TimePoint> lastSyncAt;
    std::map<std::string, DiscoveredJournalRecord> discoveredJournals;
};

struct JournalTradingSnapshotTombstone {
    Uuid journalID{};
    TimePoint deletedAt{};
    std::string deviceID;
};

struct JournalDeviceSyncState {
    std::vector<JournalDeletionTombstone> pendingJournalDeletions;
    std::vector<Uuid> unackedRemoteDeletions;
    std::vector<Uuid> processedJournalTombstones;
    std::vector<JournalTradingSnapshotTombstone> pendingTradingSnapshotDeletions;

    bool isTombstoned(const Uuid& journalID) const;
};

class JournalSyncStateStore {
public:
    explicit JournalSyncStateStore(std::filesystem::path directory);

    std::filesystem::path stateURL(const Uuid& journalID) const;
    bool stateExists(const Uuid& journalID) const;
    JournalSyncState load(const Uuid& journalID) const;
    void save(const JournalSyncState& state, const Uuid& journalID) const;
    void clear(const Uuid& journalID) const;

    JournalDeviceSyncState loadDeviceState() const;
    void saveDeviceState(const JournalDeviceSyncState& state) const;

private:
    std::filesystem::path directory_;
    std::filesystem::path deviceStateURL() const;
};

std::string encodeManifest(const JournalSyncManifest& m);
JournalSyncManifest decodeManifest(std::string_view json);
std::string encodeTombstone(const JournalTombstone& t);
JournalTombstone decodeTombstone(std::string_view json);
std::string encodeJournalDeletionTombstone(const JournalDeletionTombstone& t);
JournalDeletionTombstone decodeJournalDeletionTombstone(std::string_view json);
std::string encodeSettlementMarker(const JournalSettlementMarker& m);
JournalSettlementMarker decodeSettlementMarker(std::string_view json);
std::string encodeConflictPayload(const JournalConflictPayload& p);
JournalConflictPayload decodeConflictPayload(std::string_view json);

void appendUniqueHash(std::vector<std::string>& hashes, const std::string& hash, int limit);

} // namespace wick
