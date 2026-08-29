#include "DropboxSyncBackend.h"

#include "JournalModels.h"
#include "PKCE.h"

#include <QEventLoop>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QTimer>
#include <QUrlQuery>

#include <nlohmann/json.hpp>

#include <algorithm>
#include <utility>

namespace wick {
namespace {

using json = nlohmann::json;

QByteArray formEncode(const std::vector<std::pair<std::string, std::string>>& parameters) {
    QByteArray out;
    for (const auto& [k, v] : parameters) {
        if (!out.isEmpty())
            out += '&';
        out += QUrl::toPercentEncoding(QString::fromStdString(k));
        out += '=';
        out += QUrl::toPercentEncoding(QString::fromStdString(v));
    }
    return out;
}

std::string headerValue(QNetworkReply* reply, const QByteArray& name) {
    return QString::fromUtf8(reply->rawHeader(name)).toStdString();
}

} // namespace

DropboxSyncBackend::DropboxSyncBackend(std::shared_ptr<TokenStore> tokenStore,
                                       QNetworkAccessManager* nam)
    : tokenStore_(std::move(tokenStore))
{
    if (nam) {
        nam_ = nam;
    } else {
        ownedNam_ = std::make_unique<QNetworkAccessManager>();
        nam_ = ownedNam_.get();
    }
}

DropboxSyncBackend::~DropboxSyncBackend() = default;

void DropboxSyncBackend::setAccessTokenForTest(std::string token, int expiresInSeconds) {
    accessToken_ = std::move(token);
    const int skewed = std::max(0, expiresInSeconds - 300);
    accessTokenExpiry_ = std::chrono::steady_clock::now() + std::chrono::seconds(skewed);
}

bool DropboxSyncBackend::isAuthorized() const {
    return storedRefreshToken().has_value();
}

std::optional<std::string> DropboxSyncBackend::storedRefreshToken() const {
    if (!didProbeStore_) {
        didProbeStore_ = true;
        if (tokenStore_)
            cachedRefreshToken_ = tokenStore_->load();
    }
    return cachedRefreshToken_;
}

void DropboxSyncBackend::apply(const TokenResponse& token) {
    accessToken_ = token.accessToken;
    const int skewed = static_cast<int>(std::max(0.0, token.expiresIn - 300.0));
    accessTokenExpiry_ = std::chrono::steady_clock::now() + std::chrono::seconds(skewed);
    if (token.refreshToken) {
        if (tokenStore_)
            tokenStore_->save(*token.refreshToken);
        cachedRefreshToken_ = *token.refreshToken;
        didProbeStore_ = true;
    }
}

std::string DropboxSyncBackend::authorize() {
    if (!authSession_) {
        throw SyncBackendError::server(0, "auth session not configured");
    }
    const std::string verifier = PKCE::verifier();
    const std::string state = Uuid::generate().toString();

    QUrl url(endpoints_.authorize);
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("client_id"), QString::fromLatin1(kAppKey));
    query.addQueryItem(QStringLiteral("response_type"), QStringLiteral("code"));
    query.addQueryItem(QStringLiteral("redirect_uri"), QString::fromLatin1(kRedirectURI));
    query.addQueryItem(QStringLiteral("code_challenge"), QString::fromStdString(PKCE::challenge(verifier)));
    query.addQueryItem(QStringLiteral("code_challenge_method"), QStringLiteral("S256"));
    query.addQueryItem(QStringLiteral("token_access_type"), QStringLiteral("offline"));
    query.addQueryItem(QStringLiteral("state"), QString::fromStdString(state));
    url.setQuery(query);

    const QUrl callback = authSession_(url, QString::fromLatin1(kCallbackScheme));
    const QUrlQuery cbQuery(callback);
    const QString gotState = cbQuery.queryItemValue(QStringLiteral("state"));
    const QString code = cbQuery.queryItemValue(QStringLiteral("code"));
    if (gotState.toStdString() != state || code.isEmpty())
        throw SyncBackendError::authorizationCancelled();

    const auto token = tokenRequest({
        {"grant_type", "authorization_code"},
        {"code", code.toStdString()},
        {"redirect_uri", kRedirectURI},
        {"code_verifier", verifier},
        {"client_id", kAppKey},
    });
    apply(token);

    std::string email;
    try {
        email = fetchAccountEmail();
    } catch (...) {
        email.clear();
    }
    accountEmail_ = email;
    return email;
}

void DropboxSyncBackend::signOut() {
    cachedRefreshToken_.reset();
    accessToken_.reset();
    accessTokenExpiry_.reset();
    accountEmail_.reset();
    if (tokenStore_)
        tokenStore_->clear();
}

