import Foundation

extension Notification.Name {
    /// `wickWillFlushJournalDrafts` lives in WickSync so the iOS store shares
    /// the same flush protocol (posted before a remote apply / journal switch).

    /// Posted when the journal store finishes a restore from backup or recovers from load failure.
    static let wickJournalStoreDidRecover = Notification.Name("wick.journalStoreDidRecover")

    /// Posted when the active journal changes (switch / create / delete / rename).
    static let wickActiveJournalDidChange = Notification.Name("wick.activeJournalDidChange")
    static let wickTradingSnapshotDidChange = Notification.Name("wick.tradingSnapshotDidChange")

    /// Posted by ⌘F so the titlebar accessory can focus its search field (UI-03).
    static let wickJournalFocusSearch = Notification.Name("wick.journalFocusSearch")

    /// Posted by `MenuBarExtraPanel.dismiss` after ordering the panel out, so
    /// the panel's SwiftUI scene (which macOS keeps alive while hidden) can
    /// stop its minute tick and flame breathing even if the visibility probe's
    /// KVO races the dismissal.
    static let wickMenuBarPanelDidDismiss = Notification.Name("wick.menuBarPanelDidDismiss")
}
