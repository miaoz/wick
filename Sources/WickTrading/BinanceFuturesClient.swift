import CryptoKit
import Foundation

/// Failures surfaced by the Binance client. The app layer maps these to
/// localized UI text, so they stay plain and comparable.
public enum BinanceError: Error, Equatable, Sendable {
    /// -2014 / -2015 / -1022 (or 401/403): key invalid, wrong secret,
    /// no read permission, or IP restriction.
    case invalidCredentials(String)
    /// -1021: local clock too far from server time.
    case timestampOutsideRecvWindow
    /// HTTP 429 / 418.
    case rateLimited
    case http(Int, String)
    case network(String)
    case malformedResponse

    public var isAuthFailure: Bool {
        switch self {
        case .invalidCredentials:
            return true
        default:
            return false
        }
    }
}

/// Read-only Binance USDⓈ-M futures client that pulls the account trade list
/// (`GET /fapi/v1/userTrades`, HMAC-SHA256 signed) and reconstructs position
/// sessions from it.
///
/// All request plumbing goes through an injectable `transport`, so tests drive
/// pagination and error mapping without a network. The fetch window is walked
/// in 7-day chunks with time-based pagination (trade ids are per-symbol and
/// therefore unsafe to page across a mixed-symbol response).
public struct BinanceFuturesClient: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    public static let historyWindow: TimeInterval = 180 * 24 * 3600

    public var apiKey: String
    public var secret: String
    public var baseURL: URL
    public var transport: Transport
    public var now: @Sendable () -> Date
    /// Time-chunk size for the history walk; injectable for tests.
    public var chunkInterval: TimeInterval
    /// Page size requested per call; injectable for tests.
    public var pageLimit: Int

    public init(
        apiKey: String,
        secret: String,
        baseURL: URL = URL(string: "https://fapi.binance.com")!,
        transport: @escaping Transport = { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw BinanceError.network("not an HTTP response")
            }
            return (data, http)
        },
        now: @escaping @Sendable () -> Date = Date.init,
        chunkInterval: TimeInterval = 7 * 24 * 3600,
        pageLimit: Int = 1000
    ) {
        self.apiKey = apiKey
        self.secret = secret
        self.baseURL = baseURL
        self.transport = transport
        self.now = now
        self.chunkInterval = chunkInterval
        self.pageLimit = pageLimit
    }

    // MARK: - Public API

    /// Fetches fills across `window` ending at `end` (defaults to now) and
    /// aggregates them into position sessions.
    public func fetchPositions(
        window: TimeInterval = BinanceFuturesClient.historyWindow,
        asOf end: Date? = nil
    ) async throws -> [TradingPosition] {
        let fills = try await fetchFills(
            from: (end ?? now()).addingTimeInterval(-window),
            to: end ?? now()
        )
        return PositionAggregator.aggregate(fills: fills)
    }

    public func fetchFills(from start: Date, to end: Date) async throws -> [TradingFill] {
        guard start < end else { return [] }
        // Sync the clock up front: ad-hoc NTP drift is the most common cause
        // of -1021 rejections on personal machines.
        let offset = try await serverTimeOffsetMs()

        var result: [TradingFill] = []
        var chunkStart = start
        while chunkStart < end {
            let chunkEnd = min(end, chunkStart.addingTimeInterval(chunkInterval))
            var cursor = chunkStart
            var pageCount = 0
            while cursor < chunkEnd && pageCount < 200 {
                pageCount += 1
                let page = try await userTradesPage(from: cursor, to: chunkEnd, offsetMs: offset)
                result.append(contentsOf: page)
                guard page.count >= pageLimit,
                      let lastTime = page.map(\.time).max()
                else { break }
                let nextCursor = Date(timeIntervalSince1970: Double(lastTime + 1) / 1000)
                // Guard against a server that ignores startTime: always advance.
                cursor = max(nextCursor, cursor.addingTimeInterval(1))
            }
            // Binance's endTime filter is INCLUSIVE, so a fill exactly at the
            // boundary would otherwise be fetched again by the next chunk
            // (TR-04). Advance the chunk start by 1ms to keep chunks exclusive.
            chunkStart = chunkEnd.addingTimeInterval(0.001)
        }
        return result
    }

    /// Funding-fee settlements (`incomeType=FUNDING_FEE`) in `[start, end)`,
    /// walked in the same time-chunked pagination as fills.
    public func fetchFunding(from start: Date, to end: Date) async throws -> [FundingEvent] {
        guard start < end else { return [] }
        let offset = try await serverTimeOffsetMs()

        var result: [FundingEvent] = []
        var chunkStart = start
        while chunkStart < end {
            let chunkEnd = min(end, chunkStart.addingTimeInterval(chunkInterval))
            var cursor = chunkStart
            var pageCount = 0
            while cursor < chunkEnd && pageCount < 200 {
                pageCount += 1
                let page = try await incomePage(from: cursor, to: chunkEnd, offsetMs: offset)
                result.append(contentsOf: page)
                guard page.count >= pageLimit,
                      let lastTime = page.map(\.time).max()
                else { break }
                let nextCursor = Date(timeIntervalSince1970: Double(lastTime + 1) / 1000)
                cursor = max(nextCursor, cursor.addingTimeInterval(1))
            }
            // Inclusively-filtered endTime → advance by 1ms (TR-04).
            chunkStart = chunkEnd.addingTimeInterval(0.001)
        }
        return result
    }

    // MARK: - Requests

    struct ServerTimeResponse: Decodable {
        var serverTime: Int64
    }

    /// Offset (ms) to add to local time when signing, refreshed per fetch.
    func serverTimeOffsetMs() async throws -> Int64 {
        let request = URLRequest(url: baseURL.appendingPathComponent("fapi/v1/time"))
        let (data, response) = try await transport(request)
        try checkResponse(data: data, response: response)
        guard let decoded = try? JSONDecoder().decode(ServerTimeResponse.self, from: data) else {
            throw BinanceError.malformedResponse
        }
        return decoded.serverTime - milliseconds(now())
    }

    func userTradesPage(from: Date, to: Date, offsetMs: Int64) async throws -> [TradingFill] {
        // The clock offset only belongs on `timestamp` (signature validation);
        // startTime/endTime filter server-side trade data, which is absolute.
        let params: [(String, String)] = [
            ("startTime", String(milliseconds(from))),
            ("endTime", String(milliseconds(to))),
            ("limit", String(pageLimit)),
            ("recvWindow", "5000"),
            ("timestamp", String(milliseconds(now()) + offsetMs))
        ]
        let request = try signedRequest(path: "fapi/v1/userTrades", params: params)
        let (data, response) = try await transport(request)
        try checkResponse(data: data, response: response)
        do {
            let fills = try JSONDecoder().decode([TradingFill].self, from: data)
            // Binance reports commission as a POSITIVE cost. The app's unified
            // commission convention is negative = paid (TR-03), so negate on
            // the way in — otherwise a fee would be added back to net PnL.
            return fills.map { fill in
                var f = fill
                f.commission = -fill.commission
                return f
            }
        } catch {
            throw BinanceError.malformedResponse
        }
    }

    func incomePage(from: Date, to: Date, offsetMs: Int64) async throws -> [FundingEvent] {
        let params: [(String, String)] = [
            ("incomeType", "FUNDING_FEE"),
            ("startTime", String(milliseconds(from))),
            ("endTime", String(milliseconds(to))),
            ("limit", String(pageLimit)),
            ("recvWindow", "5000"),
            ("timestamp", String(milliseconds(now()) + offsetMs))
        ]
        let request = try signedRequest(path: "fapi/v1/income", params: params)
        let (data, response) = try await transport(request)
        try checkResponse(data: data, response: response)
        do {
            return try JSONDecoder().decode([IncomeRow].self, from: data).map { $0.asFundingEvent() }
        } catch {
            throw BinanceError.malformedResponse
        }
    }

    /// A `GET /fapi/v1/income` row; only the fields funding needs are kept.
    struct IncomeRow: Decodable {
        var symbol: String?
        var income: String?
        var time: Int64?

        func asFundingEvent() -> FundingEvent {
            FundingEvent(
                symbol: symbol ?? "",
                amount: Double(income ?? "") ?? 0,
                time: time ?? 0
            )
        }
    }

    func signedRequest(path: String, params: [(String, String)]) throws -> URLRequest {
        // Params are numeric-only, so no percent-encoding subtleties; the
        // signature must cover exactly the query string that gets sent.
        let query = params.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        let signature = Self.sign(query: query, secret: secret)
        var request = URLRequest(
            url: baseURL
                .appendingPathComponent(path)
                .appending(queryComponents: "?\(query)&signature=\(signature)")
        )
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-MBX-APIKEY")
        request.timeoutInterval = 20
        return request
    }

    /// Lowercase hex HMAC-SHA256 of the query string with the API secret.
    public static func sign(query: String, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let code = HMAC<SHA256>.authenticationCode(for: Data(query.utf8), using: key)
        return code.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Error mapping

    struct APIErrorPayload: Decodable {
        var code: Int?
        var msg: String?
    }

    func checkResponse(data: Data, response: HTTPURLResponse) throws {
        guard !(200...299).contains(response.statusCode) else { return }
        let payload = try? JSONDecoder().decode(APIErrorPayload.self, from: data)
        let message = payload?.msg ?? ""
        switch response.statusCode {
        case 429, 418:
            throw BinanceError.rateLimited
        case 401, 403:
            throw BinanceError.invalidCredentials(message)
        default:
            throw error(forCode: payload?.code, message: message, status: response.statusCode)
        }
    }

    private func error(forCode code: Int?, message: String, status: Int) -> BinanceError {
        switch code {
        case -2014, -2015, -1022:
            return .invalidCredentials(message)
        case -1021:
            return .timestampOutsideRecvWindow
        default:
            return .http(status, message)
        }
    }

    private func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}

extension BinanceFuturesClient: ExchangeTradeClient {}

private extension URL {
    /// `appendingPathComponent` percent-encodes query metacharacters, so the
    /// raw query is attached as a string instead.
    func appending(queryComponents: String) -> URL {
        URL(string: absoluteString + queryComponents)!
    }
}
