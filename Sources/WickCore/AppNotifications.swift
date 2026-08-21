import Foundation

extension Notification.Name {
    /// Posted before the app terminates so journal editors can flush drafts immediately.
    static let wickWillFlushJournalDrafts = Notification.Name("wick.willFlushJournalDrafts")

    /// Posted when the journal store finishes a restore from backup or recovers from load failure.
    static let wickJournalStoreDidRecover = Notification.Name("wick.journalStoreDidRecover")

    /// Posted when the active journal changes (switch / create / delete / rename).
    static let wickActiveJournalDidChange = Notification.Name("wick.activeJournalDidChange")
}
