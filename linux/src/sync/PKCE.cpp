#include "PKCE.h"

#include <openssl/rand.h>
#include <openssl/sha.h>

#include <stdexcept>

namespace wick {
namespace {

constexpr char kTable[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

} // namespace

std::string PKCE::base64url(const unsigned char* data, std::size_t n) {
    std::string out;
    out.reserve((n + 2) / 3 * 4);
    std::size_t i = 0;
    while (i + 2 < n) {
        const unsigned v = (static_cast<unsigned>(data[i]) << 16)
            | (static_cast<unsigned>(data[i + 1]) << 8)
            | static_cast<unsigned>(data[i + 2]);
        out.push_back(kTable[(v >> 18) & 63]);
        out.push_back(kTable[(v >> 12) & 63]);
        out.push_back(kTable[(v >> 6) & 63]);
        out.push_back(kTable[v & 63]);
        i += 3;
    }
    if (i < n) {
        unsigned v = static_cast<unsigned>(data[i]) << 16;
        if (i + 1 < n)
            v |= static_cast<unsigned>(data[i + 1]) << 8;
        out.push_back(kTable[(v >> 18) & 63]);
        out.push_back(kTable[(v >> 12) & 63]);
        if (i + 1 < n)
            out.push_back(kTable[(v >> 6) & 63]);
    }
    return out;
}

std::string PKCE::base64url(std::string_view data) {
    return base64url(reinterpret_cast<const unsigned char*>(data.data()), data.size());
}

std::string PKCE::verifier() {
    unsigned char bytes[32];
    if (RAND_bytes(bytes, sizeof(bytes)) != 1)
        throw std::runtime_error("PKCE: RAND_bytes failed");
    return base64url(bytes, sizeof(bytes));
}

std::string PKCE::challenge(std::string_view ver) {
    unsigned char digest[SHA256_DIGEST_LENGTH];
    SHA256(reinterpret_cast<const unsigned char*>(ver.data()), ver.size(), digest);
    return base64url(digest, SHA256_DIGEST_LENGTH);
}

} // namespace wick
