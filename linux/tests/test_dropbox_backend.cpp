#include "DropboxSyncBackend.h"
#include "SecretTokenStore.h"

#include <QCoreApplication>
#include <QHostAddress>
#include <QTcpServer>
#include <QTcpSocket>
#include <QUrlQuery>

#include <functional>
#include <iostream>
#include <map>
#include <memory>
#include <string>
#include <vector>

using namespace wick;

static int g_fails = 0;
static int g_passes = 0;

#define CHECK(cond)                                                                          \
    do {                                                                                     \
        if (!(cond)) {                                                                       \
            std::cerr << "FAIL " << __FILE__ << ":" << __LINE__ << " : " << #cond << "\n"; \
            ++g_fails;                                                                       \
        } else {                                                                             \
            ++g_passes;                                                                      \
        }                                                                                    \
    } while (0)

struct HttpReq {
    QByteArray method;
    QByteArray path;
    std::map<QByteArray, QByteArray> headers;
    QByteArray body;
};

struct HttpResp {
    int status = 200;
    QByteArray body;
    std::vector<std::pair<QByteArray, QByteArray>> headers;
};

class FakeHttpServer : public QObject {
public:
    std::function<HttpResp(const HttpReq&)> handler;
    std::vector<HttpReq> log;

    bool start() {
        return server_.listen(QHostAddress::LocalHost, 0);
    }
    quint16 port() const { return server_.serverPort(); }
    QString origin() const {
        return QStringLiteral("http://127.0.0.1:%1").arg(port());
    }

    FakeHttpServer() {
        QObject::connect(&server_, &QTcpServer::newConnection, this, [this]() {
            while (server_.hasPendingConnections())
                serve(server_.nextPendingConnection());
        });
    }

private:
    QTcpServer server_;

    static bool parseRequest(const QByteArray& buf, HttpReq& req, int& consumed) {
        const int hdrEnd = buf.indexOf("\r\n\r\n");
        if (hdrEnd < 0)
            return false;
        const QByteArray head = buf.left(hdrEnd);
        const QList<QByteArray> lines = head.split('\n');
        if (lines.isEmpty())
            return false;
        const QByteArray first = lines[0].trimmed();
        const int sp1 = first.indexOf(' ');
        const int sp2 = first.indexOf(' ', sp1 + 1);
        if (sp1 < 0 || sp2 < 0)
            return false;
        req.method = first.left(sp1);
        req.path = first.mid(sp1 + 1, sp2 - sp1 - 1);
        for (int i = 1; i < lines.size(); ++i) {
            QByteArray line = lines[i].trimmed();
            const int c = line.indexOf(':');
            if (c < 0)
                continue;
            req.headers[line.left(c).trimmed().toLower()] = line.mid(c + 1).trimmed();
        }
        int len = 0;
        auto it = req.headers.find("content-length");
        if (it != req.headers.end())
            len = it->second.toInt();
        if (buf.size() < hdrEnd + 4 + len)
            return false;
        req.body = buf.mid(hdrEnd + 4, len);
        consumed = hdrEnd + 4 + len;
        return true;
    }

    void reply(QTcpSocket* sock, const HttpResp& resp) {
        QByteArray out;
        out += "HTTP/1.1 " + QByteArray::number(resp.status) + " X\r\n";
        bool hasLen = false;
        bool hasConn = false;
        for (const auto& [k, v] : resp.headers) {
            out += k + ": " + v + "\r\n";
            if (k.toLower() == "content-length")
                hasLen = true;
            if (k.toLower() == "connection")
                hasConn = true;
        }
        if (!hasLen)
            out += "Content-Length: " + QByteArray::number(resp.body.size()) + "\r\n";
        if (!hasConn)
            out += "Connection: close\r\n";
        out += "\r\n";
        out += resp.body;
        sock->write(out);
        sock->flush();
        sock->disconnectFromHost();
    }

    void serve(QTcpSocket* sock) {
        sock->setParent(this);
        auto* acc = new QByteArray;
        QObject::connect(sock, &QTcpSocket::disconnected, this, [sock, acc]() {
            delete acc;
            sock->deleteLater();
        });
        QObject::connect(sock, &QTcpSocket::readyRead, this, [this, sock, acc]() {
            acc->append(sock->readAll());
            HttpReq req;
            int consumed = 0;
            if (!parseRequest(*acc, req, consumed))
                return;
            acc->remove(0, consumed);
            log.push_back(req);
            HttpResp resp;
            try {
                resp = handler ? handler(req) : HttpResp{};
            } catch (...) {
                resp.status = 500;
                resp.body = "handler threw";
            }
            reply(sock, resp);
        });
    }
};

