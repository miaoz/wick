#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include "JournalModels.h"

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <ctime>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <random>
#include <sstream>

namespace wick {
namespace {

int hexVal(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

bool parseTwoHex(std::string_view s, size_t i, uint8_t& out) {
    if (i + 1 >= s.size()) return false;
    int hi = hexVal(s[i]);
    int lo = hexVal(s[i + 1]);
    if (hi < 0 || lo < 0) return false;
    out = static_cast<uint8_t>((hi << 4) | lo);
    return true;
}

} // namespace

Uuid Uuid::generate() {
    Uuid u;
    std::ifstream urandom("/dev/urandom", std::ios::binary);
    if (urandom) {
        urandom.read(reinterpret_cast<char*>(u.bytes.data()), static_cast<std::streamsize>(u.bytes.size()));
    } else {
        std::random_device rd;
        for (auto& b : u.bytes) b = static_cast<uint8_t>(rd());
    }
    u.bytes[6] = static_cast<uint8_t>((u.bytes[6] & 0x0f) | 0x40);
    u.bytes[8] = static_cast<uint8_t>((u.bytes[8] & 0x3f) | 0x80);
    return u;
}

std::optional<Uuid> Uuid::parse(std::string_view text) {
    // Accept 8-4-4-4-12 dashed form, any hex case.
    if (text.size() != 36) return std::nullopt;
    if (text[8] != '-' || text[13] != '-' || text[18] != '-' || text[23] != '-') {
        return std::nullopt;
    }
    Uuid u;
    size_t bi = 0;
    auto take = [&](size_t i) -> bool {
        if (bi >= 16) return false;
        return parseTwoHex(text, i, u.bytes[bi++]);
    };
    if (!take(0) || !take(2) || !take(4) || !take(6)) return std::nullopt;
    if (!take(9) || !take(11)) return std::nullopt;
    if (!take(14) || !take(16)) return std::nullopt;
    if (!take(19) || !take(21)) return std::nullopt;
    if (!take(24) || !take(26) || !take(28) || !take(30) || !take(32) || !take(34)) {
        return std::nullopt;
    }
    return u;
}

std::string Uuid::toString() const {
    static constexpr char kHex[] = "0123456789ABCDEF";
    std::string s;
    s.resize(36);
    auto put = [&](size_t pos, uint8_t b) {
        s[pos] = kHex[b >> 4];
        s[pos + 1] = kHex[b & 0x0f];
    };
    put(0, bytes[0]); put(2, bytes[1]); put(4, bytes[2]); put(6, bytes[3]);
    s[8] = '-';
    put(9, bytes[4]); put(11, bytes[5]);
    s[13] = '-';
    put(14, bytes[6]); put(16, bytes[7]);
    s[18] = '-';
    put(19, bytes[8]); put(21, bytes[9]);
    s[23] = '-';
    put(24, bytes[10]); put(26, bytes[11]); put(28, bytes[12]);
    put(30, bytes[13]); put(32, bytes[14]); put(34, bytes[15]);
    return s;
}

bool JournalImageFilename::isValid(std::string_view filename) {
    if (filename.empty()) return false;
    if (filename.find('\0') != std::string_view::npos) return false;
    if (filename.find('/') != std::string_view::npos) return false;
    if (filename.find('\\') != std::string_view::npos) return false;
    if (filename == "." || filename == "..") return false;

    // Mirror Swift:
    //   URL(fileURLWithPath: filename, relativeTo: URL(fileURLWithPath: "/"))
    //   lastPathComponent == filename
    //   standardizedFileURL.path == "/" + filename
    const std::string name(filename);
    const std::filesystem::path combined = std::filesystem::path("/") / name;
    if (combined.filename().string() != name) return false;
    if (combined.lexically_normal().generic_string() != (std::string("/") + name)) {
        return false;
    }
    return true;
}

void JournalImageFilename::validateAll(const std::vector<std::string>& filenames) {
    for (const auto& filename : filenames) {
        if (!isValid(filename)) {
            throw InvalidReference(filename);
        }
    }
}

std::string_view toString(JournalReviewVerdict v) {
    switch (v) {
    case JournalReviewVerdict::correct: return "correct";
    case JournalReviewVerdict::wrong: return "wrong";
    }
    return "correct";
}

std::optional<JournalReviewVerdict> parseReviewVerdict(std::string_view s) {
    if (s == "correct") return JournalReviewVerdict::correct;
    if (s == "wrong") return JournalReviewVerdict::wrong;
    return std::nullopt;
}

std::string_view toString(ExchangeVenue v) {
    switch (v) {
    case ExchangeVenue::binance: return "binance";
    case ExchangeVenue::okx: return "okx";
    case ExchangeVenue::hyperliquid: return "hyperliquid";
    }
    return "binance";
}

std::optional<ExchangeVenue> parseExchangeVenue(std::string_view s) {
    if (s == "binance") return ExchangeVenue::binance;
    if (s == "okx") return ExchangeVenue::okx;
    if (s == "hyperliquid") return ExchangeVenue::hyperliquid;
    return std::nullopt;
}

TimePoint timeFromUnix(std::int64_t seconds) {
    return std::chrono::system_clock::from_time_t(static_cast<std::time_t>(seconds));
}

std::int64_t unixFromTime(TimePoint tp) {
    return static_cast<std::int64_t>(std::chrono::system_clock::to_time_t(tp));
}

std::string formatIso8601(TimePoint tp) {
    const std::time_t t = std::chrono::system_clock::to_time_t(tp);
    std::tm tm{};
    gmtime_r(&t, &tm);
    char buf[32];
    std::strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", &tm);
    return buf;
}

TimePoint parseIso8601(std::string_view text) {
    // Swift JSONDecoder .iso8601 uses ISO8601DateFormatter withInternetDateTime
    // (whole seconds). We also accept fractional seconds on decode.
    if (text.empty()) throw DecodeError("empty date");

    int Y = 0, M = 0, D = 0, h = 0, m = 0, s = 0;
    const std::string str(text);
    const char* p = str.c_str();
    int n = 0;
    if (std::sscanf(p, "%d-%d-%dT%d:%d:%d%n", &Y, &M, &D, &h, &m, &s, &n) != 6) {
        throw DecodeError("invalid ISO-8601 date: " + str);
    }
    if (n < 19) throw DecodeError("invalid ISO-8601 date: " + str);

    const char* rest = p + n;
    // Optional fractional seconds.
    if (*rest == '.' || *rest == ',') {
        ++rest;
        while (*rest >= '0' && *rest <= '9') ++rest;
    }

    int tzSign = 0;
    int tzH = 0, tzM = 0;
    if (*rest == 'Z' || *rest == 'z') {
        ++rest;
    } else if (*rest == '+' || *rest == '-') {
        tzSign = (*rest == '+') ? 1 : -1;
        ++rest;
        if (std::sscanf(rest, "%d:%d", &tzH, &tzM) != 2) {
            // also accept ±HHMM
            if (std::sscanf(rest, "%2d%2d", &tzH, &tzM) != 2) {
                throw DecodeError("invalid ISO-8601 timezone: " + str);
            }
            rest += 4;
        } else {
            // skip HH:MM
            while (*rest && *rest != 'Z') {
                if ((*rest >= '0' && *rest <= '9') || *rest == ':') {
                    ++rest;
                    continue;
                }
                break;
            }
        }
    } else if (*rest == '\0') {
        // treat as UTC
    } else {
        throw DecodeError("invalid ISO-8601 date: " + str);
    }

    std::tm tm{};
    tm.tm_year = Y - 1900;
    tm.tm_mon = M - 1;
    tm.tm_mday = D;
    tm.tm_hour = h;
    tm.tm_min = m;
    tm.tm_sec = s;
    tm.tm_isdst = 0;
    const std::time_t utc = timegm(&tm);
    if (utc == static_cast<std::time_t>(-1) && (Y < 1969)) {
        throw DecodeError("invalid ISO-8601 date: " + str);
    }
    std::int64_t epoch = static_cast<std::int64_t>(utc);
    if (tzSign != 0) {
        epoch -= tzSign * (tzH * 3600 + tzM * 60);
    }
    return timeFromUnix(epoch);
}

std::string JournalDayKey::make(TimePoint date, int tzOffsetSeconds) {
    const std::time_t t = std::chrono::system_clock::to_time_t(date) + tzOffsetSeconds;
    std::tm tm{};
    gmtime_r(&t, &tm);
    char buf[16];
    std::strftime(buf, sizeof(buf), "%Y-%m-%d", &tm);
    return buf;
}

bool atomicWriteFile(const std::filesystem::path& dest, std::string_view data) {
    std::error_code ec;
    std::filesystem::create_directories(dest.parent_path(), ec);
    const auto tmp = dest.string() + ".tmp";
    {
        std::ofstream out(tmp, std::ios::binary | std::ios::trunc);
        if (!out) return false;
        out.write(data.data(), static_cast<std::streamsize>(data.size()));
        out.close();
        if (!out) {
            std::filesystem::remove(tmp, ec);
            return false;
        }
    }
    std::filesystem::rename(tmp, dest, ec);
    if (ec) {
        std::filesystem::remove(tmp, ec);
        return false;
    }
    return true;
}

std::optional<std::string> readFileBytes(const std::filesystem::path& path) {
    std::error_code ec;
    if (!std::filesystem::exists(path, ec)) return std::nullopt;
    std::ifstream in(path, std::ios::binary);
    if (!in) return std::nullopt;
    std::ostringstream ss;
    ss << in.rdbuf();
    return ss.str();
}

} // namespace wick
