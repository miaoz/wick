#include "ExchangeClients.h"

#include "Crypto.h"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <ctime>
#include <regex>
#include <thread>

namespace wick {
namespace {

using json = nlohmann::json;

std::int64_t nowMs()
{
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

double asNumber(const json &v)
{
    if (v.is_number())
        return v.get<double>();
    if (v.is_string()) {
        try {
            return std::stod(v.get<std::string>());
        } catch (...) {
            return 0.0;
        }
    }
    return 0.0;
}

std::int64_t asInt64(const json &v)
{
    if (v.is_number_integer())
        return v.get<std::int64_t>();
    if (v.is_number())
        return static_cast<std::int64_t>(v.get<double>());
    if (v.is_string()) {
        try {
            return std::stoll(v.get<std::string>());
        } catch (...) {
            return 0;
        }
    }
    return 0;
}

std::string jsonString(const json &v)
{
    if (v.is_string())
        return v.get<std::string>();
    return {};
}

json parseJson(const std::string &body)
{
    try {
        return json::parse(body);
    } catch (const std::exception &e) {
        throw ExchangeHttpError(ExchangeHttpError::malformed, e.what());
    }
}

void throwIfHttpFailed(int status, const std::string &body)
{
    if (status >= 200 && status < 300)
        return;
    std::string msg;
    int code = 0;
    try {
        const auto doc = json::parse(body);
        if (doc.is_object()) {
            if (doc.contains("msg") && doc["msg"].is_string())
                msg = doc["msg"].get<std::string>();
            else if (doc.contains("message") && doc["message"].is_string())
                msg = doc["message"].get<std::string>();
            if (doc.contains("code") && doc["code"].is_number_integer())
                code = doc["code"].get<int>();
        }
    } catch (...) {
    }
    if (status == 429 || status == 418)
        throw ExchangeHttpError(ExchangeHttpError::rateLimited, msg, status);
    if (status == 401 || status == 403 || code == -2014 || code == -2015 || code == -1022)
        throw ExchangeHttpError(ExchangeHttpError::invalidCredentials, msg, status);
    if (code == -1021)
        throw ExchangeHttpError(ExchangeHttpError::timestamp, msg, status);
    throw ExchangeHttpError(ExchangeHttpError::http, msg, status);
}

TradingFill fillFromBinance(const json &o)
{
    TradingFill f;
    f.id = asInt64(o.value("id", json(0)));
    f.symbol = jsonString(o.value("symbol", json("")));
    f.side = jsonString(o.value("side", json("")));
    const std::string ps = jsonString(o.value("positionSide", json("")));
    f.positionSide = ps.empty() ? "BOTH" : ps;
    f.price = asNumber(o.value("price", json(0.0)));
    f.qty = asNumber(o.value("qty", json(0.0)));
    f.quoteQty = asNumber(o.value("quoteQty", json(0.0)));
    f.commission = -asNumber(o.value("commission", json(0.0)));
    f.commissionAsset = jsonString(o.value("commissionAsset", json("")));
    f.realizedPnl = asNumber(o.value("realizedPnl", json(0.0)));
    f.time = asInt64(o.value("time", json(0)));
    f.effect = TradingFill::inferredEffect(f.side, f.positionSide, f.realizedPnl);
    return f;
}

} // namespace

std::int64_t exchangeNowMs()
{
    return nowMs();
}

std::string BinanceFuturesClient::sign(const std::string &query, const std::string &secret)
{
    return hmacSha256Hex(secret, query);
}

std::vector<TradingFill> BinanceFuturesClient::fetchFills(std::int64_t fromMs, std::int64_t toMs) const
{
    if (fromMs >= toMs || !transport)
        return {};
    ExchangeHttpRequest timeReq;
    timeReq.url = baseURL + "/fapi/v1/time";
    const auto timeResp = transport(timeReq);
    if (!timeResp.error.empty())
        throw ExchangeHttpError(ExchangeHttpError::network, timeResp.error);
    throwIfHttpFailed(timeResp.status, timeResp.body);
    const auto timeDoc = parseJson(timeResp.body);
    const std::int64_t serverTime = asInt64(timeDoc.value("serverTime", json(0)));
    const std::int64_t offset = serverTime - nowMs();

    std::vector<TradingFill> result;
    std::int64_t chunkStart = fromMs;
    while (chunkStart < toMs) {
        const std::int64_t chunkEnd = std::min(toMs, chunkStart + chunkMs);
        std::int64_t cursor = chunkStart;
        int pages = 0;
        while (cursor < chunkEnd && pages < 200) {
            ++pages;
            const std::string query =
                "startTime=" + std::to_string(cursor)
                + "&endTime=" + std::to_string(chunkEnd)
                + "&limit=" + std::to_string(pageLimit)
                + "&recvWindow=5000"
                + "&timestamp=" + std::to_string(nowMs() + offset);
            const std::string signature = sign(query, secret);
            ExchangeHttpRequest req;
            req.url = baseURL + "/fapi/v1/userTrades?" + query + "&signature=" + signature;
            req.headers.push_back({"X-MBX-APIKEY", apiKey});
            const auto resp = transport(req);
            if (!resp.error.empty())
                throw ExchangeHttpError(ExchangeHttpError::network, resp.error);
            throwIfHttpFailed(resp.status, resp.body);
            const auto doc = parseJson(resp.body);
            if (!doc.is_array())
                throw ExchangeHttpError(ExchangeHttpError::malformed, "binance trades not array");
            std::int64_t lastTime = cursor;
            for (const auto &v : doc) {
                const auto fill = fillFromBinance(v);
                result.push_back(fill);
                lastTime = std::max(lastTime, fill.time);
            }
            if (static_cast<int>(doc.size()) < pageLimit)
                break;
            cursor = std::max(lastTime + 1, cursor + 1);
        }
        chunkStart = chunkEnd + 1;
    }
    return result;
}

std::vector<FundingEvent> BinanceFuturesClient::fetchFunding(std::int64_t fromMs, std::int64_t toMs) const
{
    if (fromMs >= toMs || !transport)
        return {};
    ExchangeHttpRequest timeReq;
    timeReq.url = baseURL + "/fapi/v1/time";
    const auto timeResp = transport(timeReq);
    if (!timeResp.error.empty())
        throw ExchangeHttpError(ExchangeHttpError::network, timeResp.error);
    throwIfHttpFailed(timeResp.status, timeResp.body);
    const auto timeDoc = parseJson(timeResp.body);
    const std::int64_t serverTime = asInt64(timeDoc.value("serverTime", json(0)));
    const std::int64_t offset = serverTime - nowMs();

    std::vector<FundingEvent> result;
    std::int64_t chunkStart = fromMs;
    while (chunkStart < toMs) {
        const std::int64_t chunkEnd = std::min(toMs, chunkStart + chunkMs);
        std::int64_t cursor = chunkStart;
        int pages = 0;
        while (cursor < chunkEnd && pages < 200) {
            ++pages;
            const std::string query =
                "incomeType=FUNDING_FEE&startTime=" + std::to_string(cursor)
                + "&endTime=" + std::to_string(chunkEnd)
                + "&limit=" + std::to_string(pageLimit)
                + "&recvWindow=5000"
                + "&timestamp=" + std::to_string(nowMs() + offset);
            const std::string signature = sign(query, secret);
            ExchangeHttpRequest req;
            req.url = baseURL + "/fapi/v1/income?" + query + "&signature=" + signature;
            req.headers.push_back({"X-MBX-APIKEY", apiKey});
            const auto resp = transport(req);
            if (!resp.error.empty())
                throw ExchangeHttpError(ExchangeHttpError::network, resp.error);
            throwIfHttpFailed(resp.status, resp.body);
            const auto doc = parseJson(resp.body);
            if (!doc.is_array())
                throw ExchangeHttpError(ExchangeHttpError::malformed, "binance income not array");
            std::int64_t lastTime = cursor;
            for (const auto &v : doc) {
                FundingEvent fe;
                fe.symbol = jsonString(v.value("symbol", json("")));
                fe.amount = asNumber(v.value("income", json(0.0)));
                fe.time = asInt64(v.value("time", json(0)));
                result.push_back(fe);
                lastTime = std::max(lastTime, fe.time);
            }
            if (static_cast<int>(doc.size()) < pageLimit)
                break;
            cursor = std::max(lastTime + 1, cursor + 1);
        }
        chunkStart = chunkEnd + 1;
    }
    return result;
}

std::string OKXSwapClient::symbolFromInstID(std::string instID)
{
    std::vector<std::string> parts;
    std::string cur;
    for (char c : instID) {
        if (c == '-') {
            parts.push_back(cur);
            cur.clear();
        } else {
            cur.push_back(c);
        }
    }
    if (!cur.empty())
        parts.push_back(cur);
    if (parts.size() < 2) {
        instID.erase(std::remove(instID.begin(), instID.end(), '-'), instID.end());
        return instID;
    }
    if (!parts.empty() && (parts.back() == "SWAP" || parts.back() == "FUTURES"))
        parts.pop_back();
    std::string out;
    for (const auto &p : parts)
        out += p;
    return out;
}

std::string OKXSwapClient::timestampString(std::int64_t epochMs)
{
    const std::time_t sec = static_cast<std::time_t>(epochMs / 1000);
    const int milli = static_cast<int>(epochMs % 1000);
    std::tm tm{};
    gmtime_r(&sec, &tm);
    char buf[64];
    std::snprintf(buf, sizeof(buf), "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
                  tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday,
                  tm.tm_hour, tm.tm_min, tm.tm_sec, milli);
    return buf;
}

std::string OKXSwapClient::sign(const std::string &prehash, const std::string &secret)
{
    return hmacSha256Base64(secret, prehash);
}

std::vector<TradingFill> OKXSwapClient::fetchFills(std::int64_t fromMs, std::int64_t toMs) const
{
    if (fromMs >= toMs || !transport)
        return {};
    std::vector<TradingFill> results;
    std::string after;
    int pages = 0;
    while (pages < 200) {
        ++pages;
        std::string query = "instType=SWAP&begin=" + std::to_string(fromMs)
            + "&end=" + std::to_string(toMs) + "&limit=" + std::to_string(pageLimit);
        if (!after.empty())
            query += "&after=" + after;
        const std::string path = "/api/v5/trade/fills-history?" + query;
        const std::string ts = timestampString(nowMs());
        const std::string prehash = ts + "GET" + path;
        ExchangeHttpRequest req;
        req.url = baseURL + path;
        req.headers.push_back({"OK-ACCESS-KEY", apiKey});
        req.headers.push_back({"OK-ACCESS-SIGN", sign(prehash, secret)});
        req.headers.push_back({"OK-ACCESS-TIMESTAMP", ts});
        req.headers.push_back({"OK-ACCESS-PASSPHRASE", passphrase});
        const auto resp = transport(req);
        if (!resp.error.empty())
            throw ExchangeHttpError(ExchangeHttpError::network, resp.error);
        throwIfHttpFailed(resp.status, resp.body);
        const auto doc = parseJson(resp.body);
        if (doc.value("code", "") != "0") {
            const std::string msg = doc.value("msg", "");
            throw ExchangeHttpError(ExchangeHttpError::invalidCredentials, msg);
        }
        const auto arr = doc.value("data", json::array());
        std::string lastBill;
        bool crossedFloor = false;
        for (const auto &o : arr) {
            TradingFill f;
            const std::string tradeId = jsonString(o.value("tradeId", json("")));
            const std::string billId = jsonString(o.value("billId", json("")));
            f.id = TradingFill::integerID(tradeId.empty() ? billId : tradeId);
            f.symbol = symbolFromInstID(jsonString(o.value("instId", json(""))));
            std::string side = jsonString(o.value("side", json("")));
            std::transform(side.begin(), side.end(), side.begin(), ::tolower);
            f.side = (side == "sell") ? "SELL" : "BUY";
            std::string pos = jsonString(o.value("posSide", json("")));
            std::transform(pos.begin(), pos.end(), pos.begin(), ::tolower);
            if (pos == "long")
                f.positionSide = "LONG";
            else if (pos == "short")
                f.positionSide = "SHORT";
            else
                f.positionSide = "BOTH";
            f.price = asNumber(o.value("fillPx", json(0.0)));
            f.qty = asNumber(o.value("fillSz", json(0.0)));
            f.commission = asNumber(o.value("fee", json(0.0)));
            f.commissionAsset = jsonString(o.value("feeCcy", json("")));
            f.realizedPnl = asNumber(o.value("fillPnl", json(0.0)));
            f.time = asInt64(o.value("ts", json(0)));
            const std::string sub = jsonString(o.value("subType", json("")));
            static const char *kClose[] = {"5", "6", "100", "101", "104", "105", "112", "113", "125", "126"};
            f.effect = TradingFillEffect::unknown;
            for (const char *c : kClose) {
                if (sub == c) {
                    f.effect = TradingFillEffect::close;
                    break;
                }
            }
            if (f.effect == TradingFillEffect::unknown)
                f.effect = TradingFill::inferredEffect(f.side, f.positionSide, f.realizedPnl);
            if (f.time >= fromMs && f.time < toMs)
                results.push_back(f);
            if (f.time < fromMs)
                crossedFloor = true;
            lastBill = billId;
        }
        if (crossedFloor || static_cast<int>(arr.size()) < pageLimit || lastBill.empty())
            break;
        after = lastBill;
        if (minPageIntervalMs > 0)
            std::this_thread::sleep_for(std::chrono::milliseconds(minPageIntervalMs));
    }
    return results;
}

std::vector<FundingEvent> OKXSwapClient::fetchFunding(std::int64_t fromMs, std::int64_t toMs) const
{
    if (fromMs >= toMs || !transport)
        return {};
    std::vector<FundingEvent> results;
    std::string after;
    int pages = 0;
    while (pages < 200) {
        ++pages;
        std::string query = "instType=SWAP&type=8&begin=" + std::to_string(fromMs)
            + "&end=" + std::to_string(toMs) + "&limit=" + std::to_string(pageLimit);
        if (!after.empty())
            query += "&after=" + after;
        const std::string path = "/api/v5/account/bills-history?" + query;
        const std::string ts = timestampString(nowMs());
        const std::string prehash = ts + "GET" + path;
        ExchangeHttpRequest req;
        req.url = baseURL + path;
        req.headers.push_back({"OK-ACCESS-KEY", apiKey});
        req.headers.push_back({"OK-ACCESS-SIGN", sign(prehash, secret)});
        req.headers.push_back({"OK-ACCESS-TIMESTAMP", ts});
        req.headers.push_back({"OK-ACCESS-PASSPHRASE", passphrase});
        const auto resp = transport(req);
        if (!resp.error.empty())
            throw ExchangeHttpError(ExchangeHttpError::network, resp.error);
        throwIfHttpFailed(resp.status, resp.body);
        const auto doc = parseJson(resp.body);
        if (doc.value("code", "") != "0") {
            const std::string msg = doc.value("msg", "");
            throw ExchangeHttpError(ExchangeHttpError::invalidCredentials, msg);
        }
        const auto arr = doc.value("data", json::array());
        std::string lastBill;
        bool crossedFloor = false;
        for (const auto &o : arr) {
            FundingEvent fe;
            const std::string billId = jsonString(o.value("billId", json("")));
            fe.symbol = symbolFromInstID(jsonString(o.value("instId", json(""))));
            const double pnl = asNumber(o.value("pnl", json(0.0)));
            fe.amount = (pnl != 0.0) ? pnl : asNumber(o.value("fee", json(0.0)));
            fe.time = asInt64(o.value("ts", json(0)));
            if (fe.time >= fromMs && fe.time < toMs)
                results.push_back(fe);
            if (fe.time < fromMs)
                crossedFloor = true;
            lastBill = billId;
        }
        if (crossedFloor || static_cast<int>(arr.size()) < pageLimit || lastBill.empty())
            break;
        after = lastBill;
        if (minPageIntervalMs > 0)
            std::this_thread::sleep_for(std::chrono::milliseconds(minPageIntervalMs));
    }
    return results;
}

std::optional<std::string> HyperliquidInfoClient::normalizedAddress(const std::string &raw)
{
    static const std::regex re("^0x[0-9a-fA-F]{40}$");
    std::string trimmed = raw;
    while (!trimmed.empty() && std::isspace(static_cast<unsigned char>(trimmed.front())))
        trimmed.erase(trimmed.begin());
    while (!trimmed.empty() && std::isspace(static_cast<unsigned char>(trimmed.back())))
        trimmed.pop_back();
    if (!std::regex_match(trimmed, re))
        return std::nullopt;
    for (char &c : trimmed) {
        if (c >= 'A' && c <= 'F')
            c = static_cast<char>(c - 'A' + 'a');
    }
    return trimmed;
}

std::vector<TradingFill> HyperliquidInfoClient::fetchFills(std::int64_t fromMs, std::int64_t toMs) const
{
    if (fromMs >= toMs || !transport)
        return {};
    std::vector<TradingFill> results;
    std::int64_t cursor = fromMs;
    int pages = 0;
    while (cursor < toMs && pages < 8) {
        ++pages;
        json body;
        body["type"] = "userFillsByTime";
        body["user"] = user;
        body["startTime"] = cursor;
        body["endTime"] = toMs;
        ExchangeHttpRequest req;
        req.method = "POST";
        req.url = baseURL + "/info";
        req.headers.push_back({"Content-Type", "application/json"});
        req.body = body.dump();
        const auto resp = transport(req);
        if (!resp.error.empty())
            throw ExchangeHttpError(ExchangeHttpError::network, resp.error);
        if (resp.status == 429)
            throw ExchangeHttpError(ExchangeHttpError::rateLimited, "rate limited", 429);
        throwIfHttpFailed(resp.status, resp.body);
        const auto doc = parseJson(resp.body);
        if (!doc.is_array())
            throw ExchangeHttpError(ExchangeHttpError::malformed, "hl fills not array");
        std::int64_t lastTime = cursor;
        for (const auto &o : doc) {
            TradingFill f;
            f.id = asInt64(o.value("tid", json(0)));
            if (f.id == 0)
                f.id = asInt64(o.value("time", json(0)));
            f.symbol = jsonString(o.value("coin", json("")));
            std::string side = jsonString(o.value("side", json("")));
            std::transform(side.begin(), side.end(), side.begin(), ::toupper);
            f.side = (side == "A" || side == "SELL") ? "SELL" : "BUY";
            f.positionSide = "BOTH";
            f.price = asNumber(o.value("px", json(0.0)));
            f.qty = asNumber(o.value("sz", json(0.0)));
            f.commission = -asNumber(o.value("fee", json(0.0)));
            std::string feeToken = jsonString(o.value("feeToken", json("")));
            f.commissionAsset = feeToken.empty() ? "USDC" : feeToken;
            f.realizedPnl = asNumber(o.value("closedPnl", json(0.0)));
            f.time = asInt64(o.value("time", json(0)));
            std::string dir = jsonString(o.value("dir", json("")));
            std::transform(dir.begin(), dir.end(), dir.begin(), ::tolower);
            if (dir.rfind("open ", 0) == 0)
                f.effect = TradingFillEffect::open;
            else if (dir.rfind("close ", 0) == 0)
                f.effect = TradingFillEffect::close;
            else
                f.effect = TradingFillEffect::unknown;
            results.push_back(f);
            lastTime = std::max(lastTime, f.time);
        }
        if (static_cast<int>(doc.size()) < std::min(pageLimit, 2000) || doc.empty())
            break;
        const std::int64_t next = lastTime + 1;
        if (next <= cursor)
            break;
        cursor = next;
    }
    return TradingFill::clipped(results, fromMs, toMs);
}

std::vector<FundingEvent> HyperliquidInfoClient::fetchFunding(std::int64_t fromMs, std::int64_t toMs) const
{
    if (fromMs >= toMs || !transport)
        return {};
    std::vector<FundingEvent> results;
    std::int64_t cursor = fromMs;
    int pages = 0;
    while (cursor < toMs && pages < 50) {
        ++pages;
        json body;
        body["type"] = "userFunding";
        body["user"] = user;
        body["startTime"] = cursor;
        body["endTime"] = toMs;
        ExchangeHttpRequest req;
        req.method = "POST";
        req.url = baseURL + "/info";
        req.headers.push_back({"Content-Type", "application/json"});
        req.body = body.dump();
        const auto resp = transport(req);
        if (!resp.error.empty())
            throw ExchangeHttpError(ExchangeHttpError::network, resp.error);
        if (resp.status == 429)
            throw ExchangeHttpError(ExchangeHttpError::rateLimited, "rate limited", 429);
        throwIfHttpFailed(resp.status, resp.body);
        const auto doc = parseJson(resp.body);
        if (!doc.is_array())
            throw ExchangeHttpError(ExchangeHttpError::malformed, "hl funding not array");
        std::int64_t lastTime = cursor;
        for (const auto &o : doc) {
            if (!o.contains("delta") || !o["delta"].is_object())
                continue;
            const auto &delta = o["delta"];
            const std::string coin = jsonString(delta.value("coin", json("")));
            if (coin.empty())
                continue;
            FundingEvent fe;
            fe.symbol = coin;
            fe.amount = asNumber(delta.value("usdc", json(0.0)));
            fe.time = asInt64(o.value("time", json(0)));
            results.push_back(fe);
            lastTime = std::max(lastTime, fe.time);
        }
        if (static_cast<int>(doc.size()) < 500 || doc.empty())
            break;
        const std::int64_t next = lastTime + 1;
        if (next <= cursor)
            break;
        cursor = next;
    }
    std::vector<FundingEvent> filtered;
    for (const auto &f : results) {
        if (f.time >= fromMs && f.time < toMs)
            filtered.push_back(f);
    }
    return filtered;
}

} // namespace wick