DropboxSyncBackend::TokenResponse DropboxSyncBackend::tokenRequest(
    const std::vector<std::pair<std::string, std::string>>& parameters) {
    const auto http = perform(endpoints_.token, "POST",
                              {{"Content-Type", "application/x-www-form-urlencoded"}},
                              formEncode(parameters));
    if (http.transportFailed)
        throw SyncBackendError::transport(http.errorString.empty() ? "no HTTP response" : http.errorString);
    if (http.status != 200) {
        if (http.body.find("invalid_grant") != std::string::npos)
            throw SyncBackendError::needsAuth();
        throw SyncBackendError::server(http.status, http.body);
    }
    json j;
    try {
        j = json::parse(http.body);
    } catch (...) {
        throw SyncBackendError::server(http.status, http.body);
    }
    if (!j.contains("access_token") || !j["access_token"].is_string()) {
        if (http.body.find("invalid_grant") != std::string::npos)
            throw SyncBackendError::needsAuth();
        throw SyncBackendError::server(http.status, http.body);
    }
    TokenResponse out;
    out.accessToken = j["access_token"].get<std::string>();
    if (j.contains("refresh_token") && j["refresh_token"].is_string())
        out.refreshToken = j["refresh_token"].get<std::string>();
    if (j.contains("expires_in") && j["expires_in"].is_number())
        out.expiresIn = j["expires_in"].get<double>();
    return out;
}

std::string DropboxSyncBackend::validAccessToken() {
    if (accessToken_ && accessTokenExpiry_ && std::chrono::steady_clock::now() < *accessTokenExpiry_)
        return *accessToken_;
    const auto refresh = storedRefreshToken();
    if (!refresh)
        throw SyncBackendError::needsAuth();
    try {
        const auto response = tokenRequest({
            {"grant_type", "refresh_token"},
            {"refresh_token", *refresh},
            {"client_id", kAppKey},
        });
        apply(response);
        return response.accessToken;
    } catch (const SyncBackendError& e) {
        if (e.kind == SyncBackendError::Kind::needsAuth)
            signOut();
        throw;
    }
}

std::string DropboxSyncBackend::fetchAccountEmail() {
    const auto body = rpcCall("users/get_current_account", std::nullopt);
    try {
        const auto j = json::parse(body);
        if (j.contains("email") && j["email"].is_string())
            return j["email"].get<std::string>();
    } catch (...) {
    }
    return {};
}

std::pair<std::vector<RemoteFileMeta>, std::string>
DropboxSyncBackend::listChanges(const std::optional<std::string>& cursor) {
    std::vector<RemoteFileMeta> collected;
    std::string nextCursor;

    if (!cursor) {
        const json firstBody = {
            {"path", ""},
            {"recursive", true},
            {"include_deleted", false},
            {"limit", 2000},
        };
        const auto firstText = rpcCall("files/list_folder", firstBody.dump());
        json first;
        try {
            first = json::parse(firstText);
        } catch (...) {
            throw SyncBackendError::server(200, "list_folder: unreadable response");
        }
        auto pageMetas = parseEntries(firstText);
        collected.insert(collected.end(), pageMetas.begin(), pageMetas.end());
        if (!first.contains("cursor") || !first["cursor"].is_string())
            throw SyncBackendError::server(200, "list_folder: missing cursor");
        nextCursor = first["cursor"].get<std::string>();
        bool hasMore = first.value("has_more", false);
        while (hasMore) {
            const auto pageText = continueListing(nextCursor);
            json page;
            try {
                page = json::parse(pageText);
            } catch (...) {
                throw SyncBackendError::server(200, "list_folder/continue: unreadable response");
            }
            auto metas = parseEntries(pageText);
            collected.insert(collected.end(), metas.begin(), metas.end());
            if (page.contains("cursor") && page["cursor"].is_string())
                nextCursor = page["cursor"].get<std::string>();
            hasMore = page.value("has_more", false);
        }
        return {collected, nextCursor};
    }

    nextCursor = *cursor;
    while (true) {
        const auto pageText = continueListing(nextCursor);
        json page;
        try {
            page = json::parse(pageText);
        } catch (...) {
            throw SyncBackendError::server(200, "list_folder/continue: unreadable response");
        }
        auto metas = parseEntries(pageText);
        collected.insert(collected.end(), metas.begin(), metas.end());
        if (page.contains("cursor") && page["cursor"].is_string())
            nextCursor = page["cursor"].get<std::string>();
        if (!page.value("has_more", false))
            break;
    }
    return {collected, nextCursor};
}

