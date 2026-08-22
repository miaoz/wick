import Foundation

extension Notification.Name {
    /// `wickWillFlushJournalDrafts` lives in WickSync so the iOS store shares
    /// the same flush protocol (posted before a remote apply / journal switch).

    /// Posted when the journal store finishes a restore from backup or recovers from load failure.
    static let wickJournalStoreDidRecover = Notification.Name("wick.journalStoreDidRecover")

    /// Posted when the active journal changes (switch / create / delete / rename).
    static let wickActiveJournalDidChange = Notification.Name("wick.activeJournalDidChange")
}
