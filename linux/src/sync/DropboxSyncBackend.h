#pragma once

#include "JournalSyncBackend.h"
#include "SecretTokenStore.h"

#include <QByteArray>
#include <QString>
#include <QUrl>

#include <chrono>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

class QNetworkAccessManager;

namespace wick {

/// Dropbox API v2 backend: OAuth 2.0 PKCE + the four file operations the
/// sync engine needs. Qt Network lives here; the engine stays Qt-free.
class DropboxSyncBackend : public JournalSyncBackend {
public:
    static constexpr const char* kAppKey = "hm5yscsy9a11g0q";
    static constexpr const char* kCallbackScheme = "db-hm5yscsy9a11g0q";
    static constexpr const char* kRedirectURI = "db-hm5yscsy9a11g0q://2/token";

    struct Endpoints {
        QString authorize = QStringLiteral("https://www.dropbox.com/oauth2/authorize");
        QString token = QStringLiteral("https://api.dropboxapi.com/oauth2/token");
        QString apiHost = QStringLiteral("https://api.dropboxapi.com/2/");
        QString contentHost = QStringLiteral("https://content.dropboxapi.com/2/");
    };

    /// Platform hook: open the authorize URL and return the callback URL.
    /// Arguments: (authorizeURL, callbackScheme).
    using AuthSession = std::function<QUrl(const QUrl&, const QString&)>;

    explicit DropboxSyncBackend(std::shared_ptr<TokenStore> tokenStore = std::make_shared<SecretTokenStore>(),
                                QNetworkAccessManager* nam = nullptr);

    ~DropboxSyncBackend() override;

    void setAuthSession(AuthSession session) { authSession_ = std::move(session); }
    void setEndpoints(Endpoints e) { endpoints_ = std::move(e); }

    /// Test helper: skip OAuth and seed a live access token.
    /// `expiresIn` is the server's expires_in; locally we refresh 5 minutes early.
    void setAccessTokenForTest(std::string token, int expiresInSeconds = 4 * 3600);

    bool isAuthorized() const override;
    std::optional<std::string> accountEmail() const override { return accountEmail_; }

    std::string authorize() override;
    void signOut() override;

    std::pair<std::vector<RemoteFileMeta>, std::string>
    listChanges(const std::optional<std::string>& cursor) override;

    std::pair<std::string, std::string> download(const std::string& path) override;

    std::string upload(const std::string& path,
                       std::string_view data,
                       const std::optional<std::string>& ifRev) override;

    void deletePath(const std::string& path) override;

private:
    struct TokenResponse {
        std::string accessToken;
        std::optional<std::string> refreshToken;
        double expiresIn = 4 * 3600;
    };

    struct HttpResult {
        int status = 0;
        std::string body;
        std::string dropboxApiResult;
        std::optional<double> retryAfter;
        std::string errorString;
        bool transportFailed = false;
    };

    std::optional<std::string> storedRefreshToken() const;
    void apply(const TokenResponse& token);
    TokenResponse tokenRequest(const std::vector<std::pair<std::string, std::string>>& parameters);
    std::string validAccessToken();
    std::string fetchAccountEmail();

    HttpResult perform(const QString& url,
                       const QByteArray& method,
                       const std::vector<std::pair<QByteArray, QByteArray>>& headers,
                       const QByteArray& body);
    HttpResult performAuthorized(const std::function<HttpResult(const std::string& token)>& make);
    void validate(const HttpResult& http, const std::string& path) const;

    std::vector<RemoteFileMeta> parseEntries(const std::string& jsonText) const;
    std::string rpcCall(const std::string& path, const std::optional<std::string>& jsonBody);
    std::string continueListing(const std::string& cursor);
    static std::string apiArg(const std::string& jsonObject);

    std::shared_ptr<TokenStore> tokenStore_;
    QNetworkAccessManager* nam_ = nullptr;
    std::unique_ptr<QNetworkAccessManager> ownedNam_;
    AuthSession authSession_;
    Endpoints endpoints_;

    std::optional<std::string> accountEmail_;
    std::optional<std::string> accessToken_;
    std::optional<std::chrono::steady_clock::time_point> accessTokenExpiry_;
    mutable bool didProbeStore_ = false;
    mutable std::optional<std::string> cachedRefreshToken_;
};

} // namespace wick
