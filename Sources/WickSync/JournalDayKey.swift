import Foundation

/// Formats a date as a local Gregorian day ("yyyy-MM-dd") for display,
/// grouping, and trading attribution. It is never persisted as entry identity;
/// `JournalEntry.id` is the sole stable sync key and `date` remains editable.
public enum JournalDayKey {
    public static func make(from date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
