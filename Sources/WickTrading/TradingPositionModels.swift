import Foundation

/// Direction of a reconstructed position session.
public enum TradingPositionSide: String, Codable, Sendable {
    case long
    case short
}

/// One fill from the exchange's account trade list. Field semantics mirror
/// Binance USDⓈ-M `GET /fapi/v1/userTrades`.
public struct TradingFill: Codable, Equatable, Hashable, Sendable {
    public var id: Int64
    public var symbol: String
    /// "BUY" or "SELL".
    public var side: String
    /// "BOTH" (one-way) or "LONG"/"SHORT" (hedge mode lanes).
    public var positionSide: String
    public var price: Double
    public var qty: Double
    public var quoteQty: Double
    public var commission: Double
    public var commissionAsset: String
    public var realizedPnl: Double
    /// Fill time, milliseconds since the Unix epoch (UTC).
    public var time: Int64

    public init(
        id: Int64,
        symbol: String,
        side: String,
        positionSide: String = "BOTH",
        price: Double,
        qty: Double,
        quoteQty: Double = 0,
        commission: Double = 0,
        commissionAsset: String = "",
        realizedPnl: Double = 0,
        time: Int64
    ) {
        self.id = id
        self.symbol = symbol
        self.side = side
        self.positionSide = positionSide
        self.price = price
        self.qty = qty
        self.quoteQty = quoteQty
        self.commission = commission
        self.commissionAsset = commissionAsset
        self.realizedPnl = realizedPnl
        self.time = time
    }

    public enum CodingKeys: String, CodingKey {
        case id, symbol, side, positionSide, price, qty, quoteQty
        case commission, commissionAsset, realizedPnl, time
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        symbol = try container.decode(String.self, forKey: .symbol)
        side = try container.decode(String.self, forKey: .side)
        positionSide = try container.decodeIfPresent(String.self, forKey: .positionSide) ?? "BOTH"
        // Binance sends numeric fields as strings; tolerate both shapes.
        price = Self.flexibleNumber(container, .price)
        qty = Self.flexibleNumber(container, .qty)
        quoteQty = Self.flexibleNumber(container, .quoteQty)
        commission = Self.flexibleNumber(container, .commission)
        commissionAsset = try container.decodeIfPresent(String.self, forKey: .commissionAsset) ?? ""
        realizedPnl = Self.flexibleNumber(container, .realizedPnl)
        time = try container.decode(Int64.self, forKey: .time)
    }

    private static func flexibleNumber(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys
    ) -> Double {
        if let value = try? container.decode(Double.self, forKey: key) {
            return value
        }
        if let raw = try? container.decode(String.self, forKey: key) {
            return Double(raw) ?? 0
        }
        return 0
    }
}

/// A reconstructed position session: from flat back to flat (or still open)
/// on one symbol + hedge lane.
public struct TradingPosition: Codable, Identifiable, Equatable, Sendable {
    /// Stable identity: symbol + lane + opening fill. Re-syncing the same
    /// fills yields the same id, so SwiftUI reuse and day matching stay stable.
    public var id: String
    public var symbol: String
    public var side: TradingPositionSide
    /// When the lane went from flat to non-zero.
    public var openTime: Date
    /// When the lane returned to flat; nil while the position is still open.
    public var closeTime: Date?
    /// Volume-weighted average price of the fills that built the position.
    public var entryPrice: Double
    /// Volume-weighted average price of the fills that reduced it
    /// (nil when nothing has been closed yet).
    public var exitPrice: Double?
    /// Peak absolute size reached while the session was open.
    public var peakSize: Double
    /// Realized PnL accumulated on reducing fills, in the quote asset.
    public var realizedPnl: Double
    /// Commissions by asset (usually one quote-asset entry).
    public var commissions: [String: Double]

    public var isClosed: Bool { closeTime != nil }

    public init(
        id: String,
        symbol: String,
        side: TradingPositionSide,
        openTime: Date,
        closeTime: Date?,
        entryPrice: Double,
        exitPrice: Double?,
        peakSize: Double,
        realizedPnl: Double,
        commissions: [String: Double] = [:]
    ) {
        self.id = id
        self.symbol = symbol
        self.side = side
        self.openTime = openTime
        self.closeTime = closeTime
        self.entryPrice = entryPrice
        self.exitPrice = exitPrice
        self.peakSize = peakSize
        self.realizedPnl = realizedPnl
        self.commissions = commissions
    }

    /// Quote asset inferred from the symbol suffix (display only; no
    /// exchangeInfo round-trip for v1).
    public var quoteAsset: String? {
        let known = ["USDT", "USDC", "BUSD", "FDUSD", "TUSD", "USDP", "DAI", "USD", "BNB", "BTC", "ETH"]
        for asset in known where symbol.hasSuffix(asset) {
            return asset
        }
        return nil
    }
}

/// Cached sync state persisted between launches.
///
/// Raw fills are cached alongside the derived positions so refreshes can be
/// incremental (past fills are immutable): each sync only fetches from the
/// last successful fetch forward, plus a backward extension when the journal's
/// earliest day moves before `windowStart`. `handledPositionIDs` records
/// positions whose "needs an entry?" question was already decided, so a day
/// entry the user deleted is never resurrected by later syncs.
public struct TradingPositionSnapshot: Codable, Equatable, Sendable {
    public var version: Int
    public var fetchedAt: Date
    /// Lower bound of the covered history (start of the earliest journal day,
    /// or the fallback window when the journal is empty).
    public var windowStart: Date
    /// Derived display model; rebuilt from `fills` on every sync.
    public var positions: [TradingPosition]
    /// All fills in `[windowStart, fetchedAt)` - the source of truth.
    public var fills: [TradingFill]
    /// Position ids already considered for journal auto-creation.
    public var handledPositionIDs: Set<String>

    public static let currentVersion = 1

    public init(
        version: Int = TradingPositionSnapshot.currentVersion,
        fetchedAt: Date,
        windowStart: Date,
        positions: [TradingPosition],
        fills: [TradingFill] = [],
        handledPositionIDs: Set<String> = []
    ) {
        self.version = version
        self.fetchedAt = fetchedAt
        self.windowStart = windowStart
        self.positions = positions
        self.fills = fills
        self.handledPositionIDs = handledPositionIDs
    }

    public enum CodingKeys: String, CodingKey {
        case version, fetchedAt, windowStart, positions, fills, handledPositionIDs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
        windowStart = try container.decode(Date.self, forKey: .windowStart)
        positions = try container.decode([TradingPosition].self, forKey: .positions)
        fills = try container.decodeIfPresent([TradingFill].self, forKey: .fills) ?? []
        handledPositionIDs = try container.decodeIfPresent(Set<String>.self, forKey: .handledPositionIDs) ?? []
    }
}
