#include "Crypto.h"

#include <openssl/evp.h>
#include <openssl/hmac.h>

#include <cstdio>
#include <stdexcept>

namespace wick {
namespace {

constexpr char kB64[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

} // namespace

std::vector<unsigned char> hmacSha256(std::string_view key, std::string_view data)
{
    unsigned int len = EVP_MAX_MD_SIZE;
    std::vector<unsigned char> out(len);
    unsigned char *ok = HMAC(EVP_sha256(),
                             key.data(), static_cast<int>(key.size()),
                             reinterpret_cast<const unsigned char *>(data.data()),
                             data.size(), out.data(), &len);
    if (!ok)
        throw std::runtime_error("HMAC-SHA256 failed");
    out.resize(len);
    return out;
}

std::string hmacSha256Hex(std::string_view key, std::string_view data)
{
    const auto mac = hmacSha256(key, data);
    static const char *kHex = "0123456789abcdef";
    std::string hex;
    hex.resize(mac.size() * 2);
    for (size_t i = 0; i < mac.size(); ++i) {
        hex[i * 2] = kHex[mac[i] >> 4];
        hex[i * 2 + 1] = kHex[mac[i] & 0xf];
    }
    return hex;
}

std::string base64Encode(const unsigned char *data, std::size_t n)
{
    std::string out;
    out.reserve((n + 2) / 3 * 4);
    std::size_t i = 0;
    while (i + 2 < n) {
        const unsigned v = (static_cast<unsigned>(data[i]) << 16)
            | (static_cast<unsigned>(data[i + 1]) << 8)
            | static_cast<unsigned>(data[i + 2]);
        out.push_back(kB64[(v >> 18) & 63]);
        out.push_back(kB64[(v >> 12) & 63]);
        out.push_back(kB64[(v >> 6) & 63]);
        out.push_back(kB64[v & 63]);
        i += 3;
    }
    if (i < n) {
        unsigned v = static_cast<unsigned>(data[i]) << 16;
        if (i + 1 < n)
            v |= static_cast<unsigned>(data[i + 1]) << 8;
        out.push_back(kB64[(v >> 18) & 63]);
        out.push_back(kB64[(v >> 12) & 63]);
        if (i + 1 < n) {
            out.push_back(kB64[(v >> 6) & 63]);
            out.push_back('=');
        } else {
            out.push_back('=');
            out.push_back('=');
        }
    }
    return out;
}

std::string hmacSha256Base64(std::string_view key, std::string_view data)
{
    const auto mac = hmacSha256(key, data);
    return base64Encode(mac.data(), mac.size());
}

std::vector<unsigned char> sha256Bytes(std::string_view data)
{
    std::vector<unsigned char> out(EVP_MAX_MD_SIZE);
    unsigned int len = 0;
    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    if (!ctx)
        throw std::runtime_error("SHA256 ctx");
    if (EVP_DigestInit_ex(ctx, EVP_sha256(), nullptr) != 1
        || EVP_DigestUpdate(ctx, data.data(), data.size()) != 1
        || EVP_DigestFinal_ex(ctx, out.data(), &len) != 1) {
        EVP_MD_CTX_free(ctx);
        throw std::runtime_error("SHA256 failed");
    }
    EVP_MD_CTX_free(ctx);
    out.resize(len);
    return out;
}

} // namespace wick
