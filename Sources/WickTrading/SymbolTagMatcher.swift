import Foundation

/// Loose matching between a journal item tag and an exchange trading pair.
///
/// Journal tags are free-form, so matching is deliberately wide:
/// - case-insensitive, separators (`/`, `-`, spaces) ignored: `btc/usdt` -> BTCUSDT
/// - a base-asset tag matches any pair on that base: `BTC` -> BTCUSDT, BTCUSDC
/// - derivative notional prefixes are stripped from the symbol:
///   `PEPE` -> 1000PEPEUSDT, `MOG` -> 1000000MOGUSDT
public enum SymbolTagMatcher {
    private static let derivativePrefixes = ["1000000", "10000", "1000"]

    /// Known quote assets, longest-match order.
    public static let quoteAssets = [
        "FDUSD", "USDT", "USDC", "BUSD", "TUSD", "USDP", "DAI",
        "USD", "BNB", "BTC", "ETH"
    ]

    public static func matches(tag: String, symbol: String) -> Bool {
        guard let normalizedTag = normalize(tag),
              let normalizedSymbol = normalize(symbol)
        else { return false }

        if normalizedSymbol == normalizedTag { return true }
        if normalizedSymbol.hasPrefix(normalizedTag) { return true }
        for prefix in derivativePrefixes where normalizedSymbol.hasPrefix(prefix) {
            if normalizedSymbol.dropFirst(prefix.count).hasPrefix(normalizedTag) {
                return true
            }
        }
        return false
    }

    /// Quote asset of a pair inferred from its suffix (display only; no
    /// exchangeInfo round-trip for v1).
    public static func quoteAsset(of symbol: String) -> String? {
        quoteAssets.first { symbol.hasSuffix($0) }
    }

    /// Base asset of a pair: strips the derivative notional prefix and the
    /// quote suffix, so BTCUSDT -> BTC, 1000PEPEUSDT -> PEPE, ETHBTC -> ETH.
    /// Symbols without a known quote suffix are returned as-is (minus the
    /// derivative prefix).
    public static func baseAsset(of symbol: String) -> String {
        var base = symbol
        for prefix in derivativePrefixes where base.hasPrefix(prefix) {
            base.removeFirst(prefix.count)
            break
        }
        for quote in quoteAssets where base.hasSuffix(quote) {
            base.removeLast(quote.count)
            break
        }
        return base.isEmpty ? symbol : base
    }

    /// Positions whose symbol loosely matches `tag`. Callers pair this with
    /// their own day filter (open date == journal day).
    public static func filter(
        _ positions: [TradingPosition],
        matchingTag tag: String
    ) -> [TradingPosition] {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return positions.filter { matches(tag: trimmed, symbol: $0.symbol) }
    }

    /// Uppercased alphanumerics only; nil when nothing usable remains.
    static func normalize(_ raw: String) -> String? {
        let normalized = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        return normalized.isEmpty ? nil : normalized
    }

    /// The user's own spelling for a symbol, to reuse when auto-creating
    /// journal items: among tags that loosely match `symbol` (tag BTC for
    /// BTCUSDT), the most-used one wins; ties prefer the shorter (more
    /// general) spelling. Returns nil when the journal has no matching tag -
    /// callers then fall back to the raw symbol. Journal tags themselves are
    /// never rewritten; this only names freshly created items.
    public static func preferredTag(matching symbol: String, tagCounts: [String: Int]) -> String? {
        var best: (display: String, key: String, count: Int)?
        for (tag, count) in tagCounts {
            guard let key = normalize(tag), matches(tag: tag, symbol: symbol) else { continue }
            if let current = best {
                let better = count > current.count
                    || (count == current.count && key.count < current.key.count)
                if better {
                    best = (tag, key, count)
                }
            } else {
                best = (tag, key, count)
            }
        }
        return best?.display
    }
}
