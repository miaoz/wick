#include "ExchangeClients.h"

#include "Crypto.h"

#include <QEventLoop>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QThread>

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

std::int64_t nowMs()
{
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

double asNumber(const QJsonValue &v)
{
    if (v.isDouble())
        return v.toDouble();
    if (v.isString())
        return v.toString().toDouble();
    return 0;
}

std::int64_t asInt64(const QJsonValue &v)
{
    if (v.isDouble())
        return static_cast<std::int64_t>(v.toDouble());
    if (v.isString())
        return v.toString().toLongLong();
    return 0;
}

QJsonDocument parseJson(const QByteArray &body)
{
    QJsonParseError err;
    const auto doc = QJsonDocument::fromJson(body, &err);
    if (err.error != QJsonParseError::NoError)
        throw ExchangeHttpError(ExchangeHttpError::malformed, err.errorString().toStdString());
    return doc;
}

void throwIfHttpFailed(int status, const QByteArray &body)
{
    if (status >= 200 && status < 300)
        return;
    QString msg;
    const auto doc = QJsonDocument::fromJson(body);
    if (doc.isObject()) {
        msg = doc.object().value(QStringLiteral("msg")).toString();
        if (msg.isEmpty())
            msg = doc.object().value(QStringLiteral("message")).toString();
    }
    const int code = doc.isObject() ? doc.object().value(QStringLiteral("code")).toInt() : 0;
    if (status == 429 || status == 418)
        throw ExchangeHttpError(ExchangeHttpError::rateLimited, msg.toStdString(), status);
    if (status == 401 || status == 403 || code == -2014 || code == -2015 || code == -1022)
        throw ExchangeHttpError(ExchangeHttpError::invalidCredentials, msg.toStdString(), status);
    if (code == -1021)
        throw ExchangeHttpError(ExchangeHttpError::timestamp, msg.toStdString(), status);
    throw ExchangeHttpError(ExchangeHttpError::http, msg.toStdString(), status);
}

TradingFill fillFromBinance(const QJsonObject &o)
{
    TradingFill f;
    f.id = asInt64(o.value(QStringLiteral("id")));
    f.symbol = o.value(QStringLiteral("symbol")).toString().toStdString();
    f.side = o.value(QStringLiteral("side")).toString().toStdString();
    const QString ps = o.value(QStringLiteral("positionSide")).toString();
    f.positionSide = ps.isEmpty() ? "BOTH" : ps.toStdString();
    f.price = asNumber(o.value(QStringLiteral("price")));
    f.qty = asNumber(o.value(QStringLiteral("qty")));
    f.quoteQty = asNumber(o.value(QStringLiteral("quoteQty")));
    f.commission = -asNumber(o.value(QStringLiteral("commission")));
    f.commissionAsset = o.value(QStringLiteral("commissionAsset")).toString().toStdString();
    f.realizedPnl = asNumber(o.value(QStringLiteral("realizedPnl")));
    f.time = asInt64(o.value(QStringLiteral("time")));
    f.effect = TradingFill::inferredEffect(f.side, f.positionSide, f.realizedPnl);
    return f;
}

} // namespace

std::int64_t exchangeNowMs()
{
    return nowMs();
}

ExchangeHttpResponse qtExchangeTransport(const ExchangeHttpRequest &req)
{
    QNetworkAccessManager nam;
    QNetworkRequest qreq(req.url);
    qreq.setTransferTimeout(20000);
    for (const auto &h : req.headers)
        qreq.setRawHeader(h.first, h.second);
    QNetworkReply *reply = nullptr;
    if (req.method == QLatin1String("POST"))
        reply = nam.post(qreq, req.body);
    else
        reply = nam.get(qreq);
    QEventLoop loop;
    QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    loop.exec();
    ExchangeHttpResponse out;
    out.status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    out.body = reply->readAll();
    if (reply->error() != QNetworkReply::NoError && out.status == 0)
        out.error = reply->errorString();
    return out;
}

std::string BinanceFuturesClient::sign(const std::string &query, const std::string &secret)
{
    return hmacSha256Hex(secret, query);
}

