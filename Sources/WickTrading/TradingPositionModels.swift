import Foundation

/// Direction of a reconstructed position session.
public enum TradingPositionSide: String, Codable, Sendable {
    case long
    case short
}

/// Exchange-provided or safely inferred effect of a fill on its position lane.
public enum TradingFillEffect: String, Codable, Sendable {
    case unknown
    case open
    case close
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
    /// Used to reject a close fill whose opening history is outside the window.
    public var effect: TradingFillEffect
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
        effect: TradingFillEffect? = nil,
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
        self.effect = effect ?? Self.inferredEffect(
            side: side,
            positionSide: positionSide,
            realizedPnl: realizedPnl
        )
        self.time = time
    }

    public enum CodingKeys: String, CodingKey {
        case id, symbol, side, positionSide, price, qty, quoteQty
        case commission, commissionAsset, realizedPnl, effect, time
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
        effect = try container.decodeIfPresent(TradingFillEffect.self, forKey: .effect)
            ?? Self.inferredEffect(side: side, positionSide: positionSide, realizedPnl: realizedPnl)
        time = try container.decode(Int64.self, forKey: .time)
    }

    private static func inferredEffect(
        side: String,
        positionSide: String,
        realizedPnl: Double
    ) -> TradingFillEffect {
        switch (positionSide.uppercased(), side.uppercased()) {
        case ("LONG", "BUY"), ("SHORT", "SELL"):
            return .open
        case ("LONG", "SELL"), ("SHORT", "BUY"):
            return .close
        default:
            // One-way account trade feeds omit reduce-only/open-close intent.
            // Non-zero realized PnL is nevertheless an unambiguous reduction.
            return realizedPnl != 0 ? .close : .unknown
        }
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

/// One funding-fee settlement from a venue's income/bills history.
/// `amount` is signed: negative means the user paid funding out.
public struct FundingEvent: Codable, Equatable, Hashable, Sendable {
    public var symbol: String
    public var amount: Double
    /// Settlement time, milliseconds since the Unix epoch (UTC).
    public var time: Int64

    public init(symbol: String, amount: Double, time: Int64) {
        self.symbol = symbol
        self.amount = amount
        self.time = time
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
    /// Funding fees paid or received while this position was open, matched
    /// from the venue's funding history (negative = paid out).
    public var fundingPnl: Double

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
        commissions: [String: Double] = [:],
        fundingPnl: Double = 0
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
        self.fundingPnl = fundingPnl
    }

    public enum CodingKeys: String, CodingKey {
        case id, symbol, side, openTime, closeTime, entryPrice, exitPrice
        case peakSize, realizedPnl, commissions, fundingPnl
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        symbol = try container.decode(String.self, forKey: .symbol)
        side = try container.decode(TradingPositionSide.self, forKey: .side)
        openTime = try container.decode(Date.self, forKey: .openTime)
        closeTime = try container.decodeIfPresent(Date.self, forKey: .closeTime)
        entryPrice = try container.decode(Double.self, forKey: .entryPrice)
        exitPrice = try container.decodeIfPresent(Double.self, forKey: .exitPrice)
        peakSize = try container.decode(Double.self, forKey: .peakSize)
        realizedPnl = try container.decode(Double.self, forKey: .realizedPnl)
        commissions = try container.decodeIfPresent([String: Double].self, forKey: .commissions) ?? [:]
        fundingPnl = try container.decodeIfPresent(Double.self, forKey: .fundingPnl) ?? 0
    }

    /// Quote asset inferred from the symbol suffix (display only; no
    /// exchangeInfo round-trip for v1).
    public var quoteAsset: String? {
        SymbolTagMatcher.quoteAsset(of: symbol)
    }

    /// Commission in the quote asset as a positive magnitude. Venue sign
    /// conventions differ (Binance/OKX report fees negative, Hyperliquid
    /// positive), so the stored value is normalized here; falls back to the
    /// sum over all assets when the quote asset can't be resolved.
    public var commissionTotal: Double {
        if let quote = quoteAsset {
            return abs(commissions[quote] ?? 0)
        }
        return commissions.values.reduce(0) { $0 + abs($1) }
    }

    /// Realized PnL net of quote-asset commission and funding — the number the
    /// journal surfaces as "Net PnL". `fundingPnl` is signed (negative = paid
    /// out), so it is added rather than subtracted.
    public var netPnl: Double {
        realizedPnl - commissionTotal + fundingPnl
    }
}

/// Cached sync state persisted between launches.
///
/// Raw fills are cached alongside the derived positions so refreshes can be
/// incremental (past fills are immutable): each sync only fetches from the
/// last successful fetch forward, plus a backward extension when the journal's
/// earliest day moves before `windowStart`.
public struct TradingPositionSnapshot: Codable, Equatable, Sendable {
    public var fetchedAt: Date
    /// Lower bound of the covered history (start of the earliest journal day,
    /// or the fallback window when the journal is empty).
    public var windowStart: Date
    /// Derived display model; rebuilt from `fills` on every sync.
    public var positions: [TradingPosition]
    /// All fills in `[windowStart, fetchedAt)` - the source of truth.
    public var fills: [TradingFill]
    /// Funding-fee settlements in the same window, matched onto positions at
    /// display time.
    public var funding: [FundingEvent]
    /// Whether the funding history has been fetched across the whole window.
    public var fundingBackfilled: Bool
    /// Non-secret source metadata used when this derived cache is explicitly
    /// shared through Dropbox. Account labels must already be redacted.
    public var sourceVenue: String?
    public var sourceAccountLabel: String?

    public init(
        fetchedAt: Date,
        windowStart: Date,
        positions: [TradingPosition],
        fills: [TradingFill] = [],
        funding: [FundingEvent] = [],
        fundingBackfilled: Bool = false,
        sourceVenue: String? = nil,
        sourceAccountLabel: String? = nil
    ) {
        self.fetchedAt = fetchedAt
        self.windowStart = windowStart
        self.positions = positions
        self.fills = fills
        self.funding = funding
        self.fundingBackfilled = fundingBackfilled
        self.sourceVenue = sourceVenue
        self.sourceAccountLabel = sourceAccountLabel
    }
}
