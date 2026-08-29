#include "PKCE.h"
#include "SecretTokenStore.h"

#include <cstdlib>
#include <stdexcept>
#include <filesystem>
#include <iostream>
#include <string>
#include <unistd.h>
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

static std::filesystem::path makeTempDir(const char* prefix) {
    auto base = std::filesystem::temp_directory_path() / (std::string(prefix) + "XXXXXX");
    std::string tmpl = base.string();
    std::vector<char> buf(tmpl.begin(), tmpl.end());
    buf.push_back('\0');
    if (!mkdtemp(buf.data()))
        throw std::runtime_error("mkdtemp failed");
    return std::filesystem::path(buf.data());
}

int main() {
    // RFC 7636 Appendix B S256 vector.
    const std::string verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
    const std::string expected = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM";
    CHECK(PKCE::challenge(verifier) == expected);

    const std::string v1 = PKCE::verifier();
    const std::string v2 = PKCE::verifier();
    CHECK(v1.size() == 43);
    CHECK(v2.size() == 43);
    CHECK(v1 != v2);
    CHECK(v1.find('+') == std::string::npos);
    CHECK(v1.find('/') == std::string::npos);
    CHECK(v1.find('=') == std::string::npos);
    CHECK(PKCE::challenge(v1) == PKCE::challenge(v1));
    CHECK(PKCE::challenge(v1) != PKCE::challenge(v2));
    CHECK(PKCE::challenge(v1).size() == 43);

    // Dev-secrets fallback (never QSettings). Isolated via XDG_DATA_HOME.
    const auto tmp = makeTempDir("wick-secret-");
    setenv("WICK_DEV_SECRETS", "1", 1);
    setenv("XDG_DATA_HOME", tmp.c_str(), 1);
    {
        SecretTokenStore store;
        CHECK(!store.load().has_value());
        store.save("refresh-abc");
        CHECK(store.load() == std::string("refresh-abc"));
        const auto path = tmp / "wick" / "dev-secrets.json";
        CHECK(std::filesystem::exists(path));
        const auto perms = std::filesystem::status(path).permissions();
        using P = std::filesystem::perms;
        CHECK((perms & P::owner_read) != P::none);
        CHECK((perms & P::owner_write) != P::none);
        CHECK((perms & P::group_read) == P::none);
        CHECK((perms & P::others_read) == P::none);
        store.clear();
        CHECK(!store.load().has_value());
    }

    std::cout << "test_pkce: " << g_passes << " passed, " << g_fails << " failed\n";
    return g_fails ? 1 : 0;
}
