#include "Crypto.h"
#include "ExchangeClients.h"
#include "FundingAttributor.h"
#include "PositionAggregator.h"
#include "PositionEntryPlanner.h"
#include "SymbolTagMatcher.h"
#include "TradingModels.h"

#include <cmath>
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

    CHECK(SymbolTagMatcher::quoteAsset("BTCUSDT") == "USDT");
    CHECK(positions[0].quoteAsset() == "USDT");
    CHECK(positions[0].isClosed());
    CHECK(positions[0].netPnl() == 10);
    CHECK(!positions[0].durationText().empty());

    TradingPositionSnapshot snap;
    snap.fetchedAt = 5000;
    snap.windowStart = 1000;
    snap.positions = positions;
    snap.sourceVenue = "binance";
    const std::string encoded = snap.encode();
    const auto decoded = TradingPositionSnapshot::decode(encoded);
    CHECK(decoded.has_value());
    CHECK(decoded->positions.size() == 1);
    CHECK(decoded->positions[0].symbol == "BTCUSDT");
    CHECK(decoded->positions[0].realizedPnl == 10);
    CHECK(decoded->sourceVenue == "binance");

    // FundingAttributor tests
    TradingPosition posA;
    posA.id = "A";
    posA.symbol = "BTCUSDT";
    posA.openTime = 1000;
    posA.closeTime = 5000;

    std::vector<FundingEvent> fundingEvents = {
        {"BTCUSDT", -1.0, 2000},
        {"BTCUSDT", -0.5, 4000},
        {"BTCUSDT", -9.0, 9000} // after close — dropped
    };

    auto attached = FundingAttributor::attach({posA}, fundingEvents);
    CHECK(attached.size() == 1);
    CHECK(std::abs(attached[0].fundingPnl - (-1.5)) < 1e-9);
    CHECK(std::abs(attached[0].netPnl() - (-1.5)) < 1e-9);

    // BinanceFuturesClient test
    {
        BinanceFuturesClient client;
        client.apiKey = "mockKey";
        client.secret = "mockSecret";
        client.transport = [](const ExchangeHttpRequest &req) -> ExchangeHttpResponse {
            ExchangeHttpResponse resp;
            resp.status = 200;
            if (req.url.find("/fapi/v1/time") != std::string::npos) {
                resp.body = "{\"serverTime\": 1700000000000}";
            } else if (req.url.find("/fapi/v1/userTrades") != std::string::npos) {
                resp.body = R"([
                    {
                        "id": 12345,
                        "symbol": "BTCUSDT",
                        "side": "BUY",
                        "positionSide": "LONG",
                        "price": "50000.0",
                        "qty": "0.1",
                        "quoteQty": "5000.0",
                        "commission": "2.5",
                        "commissionAsset": "USDT",
                        "realizedPnl": "0",
                        "time": 1700000001000
                    }
                ])";
            } else if (req.url.find("/fapi/v1/income") != std::string::npos) {
                resp.body = R"([
                    {
                        "symbol": "BTCUSDT",
                        "incomeType": "FUNDING_FEE",
                        "income": "-0.50",
                        "asset": "USDT",
                        "time": 1700000002000
                    }
                ])";
            }
            return resp;
        };

        auto fills = client.fetchFills(1700000000000LL, 1700000005000LL);
        CHECK(fills.size() == 1);
        CHECK(fills[0].id == 12345);
        CHECK(fills[0].symbol == "BTCUSDT");
        CHECK(fills[0].side == "BUY");
        CHECK(fills[0].commission == -2.5); // Binance commission is negative for paid fee
        CHECK(fills[0].commissionAsset == "USDT");

        auto funding = client.fetchFunding(1700000000000LL, 1700000005000LL);
        CHECK(funding.size() == 1);
        CHECK(funding[0].symbol == "BTCUSDT");
        CHECK(funding[0].amount == -0.50);
        CHECK(funding[0].time == 1700000002000LL);
    }

    // OKXSwapClient test
    {
        CHECK(OKXSwapClient::symbolFromInstID("BTC-USDT-SWAP") == "BTCUSDT");
        CHECK(OKXSwapClient::symbolFromInstID("ETH-USDT-230630") == "ETHUSDT230630");

        OKXSwapClient client;
        client.apiKey = "mockKey";
        client.secret = "mockSecret";
        client.passphrase = "mockPass";
        client.minPageIntervalMs = 0;
        client.transport = [](const ExchangeHttpRequest &req) -> ExchangeHttpResponse {
            ExchangeHttpResponse resp;
            resp.status = 200;
            if (req.url.find("/api/v5/trade/fills-history") != std::string::npos) {
                resp.body = R"({
                    "code": "0",
                    "msg": "",
                    "data": [
                        {
                            "instId": "BTC-USDT-SWAP",
                            "tradeId": "98765",
                            "billId": "111",
                            "side": "sell",
                            "posSide": "long",
                            "fillPx": "60000.0",
                            "fillSz": "1",
                            "fee": "-3.0",
                            "feeCcy": "USDT",
                            "fillPnl": "100.0",
                            "ts": "1700000003000",
                            "subType": "5"
                        }
                    ]
                })";
            } else if (req.url.find("/api/v5/account/bills-history") != std::string::npos) {
                resp.body = R"({
                    "code": "0",
                    "msg": "",
                    "data": [
                        {
                            "instId": "BTC-USDT-SWAP",
                            "billId": "222",
                            "pnl": "-1.2",
                            "fee": "0",
                            "ts": "1700000004000"
                        }
                    ]
                })";
            }
            return resp;
        };

        auto fills = client.fetchFills(1700000000000LL, 1700000005000LL);
        CHECK(fills.size() == 1);
        CHECK(fills[0].id == 98765);
        CHECK(fills[0].symbol == "BTCUSDT");
        CHECK(fills[0].side == "SELL");
        CHECK(fills[0].positionSide == "LONG");
        CHECK(fills[0].effect == TradingFillEffect::close); // subType "5" is close
        CHECK(fills[0].commission == -3.0);
        CHECK(fills[0].realizedPnl == 100.0);

        auto funding = client.fetchFunding(1700000000000LL, 1700000005000LL);
        CHECK(funding.size() == 1);
        CHECK(funding[0].symbol == "BTCUSDT");
        CHECK(funding[0].amount == -1.2);
    }

    // HyperliquidInfoClient test
    {
        const auto valid = HyperliquidInfoClient::normalizedAddress("0x54625b1f7c703b413D6E1d29381c850B3E7A4A28");
        CHECK(valid.has_value());
        CHECK(*valid == "0x54625b1f7c703b413d6e1d29381c850b3e7a4a28");
        CHECK(!HyperliquidInfoClient::normalizedAddress("0xinvalid").has_value());
        CHECK(!HyperliquidInfoClient::normalizedAddress("12345").has_value());

        HyperliquidInfoClient client;
        client.user = "0x54625b1f7c703b413d6e1d29381c850b3e7a4a28";
        client.transport = [](const ExchangeHttpRequest &req) -> ExchangeHttpResponse {
            ExchangeHttpResponse resp;
            resp.status = 200;
            if (req.body.find("userFillsByTime") != std::string::npos) {
                resp.body = R"([
                    {
                        "closedPnl": "50.0",
                        "coin": "SOL",
                        "dir": "Close Long",
                        "fee": "0.4",
                        "feeToken": "USDC",
                        "px": "150.0",
                        "side": "A",
                        "sz": "10.0",
                        "tid": 55555,
                        "time": 1700000002000
                    }
                ])";
            } else if (req.body.find("userFunding") != std::string::npos) {
                resp.body = R"([
                    {
                        "time": 1700000003000,
                        "delta": {
                            "coin": "SOL",
                            "usdc": "-0.25"
                        }
                    }
                ])";
            }
            return resp;
        };

        auto fills = client.fetchFills(1700000000000LL, 1700000005000LL);
        CHECK(fills.size() == 1);
        CHECK(fills[0].id == 55555);
        CHECK(fills[0].symbol == "SOL");
        CHECK(fills[0].side == "SELL");
        CHECK(fills[0].effect == TradingFillEffect::close);
        CHECK(fills[0].commission == -0.4); // HL fee inverted
        CHECK(fills[0].commissionAsset == "USDC");
        CHECK(fills[0].realizedPnl == 50.0);

        auto funding = client.fetchFunding(1700000000000LL, 1700000005000LL);
        CHECK(funding.size() == 1);
        CHECK(funding[0].symbol == "SOL");
        CHECK(funding[0].amount == -0.25);
    }

    std::cout << g_passes << " passed, " << g_fails << " failed\n";
    return g_fails == 0 ? 0 : 1;
}
