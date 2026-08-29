#pragma once

#include <filesystem>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace wick {

// Mac ditto -c -k --keepParent of a folder named Wick-Journal, so the archive
// root is:
//   Wick-Journal/journal.json
//   Wick-Journal/images/<safe-filename>
inline constexpr const char* kExportPayloadDirectory = "Wick-Journal";

struct ZipEntry {
    std::string name; // archive-relative, forward slashes
    std::string data;
};

bool isSafeZipEntryName(std::string_view name);

// Returns an error message, or nullopt on success.
std::optional<std::string> writeZipFile(const std::filesystem::path& zipPath,
                                        const std::vector<ZipEntry>& entries);

// Extracts into destDir. Any unsafe entry name fails wholesale (nothing is
// left behind: destDir is not created by the caller for this purpose).
std::optional<std::string> extractZipFile(const std::filesystem::path& zipPath,
                                          const std::filesystem::path& destDir);

// Recursive search, skipping hidden names. First journal.json wins.
std::optional<std::filesystem::path> findJournalJSON(const std::filesystem::path& directory);

} // namespace wick
