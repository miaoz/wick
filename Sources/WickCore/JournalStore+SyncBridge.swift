import Foundation
import WickSync
import WickTrading

// MARK: - Sync engine bridge

/// The sync engine (`WickSync.JournalSyncEngine`) talks to the store only through
/// this surface: UUID-keyed snapshots in, whole-entry applies/removals out. The
/// shared implementation lives in `WickSync.JournalSyncBridge` (AR-01); this
/// file supplies the macOS primitives and delegates.
extension JournalStore: JournalSyncStoreHost {
    var activeJournalName: String { activeJournal?.name ?? "" }

    func persistActiveJournal() { persist() }

    func sendRemoteApply(_ apply: JournalRemoteApply) {
        remoteEntryDidApply.send(apply)
    }

    func flushEditorDrafts() {
        NotificationCenter.default.post(name: .wickWillFlushJournalDrafts, object: nil)
    }

    func reconcileSelectionAfterApply() {
        reconcileSelectionAfterChange()
    }

    func entryCollisionMerged(from oldID: UUID, to newID: UUID) {
        switch selection {
        case .day(let id) where id == oldID:
            selection = .day(newID)
        case .item(let ref) where ref.entryID == oldID:
            selection = .item(JournalItemRef(entryID: newID, itemID: ref.itemID))
        default:
            break
        }
    }

    func invalidateImageCache(filename: String) {
        JournalThumbnailCache.shared.invalidate(filename: filename)
    }
}

extension JournalStore: JournalLocalSource {
    private var syncBridge: JournalSyncBridge { JournalSyncBridge(host: self) }

    var syncJournalID: UUID? { activeJournalID }

    var syncJournalName: String { activeJournal?.name ?? "" }

    var syncIsWritable: Bool { !isReadOnlyDueToLoadFailure }

    func syncEntrySnapshots() -> [UUID: JournalEntry] {
        syncBridge.syncEntrySnapshots()
    }

    /// Test helper: apply against the currently active journal.
    func applySyncedEntry(_ entry: JournalEntry) {
        guard let activeJournalID else { return }
        applySyncedEntry(entry, journalID: activeJournalID)
    }

    @discardableResult
    func applySyncedChanges(_ changes: [JournalSyncMutation], journalID: UUID) -> Set<UUID> {
        syncBridge.applySyncedChanges(changes, journalID: journalID)
    }

    func mergeSyncedDateCollision(with incoming: JournalEntry) -> JournalEntry {
        syncBridge.mergeSyncedDateCollision(with: incoming)
    }

    func localEntryStillMatches(entryID: UUID, expectedHash: String?) -> Bool {
        syncBridge.localEntryStillMatches(entryID: entryID, expectedHash: expectedHash)
    }

    func prepareForRemoteApply(entryID: UUID) {
        syncBridge.prepareForRemoteApply(entryID: entryID)
    }

    func applySyncedEntry(_ entry: JournalEntry, journalID: UUID) {
        syncBridge.applySyncedEntry(entry, journalID: journalID)
    }

    func removeSyncedEntry(entryID: UUID) {
        guard let activeJournalID else { return }
        removeSyncedEntry(entryID: entryID, journalID: activeJournalID)
    }

    func removeSyncedEntry(entryID: UUID, journalID: UUID) {
        syncBridge.removeSyncedEntry(entryID: entryID, journalID: journalID)
    }

    /// Test helper: rename the currently active journal from a remote name.
    @discardableResult
    func applySyncedJournalName(_ name: String) -> String {
        guard let activeJournalID else { return name }
        return applySyncedJournalName(name, journalID: activeJournalID)
    }

    @discardableResult
    func applySyncedJournalName(_ name: String, journalID: UUID) -> String {
        syncBridge.applySyncedJournalName(name, journalID: journalID)
    }

    func syncedImageFilenames() -> Set<String> {
        syncBridge.syncedImageFilenames()
    }

    func syncedImageData(filename: String) -> Data? {
        syncBridge.syncedImageData(filename: filename)
    }

    func hasSyncedImage(filename: String) -> Bool {
        syncBridge.hasSyncedImage(filename: filename)
    }

    func storeSyncedImage(filename: String, data: Data) {
        guard let activeJournalID else { return }
        storeSyncedImage(filename: filename, data: data, journalID: activeJournalID)
    }

    func storeSyncedImage(filename: String, data: Data, journalID: UUID) {
        syncBridge.storeSyncedImage(filename: filename, data: data, journalID: journalID)
    }
}
