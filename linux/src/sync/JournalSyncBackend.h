#pragma once

#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace wick {

struct RemoteFileMeta {
    std::string path; // lowercased key
    std::optional<std::string> rev;
    std::optional<std::string> contentHash;
    bool isDeleted = false;
};

class SyncBackendError : public std::runtime_error {
public:
    enum class Kind {
        needsAuth,
        authorizationCancelled,
        writeConflict,
        cursorExpired,
        rateLimited,
        server,
        transport
    };

    Kind kind;
    std::string path;
    int status = 0;
    std::optional<double> retryAfter;

    explicit SyncBackendError(Kind k, std::string message, std::string path = {}, int status = 0)
        : std::runtime_error(std::move(message))
        , kind(k)
        , path(std::move(path))
        , status(status) {}

    static SyncBackendError needsAuth() {
        return SyncBackendError(Kind::needsAuth, "needsAuth");
    }
    static SyncBackendError authorizationCancelled() {
        return SyncBackendError(Kind::authorizationCancelled, "authorizationCancelled");
    }
    static SyncBackendError writeConflict(std::string p) {
        return SyncBackendError(Kind::writeConflict, "writeConflict:" + p, std::move(p));
    }
    static SyncBackendError cursorExpired() {
        return SyncBackendError(Kind::cursorExpired, "cursorExpired");
    }
    static SyncBackendError rateLimited(std::optional<double> after = std::nullopt) {
        auto e = SyncBackendError(Kind::rateLimited, "rateLimited");
        e.retryAfter = after;
        return e;
    }
    static SyncBackendError server(int status, std::string message) {
        return SyncBackendError(Kind::server, std::move(message), {}, status);
    }
    static SyncBackendError transport(std::string message) {
        return SyncBackendError(Kind::transport, std::move(message));
    }

    bool operator==(const SyncBackendError& o) const {
        return kind == o.kind && path == o.path && status == o.status;
    }
};

class JournalSyncBackend {
public:
    virtual ~JournalSyncBackend() = default;

    virtual bool isAuthorized() const = 0;
    virtual std::optional<std::string> accountEmail() const = 0;

    virtual std::string authorize() = 0;
    virtual void signOut() = 0;

    virtual std::pair<std::vector<RemoteFileMeta>, std::string>
    listChanges(const std::optional<std::string>& cursor) = 0;

    virtual std::pair<std::string, std::string> download(const std::string& path) = 0;

    // ifRev == nullopt is add-only; exists → writeConflict
    virtual std::string upload(const std::string& path,
                               std::string_view data,
                               const std::optional<std::string>& ifRev) = 0;

    // Missing paths are treated as already deleted.
    virtual void deletePath(const std::string& path) = 0;
};

} // namespace wick
