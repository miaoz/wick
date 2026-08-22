import Foundation

/// Failures from any venue client. The app layer maps these to UI text.
public enum ExchangeClientError: Error, Equatable, Sendable {
    case invalidCredentials(String)
    case timestampOutsideRecvWindow
    case rateLimited
    case http(Int, String)
    case network(String)
    case malformedResponse

    public var isAuthFailure: Bool {
        if case .invalidCredentials = self { return true }
        return false
    }
}

/// Read-only fill + funding history. Implementations talk to one venue; the
/// coordinator owns windowing, cache merge, and aggregation.
public protocol ExchangeTradeClient: Sendable {
    func fetchFills(from start: Date, to end: Date) async throws -> [TradingFill]
    /// Funding-fee settlements in `[start, end)`, signed (negative = paid).
    func fetchFunding(from start: Date, to end: Date) async throws -> [FundingEvent]
}

extension BinanceError {
    public var asExchangeClientError: ExchangeClientError {
        switch self {
        case .invalidCredentials(let message):
            return .invalidCredentials(message)
        case .timestampOutsideRecvWindow:
            return .timestampOutsideRecvWindow
        case .rateLimited:
            return .rateLimited
        case .http(let status, let message):
            return .http(status, message)
        case .network(let message):
            return .network(message)
        case .malformedResponse:
            return .malformedResponse
        }
    }
}

extension TradingFill {
    /// Stable Int64 from a venue's string trade id (OKX `tradeId`, etc.).
    public static func integerID(from raw: String) -> Int64 {
        if let value = Int64(raw) { return value }
        var hash: UInt64 = 5381
        for byte in raw.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return Int64(bitPattern: hash)
    }

    /// `[from, to)` in fill-epoch milliseconds. Venues sometimes ignore
    /// `begin`/`startTime`; callers still must not keep older history.
    public static func clipped(_ fills: [TradingFill], from: Date, to: Date) -> [TradingFill] {
        let startMs = Int64((from.timeIntervalSince1970 * 1000).rounded())
        let endMs = Int64((to.timeIntervalSince1970 * 1000).rounded())
        return fills.filter { $0.time >= startMs && $0.time < endMs }
    }
}
