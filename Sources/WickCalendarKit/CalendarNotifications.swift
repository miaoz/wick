import Foundation

extension Notification.Name {
    /// Calendar window input (arrow keys / scroll wheel) → SwiftUI: flip the events
    /// page. `userInfo["direction"]` is +1 (next) or -1 (previous); pages wrap.
    /// Defined here so both the kit's views (listener) and the macOS window (poster)
    /// can reference it without a cross-target dependency.
    public static let wickCalendarFlipEventsPage = Notification.Name("wick.calendarFlipEventsPage")
}
