#include "FundingAttributor.h"

#include <algorithm>
#include <unordered_map>

namespace wick {
namespace {

bool contains(const FundingEvent &event, const TradingPosition &pos)
{
    if (event.time < pos.openTime)
        return false;
    if (pos.closeTime.has_value())
        return event.time < *pos.closeTime;
    return true;
}

} // namespace

std::vector<TradingPosition> FundingAttributor::attach(
    const std::vector<TradingPosition> &positions,
    const std::vector<FundingEvent> &funding)
{
    if (funding.empty())
        return positions;

    std::unordered_map<std::string, std::vector<TradingPosition>> positionsBySymbol;
    for (const auto &p : positions)
        positionsBySymbol[p.symbol].push_back(p);

    std::unordered_map<std::string, std::vector<FundingEvent>> fundingBySymbol;
    for (const auto &f : funding)
        fundingBySymbol[f.symbol].push_back(f);

    std::unordered_map<std::string, double> fundingByPosId;

    for (auto &[symbol, symbolFunding] : fundingBySymbol) {
        auto it = positionsBySymbol.find(symbol);
        if (it == positionsBySymbol.end() || it->second.empty())
            continue;
        auto &candidates = it->second;
        std::sort(candidates.begin(), candidates.end(), [](const TradingPosition &a, const TradingPosition &b) {
            if (a.openTime != b.openTime)
                return a.openTime < b.openTime;
            return a.id < b.id;
        });
        std::sort(symbolFunding.begin(), symbolFunding.end(), [](const FundingEvent &a, const FundingEvent &b) {
            return a.time < b.time;
        });
        for (const auto &event : symbolFunding) {
            for (const auto &cand : candidates) {
                if (contains(event, cand)) {
                    fundingByPosId[cand.id] += event.amount;
                    break;
                }
            }
        }
    }

    std::vector<TradingPosition> result = positions;
    for (auto &pos : result) {
        auto it = fundingByPosId.find(pos.id);
        if (it != fundingByPosId.end())
            pos.fundingPnl = it->second;
    }
    return result;
}

} // namespace wick
