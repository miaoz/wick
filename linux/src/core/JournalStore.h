#pragma once

#include "JournalModels.h"

#include <filesystem>
#include <optional>
#include <string>
#include <vector>

namespace wick {

// Active-journal persist/load from JournalStore+Persistence.swift.
class JournalFileStore {
public:
    explicit JournalFileStore(std::filesystem::path journalDirectory);

    void ensureDirectories();
    void load();
    void persist();

    const std::filesystem::path& journalDirectory() const { return journalDirectory_; }
    const std::filesystem::path& databaseURL() const { return databaseURL_; }
    const std::filesystem::path& backupURL() const { return backupURL_; }
    const std::filesystem::path& backupsDirectory() const { return backupsDirectory_; }

    std::vector<JournalEntry> entries;
    bool isReadOnlyDueToLoadFailure = false;
    bool didRestoreFromBackup = false;
    bool persistBlocked = false;
    std::optional<std::string> loadFailureMessage;
    std::optional<std::string> lastPersistError;
    int maxRollingBackups = 5;
    std::optional<TimePoint> lastRollingBackupAt;
    // Optional clock for rolling-backup timestamps (tests).
    TimePoint (*now)() = nullptr;

private:
    TimePoint nowTime() const;
    std::optional<JournalSnapshot> loadSnapshot(const std::filesystem::path& url) const;
    static std::optional<std::string> writeSnapshot(
        const JournalSnapshot& snapshot,
        const std::filesystem::path& databaseURL,
        const std::filesystem::path& backupURL,
        const std::filesystem::path& backupsDirectory,
        bool copyExistingToBackup,
        bool includeRolling,
        int maxRollingBackups,
        TimePoint now);

    std::filesystem::path journalDirectory_;
    std::filesystem::path imagesDirectory_;
    std::filesystem::path databaseURL_;
    std::filesystem::path backupURL_;
    std::filesystem::path backupsDirectory_;
};

} // namespace wick
