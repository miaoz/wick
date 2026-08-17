import Foundation

/// Decides which position days still need a journal entry for display, and
/// which item tags that new entry should carry.
///
/// Rules (per product spec): a day with an existing entry is never touched;
/// a day without one gets a fresh entry holding one item per distinct symbol,
/// so the positions render inside it via tag matching. Positions already in
/// `handledPositionIDs` were decided in an earlier sync - if the user deleted
/// the auto-created entry since, the day stays deleted.
public enum PositionEntryPlanner {
    public struct PlannedDay: Equatable, Sendable {
        /// Start of the local calendar day.
        public var day: Date
        public var dayKey: String
        /// Distinct symbols opened that day, sorted - one item per symbol.
        public var symbols: [String]
        /// Position ids this plan decision covers (to record as handled).
        public var positionIDs: [String]
    }

    public static func plan(
        positions: [TradingPosition],
        existingDayKeys: Set<String>,
        handledPositionIDs: Set<String>,
        dayKey: (Date) -> String,
        startOfDay: (Date) -> Date
    ) -> [PlannedDay] {
        var byDay: [String: (day: Date, symbols: Set<String>, ids: [String])] = [:]

        for position in positions {
            let key = dayKey(position.openTime)
            guard !existingDayKeys.contains(key),
                  !handledPositionIDs.contains(position.id)
            else { continue }

            if byDay[key] == nil {
                byDay[key] = (startOfDay(position.openTime), [], [])
            }
            byDay[key]!.symbols.insert(position.symbol)
            byDay[key]!.ids.append(position.id)
        }

        return byDay
            .map { key, group in
                PlannedDay(
                    day: group.day,
                    dayKey: key,
                    symbols: group.symbols.sorted(),
                    positionIDs: group.ids
                )
            }
            .sorted { $0.day < $1.day }
    }
}
