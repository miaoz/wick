#include "SecretTokenStore.h"

#include "JournalPaths.h"

#include <nlohmann/json.hpp>

#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <system_error>

#ifdef WICK_HAVE_LIBSECRET
#include <libsecret/secret.h>
#endif

namespace wick {
namespace {

std::filesystem::path devSecretsPath() {
    auto journals = JournalPaths::defaultPaths().librariesRoot;
    return journals.parent_path() / "dev-secrets.json";
}

std::string mapKey(const std::string& service, const std::string& account) {
    return service + "\n" + account;
}

nlohmann::json readMap(const std::filesystem::path& path) {
    std::error_code ec;
    if (!std::filesystem::exists(path, ec))
        return nlohmann::json::object();
    std::ifstream in(path);
    if (!in)
        return nlohmann::json::object();
    try {
        nlohmann::json j;
        in >> j;
        if (j.is_object())
            return j;
    } catch (...) {
    }
    return nlohmann::json::object();
}

void writeMap(const std::filesystem::path& path, const nlohmann::json& map) {
    std::error_code ec;
    std::filesystem::create_directories(path.parent_path(), ec);
    const auto tmp = path.string() + ".tmp";
    {
        std::ofstream out(tmp, std::ios::binary | std::ios::trunc);
        if (!out)
            throw std::runtime_error("cannot write " + path.string());
        out << map.dump(2) << '\n';
    }
    std::filesystem::rename(tmp, path, ec);
    if (ec)
        throw std::runtime_error("cannot replace " + path.string() + ": " + ec.message());
    std::filesystem::permissions(path,
                                 std::filesystem::perms::owner_read | std::filesystem::perms::owner_write,
                                 std::filesystem::perm_options::replace, ec);
}

std::optional<std::string> loadDev(const std::string& service, const std::string& account) {
    const auto j = readMap(devSecretsPath());
    const auto key = mapKey(service, account);
    if (!j.contains(key) || !j[key].is_string())
        return std::nullopt;
    return j[key].get<std::string>();
}

void saveDev(const std::string& service, const std::string& account, const std::string& token) {
    auto j = readMap(devSecretsPath());
    j[mapKey(service, account)] = token;
    writeMap(devSecretsPath(), j);
}

void clearDev(const std::string& service, const std::string& account) {
    auto j = readMap(devSecretsPath());
    j.erase(mapKey(service, account));
    writeMap(devSecretsPath(), j);
}

[[maybe_unused]] [[noreturn]] static void throwCannotStore(const std::string& detail) {
    throw std::runtime_error(
        "Cannot store Dropbox refresh token (" + detail
        + "). Install/start libsecret (gnome-keyring or KWallet), or set WICK_DEV_SECRETS=1 "
          "for a 0600 file at ~/.local/share/wick/dev-secrets.json. The token is never written to QSettings.");
}

#ifdef WICK_HAVE_LIBSECRET

const SecretSchema& schema() {
    static const SecretSchema s = {
        "com.miaoz.wick",
        SECRET_SCHEMA_NONE,
        {
            {"service", SECRET_SCHEMA_ATTRIBUTE_STRING},
            {"account", SECRET_SCHEMA_ATTRIBUTE_STRING},
            {nullptr, static_cast<SecretSchemaAttributeType>(0)},
        },
        0,                                   // reserved (gint)
        nullptr, nullptr, nullptr, nullptr,  // reserved1 .. reserved4
        nullptr, nullptr, nullptr,           // reserved5 .. reserved7
    };
    return s;
}

#endif

} // namespace

SecretTokenStore::SecretTokenStore(std::string service, std::string account, std::string displayName)
    : service_(std::move(service))
    , account_(std::move(account))
    , displayName_(std::move(displayName)) {}

bool SecretTokenStore::devSecretsEnabled() {
    const char* e = std::getenv("WICK_DEV_SECRETS");
    return e && e[0] == '1' && e[1] == '\0';
}

bool SecretTokenStore::libsecretCompiled() {
#ifdef WICK_HAVE_LIBSECRET
    return true;
#else
    return false;
#endif
}

std::optional<std::string> SecretTokenStore::load() const {
    if (devSecretsEnabled())
        return loadDev(service_, account_);

#ifdef WICK_HAVE_LIBSECRET
    GError* error = nullptr;
    gchar* password = secret_password_lookup_sync(&schema(), nullptr, &error,
                                                  "service", service_.c_str(),
                                                  "account", account_.c_str(),
                                                  nullptr);
    if (error) {
        g_error_free(error);
        return loadDev(service_, account_);
    }
    if (!password)
        return loadDev(service_, account_);
    std::string out(password);
    secret_password_free(password);
    return out;
#else
    return loadDev(service_, account_);
#endif
}

void SecretTokenStore::save(const std::string& token) {
    if (devSecretsEnabled()) {
        saveDev(service_, account_, token);
        return;
    }

#ifdef WICK_HAVE_LIBSECRET
    GError* error = nullptr;
    const gboolean ok = secret_password_store_sync(&schema(), SECRET_COLLECTION_DEFAULT,
                                                   displayName_.c_str(), token.c_str(),
                                                   nullptr, &error,
                                                   "service", service_.c_str(),
                                                   "account", account_.c_str(),
                                                   nullptr);
    if (error) {
        g_error_free(error);
        saveDev(service_, account_, token);
        return;
    }
    if (!ok) {
        saveDev(service_, account_, token);
        return;
    }
    // Verify the store really persisted: a Secret Service daemon can ack a
    // store yet never write it through (e.g. restarted mid-session with a
    // stale in-memory keyring), silently stranding the account on next
    // launch. Fall back to the dev file when the round-trip fails.
    {
        GError* verifyError = nullptr;
        gchar* readBack = secret_password_lookup_sync(&schema(), nullptr, &verifyError,
                                                      "service", service_.c_str(),
                                                      "account", account_.c_str(),
                                                      nullptr);
        const bool verified = !verifyError && readBack && token == readBack;
        if (verifyError)
            g_error_free(verifyError);
        if (readBack)
            secret_password_free(readBack);
        if (!verified) {
            std::fprintf(stderr,
                         "Wick: secret store write did not round-trip; using dev-secrets fallback\n");
            saveDev(service_, account_, token);
            return;
        }
    }
    // Single source of truth: a stale dev copy must not outlive a verified
    // keyring store, or load() could resurrect an old token after a keyring
    // loss.
    clearDev(service_, account_);
#else
    saveDev(service_, account_, token);
#endif
}

void SecretTokenStore::clear() {
    clearDev(service_, account_);
#ifdef WICK_HAVE_LIBSECRET
    GError* error = nullptr;
    secret_password_clear_sync(&schema(), nullptr, &error,
                               "service", service_.c_str(),
                               "account", account_.c_str(),
                               nullptr);
    if (error)
        g_error_free(error);
#endif
}

} // namespace wick
