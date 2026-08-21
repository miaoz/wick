import Foundation

/// Realized PnL summed per local calendar day, for the journal sidebar's
/// PnL calendar. Pure computation; the UI layer supplies the calendar.
public enum DailyRealizedPnl {
    /// Fills whose absolute realized PnL is at or below this are treated as
    /// opening fills and never mark a day as traded.
    static let epsilon = 1e-9

    /// Sums `realizedPnl` per day (keyed by `calendar.startOfDay`). Only days
    /// with at least one fill carrying a non-zero realized PnL appear in the
    /// result - opening fills (`realizedPnl == 0`) never mark a day.
    public static func sumsByDay(fills: [TradingFill], calendar: Calendar) -> [Date: Double] {
        var sums: [Date: Double] = [:]
        for fill in fills where abs(fill.realizedPnl) > epsilon {
            let day = calendar.startOfDay(
                for: Date(timeIntervalSince1970: TimeInterval(fill.time) / 1000)
            )
            sums[day, default: 0] += fill.realizedPnl
        }
        return sums
    }
}
