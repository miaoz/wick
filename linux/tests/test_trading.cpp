#include "Crypto.h"
#include "PositionAggregator.h"
#include "PositionEntryPlanner.h"
#include "SymbolTagMatcher.h"
#include "TradingModels.h"

#include <iostream>
#include <string>

using namespace wick;

static int g_fails = 0;
static int g_passes = 0;

#define CHECK(cond)                                                                          \
    do {                                                                                     \
        if (!(cond)) {                                                                       \
            std::cerr << "FAIL " << __FILE__ << ":" << __LINE__ << " : " << #cond << "\n"; \
            ++g_fails;                                                                       \
        } else {                                                                             \
            ++g_passes;                                                                      \
        }                                                                                    \
    } while (0)

static TradingFill fill(const char *symbol, const char *side, double price, double qty,
                        std::int64_t time, std::int64_t id, double pnl = 0)
{
    TradingFill f;
    f.id = id;
    f.symbol = symbol;
    f.side = side;
    f.positionSide = "BOTH";
    f.price = price;
    f.qty = qty;
    f.time = time;
    f.realizedPnl = pnl;
    f.effect = TradingFill::inferredEffect(side, "BOTH", pnl);
    return f;
}

int main()
{
    CHECK(hmacSha256Hex("key", "The quick brown fox jumps over the lazy dog")
          == "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8");

    CHECK(SymbolTagMatcher::matches("BTC", "BTCUSDT"));
    CHECK(SymbolTagMatcher::matches("btc/usdt", "BTCUSDT"));
    CHECK(SymbolTagMatcher::matches("PEPE", "1000PEPEUSDT"));
    CHECK(!SymbolTagMatcher::matches("BTCUSDT", "BTCUSDC"));
    CHECK(SymbolTagMatcher::baseAsset("BTCUSDT") == "BTC");

    auto positions = PositionAggregator::aggregate({
        fill("BTCUSDT", "BUY", 100, 1, 1000, 1),
        fill("BTCUSDT", "SELL", 110, 1, 2000, 2, 10),
    });
    CHECK(positions.size() == 1);
    CHECK(positions[0].symbol == "BTCUSDT");
    CHECK(positions[0].side == TradingPositionSide::longSide);
    CHECK(positions[0].closeTime.has_value());
    CHECK(positions[0].realizedPnl == 10);

    const auto id = Uuid::parse("01234567-89AB-CDEF-0123-456789ABCDEF");
    CHECK(id.has_value());
    const auto stable = PositionEntryPlanner::stableItemID(*id, "2026-01-01", "btcusdt");
    const auto again = PositionEntryPlanner::stableItemID(*id, "2026-01-01", "BTCUSDT");
    CHECK(stable == again);

    std::cout << g_passes << " passed, " << g_fails << " failed\n";
    return g_fails == 0 ? 0 : 1;
}
