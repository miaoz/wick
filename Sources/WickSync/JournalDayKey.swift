import Foundation

/// Stable per-day key ("yyyy-MM-dd") used as the sync-layer identity of a `JournalEntry`.
///
/// The key is generated once at creation (or when the entry is explicitly moved to
/// another day) and then stored on the entry — never derived on the fly — so a
/// device crossing timezones cannot silently re-key existing days.
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
