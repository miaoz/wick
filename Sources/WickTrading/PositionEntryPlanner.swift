import CryptoKit
import Foundation

/// Decides which position days still need a journal item for display, and
/// which symbols those new items should carry.
///
/// Existing tags are never rewritten. A position is covered when any item on
/// its opening day already matches the symbol; otherwise one item per missing
/// distinct symbol is planned, whether or not the day entry already exists.
public enum PositionEntryPlanner {
    public struct PlannedDay: Equatable, Sendable {
        /// Start of the local calendar day.
        public var day: Date
        public var dayKey: String
        /// Distinct symbols opened that day, sorted - one item per symbol.
        public var symbols: [String]
    }

    public static func plan(
        positions: [TradingPosition],
        existingTagsByDay: [String: [String]],
        dayKey: (Date) -> String,
        startOfDay: (Date) -> Date
    ) -> [PlannedDay] {
        var byDay: [String: (day: Date, symbols: Set<String>)] = [:]

        for position in positions {
            let key = dayKey(position.openTime)
            let existingTags = existingTagsByDay[key] ?? []
            guard !existingTags.contains(where: {
                SymbolTagMatcher.matches(tag: $0, symbol: position.symbol)
            }) else { continue }

            if byDay[key] == nil {
                byDay[key] = (startOfDay(position.openTime), [])
            }
            byDay[key]!.symbols.insert(position.symbol)
        }

        return byDay
            .map { key, group in
                PlannedDay(
                    day: group.day,
                    dayKey: key,
                    symbols: group.symbols.sorted()
                )
            }
            .sorted { $0.day < $1.day }
    }

    /// Stable across devices so concurrent first syncs create the same item
    /// identity. Dropbox can then merge the two day snapshots without keeping
    /// duplicate tag-only items that would render every position twice.
    public static func stableItemID(
        journalID: UUID,
        dayKey: String,
        symbol: String
    ) -> UUID {
        let components = [
            "wick.exchange-item.v1",
            journalID.uuidString.lowercased(),
            dayKey,
            symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
        ]
        let source = components.joined(separator: "|")
        var bytes = Array(SHA256.hash(data: Data(source.utf8)).prefix(16))
        // Mark the digest as an RFC 4122 name-based UUID.
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
