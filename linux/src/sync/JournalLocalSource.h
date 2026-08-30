#pragma once

#include "JournalModels.h"

#include <map>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <vector>

namespace wick {

struct JournalSyncMutation {
    enum class Kind { upsert, remove };
    Kind kind = Kind::upsert;
    JournalEntry entry;
    Uuid entryID{};
    std::optional<std::string> expectedLocalHash;

    static JournalSyncMutation upsert(JournalEntry e, std::optional<std::string> expected) {
        JournalSyncMutation m;
        m.kind = Kind::upsert;
        m.entryID = e.id;
        m.entry = std::move(e);
        m.expectedLocalHash = std::move(expected);
        return m;
    }
    static JournalSyncMutation remove(Uuid id, std::optional<std::string> expected) {
        JournalSyncMutation m;
        m.kind = Kind::remove;
        m.entryID = id;
        m.expectedLocalHash = std::move(expected);
        return m;
    }
};

struct JournalTradingSnapshotDocument {
    static constexpr int currentFormatVersion = 1;
    int formatVersion = currentFormatVersion;
    Uuid journalID{};
    std::string venue;
    std::string accountLabel;
    std::int64_t fetchedAtMilliseconds = 0;
    std::string payload; // decoded JSON bytes
};

struct JournalTradingSnapshotTombstone {
    Uuid journalID{};
    std::int64_t deletedAtMilliseconds = 0;
    std::string deviceID;
};

class JournalLocalSource {
public:
    virtual ~JournalLocalSource() = default;

    virtual std::optional<Uuid> syncJournalID() const = 0;
    virtual std::string syncJournalName() const = 0;
    virtual bool syncIsWritable() const = 0;

    virtual std::map<Uuid, JournalEntry> syncEntrySnapshots() = 0;
    virtual std::optional<JournalEntry> syncEntrySnapshot(const Uuid& entryID) = 0;

    virtual void prepareForRemoteApply(const Uuid& entryID) = 0;

    virtual std::set<Uuid> applySyncedChanges(const std::vector<JournalSyncMutation>& changes,
                                              const Uuid& journalID) = 0;
    virtual void applySyncedEntry(const JournalEntry& entry, const Uuid& journalID) = 0;
    virtual void removeSyncedEntry(const Uuid& entryID, const Uuid& journalID) = 0;
    virtual std::string applySyncedJournalName(const std::string& name, const Uuid& journalID) = 0;

    virtual std::set<std::string> syncedImageFilenames() = 0;
    virtual std::optional<std::string> syncedImageData(const std::string& filename) = 0;
    virtual bool hasSyncedImage(const std::string& filename) = 0;
    virtual void storeSyncedImage(const std::string& filename,
                                  std::string_view data,
                                  const Uuid& journalID) = 0;

    virtual bool syncTradingSnapshotEnabled() const { return true; }
    virtual std::optional<JournalTradingSnapshotDocument> syncedTradingSnapshot(const Uuid& journalID) { (void)journalID; return std::nullopt; }
    virtual void applySyncedTradingSnapshot(const JournalTradingSnapshotDocument& document, const Uuid& journalID) { (void)document; (void)journalID; }
    virtual void removeSyncedTradingSnapshot(const Uuid& journalID) { (void)journalID; }
};

} // namespace wick