std::vector<TradingFill> BinanceFuturesClient::fetchFills(std::int64_t fromMs, std::int64_t toMs) const
{
    if (fromMs >= toMs)
        return {};
    ExchangeHttpRequest timeReq;
    timeReq.url = QUrl(QString::fromStdString(baseURL + "/fapi/v1/time"));
    const auto timeResp = transport(timeReq);
    if (!timeResp.error.isEmpty())
        throw ExchangeHttpError(ExchangeHttpError::network, timeResp.error.toStdString());
    throwIfHttpFailed(timeResp.status, timeResp.body);
    const auto timeDoc = parseJson(timeResp.body);
    const std::int64_t serverTime = asInt64(timeDoc.object().value(QStringLiteral("serverTime")));
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
            req.url = QUrl(QString::fromStdString(baseURL + "/fapi/v1/userTrades?" + query
                                                  + "&signature=" + signature));
            req.headers.append({QByteArray("X-MBX-APIKEY"), QByteArray::fromStdString(apiKey)});
            const auto resp = transport(req);
            if (!resp.error.isEmpty())
                throw ExchangeHttpError(ExchangeHttpError::network, resp.error.toStdString());
            throwIfHttpFailed(resp.status, resp.body);
            const auto doc = parseJson(resp.body);
            if (!doc.isArray())
                throw ExchangeHttpError(ExchangeHttpError::malformed, "binance trades not array");
            const auto arr = doc.array();
            std::int64_t lastTime = cursor;
            for (const auto &v : arr) {
                const auto fill = fillFromBinance(v.toObject());
                result.push_back(fill);
                lastTime = std::max(lastTime, fill.time);
            }
            if (arr.size() < pageLimit)
                break;
            cursor = std::max(lastTime + 1, cursor + 1);
        }
        chunkStart = chunkEnd + 1;
    }
    return result;
}

