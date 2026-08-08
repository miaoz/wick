import Foundation

extension Notification.Name {
    /// Posted before the app terminates so journal editors can flush drafts immediately.
    static let wickWillFlushJournalDrafts = Notification.Name("wick.willFlushJournalDrafts")

    /// Posted when the journal store finishes a restore from backup or recovers from load failure.
    static let wickJournalStoreDidRecover = Notification.Name("wick.journalStoreDidRecover")

    /// Posted when the active journal changes (switch / create / delete / rename).
    static let wickActiveJournalDidChange = Notification.Name("wick.activeJournalDidChange")

    /// AppKit toolbar (macOS 13) → SwiftUI: open the new-journal name alert.
    static let wickJournalLibraryNewRequested = Notification.Name("wick.journalLibraryNewRequested")

    /// AppKit toolbar (macOS 13) → SwiftUI: open the rename-journal alert.
    static let wickJournalLibraryRenameRequested = Notification.Name("wick.journalLibraryRenameRequested")

    /// AppKit toolbar (macOS 13) → SwiftUI: open the delete-journal confirmation.
    static let wickJournalLibraryDeleteRequested = Notification.Name("wick.journalLibraryDeleteRequested")
}
