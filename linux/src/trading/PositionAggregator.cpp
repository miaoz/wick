#include "PositionAggregator.h"

#include <algorithm>
#include <cmath>
#include <map>

namespace wick {
namespace {

struct SessionBuilder {
    std::string symbol;
    std::string lane;
    std::int64_t openTime = 0;
    std::int64_t openFillID = 0;
    TradingPositionSide side = TradingPositionSide::longSide;
    std::optional<std::int64_t> closeTime;
    double peakSize = 0;
    double realizedPnl = 0;
    double entryNotional = 0;
    double entryQty = 0;
    double exitNotional = 0;
    double exitQty = 0;
    std::map<std::string, double> commissions;

    void addEntry(double price, double qty)
    {
        entryNotional += price * qty;
        entryQty += qty;
    }
    void addExit(double price, double qty)
    {
        exitNotional += price * qty;
        exitQty += qty;
    }
    void absorb(double pnl, double commission, const std::string &asset)
    {
        realizedPnl += pnl;
        if (commission != 0)
            commissions[asset] += commission;
    }
    TradingPosition build() const
    {
        TradingPosition p;
        p.id = symbol + "|" + lane + "|" + std::to_string(openTime) + "|" + std::to_string(openFillID);
        p.symbol = symbol;
        p.side = side;
        p.openTime = openTime;
        p.closeTime = closeTime;
        p.entryPrice = entryQty > 0 ? entryNotional / entryQty : 0;
        if (exitQty > 0)
            p.exitPrice = exitNotional / exitQty;
        p.peakSize = peakSize;
        p.realizedPnl = realizedPnl;
        p.commissions = commissions;
        return p;
    }
};

int signOf(double v)
{
    if (v > 0)
        return 1;
    if (v < 0)
        return -1;
    return 0;
}

std::vector<TradingPosition> walkLane(std::vector<TradingFill> fills)
{
    std::sort(fills.begin(), fills.end(), [](const TradingFill &a, const TradingFill &b) {
        if (a.time != b.time)
            return a.time < b.time;
        return a.id < b.id;
    });

    std::vector<TradingPosition> positions;
    double net = 0;
    double gross = 0;
    std::optional<SessionBuilder> session;

    auto snap = [&](double value) {
        return std::abs(value) <= std::max(1e-12, gross * 1e-9) ? 0.0 : value;
    };

    for (const auto &fill : fills) {
        const double delta = (fill.side == "BUY" ? 1.0 : -1.0) * fill.qty;
        gross += std::abs(delta);
        const double nextNet = snap(net + delta);
        if (nextNet == net)
            continue;

        if (!session) {
            if (fill.effect == TradingFillEffect::close) {
                net = 0;
                continue;
            }
            SessionBuilder fresh;
            fresh.symbol = fill.symbol;
            fresh.lane = fill.positionSide;
            fresh.openTime = fill.time;
            fresh.openFillID = fill.id;
            fresh.side = nextNet > 0 ? TradingPositionSide::longSide : TradingPositionSide::shortSide;
            fresh.addEntry(fill.price, fill.qty);
            fresh.peakSize = std::abs(nextNet);
            fresh.absorb(fill.realizedPnl, fill.commission, fill.commissionAsset);
            session = fresh;
            net = nextNet;
            continue;
        }

        SessionBuilder current = *session;
        current.absorb(fill.realizedPnl, fill.commission, fill.commissionAsset);
        const bool closesCurrent = net != 0 && signOf(delta) != signOf(net);
        if (closesCurrent)
            current.addExit(fill.price, std::min(std::abs(net), std::abs(delta)));
        else
            current.addEntry(fill.price, std::abs(delta));

        if (signOf(nextNet) != signOf(net) && nextNet != 0) {
            current.closeTime = fill.time;
            positions.push_back(current.build());
            SessionBuilder fresh;
            fresh.symbol = fill.symbol;
            fresh.lane = fill.positionSide;
            fresh.openTime = fill.time;
            fresh.openFillID = fill.id;
            fresh.side = nextNet > 0 ? TradingPositionSide::longSide : TradingPositionSide::shortSide;
            const double openPortion = std::abs(nextNet);
            fresh.addEntry(fill.price, openPortion);
            fresh.peakSize = openPortion;
            session = fresh;
            net = nextNet;
            continue;
        }

        current.peakSize = std::max(current.peakSize, std::abs(nextNet));
        if (nextNet == 0) {
            current.closeTime = fill.time;
            positions.push_back(current.build());
            session.reset();
        } else {
            session = current;
        }
        net = nextNet;
    }

    if (session)
        positions.push_back(session->build());
    return positions;
}

} // namespace

std::vector<TradingPosition> PositionAggregator::aggregate(const std::vector<TradingFill> &fills)
{
    std::map<std::string, std::vector<TradingFill>> lanes;
    for (const auto &fill : fills) {
        if (fill.qty <= 0)
            continue;
        lanes[fill.symbol + "|" + fill.positionSide].push_back(fill);
    }
    std::vector<TradingPosition> positions;
    for (auto &[_, laneFills] : lanes) {
        auto walked = walkLane(std::move(laneFills));
        positions.insert(positions.end(), walked.begin(), walked.end());
    }
    std::sort(positions.begin(), positions.end(),
              [](const TradingPosition &a, const TradingPosition &b) { return a.openTime < b.openTime; });
    return positions;
}

} // namespace wick