std::vector<FundingEvent> BinanceFuturesClient::fetchFunding(std::int64_t fromMs, std::int64_t toMs) const
{
    if (fromMs >= toMs)
        return {};
    ExchangeHttpRequest timeReq;
    timeReq.url = QUrl(QString::fromStdString(baseURL + "/fapi/v1/time"));
    const auto timeResp = transport(timeReq);
    if (!timeResp.error.isEmpty())
        throw ExchangeHttpError(ExchangeHttpError::network, timeResp.error.toStdString());
    throwIfHttpFailed(timeResp.status, timeResp.body);
    const auto timeDoc = parseJson(timeResp.body);
    const std::int64_t serverTime = asInt64(timeDoc.object().value(QStringLiteral("serverTime")));
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
            req.url = QUrl(QString::fromStdString(baseURL + "/fapi/v1/income?" + query
                                                  + "&signature=" + signature));
            req.headers.append({QByteArray("X-MBX-APIKEY"), QByteArray::fromStdString(apiKey)});
            const auto resp = transport(req);
            if (!resp.error.isEmpty())
                throw ExchangeHttpError(ExchangeHttpError::network, resp.error.toStdString());
            throwIfHttpFailed(resp.status, resp.body);
            const auto doc = parseJson(resp.body);
            if (!doc.isArray())
                throw ExchangeHttpError(ExchangeHttpError::malformed, "binance income not array");
            const auto arr = doc.array();
            std::int64_t lastTime = cursor;
            for (const auto &v : arr) {
                const auto o = v.toObject();
                FundingEvent fe;
                fe.symbol = o.value(QStringLiteral("symbol")).toString().toStdString();
                fe.amount = asNumber(o.value(QStringLiteral("income")));
                fe.time = asInt64(o.value(QStringLiteral("time")));
                result.push_back(fe);
                lastTime = std::max(lastTime, fe.time);
            }
            if (arr.size() < pageLimit)
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
    char buf[40];
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
    if (fromMs >= toMs)
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
        req.url = QUrl(QString::fromStdString(baseURL + path));
        req.headers.append({QByteArray("OK-ACCESS-KEY"), QByteArray::fromStdString(apiKey)});
        req.headers.append({QByteArray("OK-ACCESS-SIGN"), QByteArray::fromStdString(sign(prehash, secret))});
        req.headers.append({QByteArray("OK-ACCESS-TIMESTAMP"), QByteArray::fromStdString(ts)});
        req.headers.append({QByteArray("OK-ACCESS-PASSPHRASE"), QByteArray::fromStdString(passphrase)});
        const auto resp = transport(req);
        if (!resp.error.isEmpty())
            throw ExchangeHttpError(ExchangeHttpError::network, resp.error.toStdString());
        throwIfHttpFailed(resp.status, resp.body);
        const auto doc = parseJson(resp.body);
        const auto obj = doc.object();
        if (obj.value(QStringLiteral("code")).toString() != QLatin1String("0")) {
            const QString msg = obj.value(QStringLiteral("msg")).toString();
            throw ExchangeHttpError(ExchangeHttpError::invalidCredentials, msg.toStdString());
        }
        const auto arr = obj.value(QStringLiteral("data")).toArray();
        QString lastBill;
        bool crossedFloor = false;
        for (const auto &v : arr) {
            const auto o = v.toObject();
            TradingFill f;
            const QString tradeId = o.value(QStringLiteral("tradeId")).toString();
            const QString billId = o.value(QStringLiteral("billId")).toString();
            f.id = TradingFill::integerID((tradeId.isEmpty() ? billId : tradeId).toStdString());
            f.symbol = symbolFromInstID(o.value(QStringLiteral("instId")).toString().toStdString());
            f.side = o.value(QStringLiteral("side")).toString().toLower() == QLatin1String("sell")
                ? "SELL" : "BUY";
            const QString pos = o.value(QStringLiteral("posSide")).toString().toLower();
            if (pos == QLatin1String("long"))
                f.positionSide = "LONG";
            else if (pos == QLatin1String("short"))
                f.positionSide = "SHORT";
            else
                f.positionSide = "BOTH";
            f.price = asNumber(o.value(QStringLiteral("fillPx")));
            f.qty = asNumber(o.value(QStringLiteral("fillSz")));
            f.commission = asNumber(o.value(QStringLiteral("fee")));
            f.commissionAsset = o.value(QStringLiteral("feeCcy")).toString().toStdString();
            f.realizedPnl = asNumber(o.value(QStringLiteral("fillPnl")));
            f.time = asInt64(o.value(QStringLiteral("ts")));
            const QString sub = o.value(QStringLiteral("subType")).toString();
            static const char *kClose[] = {"5", "6", "100", "101", "104", "105", "112", "113", "125", "126"};
            f.effect = TradingFillEffect::unknown;
            for (const char *c : kClose) {
                if (sub == QLatin1String(c)) {
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
        if (crossedFloor || arr.size() < pageLimit || lastBill.isEmpty())
            break;
        after = lastBill.toStdString();
        if (minPageIntervalMs > 0)
            QThread::msleep(static_cast<unsigned long>(minPageIntervalMs));
    }
    return results;
}

std::vector<FundingEvent> OKXSwapClient::fetchFunding(std::int64_t fromMs, std::int64_t toMs) const
{
    if (fromMs >= toMs)
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
        req.url = QUrl(QString::fromStdString(baseURL + path));
        req.headers.append({QByteArray("OK-ACCESS-KEY"), QByteArray::fromStdString(apiKey)});
        req.headers.append({QByteArray("OK-ACCESS-SIGN"), QByteArray::fromStdString(sign(prehash, secret))});
        req.headers.append({QByteArray("OK-ACCESS-TIMESTAMP"), QByteArray::fromStdString(ts)});
        req.headers.append({QByteArray("OK-ACCESS-PASSPHRASE"), QByteArray::fromStdString(passphrase)});
        const auto resp = transport(req);
        if (!resp.error.isEmpty())
            throw ExchangeHttpError(ExchangeHttpError::network, resp.error.toStdString());
        throwIfHttpFailed(resp.status, resp.body);
        const auto doc = parseJson(resp.body);
        const auto obj = doc.object();
        if (obj.value(QStringLiteral("code")).toString() != QLatin1String("0")) {
            const QString msg = obj.value(QStringLiteral("msg")).toString();
            throw ExchangeHttpError(ExchangeHttpError::invalidCredentials, msg.toStdString());
        }
        const auto arr = obj.value(QStringLiteral("data")).toArray();
        QString lastBill;
        bool crossedFloor = false;
        for (const auto &v : arr) {
            const auto o = v.toObject();
            FundingEvent fe;
            const QString billId = o.value(QStringLiteral("billId")).toString();
            fe.symbol = symbolFromInstID(o.value(QStringLiteral("instId")).toString().toStdString());
            const double pnl = asNumber(o.value(QStringLiteral("pnl")));
            fe.amount = (pnl != 0.0) ? pnl : asNumber(o.value(QStringLiteral("fee")));
            fe.time = asInt64(o.value(QStringLiteral("ts")));
            if (fe.time >= fromMs && fe.time < toMs)
                results.push_back(fe);
            if (fe.time < fromMs)
                crossedFloor = true;
            lastBill = billId;
        }
        if (crossedFloor || arr.size() < pageLimit || lastBill.isEmpty())
            break;
        after = lastBill.toStdString();
        if (minPageIntervalMs > 0)
            QThread::msleep(static_cast<unsigned long>(minPageIntervalMs));
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
    if (fromMs >= toMs)
        return {};
    std::vector<TradingFill> results;
    std::int64_t cursor = fromMs;
    int pages = 0;
    while (cursor < toMs && pages < 8) {
        ++pages;
        QJsonObject body;
        body.insert(QStringLiteral("type"), QStringLiteral("userFillsByTime"));
        body.insert(QStringLiteral("user"), QString::fromStdString(user));
        body.insert(QStringLiteral("startTime"), static_cast<double>(cursor));
        body.insert(QStringLiteral("endTime"), static_cast<double>(toMs));
        ExchangeHttpRequest req;
        req.method = QStringLiteral("POST");
        req.url = QUrl(QString::fromStdString(baseURL + "/info"));
        req.headers.append({QByteArray("Content-Type"), QByteArray("application/json")});
        req.body = QJsonDocument(body).toJson(QJsonDocument::Compact);
        const auto resp = transport(req);
        if (!resp.error.isEmpty())
            throw ExchangeHttpError(ExchangeHttpError::network, resp.error.toStdString());
        if (resp.status == 429)
            throw ExchangeHttpError(ExchangeHttpError::rateLimited, "rate limited", 429);
        throwIfHttpFailed(resp.status, resp.body);
        const auto doc = parseJson(resp.body);
        if (!doc.isArray())
            throw ExchangeHttpError(ExchangeHttpError::malformed, "hl fills not array");
        const auto arr = doc.array();
        std::int64_t lastTime = cursor;
        for (const auto &v : arr) {
            const auto o = v.toObject();
            TradingFill f;
            f.id = asInt64(o.value(QStringLiteral("tid")));
            if (f.id == 0)
                f.id = asInt64(o.value(QStringLiteral("time")));
            f.symbol = o.value(QStringLiteral("coin")).toString().toStdString();
            const QString side = o.value(QStringLiteral("side")).toString().toUpper();
            f.side = (side == QLatin1String("A") || side == QLatin1String("SELL")) ? "SELL" : "BUY";
            f.positionSide = "BOTH";
            f.price = asNumber(o.value(QStringLiteral("px")));
            f.qty = asNumber(o.value(QStringLiteral("sz")));
            f.commission = -asNumber(o.value(QStringLiteral("fee")));
            QString feeToken = o.value(QStringLiteral("feeToken")).toString().trimmed();
            f.commissionAsset = feeToken.isEmpty() ? "USDC" : feeToken.toStdString();
            f.realizedPnl = asNumber(o.value(QStringLiteral("closedPnl")));
            f.time = asInt64(o.value(QStringLiteral("time")));
            const QString dir = o.value(QStringLiteral("dir")).toString().toLower();
            if (dir.startsWith(QLatin1String("open ")))
                f.effect = TradingFillEffect::open;
            else if (dir.startsWith(QLatin1String("close ")))
                f.effect = TradingFillEffect::close;
            else
                f.effect = TradingFillEffect::unknown;
            results.push_back(f);
            lastTime = std::max(lastTime, f.time);
        }
        if (arr.size() < std::min(pageLimit, 2000) || arr.isEmpty())
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
    if (fromMs >= toMs)
        return {};
    std::vector<FundingEvent> results;
    std::int64_t cursor = fromMs;
    int pages = 0;
    while (cursor < toMs && pages < 50) {
        ++pages;
        QJsonObject body;
        body.insert(QStringLiteral("type"), QStringLiteral("userFunding"));
        body.insert(QStringLiteral("user"), QString::fromStdString(user));
        body.insert(QStringLiteral("startTime"), static_cast<double>(cursor));
        body.insert(QStringLiteral("endTime"), static_cast<double>(toMs));
        ExchangeHttpRequest req;
        req.method = QStringLiteral("POST");
        req.url = QUrl(QString::fromStdString(baseURL + "/info"));
        req.headers.append({QByteArray("Content-Type"), QByteArray("application/json")});
        req.body = QJsonDocument(body).toJson(QJsonDocument::Compact);
        const auto resp = transport(req);
        if (!resp.error.isEmpty())
            throw ExchangeHttpError(ExchangeHttpError::network, resp.error.toStdString());
        if (resp.status == 429)
            throw ExchangeHttpError(ExchangeHttpError::rateLimited, "rate limited", 429);
        throwIfHttpFailed(resp.status, resp.body);
        const auto doc = parseJson(resp.body);
        if (!doc.isArray())
            throw ExchangeHttpError(ExchangeHttpError::malformed, "hl funding not array");
        const auto arr = doc.array();
        std::int64_t lastTime = cursor;
        for (const auto &v : arr) {
            const auto o = v.toObject();
            const auto delta = o.value(QStringLiteral("delta")).toObject();
            const QString coin = delta.value(QStringLiteral("coin")).toString().trimmed();
            if (coin.isEmpty())
                continue;
            FundingEvent fe;
            fe.symbol = coin.toStdString();
            fe.amount = delta.value(QStringLiteral("usdc")).toString().trimmed().toDouble();
            fe.time = asInt64(o.value(QStringLiteral("time")));
            results.push_back(fe);
            lastTime = std::max(lastTime, fe.time);
        }
        if (arr.size() < 500 || arr.isEmpty())
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
