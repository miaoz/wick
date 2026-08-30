#pragma once

#include <string>
#include <string_view>
#include <vector>

namespace wick {

std::vector<unsigned char> hmacSha256(std::string_view key, std::string_view data);
std::string hmacSha256Hex(std::string_view key, std::string_view data);
std::string hmacSha256Base64(std::string_view key, std::string_view data);
std::vector<unsigned char> sha256Bytes(std::string_view data);
std::string base64Encode(const unsigned char *data, std::size_t n);
std::string base64Decode(std::string_view input);

} // namespace wick
