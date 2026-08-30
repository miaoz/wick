#pragma once

#include "JournalModels.h"

#include <filesystem>

namespace wick {

// Linux layout (Mac: ~/Library/Application Support/Wick/Journals/):
//   ~/.local/share/wick/Journals/
//     catalog.json
//     catalog.json.bak
//     <UUID>/{journal.json,journal.json.bak,backups/,images/}  (uppercase uuidString)
struct JournalPaths {
    std::filesystem::path librariesRoot;

    static JournalPaths defaultPaths(); // $XDG_DATA_HOME/wick/Journals or ~/.local/share/...
    static JournalPaths inRoot(std::filesystem::path librariesRoot);

    std::filesystem::path catalogURL() const;
    std::filesystem::path catalogBackupURL() const;
    std::filesystem::path journalDirectory(const Uuid& id) const;
    std::filesystem::path journalJSON(const Uuid& id) const;
    std::filesystem::path journalBackup(const Uuid& id) const;
    std::filesystem::path tradingJSON(const Uuid& id) const;
    std::filesystem::path backupsDirectory(const Uuid& id) const;
    std::filesystem::path imagesDirectory(const Uuid& id) const;

    void ensureJournalDirectories(const Uuid& id) const;
};

} // namespace wick
