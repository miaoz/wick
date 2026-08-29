#include "JournalCatalog.h"
#include "JournalSyncEncoding.h"

#include <fstream>

namespace wick {
namespace {

enum class FileOutcomeKind { valid, unsupportedVersion, corrupt, absent };

struct FileOutcome {
    FileOutcomeKind kind = FileOutcomeKind::absent;
    JournalCatalogSnapshot catalog;
    int version = 0;
};

FileOutcome decodeFile(const std::filesystem::path& url, int currentVersion) {
    FileOutcome out;
    std::error_code ec;
    if (!std::filesystem::exists(url, ec) || !std::filesystem::is_regular_file(url, ec)) {
        out.kind = FileOutcomeKind::absent;
        return out;
    }
    auto data = readFileBytes(url);
    if (!data) {
        out.kind = FileOutcomeKind::corrupt;
        return out;
    }
    try {
        out.catalog = JournalCatalogCodec::decode(*data, currentVersion);
        out.kind = FileOutcomeKind::valid;
        return out;
    } catch (const JournalCatalogCodec::LoadError& e) {
        if (e.kind == JournalCatalogCodec::LoadErrorKind::unsupportedVersion) {
            out.kind = FileOutcomeKind::unsupportedVersion;
            out.version = e.version;
            return out;
        }
        out.kind = FileOutcomeKind::corrupt;
        return out;
    } catch (...) {
        out.kind = FileOutcomeKind::corrupt;
        return out;
    }
}

} // namespace

JournalCatalogSnapshot JournalCatalogCodec::decode(std::string_view data, int currentVersion) {
    if (data.empty()) {
        throw LoadError(LoadErrorKind::corrupt, 0, "empty catalog data");
    }
    JournalCatalogSnapshot catalog;
    try {
        catalog = JournalSyncEncoding::decodeCatalogObject(data);
    } catch (const JournalImageFilename::InvalidReference&) {
        throw LoadError(LoadErrorKind::corrupt, 0, "corrupt catalog");
    } catch (const DecodeError&) {
        throw LoadError(LoadErrorKind::corrupt, 0, "corrupt catalog");
    } catch (...) {
        throw LoadError(LoadErrorKind::corrupt, 0, "corrupt catalog");
    }
    if (catalog.version > currentVersion) {
        throw LoadError(LoadErrorKind::unsupportedVersion, catalog.version,
                        "unsupported catalog version");
    }
    if (catalog.journals.empty()) {
        throw LoadError(LoadErrorKind::empty, catalog.version, "empty catalog journals");
    }
    return catalog;
}

JournalCatalogLoader::Outcome JournalCatalogLoader::load(
    const std::filesystem::path& primaryURL,
    const std::filesystem::path& backupURL,
    int currentVersion) {
    const FileOutcome primary = decodeFile(primaryURL, currentVersion);
    switch (primary.kind) {
    case FileOutcomeKind::valid:
        return Loaded{primary.catalog};
    case FileOutcomeKind::unsupportedVersion:
        // Future format: never rewrite the primary or consult the backup.
        return UnsupportedVersion{primary.version};
    case FileOutcomeKind::corrupt: {
        const FileOutcome backup = decodeFile(backupURL, currentVersion);
        switch (backup.kind) {
        case FileOutcomeKind::valid:
            return RestoredFromBackup{backup.catalog};
        case FileOutcomeKind::unsupportedVersion:
            return UnsupportedVersion{backup.version};
        case FileOutcomeKind::corrupt:
        case FileOutcomeKind::absent:
            return Corrupt{};
        }
        break;
    }
    case FileOutcomeKind::absent: {
        const FileOutcome backup = decodeFile(backupURL, currentVersion);
        switch (backup.kind) {
        case FileOutcomeKind::valid:
            return RestoredFromBackup{backup.catalog};
        case FileOutcomeKind::unsupportedVersion:
            return UnsupportedVersion{backup.version};
        case FileOutcomeKind::corrupt:
            return Corrupt{};
        case FileOutcomeKind::absent:
            return Missing{};
        }
        break;
    }
    }
    return Corrupt{};
}

bool persistCatalog(const std::filesystem::path& librariesRoot,
                    const JournalCatalogSnapshot& catalog) {
    if (catalog.journals.empty()) return false;
    std::string data;
    try {
        data = JournalSyncEncoding::encode(catalog);
    } catch (...) {
        return false;
    }
    std::error_code ec;
    std::filesystem::create_directories(librariesRoot, ec);
    const auto primary = librariesRoot / "catalog.json";
    const auto backup = librariesRoot / "catalog.json.bak";
    if (std::filesystem::exists(primary, ec)) {
        std::filesystem::remove(backup, ec);
        std::filesystem::copy_file(primary, backup, ec);
    }
    return atomicWriteFile(primary, data);
}

} // namespace wick
