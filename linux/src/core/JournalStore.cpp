#include "JournalStore.h"
#include "JournalSyncEncoding.h"

#include <algorithm>
#include <cctype>
#include <ctime>
#include <fstream>
#include <sstream>

namespace wick {
namespace {

void copyDatabaseToSidecarBackup(
    const std::filesystem::path& databaseURL,
    const std::filesystem::path& backupURL,
    const std::filesystem::path& backupsDirectory,
    bool includeRolling,
    int maxRollingBackups,
    TimePoint now) {
    std::error_code ec;
    if (!std::filesystem::exists(databaseURL, ec)) return;
    std::filesystem::remove(backupURL, ec);
    std::filesystem::copy_file(databaseURL, backupURL, ec);

    if (!includeRolling) return;
    std::filesystem::create_directories(backupsDirectory, ec);
    const std::time_t t = std::chrono::system_clock::to_time_t(now);
    std::tm local{};
    localtime_r(&t, &local);
    char stamp[32];
    std::strftime(stamp, sizeof(stamp), "%Y%m%d-%H%M%S", &local);
    const auto rolling = backupsDirectory / (std::string("journal-") + stamp + ".json");
    std::filesystem::copy_file(databaseURL, rolling, ec);

    std::vector<std::filesystem::path> jsons;
    for (const auto& entry : std::filesystem::directory_iterator(backupsDirectory, ec)) {
        if (!entry.is_regular_file(ec)) continue;
        if (entry.path().filename().string().starts_with(".")) continue;
        auto ext = entry.path().extension().string();
        std::transform(ext.begin(), ext.end(), ext.begin(),
                       [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
        if (ext == ".json") jsons.push_back(entry.path());
    }
    std::sort(jsons.begin(), jsons.end(), [&](const auto& a, const auto& b) {
        auto ta = std::filesystem::last_write_time(a, ec);
        auto tb = std::filesystem::last_write_time(b, ec);
        return ta > tb;
    });
    if (static_cast<int>(jsons.size()) > maxRollingBackups) {
        for (size_t i = static_cast<size_t>(maxRollingBackups); i < jsons.size(); ++i) {
            std::filesystem::remove(jsons[i], ec);
        }
    }
}

} // namespace

JournalFileStore::JournalFileStore(std::filesystem::path journalDirectory)
    : journalDirectory_(std::move(journalDirectory)) {
    imagesDirectory_ = journalDirectory_ / "images";
    databaseURL_ = journalDirectory_ / "journal.json";
    backupURL_ = journalDirectory_ / "journal.json.bak";
    backupsDirectory_ = journalDirectory_ / "backups";
}

void JournalFileStore::ensureDirectories() {
    std::error_code ec;
    std::filesystem::create_directories(journalDirectory_, ec);
    std::filesystem::create_directories(imagesDirectory_, ec);
    std::filesystem::create_directories(backupsDirectory_, ec);
}

TimePoint JournalFileStore::nowTime() const {
    if (now) return now();
    return std::chrono::system_clock::now();
}

std::optional<JournalSnapshot> JournalFileStore::loadSnapshot(
    const std::filesystem::path& url) const {
    std::error_code ec;
    if (!std::filesystem::exists(url, ec)) return std::nullopt;
    auto data = readFileBytes(url);
    if (!data) return std::nullopt;
    try {
        auto snapshot = JournalSyncEncoding::decodeSnapshot(*data);
        if (snapshot.version > JournalSnapshot::currentVersion) return std::nullopt;
        return snapshot;
    } catch (...) {
        return std::nullopt;
    }
}

void JournalFileStore::load() {
    isReadOnlyDueToLoadFailure = false;
    loadFailureMessage.reset();
    // didRestoreFromBackup is intentionally NOT reset (Mac bootstrap).
    ensureDirectories();

    std::error_code ec;
    if (!std::filesystem::exists(databaseURL_, ec)) {
        if (auto restored = loadSnapshot(backupURL_)) {
            entries = restored->entries;
            std::sort(entries.begin(), entries.end(),
                      [](const JournalEntry& a, const JournalEntry& b) { return a.date > b.date; });
            didRestoreFromBackup = true;
            persist();
            return;
        }
        entries.clear();
        return;
    }

    try {
        auto data = readFileBytes(databaseURL_);
        if (!data) throw DecodeError("unreadable journal.json");
        auto snapshot = JournalSyncEncoding::decodeSnapshot(*data);
        if (snapshot.version > JournalSnapshot::currentVersion) {
            entries.clear();
            isReadOnlyDueToLoadFailure = true;
            loadFailureMessage = "newer journal format v" + std::to_string(snapshot.version);
            return;
        }
        entries = snapshot.entries;
        std::sort(entries.begin(), entries.end(),
                  [](const JournalEntry& a, const JournalEntry& b) { return a.date > b.date; });
    } catch (const std::exception& error) {
        if (auto restored = loadSnapshot(backupURL_)) {
            entries = restored->entries;
            std::sort(entries.begin(), entries.end(),
                      [](const JournalEntry& a, const JournalEntry& b) { return a.date > b.date; });
            didRestoreFromBackup = true;
            const auto stamp = static_cast<long long>(unixFromTime(nowTime()));
            const auto quarantine =
                journalDirectory_ / ("journal.corrupt-" + std::to_string(stamp) + ".json");
            std::filesystem::rename(databaseURL_, quarantine, ec);
            isReadOnlyDueToLoadFailure = false;
            persist();
            return;
        }
        entries.clear();
        isReadOnlyDueToLoadFailure = true;
        if (dynamic_cast<const JournalImageFilename::InvalidReference*>(&error)) {
            loadFailureMessage = "unsafe image references";
        } else {
            loadFailureMessage = error.what();
        }
    }
}

void JournalFileStore::persist() {
    if (persistBlocked) return;
    if (isReadOnlyDueToLoadFailure) return;
    ensureDirectories();

    const JournalSnapshot snapshot{JournalSnapshot::currentVersion, entries};
    std::error_code ec;
    const bool fileExists = std::filesystem::exists(databaseURL_, ec);
    bool shouldRoll = true;
    const TimePoint t = nowTime();
    if (lastRollingBackupAt) {
        shouldRoll = (t - *lastRollingBackupAt) >= std::chrono::minutes(30);
    }
    if (fileExists && shouldRoll) {
        lastRollingBackupAt = t;
    }
    const bool copyExistingToBackup = fileExists;
    const bool includeRolling = fileExists && shouldRoll;
    auto err = writeSnapshot(snapshot, databaseURL_, backupURL_, backupsDirectory_,
                             copyExistingToBackup, includeRolling, maxRollingBackups, t);
    if (err) lastPersistError = *err;
    else lastPersistError.reset();
}

std::optional<std::string> JournalFileStore::writeSnapshot(
    const JournalSnapshot& snapshot,
    const std::filesystem::path& databaseURL,
    const std::filesystem::path& backupURL,
    const std::filesystem::path& backupsDirectory,
    bool copyExistingToBackup,
    bool includeRolling,
    int maxRollingBackups,
    TimePoint now) {
    try {
        if (copyExistingToBackup) {
            copyDatabaseToSidecarBackup(databaseURL, backupURL, backupsDirectory,
                                        includeRolling, maxRollingBackups, now);
        }
        const std::string data = JournalSyncEncoding::encode(snapshot);
        if (!atomicWriteFile(databaseURL, data)) {
            return std::string("atomic write failed");
        }
        return std::nullopt;
    } catch (const std::exception& e) {
        return std::string(e.what());
    }
}

} // namespace wick