std::string DropboxSyncBackend::continueListing(const std::string& cursor) {
    const json body = {{"cursor", cursor}};
    try {
        return rpcCall("files/list_folder/continue", body.dump());
    } catch (const SyncBackendError& e) {
        if (e.kind == SyncBackendError::Kind::server && e.status == 409) {
            const std::string& message = e.what();
            if (message.find("reset") != std::string::npos
                || message.find("expired") != std::string::npos) {
                throw SyncBackendError::cursorExpired();
            }
        }
        throw;
    }
}

std::vector<RemoteFileMeta> DropboxSyncBackend::parseEntries(const std::string& jsonText) const {
    json j;
    try {
        j = json::parse(jsonText);
    } catch (...) {
        return {};
    }
    if (!j.contains("entries") || !j["entries"].is_array())
        return {};
    std::vector<RemoteFileMeta> out;
    for (const auto& entry : j["entries"]) {
        if (!entry.is_object())
            continue;
        std::string path;
        if (entry.contains("path_lower") && entry["path_lower"].is_string())
            path = entry["path_lower"].get<std::string>();
        else if (entry.contains("path_display") && entry["path_display"].is_string())
            path = entry["path_display"].get<std::string>();
        else
            continue;
        const std::string tag = entry.value(".tag", "");
        if (tag == "file") {
            RemoteFileMeta m;
            m.path = std::move(path);
            if (entry.contains("rev") && entry["rev"].is_string())
                m.rev = entry["rev"].get<std::string>();
            if (entry.contains("content_hash") && entry["content_hash"].is_string())
                m.contentHash = entry["content_hash"].get<std::string>();
            out.push_back(std::move(m));
        } else if (tag == "deleted") {
            RemoteFileMeta m;
            m.path = std::move(path);
            m.isDeleted = true;
            out.push_back(std::move(m));
        }
    }
    return out;
}

std::pair<std::string, std::string> DropboxSyncBackend::download(const std::string& path) {
    const json arg = {{"path", path}};
    const auto http = performAuthorized([&](const std::string& token) {
        return perform(endpoints_.contentHost + QStringLiteral("files/download"), "POST",
                       {{"Authorization", QByteArray("Bearer ") + QByteArray::fromStdString(token)},
                        {"Content-Type", "application/octet-stream"},
                        {"Dropbox-API-Arg", QByteArray::fromStdString(apiArg(arg.dump()))}},
                       {});
    });
    validate(http, path);
    std::string rev;
    if (!http.dropboxApiResult.empty()) {
        try {
            const auto j = json::parse(http.dropboxApiResult);
            if (j.contains("rev") && j["rev"].is_string())
                rev = j["rev"].get<std::string>();
        } catch (...) {
        }
    }
    return {http.body, rev};
}

std::string DropboxSyncBackend::upload(const std::string& path,
                                       std::string_view data,
                                       const std::optional<std::string>& ifRev) {
    json mode;
    if (ifRev) {
        mode = {{".tag", "update"}, {"update", *ifRev}};
    } else {
        mode = {{".tag", "add"}};
    }
    const json arg = {
        {"path", path},
        {"mode", mode},
        {"autorename", false},
        {"mute", true},
    };
    const auto http = performAuthorized([&](const std::string& token) {
        return perform(endpoints_.contentHost + QStringLiteral("files/upload"), "POST",
                       {{"Authorization", QByteArray("Bearer ") + QByteArray::fromStdString(token)},
                        {"Content-Type", "application/octet-stream"},
                        {"Dropbox-API-Arg", QByteArray::fromStdString(apiArg(arg.dump()))}},
                       QByteArray(data.data(), static_cast<int>(data.size())));
    });
    try {
        validate(http, path);
    } catch (const SyncBackendError& e) {
        if (e.kind == SyncBackendError::Kind::server && e.status == 409) {
            const std::string& message = e.what();
            if (message.find("conflict") != std::string::npos)
                throw SyncBackendError::writeConflict(path);
        }
        throw;
    }
    json j;
    try {
        j = json::parse(http.body);
    } catch (...) {
        throw SyncBackendError::server(200, "upload: missing rev");
    }
    if (!j.contains("rev") || !j["rev"].is_string())
        throw SyncBackendError::server(200, "upload: missing rev");
    return j["rev"].get<std::string>();
}

void DropboxSyncBackend::deletePath(const std::string& path) {
    const json body = {{"path", path}};
    try {
        (void)rpcCall("files/delete_v2", body.dump());
    } catch (const SyncBackendError& e) {
        if (e.kind == SyncBackendError::Kind::server && e.status == 409) {
            const std::string& message = e.what();
            if (message.find("not_found") != std::string::npos)
                return;
        }
        throw;
    }
}

