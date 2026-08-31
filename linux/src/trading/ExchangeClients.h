#pragma once

#include "TradingModels.h"

#include <cstdint>
#include <functional>
#include <optional>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace wick {

struct ExchangeHttpError : std::runtime_error {
    enum Kind { invalidCredentials, timestamp, rateLimited, http, network, malformed };
    Kind kind;
    int status = 0;
    explicit ExchangeHttpError(Kind k, const std::string &msg, int st = 0)
        : std::runtime_error(msg), kind(k), status(st) {}
};

struct ExchangeHttpRequest {
    std::string method = "GET";
    std::string url;
    std::vector<std::pair<std::string, std::string>> headers;
    std::string body;
};

struct ExchangeHttpResponse {
    int status = 0;
    std::string body;
    std::string error;
};

using ExchangeTransport = std::function<ExchangeHttpResponse(const ExchangeHttpRequest &)>;

std::int64_t exchangeNowMs();

struct BinanceFuturesClient {
    std::string apiKey;
    std::string secret;
    std::string baseURL = "https://fapi.binance.com";
    ExchangeTransport transport;
    std::int64_t chunkMs = 7LL * 24 * 3600 * 1000;
    int pageLimit = 1000;

    std::vector<TradingFill> fetchFills(std::int64_t fromMs, std::int64_t toMs) const;
    std::vector<FundingEvent> fetchFunding(std::int64_t fromMs, std::int64_t toMs) const;
    static std::string sign(const std::string &query, const std::string &secret);
};

struct OKXSwapClient {
    std::string apiKey;
    std::string secret;
    std::string passphrase;
    std::string baseURL = "https://www.okx.com";
    ExchangeTransport transport;
    int pageLimit = 100;
    int minPageIntervalMs = 220;

    std::vector<TradingFill> fetchFills(std::int64_t fromMs, std::int64_t toMs) const;
    std::vector<FundingEvent> fetchFunding(std::int64_t fromMs, std::int64_t toMs) const;
    static std::string symbolFromInstID(std::string instID);
    static std::string timestampString(std::int64_t epochMs);
    static std::string sign(const std::string &prehash, const std::string &secret);
};

struct HyperliquidInfoClient {
    std::string user;
    std::string baseURL = "https://api.hyperliquid.xyz";
    ExchangeTransport transport;
    int pageLimit = 2000;

    static std::optional<std::string> normalizedAddress(const std::string &raw);
    std::vector<TradingFill> fetchFills(std::int64_t fromMs, std::int64_t toMs) const;
    std::vector<FundingEvent> fetchFunding(std::int64_t fromMs, std::int64_t toMs) const;
};

} // namespace wick
