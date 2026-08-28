import CryptoKit
import Foundation

/// Read-only OKX perpetual (`SWAP`) fill history.
///
/// Signs with `Base64(HMAC-SHA256(secret, timestamp + METHOD + requestPath + body))`.
/// History is capped by OKX at roughly three months (`fills-history`).
public struct OKXSwapClient: ExchangeTradeClient, Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    public var apiKey: String
    public var secret: String
    public var passphrase: String
    public var baseURL: URL
    public var transport: Transport
    public var now: @Sendable () -> Date
    public var pageLimit: Int
    /// Minimum spacing between paginated requests. OKX throttles private
    /// endpoints to ~10 requests / 2s, so a large backfill paced below this
    /// would otherwise fail the whole round (TR-05).
    public var minPageInterval: TimeInterval

    public init(
        apiKey: String,
        secret: String,
        passphrase: String,
        baseURL: URL = URL(string: "https://www.okx.com")!,
        transport: @escaping Transport = Self.defaultTransport,
        now: @escaping @Sendable () -> Date = Date.init,
        pageLimit: Int = 100,
        minPageInterval: TimeInterval = 0.22
    ) {
        self.apiKey = apiKey
        self.secret = secret
        self.passphrase = passphrase
        self.baseURL = baseURL
        self.transport = transport
        self.now = now
        self.pageLimit = pageLimit
        self.minPageInterval = minPageInterval
    }

    public func fetchFills(from start: Date, to end: Date) async throws -> [TradingFill] {
        guard start < end else { return [] }
        let startMs = Int64((start.timeIntervalSince1970 * 1000).rounded())
        var results: [TradingFill] = []
        var after: String?
        var pages = 0
        while pages < 200 {
            pages += 1
            let (page, lastBillID) = try await fillsPage(
                from: start,
                to: end,
                after: after
            )
            results.append(contentsOf: TradingFill.clipped(page, from: start, to: end))
            // `after` walks toward older bills; stop once the page crosses
            // the journal-day floor even if OKX ignored `begin`.
            if page.contains(where: { $0.time < startMs }) { break }
            guard page.count >= pageLimit, let lastBillID else { break }
            after = lastBillID
            await paceNextPage()
        }
        return results
    }

    /// Funding-fee bills (`type=8`) in `[start, end)`. History is capped at
    /// roughly three months, the same as fills.
    public func fetchFunding(from start: Date, to end: Date) async throws -> [FundingEvent] {
        guard start < end else { return [] }
        let startMs = Int64((start.timeIntervalSince1970 * 1000).rounded())
        let endMs = Int64((end.timeIntervalSince1970 * 1000).rounded())
        var results: [FundingEvent] = []
        var after: String?
        var pages = 0
        while pages < 200 {
            pages += 1
            let (page, lastBillID) = try await billsPage(
                from: start,
                to: end,
                after: after
            )
            results.append(contentsOf: page.filter { $0.time >= startMs && $0.time < endMs })
            if page.contains(where: { $0.time < startMs }) { break }
            guard page.count >= pageLimit, let lastBillID else { break }
            after = lastBillID
            await paceNextPage()
        }
        return results
    }

    /// Sleeps `minPageInterval` between paginated requests to stay under OKX's
    /// ~10 req / 2s private-endpoint throttle (TR-05).
    private func paceNextPage() async {
        guard minPageInterval > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(minPageInterval * 1_000_000_000))
    }

    // MARK: - Signing

    /// ISO-8601 UTC with milliseconds, as OKX requires on `OK-ACCESS-TIMESTAMP`.
    public static func timestampString(from date: Date) -> String {
        let millis = Int((date.timeIntervalSince1970 * 1000).rounded())
        let seconds = TimeInterval(millis) / 1000
        let formatted = ISO8601DateFormatter()
        formatted.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatted.timeZone = TimeZone(secondsFromGMT: 0)
        return formatted.string(from: Date(timeIntervalSince1970: seconds))
    }

    public static func sign(prehash: String, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let code = HMAC<SHA256>.authenticationCode(for: Data(prehash.utf8), using: key)
        return Data(code).base64EncodedString()
    }

    public static func prehash(timestamp: String, method: String, requestPath: String, body: String = "") -> String {
        timestamp + method + requestPath + body
    }

    /// `BTC-USDT-SWAP` → `BTCUSDT`; unknown shapes pass through without dashes.
    public static func symbol(fromInstID instID: String) -> String {
        let parts = instID.split(separator: "-").map(String.init)
        guard parts.count >= 2 else {
            return instID.replacingOccurrences(of: "-", with: "")
        }
        var tokens = parts
        if let last = tokens.last, last == "SWAP" || last == "FUTURES" {
            tokens.removeLast()
        }
        return tokens.joined()
    }

    // MARK: - Requests

    private func fillsPage(
        from: Date,
        to: Date,
        after: String?
    ) async throws -> ([TradingFill], String?) {
        var query: [(String, String)] = [
            ("instType", "SWAP"),
            ("begin", String(Self.milliseconds(from))),
            ("end", String(Self.milliseconds(to))),
            ("limit", String(pageLimit)),
        ]
        if let after {
            query.append(("after", after))
        }
        let path = "/api/v5/trade/fills-history?" + query.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        let request = try signedRequest(method: "GET", requestPath: path, body: "")
        let (data, response) = try await transport(request)
        try checkResponse(data: data, response: response)
        let decoded = try decodeEnvelope(data)
        let fills = decoded.data.map { $0.asTradingFill() }
        return (fills, decoded.data.last?.billId)
    }

    private func billsPage(
        from: Date,
        to: Date,
        after: String?
    ) async throws -> ([FundingEvent], String?) {
        var query: [(String, String)] = [
            ("instType", "SWAP"),
            ("type", "8"),
            ("begin", String(Self.milliseconds(from))),
            ("end", String(Self.milliseconds(to))),
            ("limit", String(pageLimit)),
        ]
        if let after {
            query.append(("after", after))
        }
        let path = "/api/v5/account/bills-history?" + query.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        let request = try signedRequest(method: "GET", requestPath: path, body: "")
        let (data, response) = try await transport(request)
        try checkResponse(data: data, response: response)
        let decoded = try decodeBillEnvelope(data)
        let events = decoded.data.map { $0.asFundingEvent() }
        return (events, decoded.data.last?.billId)
    }

    func signedRequest(method: String, requestPath: String, body: String) throws -> URLRequest {
        let timestamp = Self.timestampString(from: now())
        let prehash = Self.prehash(
            timestamp: timestamp,
            method: method,
            requestPath: requestPath,
            body: body
        )
        let signature = Self.sign(prehash: prehash, secret: secret)
        guard let url = URL(string: baseURL.absoluteString + requestPath) else {
            throw ExchangeClientError.network("bad url")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue(apiKey, forHTTPHeaderField: "OK-ACCESS-KEY")
        request.setValue(signature, forHTTPHeaderField: "OK-ACCESS-SIGN")
        request.setValue(timestamp, forHTTPHeaderField: "OK-ACCESS-TIMESTAMP")
        request.setValue(passphrase, forHTTPHeaderField: "OK-ACCESS-PASSPHRASE")
        if !body.isEmpty {
            request.httpBody = Data(body.utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    // MARK: - Decode

    struct Envelope: Decodable {
        var code: String
        var msg: String?
        var data: [FillRow]
    }

    struct FillRow: Decodable {
        var instId: String
        var tradeId: String?
        var billId: String?
        var side: String?
        var posSide: String?
        var subType: String?
        var fillPx: String?
        var fillSz: String?
        var fillPnl: String?
        var fee: String?
        var feeCcy: String?
        var ts: String?

        func asTradingFill() -> TradingFill {
            let idRaw = tradeId ?? billId ?? "0"
            let pos: String = {
                switch (posSide ?? "net").lowercased() {
                case "long": return "LONG"
                case "short": return "SHORT"
                default: return "BOTH"
                }
            }()
            let sideNorm = (side ?? "").lowercased() == "sell" ? "SELL" : "BUY"
            let tsMs = Int64(ts ?? "0") ?? 0
            // `subType` disambiguates fills whose open/close intent is not
            // derivable from side alone. OKX encodes it as NUMERIC codes
            // (5 = 平多 close long, 6 = 平空 close short, 104/105 = 强平
            // long/short, 125/126 = ADL 平多/空, plus other close-side codes);
            // these always reduce a position, so a lone one at a flat window is
            // a close — not a phantom new position (TR-06).
            let effect: TradingFillEffect? = {
                switch subType ?? "" {
                case "5", "6", "100", "101", "104", "105", "112", "113", "125", "126":
                    return .close
                default:
                    return nil
                }
            }()
            return TradingFill(
                id: TradingFill.integerID(from: idRaw),
                symbol: OKXSwapClient.symbol(fromInstID: instId),
                side: sideNorm,
                positionSide: pos,
                price: Double(fillPx ?? "") ?? 0,
                // NOTE (TR-02): `fillSz` is in CONTRACTS (张), not base units —
                // a BTC SWAP contract is 100 coin, so this magnitude is ~100x
                // the base quantity. The real conversion needs instruments
                // `ctVal`; until then treat this as display-only.
                qty: Double(fillSz ?? "") ?? 0,
                quoteQty: 0,
                commission: Double(fee ?? "") ?? 0,
                commissionAsset: feeCcy ?? "",
                realizedPnl: Double(fillPnl ?? "") ?? 0,
                effect: effect,
                time: tsMs
            )
        }
    }

    /// A funding-fee bill from `bills-history`. The exact field carrying the
    /// funding amount (`pnl` vs `fee`) is venue-dependent; prefer `pnl` and
    /// fall back to `fee` defensively.
    struct BillRow: Decodable {
        var billId: String?
        var instId: String?
        var pnl: String?
        var fee: String?
        var ts: String?

        func asFundingEvent() -> FundingEvent {
            let amount: Double = {
                if let pnl = Double(pnl ?? ""), pnl != 0 { return pnl }
                return Double(fee ?? "") ?? 0
            }()
            return FundingEvent(
                symbol: OKXSwapClient.symbol(fromInstID: instId ?? ""),
                amount: amount,
                time: Int64(ts ?? "0") ?? 0
            )
        }
    }

    private func decodeEnvelope(_ data: Data) throws -> Envelope {
        guard let decoded = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw ExchangeClientError.malformedResponse
        }
        return decoded
    }

    private func decodeBillEnvelope(_ data: Data) throws -> BillEnvelope {
        guard let decoded = try? JSONDecoder().decode(BillEnvelope.self, from: data) else {
            throw ExchangeClientError.malformedResponse
        }
        return decoded
    }

    struct BillEnvelope: Decodable {
        var code: String
        var msg: String?
        var data: [BillRow]
    }

    private func checkResponse(data: Data, response: HTTPURLResponse) throws {
        if response.statusCode == 429 || response.statusCode == 418 {
            throw ExchangeClientError.rateLimited
        }
        if response.statusCode == 401 || response.statusCode == 403 {
            throw ExchangeClientError.invalidCredentials("")
        }
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: data) {
            if envelope.code == "0" { return }
            // 50011 — request rate limited (HTTP still 200); surface as rateLimited.
            if envelope.code == "50011" {
                throw ExchangeClientError.rateLimited
            }
            // 50111 / 50113 / 50119 — invalid key / sign / passphrase
            if ["50111", "50113", "50119", "50105"].contains(envelope.code) {
                throw ExchangeClientError.invalidCredentials(envelope.msg ?? envelope.code)
            }
            throw ExchangeClientError.http(response.statusCode, envelope.msg ?? envelope.code)
        }
        guard (200...299).contains(response.statusCode) else {
            throw ExchangeClientError.http(response.statusCode, "")
        }
    }

}
