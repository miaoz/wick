import Foundation

/// Read-only Hyperliquid perpetual fills via the public `info` endpoint.
///
/// No API key: `userFillsByTime` is keyed by the user's `0x` address.
/// The venue only retains roughly the most recent 10,000 fills.
public struct HyperliquidInfoClient: ExchangeTradeClient, Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    public var user: String
    public var baseURL: URL
    public var transport: Transport
    /// Hard cap per response; the API documents 2000.
    public var pageLimit: Int

    public init(
        user: String,
        baseURL: URL = URL(string: "https://api.hyperliquid.xyz")!,
        transport: @escaping Transport = { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ExchangeClientError.network("not an HTTP response")
            }
            return (data, http)
        },
        pageLimit: Int = 2000
    ) {
        self.user = user
        self.baseURL = baseURL
        self.transport = transport
        self.pageLimit = pageLimit
    }

    public static func normalizedAddress(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = /^0x[0-9a-fA-F]{40}$/
        guard trimmed.wholeMatch(of: pattern) != nil else { return nil }
        return trimmed.lowercased()
    }

    public func fetchFills(from start: Date, to end: Date) async throws -> [TradingFill] {
        guard start < end else { return [] }
        var results: [TradingFill] = []
        var cursor = milliseconds(start)
        let endMs = milliseconds(end)
        var pages = 0
        while cursor < endMs, pages < 8 {
            pages += 1
            let page = try await fillsPage(startMs: cursor, endMs: endMs)
            results.append(contentsOf: page)
            guard page.count >= min(pageLimit, 2000), let last = page.last else { break }
            let next = last.time + 1
            if next <= cursor { break }
            cursor = next
        }
        return TradingFill.clipped(results, from: start, to: end)
    }

    /// Funding-fee settlements via `userFunding`. The amount is the `usdc`
    /// delta of each funding record (signed; negative = paid out).
    public func fetchFunding(from start: Date, to end: Date) async throws -> [FundingEvent] {
        guard start < end else { return [] }
        let startMs = milliseconds(start)
        let endMs = milliseconds(end)
        var results: [FundingEvent] = []
        var cursor = startMs
        var pages = 0
        while cursor < endMs, pages < 8 {
            pages += 1
            let page = try await fundingPage(startMs: cursor, endMs: endMs)
            results.append(contentsOf: page)
            guard page.count >= min(pageLimit, 2000), let last = page.last else { break }
            let next = last.time + 1
            if next <= cursor { break }
            cursor = next
        }
        return results.filter { $0.time >= startMs && $0.time < endMs }
    }

    private func fillsPage(startMs: Int64, endMs: Int64) async throws -> [TradingFill] {
        let body: [String: Any] = [
            "type": "userFillsByTime",
            "user": user,
            "startTime": startMs,
            "endTime": endMs,
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: baseURL.appendingPathComponent("info"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload
        let (data, response) = try await transport(request)
        if response.statusCode == 429 {
            throw ExchangeClientError.rateLimited
        }
        guard (200...299).contains(response.statusCode) else {
            throw ExchangeClientError.http(response.statusCode, "")
        }
        guard let rows = try? JSONDecoder().decode([FillRow].self, from: data) else {
            throw ExchangeClientError.malformedResponse
        }
        return rows.map { $0.asTradingFill() }
    }

    struct FillRow: Decodable {
        var closedPnl: String?
        var coin: String
        var px: String?
        var side: String?
        var sz: String?
        var time: Int64
        var fee: String?
        var feeToken: String?
        var tid: Int64?

        func asTradingFill() -> TradingFill {
            let sideNorm: String
            switch (side ?? "").uppercased() {
            case "A", "SELL":
                sideNorm = "SELL"
            default:
                sideNorm = "BUY"
            }
            return TradingFill(
                id: tid ?? time,
                symbol: coin,
                side: sideNorm,
                positionSide: "BOTH",
                price: Double(px ?? "") ?? 0,
                qty: Double(sz ?? "") ?? 0,
                quoteQty: 0,
                commission: Double(fee ?? "") ?? 0,
                commissionAsset: feeToken ?? "USDC",
                realizedPnl: Double(closedPnl ?? "") ?? 0,
                time: time
            )
        }
    }

    private func fundingPage(startMs: Int64, endMs: Int64) async throws -> [FundingEvent] {
        let body: [String: Any] = [
            "type": "userFunding",
            "user": user,
            "startTime": startMs,
            "endTime": endMs,
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: baseURL.appendingPathComponent("info"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload
        let (data, response) = try await transport(request)
        if response.statusCode == 429 {
            throw ExchangeClientError.rateLimited
        }
        guard (200...299).contains(response.statusCode) else {
            throw ExchangeClientError.http(response.statusCode, "")
        }
        guard let rows = try? JSONDecoder().decode([FundingRow].self, from: data) else {
            throw ExchangeClientError.malformedResponse
        }
        return rows.compactMap { $0.asFundingEvent() }
    }

    struct FundingRow: Decodable {
        var delta: Delta
        var time: Int64

        struct Delta: Decodable {
            var coin: String?
            var usdc: String?
        }

        func asFundingEvent() -> FundingEvent? {
            guard let coin = delta.coin, !coin.isEmpty else { return nil }
            return FundingEvent(
                symbol: coin,
                // The API pads `usdc` with a leading space; trim before parsing.
                amount: Double(delta.usdc?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0,
                time: time
            )
        }
    }

    private func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}
