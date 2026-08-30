#include "TradingModels.h"

#include <algorithm>
#include <cctype>

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

} // namespace wick
