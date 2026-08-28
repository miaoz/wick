import Foundation

/// Which day the physical tear-off pad is showing. Persisted so the pad keeps
/// its torn-to page across launches and midnights — a real himekuri never
/// flips itself: a day the user didn't tear stays on top tomorrow, and a stack
/// torn ahead stays ahead. The ONLY reset is toggling the easter egg off and
/// on in settings (`resetToToday`); opening the window or the date rolling
/// over must never move the pad.
public enum TearOffState {
    public static let defaultsKey = "wick.calendar.tornToDate"

    /// The day the pad shows: the persisted torn-to day, or `now` when the pad
    /// has never been on screen. Normalized to the start of the day so page
    /// identity is date-pure.
    public static func displayedDate(
        now: Date = Date(),
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) -> Date {
        guard let stored = defaults.object(forKey: defaultsKey) as? Date else { return now }
        return calendar.startOfDay(for: stored)
    }

    /// Pins the day now on top of the pad. Called when the pad appears (an
    /// untouched pad sticks to the day it was first shown) and after each tear.
    public static func saveDisplayedDate(
        _ date: Date,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        defaults.set(calendar.startOfDay(for: date), forKey: defaultsKey)
    }

    /// Returns the pad to today. Sole caller: the easter-egg toggle being
    /// switched back on in settings.
    public static func resetToToday(
        now: Date = Date(),
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        saveDisplayedDate(now, defaults: defaults, calendar: calendar)
    }
}
