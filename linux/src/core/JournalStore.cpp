#include "JournalStore.h"
#include "JournalArchive.h"
#include "JournalSyncEncoding.h"

#include <algorithm>
#include <cctype>
#include <ctime>
#include <fstream>
#include <set>
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

int JournalFileStore::entryCountOnDisk(const std::filesystem::path& journalDirectory) {
    if (auto entries = loadEntriesReadOnly(journalDirectory))
        return static_cast<int>(entries->size());
    return 0;
}

std::optional<std::vector<JournalEntry>> JournalFileStore::loadEntriesReadOnly(
    const std::filesystem::path& journalDirectory) {
    JournalFileStore probe(journalDirectory);
    if (auto snap = probe.loadSnapshot(probe.databaseURL_))
        return snap->entries;
    if (auto snap = probe.loadSnapshot(probe.backupURL_))
        return snap->entries;
    return std::nullopt;
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


std::optional<std::filesystem::path> JournalFileStore::imageURL(const std::string& filename) const {
    if (!JournalImageFilename::isValid(filename)) return std::nullopt;
    const auto url = imagesDirectory_ / filename;
    const auto standard = url.lexically_normal();
    const auto imagesStandard = imagesDirectory_.lexically_normal();
    auto prefix = imagesStandard.generic_string();
    if (prefix.empty() || prefix.back() != '/') prefix.push_back('/');
    const auto path = standard.generic_string();
    if (path.find(prefix) != 0) return std::nullopt;
    return url;
}

std::string JournalFileStore::sanitizedExtension(std::string raw) {
    while (!raw.empty() && raw.front() == '.') raw.erase(raw.begin());
    while (!raw.empty() && raw.back() == '.') raw.pop_back();
    std::transform(raw.begin(), raw.end(), raw.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    static const std::set<std::string> allowed = {
        "png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp"};
    if (allowed.count(raw)) return raw == "jpeg" ? "jpg" : raw;
    return "png";
}

void JournalFileStore::removeImageFile(const std::string& filename) {
    const auto url = imageURL(filename);
    if (!url) return;
    std::error_code ec;
    std::filesystem::remove(*url, ec);
}

std::optional<std::string> JournalFileStore::addImage(const Uuid& entryID, const Uuid& itemID,
                                                      std::string_view data,
                                                      std::string preferredExtension) {
    if (isReadOnlyDueToLoadFailure) return std::nullopt;
    JournalEntry* entry = nullptr;
    JournalItem* item = nullptr;
    for (auto& e : entries) {
        if (e.id != entryID) continue;
        for (auto& it : e.items) {
            if (it.id == itemID) {
                entry = &e;
                item = &it;
                break;
            }
        }
        if (item) break;
    }
    if (!entry || !item) return std::nullopt;

    ensureDirectories();
    const std::string ext = sanitizedExtension(std::move(preferredExtension));
    const std::string filename = Uuid::generate().toString() + "." + ext;
    const auto destination = imageURL(filename);
    if (!destination) return std::nullopt;
    if (!atomicWriteFile(*destination, data)) return std::nullopt;

    item->imageFilenames.push_back(filename);
    entry->updatedAt = nowTime();
    persist();
    return filename;
}

std::optional<std::string> JournalFileStore::addImageFromFile(
    const Uuid& entryID, const Uuid& itemID, const std::filesystem::path& sourceFile) {
    auto data = readFileBytes(sourceFile);
    if (!data) return std::nullopt;
    std::string ext = sourceFile.extension().string();
    if (!ext.empty() && ext.front() == '.') ext.erase(ext.begin());
    return addImage(entryID, itemID, *data, std::move(ext));
}

void JournalFileStore::removeImage(const std::string& filename, const Uuid& entryID,
                                   const Uuid& itemID) {
    if (isReadOnlyDueToLoadFailure) return;
    JournalEntry* entry = nullptr;
    JournalItem* item = nullptr;
    for (auto& e : entries) {
        if (e.id != entryID) continue;
        for (auto& it : e.items) {
            if (it.id == itemID) {
                entry = &e;
                item = &it;
                break;
            }
        }
        if (item) break;
    }
    if (!entry || !item) return;
    auto& names = item->imageFilenames;
    names.erase(std::remove(names.begin(), names.end(), filename), names.end());
    entry->updatedAt = nowTime();
    removeImageFile(filename);
    persist();
}

void JournalFileStore::backupPrimaryIfPresent(bool includeRolling) {
    copyDatabaseToSidecarBackup(databaseURL_, backupURL_, backupsDirectory_, includeRolling,
                                maxRollingBackups, nowTime());
}

std::optional<std::string> JournalFileStore::exportArchive(
    const std::filesystem::path& destinationURL) {
    // A load-failure read-only store has already emptied `entries`; encoding
    // that empty snapshot would atomically overwrite a previous good export.
    if (isReadOnlyDueToLoadFailure) {
        return std::string(
            "The journal is under read-only protection after a load failure; export is disabled.");
    }

    const JournalSnapshot snapshot{JournalSnapshot::currentVersion, entries};
    const std::string json = JournalSyncEncoding::encode(snapshot);

    std::vector<ZipEntry> zipEntries;
    zipEntries.push_back(ZipEntry{std::string(kExportPayloadDirectory) + "/journal.json", json});

    std::error_code ec;
    if (std::filesystem::exists(imagesDirectory_, ec)
        && std::filesystem::is_directory(imagesDirectory_, ec)) {
        for (const auto& file : std::filesystem::directory_iterator(imagesDirectory_, ec)) {
            if (!file.is_regular_file(ec)) continue;
            const auto name = file.path().filename().string();
            if (!JournalImageFilename::isValid(name)) continue;
            auto bytes = readFileBytes(file.path());
            if (!bytes) continue;
            zipEntries.push_back(ZipEntry{
                std::string(kExportPayloadDirectory) + "/images/" + name, std::move(*bytes)});
        }
    }

    const auto destDir = destinationURL.parent_path();
    std::filesystem::create_directories(destDir, ec);
    const auto tempZip =
        destDir / (".Wick-export-" + Uuid::generate().toString() + ".tmp");
    auto err = writeZipFile(tempZip, zipEntries);
    if (err) {
        std::filesystem::remove(tempZip, ec);
        return err;
    }
    std::filesystem::rename(tempZip, destinationURL, ec);
    if (ec) {
        std::filesystem::remove(tempZip, ec);
        return std::string("failed to replace export destination: ") + ec.message();
    }
    return std::nullopt;
}

namespace {

struct PreparedImport {
    JournalSnapshot snapshot;
    std::optional<std::filesystem::path> importedImages;
};

std::optional<std::string> prepareImport(const std::filesystem::path& sourceURL,
                                         const std::filesystem::path& tempRoot,
                                         PreparedImport& out) {
    std::error_code ec;
    std::filesystem::path jsonURL;
    std::optional<std::filesystem::path> importedImages;

    auto ext = sourceURL.extension().string();
    std::transform(ext.begin(), ext.end(), ext.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });

    if (ext == ".json") {
        jsonURL = sourceURL;
        importedImages.reset();
    } else {
        auto unzipErr = extractZipFile(sourceURL, tempRoot);
        if (unzipErr) return unzipErr;
        auto found = findJournalJSON(tempRoot);
        if (!found) return std::string("importMissingJournalJSON");
        jsonURL = *found;
        const auto sibling = jsonURL.parent_path() / "images";
        if (std::filesystem::exists(sibling, ec) && std::filesystem::is_directory(sibling, ec)) {
            importedImages = sibling;
        }
    }

    auto data = readFileBytes(jsonURL);
    if (!data) return std::string("unreadable journal.json");
    try {
        auto snapshot = JournalSyncEncoding::decodeSnapshot(*data);
        if (snapshot.version > JournalSnapshot::currentVersion) {
            return std::string("unsupportedSnapshotVersion:") + std::to_string(snapshot.version);
        }
        if (importedImages) {
            for (const auto& file : std::filesystem::directory_iterator(*importedImages, ec)) {
                if (!file.is_regular_file(ec)) continue;
                const auto name = file.path().filename().string();
                if (!JournalImageFilename::isValid(name)) {
                    return std::string("unsafe image filename: ") + name;
                }
            }
        }
        out.snapshot = std::move(snapshot);
        out.importedImages = importedImages;
        return std::nullopt;
    } catch (const JournalImageFilename::InvalidReference& e) {
        return std::string("unsafe image filename: ") + e.filename;
    } catch (const std::exception& e) {
        return std::string(e.what());
    }
}

} // namespace

std::optional<std::string> JournalFileStore::importArchive(const std::filesystem::path& sourceURL) {
    const auto tempRoot =
        std::filesystem::temp_directory_path() / ("WickImport-" + Uuid::generate().toString());
    std::error_code ec;
    std::filesystem::create_directories(tempRoot, ec);
    struct TempGuard {
        std::filesystem::path p;
        ~TempGuard() {
            std::error_code e;
            std::filesystem::remove_all(p, e);
        }
    } guard{tempRoot};

    PreparedImport prepared;
    auto prepErr = prepareImport(sourceURL, tempRoot, prepared);
    if (prepErr) return prepErr;

    // Fully validated. Backup + image swap happen next; read-only stays until
    // the in-memory snapshot is replaced so a failed copy cannot leave the
    // store writable after a no-op.

    if (std::filesystem::exists(databaseURL_, ec)) {
        backupPrimaryIfPresent(true);
        lastRollingBackupAt = nowTime();
    }

    std::optional<std::filesystem::path> imagesQuarantine;
    bool imagesMovedAside = false;
    if (std::filesystem::exists(imagesDirectory_, ec)) {
        const auto quarantine =
            journalDirectory_ / (".WickImagesQuarantine-" + Uuid::generate().toString());
        std::filesystem::rename(imagesDirectory_, quarantine, ec);
        if (!ec) {
            imagesQuarantine = quarantine;
            imagesMovedAside = true;
        }
    }

    auto rollbackImages = [&]() {
        if (!imagesMovedAside) return;
        std::filesystem::remove_all(imagesDirectory_, ec);
        if (imagesQuarantine) {
            std::filesystem::rename(*imagesQuarantine, imagesDirectory_, ec);
        }
    };

    std::filesystem::create_directories(imagesDirectory_, ec);
    if (prepared.importedImages) {
        for (const auto& file : std::filesystem::directory_iterator(*prepared.importedImages, ec)) {
            if (!file.is_regular_file(ec)) continue;
            const auto name = file.path().filename().string();
            if (!JournalImageFilename::isValid(name)) {
                rollbackImages();
                return std::string("unsafe image filename: ") + name;
            }
            const auto dest = imagesDirectory_ / name;
            std::filesystem::copy_file(file.path(), dest,
                                       std::filesystem::copy_options::overwrite_existing, ec);
            if (ec) {
                rollbackImages();
                return std::string("failed to copy imported image: ") + name;
            }
        }
    }

    if (imagesQuarantine) {
        std::filesystem::remove_all(*imagesQuarantine, ec);
    }

    isReadOnlyDueToLoadFailure = false;
    loadFailureMessage.reset();
    entries = std::move(prepared.snapshot.entries);
    std::sort(entries.begin(), entries.end(),
              [](const JournalEntry& a, const JournalEntry& b) { return a.date > b.date; });
    isReadOnlyDueToLoadFailure = false;
    loadFailureMessage.reset();
    didRestoreFromBackup = false;
    lastPersistError.reset();
    persist();
    return std::nullopt;
}

} // namespace wick
