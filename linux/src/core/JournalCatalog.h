#pragma once

#include "JournalModels.h"

#include <filesystem>
#include <string>
#include <variant>

namespace wick {

struct JournalCatalogCodec {
    enum class LoadErrorKind { corrupt, empty, unsupportedVersion };

    struct LoadError : std::runtime_error {
        LoadErrorKind kind;
        int version = 0;
        LoadError(LoadErrorKind k, int v, const std::string& msg)
            : std::runtime_error(msg), kind(k), version(v) {}
    };

    static JournalCatalogSnapshot decode(std::string_view data, int currentVersion);
};

struct JournalCatalogLoader {
    struct Missing {};
    struct Loaded { JournalCatalogSnapshot catalog; };
    struct RestoredFromBackup { JournalCatalogSnapshot catalog; };
    struct Corrupt {};
    struct UnsupportedVersion { int version = 0; };

    using Outcome = std::variant<Missing, Loaded, RestoredFromBackup, Corrupt, UnsupportedVersion>;

    static Outcome load(const std::filesystem::path& primaryURL,
                        const std::filesystem::path& backupURL,
                        int currentVersion);
};

// Sidecar .bak of the previous primary, then atomic overwrite. False if
// journals is empty or the write fails (matches JournalLibraryCore.persistCatalog
// without the host read-only gate — caller must check that).
bool persistCatalog(const std::filesystem::path& librariesRoot,
                    const JournalCatalogSnapshot& catalog);

} // namespace wick
