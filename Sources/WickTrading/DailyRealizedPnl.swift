import Foundation

/// Realized PnL summed per local calendar day, for the journal sidebar's
/// PnL calendar. Pure computation; the UI layer supplies the calendar.
public enum DailyRealizedPnl {
    /// Positions whose absolute realized PnL is at or below this do not mark
    /// an opening day as having realized PnL.
    static let epsilon = 1e-9

    /// Attributes each position's realized PnL to the day that position was
    /// opened, regardless of when its closing fills occurred.
    public static func sumsByOpenDay(
        positions: [TradingPosition],
        calendar: Calendar
    ) -> [Date: Double] {
        var sums: [Date: Double] = [:]
        for position in positions where abs(position.realizedPnl) > epsilon {
            let day = calendar.startOfDay(for: position.openTime)
            sums[day, default: 0] += position.realizedPnl
        }
        return sums
    }

    /// Attributes each position's net PnL (realized − commission − funding) to
    /// the day that position was opened. This is the figure the journal
    /// surfaces in the PnL calendar, day list, and day page header.
    public static func netSumsByOpenDay(
        positions: [TradingPosition],
        calendar: Calendar
    ) -> [Date: Double] {
        var sums: [Date: Double] = [:]
        for position in positions {
            let net = position.netPnl
            guard abs(net) > epsilon else { continue }
            let day = calendar.startOfDay(for: position.openTime)
            sums[day, default: 0] += net
        }
        return sums
    }
}
