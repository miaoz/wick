#pragma once

#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace wick {

enum class TradingPositionSide { longSide, shortSide };
enum class TradingFillEffect { unknown, open, close };

struct TradingFill {
    std::int64_t id = 0;
    std::string symbol;
    std::string side;          // BUY / SELL
    std::string positionSide = "BOTH";
    double price = 0;
    double qty = 0;
    double quoteQty = 0;
    double commission = 0;    // negative = paid
    std::string commissionAsset;
    double realizedPnl = 0;
    TradingFillEffect effect = TradingFillEffect::unknown;
    std::int64_t time = 0;     // ms since epoch UTC

    static TradingFillEffect inferredEffect(std::string_view side,
                                            std::string_view positionSide,
                                            double realizedPnl);
    static std::int64_t integerID(std::string_view raw);
    static std::vector<TradingFill> clipped(const std::vector<TradingFill> &fills,
                                            std::int64_t fromMs, std::int64_t toMs);
};

struct FundingEvent {
    std::string symbol;
    double amount = 0;
    std::int64_t time = 0;
};

struct TradingPosition {
    std::string id;
    std::string symbol;
    TradingPositionSide side = TradingPositionSide::longSide;
    std::int64_t openTime = 0;
    std::optional<std::int64_t> closeTime;
    double entryPrice = 0;
    std::optional<double> exitPrice;
    double peakSize = 0;
    double realizedPnl = 0;
    std::map<std::string, double> commissions;
    double fundingPnl = 0;

    bool isClosed() const { return closeTime.has_value(); }
    double commissionTotal() const
    {
        double total = 0;
        for (const auto &[_, c] : commissions)
            total += c;
        return total;
    }
    double netPnl() const
    {
        return realizedPnl + commissionTotal() + fundingPnl;
    }
    std::string durationText() const;
    std::string quoteAsset() const;
};

struct TradingPositionSnapshot {
    std::int64_t fetchedAt = 0;
    std::int64_t windowStart = 0;
    std::vector<TradingPosition> positions;
    std::vector<TradingFill> fills;
    std::vector<FundingEvent> funding;
    bool fundingBackfilled = false;
    std::optional<std::string> sourceVenue;
    std::optional<std::string> sourceAccountLabel;

    std::string encode() const;
    static std::optional<TradingPositionSnapshot> decode(std::string_view jsonStr);
};

} // namespace wick
