#pragma once

#include <cstddef>
#include <string>
#include <string_view>

namespace wick {

/// OAuth 2.0 PKCE helpers (RFC 7636). Public client — no app secret.
struct PKCE {
    /// 43-character base64url verifier from 32 random bytes.
    static std::string verifier();

    /// S256 challenge: base64url(SHA256(verifier)) with no padding.
    static std::string challenge(std::string_view verifier);

    /// Base64url without padding, per RFC 7636 §3.
    static std::string base64url(const unsigned char* data, std::size_t n);
    static std::string base64url(std::string_view data);
};

} // namespace wick