std::string DropboxSyncBackend::rpcCall(const std::string& path, const std::optional<std::string>& jsonBody) {
    const QByteArray body = jsonBody ? QByteArray::fromStdString(*jsonBody) : QByteArray("null");
    const auto http = performAuthorized([&](const std::string& token) {
        return perform(endpoints_.apiHost + QString::fromStdString(path), "POST",
                       {{"Authorization", QByteArray("Bearer ") + QByteArray::fromStdString(token)},
                        {"Content-Type", "application/json"}},
                       body);
    });
    validate(http, path);
    json j;
    try {
        j = json::parse(http.body);
    } catch (...) {
        throw SyncBackendError::server(200, path + ": unreadable response");
    }
    if (!j.is_object())
        throw SyncBackendError::server(200, path + ": unreadable response");
    return http.body;
}

std::string DropboxSyncBackend::apiArg(const std::string& jsonObject) {
    return jsonObject;
}

DropboxSyncBackend::HttpResult DropboxSyncBackend::perform(
    const QString& url,
    const QByteArray& method,
    const std::vector<std::pair<QByteArray, QByteArray>>& headers,
    const QByteArray& body) {
    HttpResult out;
    if (!nam_) {
        out.transportFailed = true;
        out.errorString = "no network manager";
        return out;
    }
    QNetworkRequest req{QUrl(url)};
    req.setTransferTimeout(30000);
    for (const auto& [k, v] : headers)
        req.setRawHeader(k, v);

    QNetworkReply* reply = nam_->sendCustomRequest(req, method, body);
    QEventLoop loop;
    QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    loop.exec();

    if (reply->error() == QNetworkReply::TimeoutError
        || reply->error() == QNetworkReply::ConnectionRefusedError
        || reply->error() == QNetworkReply::HostNotFoundError
        || reply->error() == QNetworkReply::SslHandshakeFailedError
        || reply->error() == QNetworkReply::UnknownNetworkError
        || reply->error() == QNetworkReply::TemporaryNetworkFailureError
        || reply->error() == QNetworkReply::NetworkSessionFailedError
        || reply->error() == QNetworkReply::RemoteHostClosedError
        || reply->error() == QNetworkReply::OperationCanceledError) {
        // HTTP status errors (401/409/429) also set QNetworkReply::error, so only
        // treat true transport failures when there is no HTTP status.
        const QVariant statusVar = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute);
        if (!statusVar.isValid()) {
            out.transportFailed = true;
            out.errorString = reply->errorString().toStdString();
            reply->deleteLater();
            return out;
        }
    }

    out.status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    out.body = reply->readAll().toStdString();
    out.dropboxApiResult = headerValue(reply, "Dropbox-API-Result");
    const QByteArray retry = reply->rawHeader("Retry-After");
    if (!retry.isEmpty()) {
        bool ok = false;
        const double seconds = QString::fromUtf8(retry).toDouble(&ok);
        if (ok)
            out.retryAfter = seconds;
    }
    if (out.status == 0 && reply->error() != QNetworkReply::NoError) {
        out.transportFailed = true;
        out.errorString = reply->errorString().toStdString();
    }
    reply->deleteLater();
    return out;
}

DropboxSyncBackend::HttpResult DropboxSyncBackend::performAuthorized(
    const std::function<HttpResult(const std::string& token)>& make) {
    std::string token = validAccessToken();
    bool didRefresh = false;
    while (true) {
        HttpResult http = make(token);
        if (http.transportFailed)
            throw SyncBackendError::transport(http.errorString.empty() ? "no HTTP response" : http.errorString);
        if (http.status != 401)
            return http;
        if (didRefresh)
            throw SyncBackendError::needsAuth();
        accessToken_.reset();
        accessTokenExpiry_.reset();
        token = validAccessToken();
        didRefresh = true;
    }
}

void DropboxSyncBackend::validate(const HttpResult& http, const std::string& path) const {
    (void)path;
    if (http.transportFailed)
        throw SyncBackendError::transport(http.errorString.empty() ? "no HTTP response" : http.errorString);
    if (http.status >= 200 && http.status <= 299)
        return;
    if (http.status == 401)
        throw SyncBackendError::needsAuth();
    if (http.status == 429)
        throw SyncBackendError::rateLimited(http.retryAfter);
    throw SyncBackendError::server(http.status, http.body);
}

} // namespace wick
