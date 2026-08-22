import Foundation

/// Attributes funding-fee settlements to position sessions, purely.
///
/// A funding event belongs to a position on the same symbol whose open window
/// (`[openTime, closeTime)`, or `[openTime, ∞)` while still open) contains the
/// event's timestamp. When two positions on the same symbol overlap in time
/// (hedge mode with both lanes open) an event is assigned to exactly one of
/// them — the earliest-opened — so it is never double-counted. Funding events
/// for symbols with no matching position are dropped.
public enum FundingAttributor {
    /// Returns copies of `positions` with `fundingPnl` set to the sum of the
    /// funding attributed to each position.
    public static func attach(
        positions: [TradingPosition],
        funding: [FundingEvent]
    ) -> [TradingPosition] {
        guard !funding.isEmpty else { return positions }

        let positionsBySymbol = Dictionary(grouping: positions, by: { $0.symbol })
        var fundingByPosition: [String: Double] = [:]

        for (symbol, symbolFunding) in Dictionary(grouping: funding, by: { $0.symbol }) {
            guard let candidates = positionsBySymbol[symbol], !candidates.isEmpty else { continue }
            let sorted = candidates.sorted { ($0.openTime, $0.id) < ($1.openTime, $1.id) }
            for event in symbolFunding.sorted(by: { $0.time < $1.time }) {
                guard let match = sorted.first(where: { contains(event, in: $0) }) else { continue }
                fundingByPosition[match.id, default: 0] += event.amount
            }
        }

        guard !fundingByPosition.isEmpty else { return positions }
        return positions.map { position in
            guard let funding = fundingByPosition[position.id], funding != 0 else { return position }
            var updated = position
            updated.fundingPnl = funding
            return updated
        }
    }

    private static func contains(_ event: FundingEvent, in position: TradingPosition) -> Bool {
        let openMs = Int64((position.openTime.timeIntervalSince1970 * 1000).rounded())
        guard event.time >= openMs else { return false }
        if let close = position.closeTime {
            let closeMs = Int64((close.timeIntervalSince1970 * 1000).rounded())
            return event.time < closeMs
        }
        return true
    }
}
