#include "TradingModels.h"
#include "SymbolTagMatcher.h"

#include <algorithm>
#include <cctype>
#include <nlohmann/json.hpp>

namespace wick {

TradingFillEffect TradingFill::inferredEffect(std::string_view side,
                                              std::string_view positionSide,
                                              double realizedPnl)
{
    auto upper = [](std::string_view s) {
        std::string o(s);
        for (char &c : o)
            c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
        return o;
    };
    const std::string ps = upper(positionSide);
    const std::string sd = upper(side);
    if ((ps == "LONG" && sd == "BUY") || (ps == "SHORT" && sd == "SELL"))
        return TradingFillEffect::open;
    if ((ps == "LONG" && sd == "SELL") || (ps == "SHORT" && sd == "BUY"))
        return TradingFillEffect::close;
    return realizedPnl != 0 ? TradingFillEffect::close : TradingFillEffect::unknown;
}

std::int64_t TradingFill::integerID(std::string_view raw)
{
    try {
        size_t idx = 0;
        const long long v = std::stoll(std::string(raw), &idx, 10);
        if (idx == raw.size())
            return static_cast<std::int64_t>(v);
    } catch (...) {
    }
    std::uint64_t hash = 5381;
    for (unsigned char b : raw)
        hash = hash * 33 + b;
    return static_cast<std::int64_t>(hash);
}

std::vector<TradingFill> TradingFill::clipped(const std::vector<TradingFill> &fills,
                                              std::int64_t fromMs, std::int64_t toMs)
{
    std::vector<TradingFill> out;
    for (const auto &f : fills) {
        if (f.time >= fromMs && f.time < toMs)
            out.push_back(f);
    }
    return out;
}

std::string TradingPosition::durationText(bool isChinese) const
{
    if (!closeTime.has_value())
        return isChinese ? "持仓中" : "Open";
    int64_t diffSec = (*closeTime - openTime) / 1000;
    if (diffSec < 0)
        diffSec = 0;
    const int64_t days = diffSec / 86400;
    const int64_t hours = (diffSec % 86400) / 3600;
    const int64_t minutes = (diffSec % 3600) / 60;
    if (isChinese) {
        if (days > 0) {
            if (hours > 0)
                return std::to_string(days) + " 天 " + std::to_string(hours) + " 小时";
            return std::to_string(days) + " 天";
        }
        if (hours > 0) {
            if (minutes > 0)
                return std::to_string(hours) + " 小时 " + std::to_string(minutes) + " 分钟";
            return std::to_string(hours) + " 小时";
        }
        if (minutes > 0)
            return std::to_string(minutes) + " 分钟";
        return "1 分钟内";
    } else {
        if (days > 0) {
            if (hours > 0)
                return std::to_string(days) + "d " + std::to_string(hours) + "h";
            return std::to_string(days) + (days == 1 ? " day" : " days");
        }
        if (hours > 0) {
            if (minutes > 0)
                return std::to_string(hours) + "h " + std::to_string(minutes) + "m";
            return std::to_string(hours) + (hours == 1 ? " hr" : " hrs");
        }
        if (minutes > 0)
            return std::to_string(minutes) + (minutes == 1 ? " min" : " mins");
        return "< 1 min";
    }
}

std::string TradingPosition::headerTitle(bool isChinese) const
{
    std::string header = symbol;
    auto endsWith = [](const std::string &str, const std::string &suffix) {
        return str.size() >= suffix.size() && str.compare(str.size() - suffix.size(), suffix.size(), suffix) == 0;
    };
    if (!endsWith(header, "永续") && !endsWith(header, "PERP") && header.find(' ') == std::string::npos) {
        header += isChinese ? " 永续" : " PERP";
    }
    return header;
}

std::string TradingPosition::quoteAsset() const
{
    if (const auto q = SymbolTagMatcher::quoteAsset(symbol))
        return *q;
    return "USDT";
}

static nlohmann::json positionToJson(const TradingPosition &p)
{
    nlohmann::json j;
    j["id"] = p.id;
    j["symbol"] = p.symbol;
    j["side"] = p.side == TradingPositionSide::longSide ? "long" : "short";
    j["openTime"] = p.openTime;
    if (p.closeTime.has_value())
        j["closeTime"] = *p.closeTime;
    else
        j["closeTime"] = nullptr;
    j["entryPrice"] = p.entryPrice;
    if (p.exitPrice.has_value())
        j["exitPrice"] = *p.exitPrice;
    else
        j["exitPrice"] = nullptr;
    j["peakSize"] = p.peakSize;
    j["realizedPnl"] = p.realizedPnl;
    j["commissions"] = p.commissions;
    j["fundingPnl"] = p.fundingPnl;
    return j;
}

static constexpr int64_t kAppleEpochOffsetSeconds = 978307200;

static int64_t normalizeTimestampMs(double raw)
{
    if (raw <= 0)
        return 0;
    // Apple Reference Date seconds (e.g. 809141400 for year 2026):
    if (raw < 1000000000.0)
        return static_cast<int64_t>((raw + kAppleEpochOffsetSeconds) * 1000.0);
    // Unix seconds (e.g. 1787448600 for year 2026):
    if (raw < 10000000000.0)
        return static_cast<int64_t>(raw * 1000.0);
    // Already Unix milliseconds (e.g. 1787448600000):
    return static_cast<int64_t>(raw);
}

static TradingPosition positionFromJson(const nlohmann::json &j)
{
    TradingPosition p;
    p.id = j.value("id", "");
    p.symbol = j.value("symbol", "");
    const std::string s = j.value("side", "long");
    p.side = (s == "short" || s == "SHORT") ? TradingPositionSide::shortSide : TradingPositionSide::longSide;
    if (j.contains("openTime") && j["openTime"].is_number())
        p.openTime = normalizeTimestampMs(j["openTime"].get<double>());
    if (j.contains("closeTime") && j["closeTime"].is_number())
        p.closeTime = normalizeTimestampMs(j["closeTime"].get<double>());
    p.entryPrice = j.value("entryPrice", 0.0);
    if (j.contains("exitPrice") && !j["exitPrice"].is_null())
        p.exitPrice = j["exitPrice"].get<double>();
    p.peakSize = j.value("peakSize", 0.0);
    p.realizedPnl = j.value("realizedPnl", 0.0);
    if (j.contains("commissions") && j["commissions"].is_object())
        p.commissions = j["commissions"].get<std::map<std::string, double>>();
    p.fundingPnl = j.value("fundingPnl", 0.0);
    return p;
}

std::string TradingPositionSnapshot::encode() const
{
    nlohmann::json j;
    j["fetchedAt"] = fetchedAt;
    j["windowStart"] = windowStart;
    j["fundingBackfilled"] = fundingBackfilled;
    if (sourceVenue.has_value())
        j["sourceVenue"] = *sourceVenue;
    if (sourceAccountLabel.has_value())
        j["sourceAccountLabel"] = *sourceAccountLabel;

    auto posArr = nlohmann::json::array();
    for (const auto &p : positions)
        posArr.push_back(positionToJson(p));
    j["positions"] = posArr;

    auto fillArr = nlohmann::json::array();
    for (const auto &f : fills) {
        nlohmann::json fj;
        fj["id"] = f.id;
        fj["symbol"] = f.symbol;
        fj["side"] = f.side;
        fj["positionSide"] = f.positionSide;
        fj["price"] = f.price;
        fj["qty"] = f.qty;
        fj["quoteQty"] = f.quoteQty;
        fj["commission"] = f.commission;
        fj["commissionAsset"] = f.commissionAsset;
        fj["realizedPnl"] = f.realizedPnl;
        fj["time"] = f.time;
        fillArr.push_back(fj);
    }
    j["fills"] = fillArr;

    auto fundArr = nlohmann::json::array();
    for (const auto &fe : funding) {
        nlohmann::json fej;
        fej["symbol"] = fe.symbol;
        fej["amount"] = fe.amount;
        fej["time"] = fe.time;
        fundArr.push_back(fej);
    }
    j["funding"] = fundArr;

    return j.dump(2);
}

std::optional<TradingPositionSnapshot> TradingPositionSnapshot::decode(std::string_view jsonStr)
{
    try {
        const auto j = nlohmann::json::parse(jsonStr);
        TradingPositionSnapshot s;
        if (j.contains("fetchedAt") && j["fetchedAt"].is_number())
            s.fetchedAt = normalizeTimestampMs(j["fetchedAt"].get<double>());
        if (j.contains("windowStart") && j["windowStart"].is_number())
            s.windowStart = normalizeTimestampMs(j["windowStart"].get<double>());
        s.fundingBackfilled = j.value("fundingBackfilled", false);
        if (j.contains("sourceVenue") && j["sourceVenue"].is_string())
            s.sourceVenue = j["sourceVenue"].get<std::string>();
        if (j.contains("sourceAccountLabel") && j["sourceAccountLabel"].is_string())
            s.sourceAccountLabel = j["sourceAccountLabel"].get<std::string>();

        if (j.contains("positions") && j["positions"].is_array()) {
            for (const auto &pj : j["positions"])
                s.positions.push_back(positionFromJson(pj));
        }

        if (j.contains("fills") && j["fills"].is_array()) {
            for (const auto &fj : j["fills"]) {
                TradingFill f;
                f.id = fj.value("id", static_cast<std::int64_t>(0));
                f.symbol = fj.value("symbol", "");
                f.side = fj.value("side", "");
                f.positionSide = fj.value("positionSide", "BOTH");
                f.price = fj.value("price", 0.0);
                f.qty = fj.value("qty", 0.0);
                f.quoteQty = fj.value("quoteQty", 0.0);
                f.commission = fj.value("commission", 0.0);
                f.commissionAsset = fj.value("commissionAsset", "");
                f.realizedPnl = fj.value("realizedPnl", 0.0);
                if (fj.contains("time") && fj["time"].is_number())
                    f.time = normalizeTimestampMs(fj["time"].get<double>());
                f.effect = TradingFill::inferredEffect(f.side, f.positionSide, f.realizedPnl);
                s.fills.push_back(f);
            }
        }

        if (j.contains("funding") && j["funding"].is_array()) {
            for (const auto &fej : j["funding"]) {
                FundingEvent fe;
                fe.symbol = fej.value("symbol", "");
                fe.amount = fej.value("amount", 0.0);
                if (fej.contains("time") && fej["time"].is_number())
                    fe.time = normalizeTimestampMs(fej["time"].get<double>());
                s.funding.push_back(fe);
            }
        }

        return s;
    } catch (...) {
        return std::nullopt;
    }
}

} // namespace wick
