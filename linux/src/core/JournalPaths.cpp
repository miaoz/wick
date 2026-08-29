#include "JournalPaths.h"

#include <cstdlib>

namespace wick {

JournalPaths JournalPaths::defaultPaths() {
    std::filesystem::path root;
    if (const char* xdg = std::getenv("XDG_DATA_HOME"); xdg && *xdg) {
        root = std::filesystem::path(xdg) / "wick" / "Journals";
    } else {
        const char* home = std::getenv("HOME");
        const std::filesystem::path homePath = (home && *home) ? std::filesystem::path(home)
                                                               : std::filesystem::path(".");
        root = homePath / ".local" / "share" / "wick" / "Journals";
    }
    return inRoot(std::move(root));
}

JournalPaths JournalPaths::inRoot(std::filesystem::path librariesRoot) {
    JournalPaths p;
    p.librariesRoot = std::move(librariesRoot);
    return p;
}

std::filesystem::path JournalPaths::catalogURL() const {
    return librariesRoot / "catalog.json";
}
std::filesystem::path JournalPaths::catalogBackupURL() const {
    return librariesRoot / "catalog.json.bak";
}
std::filesystem::path JournalPaths::journalDirectory(const Uuid& id) const {
    return librariesRoot / id.toString();
}
std::filesystem::path JournalPaths::journalJSON(const Uuid& id) const {
    return journalDirectory(id) / "journal.json";
}
std::filesystem::path JournalPaths::journalBackup(const Uuid& id) const {
    return journalDirectory(id) / "journal.json.bak";
}
std::filesystem::path JournalPaths::backupsDirectory(const Uuid& id) const {
    return journalDirectory(id) / "backups";
}
std::filesystem::path JournalPaths::imagesDirectory(const Uuid& id) const {
    return journalDirectory(id) / "images";
}

void JournalPaths::ensureJournalDirectories(const Uuid& id) const {
    std::error_code ec;
    std::filesystem::create_directories(journalDirectory(id), ec);
    std::filesystem::create_directories(imagesDirectory(id), ec);
    std::filesystem::create_directories(backupsDirectory(id), ec);
}

} // namespace wick
