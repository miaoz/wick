#include "FakeSyncBackend.h"

#include <openssl/sha.h>

#include <algorithm>
#include <cctype>

namespace wick {
namespace {

std::string lowerPath(std::string path) {
    for (char& c : path) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return path;
}

std::string sha256Hex(const unsigned char* data, size_t n) {
    unsigned char digest[SHA256_DIGEST_LENGTH];
    SHA256(data, n, digest);
    static constexpr char kHex[] = "0123456789abcdef";
    std::string hex(SHA256_DIGEST_LENGTH * 2, '0');
    for (int i = 0; i < SHA256_DIGEST_LENGTH; ++i) {
        hex[static_cast<size_t>(i) * 2] = kHex[digest[i] >> 4];
        hex[static_cast<size_t>(i) * 2 + 1] = kHex[digest[i] & 0x0f];
    }
    return hex;
}

} // namespace

std::string dropboxStyleContentHash(std::string_view data) {
    constexpr size_t blockSize = 4 * 1024 * 1024;
    std::string digests;
    if (data.empty()) {
        unsigned char digest[SHA256_DIGEST_LENGTH];
        SHA256(reinterpret_cast<const unsigned char*>(data.data()), 0, digest);
        digests.assign(reinterpret_cast<char*>(digest), SHA256_DIGEST_LENGTH);
    } else {
        size_t offset = 0;
        while (offset < data.size()) {
            const size_t end = std::min(offset + blockSize, data.size());
            unsigned char digest[SHA256_DIGEST_LENGTH];
            SHA256(reinterpret_cast<const unsigned char*>(data.data() + offset), end - offset, digest);
            digests.append(reinterpret_cast<char*>(digest), SHA256_DIGEST_LENGTH);
            offset = end;
        }
    }
    unsigned char out[SHA256_DIGEST_LENGTH];
    SHA256(reinterpret_cast<const unsigned char*>(digests.data()), digests.size(), out);
    static constexpr char kHex[] = "0123456789abcdef";
    std::string hex(SHA256_DIGEST_LENGTH * 2, '0');
    for (int i = 0; i < SHA256_DIGEST_LENGTH; ++i) {
        hex[static_cast<size_t>(i) * 2] = kHex[out[i] >> 4];
        hex[static_cast<size_t>(i) * 2 + 1] = kHex[out[i] & 0x0f];
    }
    return hex;
}

std::string FakeSyncBackend::authorize() { authorized = true; return "fake@example.com"; }

std::pair<std::vector<RemoteFileMeta>, std::string>
FakeSyncBackend::listChanges(const std::optional<std::string>& cursor) {
    if (onListChanges) {
        auto cb = std::move(onListChanges);
        onListChanges = nullptr;
        cb();
    }
    if (cursor) {
        if (failNextIncremental) {
            auto err = *failNextIncremental;
            failNextIncremental.reset();
            throw err;
        }
        int sinceVersion = 0;
        if (cursor->size() > 1 && (*cursor)[0] == 'v') {
            try {
                sinceVersion = std::stoi(cursor->substr(1));
            } catch (...) {
                sinceVersion = 0;
            }
        }
        std::vector<RemoteFileMeta> metas;
        for (const auto& c : changeLog_) {
            if (c.version > sinceVersion) metas.push_back(c.meta);
        }
        return {metas, "v" + std::to_string(version_)};
    }
    std::vector<RemoteFileMeta> metas;
    for (const auto& [path, file] : files_) {
        RemoteFileMeta m;
        m.path = path;
        m.rev = file.rev;
        m.contentHash = dropboxStyleContentHash(file.data);
        metas.push_back(std::move(m));
    }
    return {metas, "v" + std::to_string(version_)};
}

std::pair<std::string, std::string> FakeSyncBackend::download(const std::string& path) {
    ++downloadCount;
    const auto key = lowerPath(path);
    auto it = files_.find(key);
    if (it == files_.end()) {
        throw SyncBackendError::server(409, "path/not_found/");
    }
    return {it->second.data, it->second.rev};
}

std::string FakeSyncBackend::upload(const std::string& path,
                                    std::string_view data,
                                    const std::optional<std::string>& ifRev) {
    ++uploadCount;
    const auto key = lowerPath(path);
    if (failNextEntryUpload && key.find("/entries/") != std::string::npos) {
        auto err = *failNextEntryUpload;
        failNextEntryUpload.reset();
        throw err;
    }
    auto it = files_.find(key);
    if (it != files_.end()) {
        if (!ifRev || *ifRev != it->second.rev) {
            throw SyncBackendError::writeConflict(key);
        }
    }
    ++revCounter_;
    const std::string rev = "r" + std::to_string(revCounter_);
    files_[key] = StoredFile{std::string(data), rev};
    RemoteFileMeta meta;
    meta.path = key;
    meta.rev = rev;
    meta.contentHash = dropboxStyleContentHash(data);
    log(meta);
    return rev;
}

void FakeSyncBackend::deletePath(const std::string& path) {
    const auto key = lowerPath(path);
    std::vector<std::string> doomed;
    for (const auto& [p, _] : files_) {
        if (p == key || p.find(key + "/") == 0) doomed.push_back(p);
    }
    if (doomed.empty()) return;
    for (const auto& existing : doomed) {
        files_.erase(existing);
        RemoteFileMeta meta;
        meta.path = existing;
        meta.isDeleted = true;
        log(meta);
    }
}

std::optional<std::string> FakeSyncBackend::fileData(const std::string& path) const {
    auto it = files_.find(lowerPath(path));
    if (it == files_.end()) return std::nullopt;
    return it->second.data;
}

bool FakeSyncBackend::hasFile(const std::string& path) const {
    return files_.count(lowerPath(path)) > 0;
}

std::vector<std::string> FakeSyncBackend::allPaths() const {
    std::vector<std::string> out;
    out.reserve(files_.size());
    for (const auto& [p, _] : files_) out.push_back(p);
    return out;
}

void FakeSyncBackend::seedFile(const std::string& path, std::string_view data) {
    ++revCounter_;
    const std::string rev = "r" + std::to_string(revCounter_);
    const auto key = lowerPath(path);
    files_[key] = StoredFile{std::string(data), rev};
    RemoteFileMeta meta;
    meta.path = key;
    meta.rev = rev;
    meta.contentHash = dropboxStyleContentHash(data);
    log(meta);
}

void FakeSyncBackend::log(const RemoteFileMeta& meta) {
    ++version_;
    changeLog_.push_back(Change{version_, meta});
}

} // namespace wick
