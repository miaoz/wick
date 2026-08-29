#pragma once

#include <array>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace wick {

using TimePoint = std::chrono::system_clock::time_point;

// Dashed 8-4-4-4-12. Encoded UPPERCASE to match Swift Foundation
// UUID.uuidString; decoder accepts both cases.
struct Uuid {
    std::array<uint8_t, 16> bytes{};

    static Uuid generate();
    static std::optional<Uuid> parse(std::string_view text);

    std::string toString() const; // uppercase dashed
    std::string toLowerString() const; // Dropbox path segments (Mac uuidString.lowercased)
    bool operator==(const Uuid& other) const { return bytes == other.bytes; }
    bool operator!=(const Uuid& other) const { return !(*this == other); }
    bool operator<(const Uuid& other) const { return bytes < other.bytes; }
};

std::string trimCopy(std::string_view s);

struct JournalImageFilename {
    struct InvalidReference : std::runtime_error {
        std::string filename;
        explicit InvalidReference(std::string name)
            : std::runtime_error("unsafe journal image filename: " + name)
            , filename(std::move(name)) {}
    };

    static bool isValid(std::string_view filename);
    static void validateAll(const std::vector<std::string>& filenames);
};

enum class JournalReviewVerdict { correct, wrong };

std::string_view toString(JournalReviewVerdict v);
std::optional<JournalReviewVerdict> parseReviewVerdict(std::string_view s);

struct JournalReview {
    JournalReviewVerdict verdict = JournalReviewVerdict::correct;
    std::string note;
    TimePoint createdAt{};
    TimePoint updatedAt{};

    bool operator==(const JournalReview& o) const {
        return verdict == o.verdict && note == o.note && createdAt == o.createdAt
            && updatedAt == o.updatedAt;
    }
};

struct JournalItem {
    Uuid id;
    std::string tag;
    std::string body;
    std::vector<std::string> imageFilenames;
    std::optional<JournalReview> review;

    bool operator==(const JournalItem& o) const {
        return id == o.id && tag == o.tag && body == o.body
            && imageFilenames == o.imageFilenames && review == o.review;
    }
    bool isEmpty() const;
};

struct JournalEntry {
    Uuid id;
    TimePoint date{};
    std::string title;
    std::vector<JournalItem> items;
    TimePoint createdAt{};
    TimePoint updatedAt{};

    bool operator==(const JournalEntry& o) const {
        return id == o.id && date == o.date && title == o.title && items == o.items
            && createdAt == o.createdAt && updatedAt == o.updatedAt;
    }
};

struct JournalSnapshot {
    static constexpr int currentVersion = 2;
    int version = currentVersion;
    std::vector<JournalEntry> entries;

    static JournalSnapshot empty() { return JournalSnapshot{currentVersion, {}}; }

    bool operator==(const JournalSnapshot& o) const {
        return version == o.version && entries == o.entries;
    }
};

enum class ExchangeVenue { binance, okx, hyperliquid };

std::string_view toString(ExchangeVenue v);
std::optional<ExchangeVenue> parseExchangeVenue(std::string_view s);

struct JournalExchangeBinding {
    ExchangeVenue venue = ExchangeVenue::binance;
    std::string accountLabel;

    bool operator==(const JournalExchangeBinding& o) const {
        return venue == o.venue && accountLabel == o.accountLabel;
    }
};

struct JournalInfo {
    Uuid id;
    std::string name;
    TimePoint createdAt{};
    TimePoint updatedAt{};
    std::optional<JournalExchangeBinding> exchangeBinding;

    bool operator==(const JournalInfo& o) const {
        return id == o.id && name == o.name && createdAt == o.createdAt
            && updatedAt == o.updatedAt && exchangeBinding == o.exchangeBinding;
    }
};

struct JournalCatalogSnapshot {
    static constexpr int currentVersion = 1;
    int version = currentVersion;
    Uuid activeJournalID;
    std::vector<JournalInfo> journals;

    bool operator==(const JournalCatalogSnapshot& o) const {
        return version == o.version && activeJournalID == o.activeJournalID
            && journals == o.journals;
    }
};

struct JournalDayKey {
    // Local Gregorian day yyyy-MM-dd. tzOffsetSeconds is seconds from GMT.
    static std::string make(TimePoint date, int tzOffsetSeconds);
};

struct DecodeError : std::runtime_error {
    using std::runtime_error::runtime_error;
};

TimePoint timeFromUnix(std::int64_t seconds);
std::int64_t unixFromTime(TimePoint tp);
std::string formatIso8601(TimePoint tp); // whole seconds, UTC, ...Z
TimePoint parseIso8601(std::string_view text); // throws DecodeError

bool atomicWriteFile(const std::filesystem::path& dest, std::string_view data);
std::optional<std::string> readFileBytes(const std::filesystem::path& path);

} // namespace wick