static std::unique_ptr<DropboxSyncBackend> makeBackend(FakeHttpServer& http,
                                                       std::shared_ptr<MemoryTokenStore> store) {
    auto b = std::make_unique<DropboxSyncBackend>(store);
    DropboxSyncBackend::Endpoints e;
    e.token = http.origin() + QStringLiteral("/oauth2/token");
    e.apiHost = http.origin() + QStringLiteral("/api/2/");
    e.contentHost = http.origin() + QStringLiteral("/content/2/");
    e.authorize = http.origin() + QStringLiteral("/oauth2/authorize");
    b->setEndpoints(e);
    store->save("refresh-seed");
    b->setAccessTokenForTest("access-live", 4 * 3600);
    return b;
}

static bool threwKind(SyncBackendError::Kind k, const std::function<void()>& fn) {
    try {
        fn();
        return false;
    } catch (const SyncBackendError& e) {
        return e.kind == k;
    } catch (...) {
        return false;
    }
}

int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);

    {
        FakeHttpServer http;
        CHECK(http.start());
        auto store = std::make_shared<MemoryTokenStore>();
        auto b = makeBackend(http, store);

        http.handler = [](const HttpReq& req) {
            HttpResp r;
            if (req.path == "/content/2/files/upload") {
                r.status = 409;
                r.body = "{\"error_summary\":\"path/conflict/file/\"}";
                return r;
            }
            r.status = 500;
            r.body = "unexpected " + req.path;
            return r;
        };
        CHECK(threwKind(SyncBackendError::Kind::writeConflict, [&]() {
            b->upload("/journals/x.json", "data", std::nullopt);
        }));
        CHECK(!http.log.empty());
        const auto& up = http.log.back();
        CHECK(up.headers.at("dropbox-api-arg").contains("\"mode\":{\".tag\":\"add\"}")
              || up.headers.at("dropbox-api-arg").contains("\"mode\":{\".tag\":\"add\""));
    }

    {
        FakeHttpServer http;
        CHECK(http.start());
        auto store = std::make_shared<MemoryTokenStore>();
        auto b = makeBackend(http, store);
        http.handler = [](const HttpReq& req) {
            HttpResp r;
            if (req.path == "/content/2/files/upload") {
                r.status = 200;
                r.body = "{\"rev\":\"rev2\"}";
                return r;
            }
            r.status = 500;
            return r;
        };
        const auto rev = b->upload("/journals/x.json", "data", std::string("rev1"));
        CHECK(rev == "rev2");
        CHECK(http.log.back().headers.at("dropbox-api-arg").contains("\"update\":\"rev1\""));
        CHECK(http.log.back().headers.at("dropbox-api-arg").contains("\"mute\":true"));
        CHECK(http.log.back().headers.at("dropbox-api-arg").contains("\"autorename\":false"));
    }

    {
        FakeHttpServer http;
        CHECK(http.start());
        auto store = std::make_shared<MemoryTokenStore>();
        auto b = makeBackend(http, store);
        http.handler = [](const HttpReq&) {
            HttpResp r;
            r.status = 409;
            r.body = "{\"error_summary\":\"path/not_found/\"}";
            return r;
        };
        try {
            b->deletePath("/gone.json");
            CHECK(true);
        } catch (...) {
            CHECK(false);
        }
    }

    {
        FakeHttpServer http;
        CHECK(http.start());
        auto store = std::make_shared<MemoryTokenStore>();
        auto b = makeBackend(http, store);
        http.handler = [](const HttpReq&) {
            HttpResp r;
            r.status = 409;
            r.body = "{\"error_summary\":\"reset/\"}";
            return r;
        };
        CHECK(threwKind(SyncBackendError::Kind::cursorExpired, [&]() {
            b->listChanges(std::string("stale-cursor"));
        }));
    }

    {
        FakeHttpServer http;
        CHECK(http.start());
        auto store = std::make_shared<MemoryTokenStore>();
        auto b = makeBackend(http, store);
        http.handler = [](const HttpReq&) {
            HttpResp r;
            r.status = 429;
            r.headers.push_back({"Retry-After", "7"});
            r.body = "slow down";
            return r;
        };
        try {
            b->listChanges(std::nullopt);
            CHECK(false);
        } catch (const SyncBackendError& e) {
            CHECK(e.kind == SyncBackendError::Kind::rateLimited);
            CHECK(e.retryAfter.has_value());
            CHECK(*e.retryAfter == 7.0);
        }
    }

    {
        FakeHttpServer http;
        CHECK(http.start());
        auto store = std::make_shared<MemoryTokenStore>();
        auto b = makeBackend(http, store);
        int apiHits = 0;
        int tokenHits = 0;
        http.handler = [&](const HttpReq& req) {
            HttpResp r;
            if (req.path == "/oauth2/token") {
                ++tokenHits;
                r.body = "{\"access_token\":\"access-fresh\",\"expires_in\":14400}";
                return r;
            }
            ++apiHits;
            const QByteArray auth = req.headers.count("authorization") ? req.headers.at("authorization") : QByteArray();
            if (auth == "Bearer access-live") {
                r.status = 401;
                r.body = "expired_access_token";
                return r;
            }
            r.body = "{\"entries\":[],\"cursor\":\"c1\",\"has_more\":false}";
            return r;
        };
        auto [entries, cursor] = b->listChanges(std::nullopt);
        CHECK(cursor == "c1");
        CHECK(apiHits == 2);
        CHECK(tokenHits == 1);
        CHECK(entries.empty());
    }

    {
        FakeHttpServer http;
        CHECK(http.start());
        auto store = std::make_shared<MemoryTokenStore>();
        auto b = makeBackend(http, store);
        http.handler = [&](const HttpReq& req) {
            HttpResp r;
            if (req.path == "/oauth2/token") {
                r.body = "{\"access_token\":\"access-fresh\",\"expires_in\":14400}";
                return r;
            }
            r.status = 401;
            r.body = "still dead";
            return r;
        };
        CHECK(threwKind(SyncBackendError::Kind::needsAuth, [&]() {
            b->listChanges(std::nullopt);
        }));
    }

    {
        FakeHttpServer http;
        CHECK(http.start());
        auto store = std::make_shared<MemoryTokenStore>();
        auto b = makeBackend(http, store);
        http.handler = [](const HttpReq& req) {
            HttpResp r;
            if (req.path == "/api/2/files/list_folder") {
                r.body = R"({
                  "entries": [
                    {".tag":"file","path_lower":"/a.json","rev":"r1","content_hash":"h1"},
                    {".tag":"deleted","path_lower":"/b.json"},
                    {".tag":"folder","path_lower":"/dir"}
                  ],
                  "cursor":"c-first",
                  "has_more":true
                })";
                return r;
            }
            if (req.path == "/api/2/files/list_folder/continue") {
                r.body = R"({"entries":[],"cursor":"c-end","has_more":false})";
                return r;
            }
            r.status = 500;
            return r;
        };
        auto [entries, cursor] = b->listChanges(std::nullopt);
        CHECK(cursor == "c-end");
        CHECK(entries.size() == 2);
        CHECK(entries[0].path == "/a.json");
        CHECK(entries[0].rev == std::string("r1"));
        CHECK(entries[1].isDeleted);
        CHECK(entries[1].path == "/b.json");
        CHECK(http.log.front().body.contains("\"include_deleted\":false"));
        CHECK(http.log.front().body.contains("\"path\":\"\""));
        CHECK(http.log.front().body.contains("\"recursive\":true"));
    }

    {
        FakeHttpServer http;
        CHECK(http.start());
        auto store = std::make_shared<MemoryTokenStore>();
        auto b = makeBackend(http, store);
        http.handler = [](const HttpReq&) {
            HttpResp r;
            r.body = "file-bytes";
            r.headers.push_back({"Dropbox-API-Result", "{\"rev\":\"rev-down\"}"});
            return r;
        };
        auto [data, rev] = b->download("/a.json");
        CHECK(data == "file-bytes");
        CHECK(rev == "rev-down");
    }

    {
        FakeHttpServer http;
        CHECK(http.start());
        auto store = std::make_shared<MemoryTokenStore>();
        auto b = makeBackend(http, store);
        http.handler = [](const HttpReq&) {
            HttpResp r;
            r.status = 400;
            r.body = "{\"error\":\"invalid_grant\"}";
            return r;
        };
        // Force refresh by expiring the access token (expires_in 200 → skew to 0).
        b->setAccessTokenForTest("access-live", 200);
        CHECK(threwKind(SyncBackendError::Kind::needsAuth, [&]() {
            b->listChanges(std::nullopt);
        }));
        CHECK(!store->load().has_value()); // signOut on needsAuth from refresh
    }

    {
        auto store = std::make_shared<MemoryTokenStore>();
        DropboxSyncBackend b(store);
        CHECK(threwKind(SyncBackendError::Kind::server, [&]() { b.authorize(); }));
    }

    {
        auto store = std::make_shared<MemoryTokenStore>();
        FakeHttpServer http;
        CHECK(http.start());
        DropboxSyncBackend b(store);
        DropboxSyncBackend::Endpoints e;
        e.token = http.origin() + QStringLiteral("/oauth2/token");
        e.apiHost = http.origin() + QStringLiteral("/api/2/");
        e.authorize = http.origin() + QStringLiteral("/oauth2/authorize");
        b.setEndpoints(e);
        http.handler = [](const HttpReq& req) {
            HttpResp r;
            if (req.path == "/oauth2/token") {
                r.body = "{\"access_token\":\"a\",\"refresh_token\":\"r\",\"expires_in\":14400}";
                return r;
            }
            r.body = "{\"email\":\"user@example.com\"}";
            return r;
        };
        b.setAuthSession([](const QUrl&, const QString&) {
            return QUrl(QStringLiteral("db-hm5yscsy9a11g0q://2/token?code=abc&state=wrong"));
        });
        CHECK(threwKind(SyncBackendError::Kind::authorizationCancelled, [&]() { b.authorize(); }));
    }

    {
        auto store = std::make_shared<MemoryTokenStore>();
        FakeHttpServer http;
        CHECK(http.start());
        DropboxSyncBackend b(store);
        DropboxSyncBackend::Endpoints e;
        e.token = http.origin() + QStringLiteral("/oauth2/token");
        e.apiHost = http.origin() + QStringLiteral("/api/2/");
        e.authorize = http.origin() + QStringLiteral("/oauth2/authorize");
        b.setEndpoints(e);
        QString capturedState;
        http.handler = [](const HttpReq& req) {
            HttpResp r;
            if (req.path == "/oauth2/token") {
                CHECK(req.body.contains("grant_type=authorization_code"));
                CHECK(req.body.contains("code=ok-code"));
                CHECK(req.body.contains("code_verifier="));
                CHECK(req.body.contains("client_id=hm5yscsy9a11g0q"));
                CHECK(req.body.contains("redirect_uri=db-hm5yscsy9a11g0q"));
                r.body = "{\"access_token\":\"a1\",\"refresh_token\":\"rt1\",\"expires_in\":14400}";
                return r;
            }
            if (req.path == "/api/2/users/get_current_account") {
                CHECK(req.body == "null");
                r.body = "{\"email\":\"ada@example.com\"}";
                return r;
            }
            r.status = 500;
            return r;
        };
        b.setAuthSession([&](const QUrl& url, const QString& scheme) {
            CHECK(scheme == QStringLiteral("db-hm5yscsy9a11g0q"));
            CHECK(url.toString().contains(QStringLiteral("code_challenge_method=S256")));
            CHECK(url.toString().contains(QStringLiteral("token_access_type=offline")));
            CHECK(url.toString().contains(QStringLiteral("redirect_uri=db-hm5yscsy9a11g0q")));
            const QUrlQuery q(url);
            capturedState = q.queryItemValue(QStringLiteral("state"));
            return QUrl(QStringLiteral("db-hm5yscsy9a11g0q://2/token?code=ok-code&state=") + capturedState);
        });
        const std::string email = b.authorize();
        CHECK(email == "ada@example.com");
        CHECK(b.isAuthorized());
        CHECK(store->load() == std::string("rt1"));
        CHECK(b.accountEmail() == std::string("ada@example.com"));
        b.signOut();
        CHECK(!b.isAuthorized());
        CHECK(!store->load().has_value());
    }

    std::cout << "test_dropbox_backend: " << g_passes << " passed, " << g_fails << " failed\n";
    return g_fails ? 1 : 0;
}
