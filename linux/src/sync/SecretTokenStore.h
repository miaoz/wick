#pragma once

#include <memory>
#include <optional>
#include <string>

namespace wick {

/// Abstract secret store used by DropboxSyncBackend (refresh token).
class TokenStore {
public:
    virtual ~TokenStore() = default;
    virtual std::optional<std::string> load() const = 0;
    virtual void save(const std::string& token) = 0;
    virtual void clear() = 0;
};

/// In-memory store for tests. Never touches disk or libsecret.
class MemoryTokenStore : public TokenStore {
public:
    std::optional<std::string> load() const override { return token_; }
    void save(const std::string& token) override { token_ = token; }
    void clear() override { token_.reset(); }

private:
    std::optional<std::string> token_;
};

/// libsecret-backed store. Schema `com.miaoz.wick`, Mac-equivalent
/// service `com.miaoz.wick.dropbox` / account `refresh-token`.
///
/// If `WICK_DEV_SECRETS=1`, persists to `~/.local/share/wick/dev-secrets.json`
/// mode 0600 (Mac unpackaged fallback). Never writes the token to QSettings.
///
/// If libsecret is missing at compile-time or the Secret Service is down at
/// runtime, save() throws with a clear message unless the dev-secrets env is set.
class SecretTokenStore : public TokenStore {
public:
    static constexpr const char* kSchemaName = "com.miaoz.wick";
    static constexpr const char* kDefaultService = "com.miaoz.wick.dropbox";
    static constexpr const char* kDefaultAccount = "refresh-token";

    explicit SecretTokenStore(std::string service = kDefaultService,
                              std::string account = kDefaultAccount,
                              std::string displayName = "Wick secret");

    std::optional<std::string> load() const override;
    void save(const std::string& token) override;
    void clear() override;

    static bool devSecretsEnabled();
    static bool libsecretCompiled();

private:
    std::string service_;
    std::string account_;
    std::string displayName_;
};

} // namespace wick
