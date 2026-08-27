import Foundation

extension Notification.Name {
    /// Calendar window input (arrow keys / scroll wheel) → SwiftUI:
    /// `userInfo["direction"]` (+1/-1) flips the events page within the active
    /// tab (pages wrap); `userInfo["tabSwitch"]` toggles the pane's tab
    /// (macro ⇄ earnings). Defined here so both the kit's views (listener) and
    /// the macOS window (poster) can reference it without a cross-target
    /// dependency.
    public static let wickCalendarFlipEventsPage = Notification.Name("wick.calendarFlipEventsPage")

    /// The font preference changed while a pad is on the desk; re-snapshots the
    /// top page so the new face set applies without reopening the window.
    /// Posted by the macOS host (`AppSettings`), observed by `TradingCalendarRootView`.
    public static let wickCalendarFontStyleChanged = Notification.Name("wick.calendarFontStyleChanged")

    /// The PnL color convention changed; re-snapshots the physical calendar so
    /// the accent color (red for redUp, green for greenUp) applies immediately.
    /// Posted by the macOS host (`AppSettings`), observed by `TradingCalendarRootView`.
    public static let wickCalendarPnlConventionChanged = Notification.Name("wick.calendarPnlConventionChanged")

    /// Reopens or summons the calendar window; resets the current date back to today
    /// so previously torn pages or stale cached dates revert to today's live feed.
    public static let wickCalendarResetToToday = Notification.Name("wick.calendarResetToToday")

    /// Toggles the event sort order between time and importance in the physical calendar pad.
    public static let wickCalendarToggleSortOrder = Notification.Name("wick.calendarToggleSortOrder")
}

