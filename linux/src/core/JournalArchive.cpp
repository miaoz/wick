#include "JournalArchive.h"

#include "miniz.h"

#include <algorithm>
#include <cstring>
#include <fstream>
#include <system_error>

namespace wick {
namespace {

bool isHiddenName(std::string_view name) {
    return !name.empty() && name.front() == '.';
}

std::string minizError(mz_zip_archive& zip) {
    const mz_zip_error err = mz_zip_get_last_error(&zip);
    const char* s = mz_zip_get_error_string(err);
    return s ? std::string(s) : std::string("zip error");
}

} // namespace

bool isSafeZipEntryName(std::string_view name) {
    if (name.empty()) return false;
    if (name.find('\0') != std::string_view::npos) return false;
    if (name.find('\\') != std::string_view::npos) return false;
    if (name.front() == '/' || name.front() == '\\') return false;

    // Allow a trailing slash for directory entries.
    if (name.back() == '/') {
        name = name.substr(0, name.size() - 1);
        if (name.empty()) return false;
    }

    size_t start = 0;
    while (start <= name.size()) {
        const size_t slash = name.find('/', start);
        const std::string_view part = name.substr(
            start, slash == std::string_view::npos ? std::string_view::npos : slash - start);
        if (part.empty() || part == "." || part == "..") return false;
        if (slash == std::string_view::npos) break;
        start = slash + 1;
        if (start == name.size()) return false; // already stripped trailing slash
    }
    return true;
}

std::optional<std::string> writeZipFile(const std::filesystem::path& zipPath,
                                        const std::vector<ZipEntry>& entries) {
    std::error_code ec;
    std::filesystem::create_directories(zipPath.parent_path(), ec);

    mz_zip_archive zip;
    std::memset(&zip, 0, sizeof(zip));
    if (!mz_zip_writer_init_file(&zip, zipPath.string().c_str(), 0)) {
        return minizError(zip);
    }

    for (const auto& entry : entries) {
        if (!isSafeZipEntryName(entry.name)) {
            mz_zip_writer_end(&zip);
            std::filesystem::remove(zipPath, ec);
            return std::string("unsafe zip entry name: ") + entry.name;
        }
        const mz_uint level = entry.data.empty() ? 0 : MZ_DEFAULT_COMPRESSION;
        if (!mz_zip_writer_add_mem(&zip, entry.name.c_str(),
                                   entry.data.data(), entry.data.size(), level)) {
            const auto msg = minizError(zip);
            mz_zip_writer_end(&zip);
            std::filesystem::remove(zipPath, ec);
            return msg;
        }
    }

    if (!mz_zip_writer_finalize_archive(&zip)) {
        const auto msg = minizError(zip);
        mz_zip_writer_end(&zip);
        std::filesystem::remove(zipPath, ec);
        return msg;
    }
    if (!mz_zip_writer_end(&zip)) {
        std::filesystem::remove(zipPath, ec);
        return std::string("failed to close zip");
    }
    return std::nullopt;
}

std::optional<std::string> extractZipFile(const std::filesystem::path& zipPath,
                                          const std::filesystem::path& destDir) {
    mz_zip_archive zip;
    std::memset(&zip, 0, sizeof(zip));
    if (!mz_zip_reader_init_file(&zip, zipPath.string().c_str(), 0)) {
        return minizError(zip);
    }

    const mz_uint n = mz_zip_reader_get_num_files(&zip);
    std::vector<std::string> names;
    names.reserve(n);
    for (mz_uint i = 0; i < n; ++i) {
        mz_zip_archive_file_stat st;
        if (!mz_zip_reader_file_stat(&zip, i, &st)) {
            const auto msg = minizError(zip);
            mz_zip_reader_end(&zip);
            return msg;
        }
        const std::string name = st.m_filename;
        if (!isSafeZipEntryName(name)) {
            mz_zip_reader_end(&zip);
            return std::string("unsafe zip entry name: ") + name;
        }
        names.push_back(name);
    }

    std::error_code ec;
    std::filesystem::create_directories(destDir, ec);

    for (mz_uint i = 0; i < n; ++i) {
        const std::string& name = names[static_cast<size_t>(i)];
        const bool isDir = !name.empty() && name.back() == '/';
        const auto dest = destDir / name;
        const auto destNorm = dest.lexically_normal();
        const auto rootNorm = destDir.lexically_normal();
        auto rootPrefix = rootNorm.generic_string();
        if (!rootPrefix.empty() && rootPrefix.back() != '/') rootPrefix.push_back('/');
        const auto destStr = destNorm.generic_string();
        if (destStr != rootNorm.generic_string() && destStr.find(rootPrefix) != 0) {
            mz_zip_reader_end(&zip);
            return std::string("zip entry escaped destination: ") + name;
        }
        if (isDir) {
            std::filesystem::create_directories(dest, ec);
            continue;
        }
        std::filesystem::create_directories(dest.parent_path(), ec);
        if (!mz_zip_reader_extract_to_file(&zip, i, dest.string().c_str(), 0)) {
            const auto msg = minizError(zip);
            mz_zip_reader_end(&zip);
            return msg;
        }
    }

    mz_zip_reader_end(&zip);
    return std::nullopt;
}

std::optional<std::filesystem::path> findJournalJSON(const std::filesystem::path& directory) {
    std::error_code ec;
    if (!std::filesystem::exists(directory, ec)) return std::nullopt;
    const auto opts = std::filesystem::directory_options::skip_permission_denied;
    for (auto it = std::filesystem::recursive_directory_iterator(directory, opts, ec);
         it != std::filesystem::recursive_directory_iterator(); it.increment(ec)) {
        if (ec) break;
        const auto name = it->path().filename().string();
        if (isHiddenName(name)) {
            if (it->is_directory(ec)) it.disable_recursion_pending();
            continue;
        }
        if (it->is_regular_file(ec) && name == "journal.json") {
            return it->path();
        }
    }
    return std::nullopt;
}

} // namespace wick
