#pragma once

#include "JournalModels.h"

#include <filesystem>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace wick {

// Active-journal persist/load from JournalStore+Persistence.swift, plus
// image attach and zip import/export from JournalStore+Media.swift.
class JournalFileStore {
public:
    explicit JournalFileStore(std::filesystem::path journalDirectory);

    void ensureDirectories();
    void load();
    void persist();

    const std::filesystem::path& journalDirectory() const { return journalDirectory_; }
    const std::filesystem::path& imagesDirectory() const { return imagesDirectory_; }
    const std::filesystem::path& databaseURL() const { return databaseURL_; }
    const std::filesystem::path& backupURL() const { return backupURL_; }
    const std::filesystem::path& backupsDirectory() const { return backupsDirectory_; }

    // The only image path constructor. Returns nullopt for any name that is
    // not a safe single-level filename or that would resolve outside images/.
    std::optional<std::filesystem::path> imageURL(const std::string& filename) const;

    static std::string sanitizedExtension(std::string raw);

    // Copies bytes into images/<UPPERCASE-UUID>.<ext>. Returns the stored
    // filename, or nullopt if read-only / missing item / write failed.
    std::optional<std::string> addImage(const Uuid& entryID, const Uuid& itemID,
                                        std::string_view data, std::string preferredExtension);
    std::optional<std::string> addImageFromFile(const Uuid& entryID, const Uuid& itemID,
                                                const std::filesystem::path& sourceFile);
    void removeImage(const std::string& filename, const Uuid& entryID, const Uuid& itemID);

    // Mac exportArchive / importArchive. nullopt = success.
    std::optional<std::string> exportArchive(const std::filesystem::path& destinationURL);
    std::optional<std::string> importArchive(const std::filesystem::path& sourceURL);

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
    void backupPrimaryIfPresent(bool includeRolling);
    void removeImageFile(const std::string& filename);

    std::filesystem::path journalDirectory_;
    std::filesystem::path imagesDirectory_;
    std::filesystem::path databaseURL_;
    std::filesystem::path backupURL_;
    std::filesystem::path backupsDirectory_;
};

} // namespace wick
