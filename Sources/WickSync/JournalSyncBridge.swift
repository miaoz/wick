import Foundation

/// The primitive surface a journal store exposes so the shared sync-bridge
/// implementation (`JournalSyncBridge`) can be written ONCE in WickSync instead
/// of being duplicated by the macOS (`JournalStore`) and iOS
/// (`PhoneJournalStore`) stores (AR-01).
///
/// The four trailing methods are macOS-only refinements (selection reconcile,
/// catalog metadata touch, thumbnail cache, journal-change notification); the
/// protocol gives them default no-ops so the iOS store only implements what it
/// needs.
@MainActor
public protocol JournalSyncStoreHost: AnyObject {
    var activeJournalID: UUID? { get set }
    var activeJournalName: String { get }
    var journals: [JournalInfo] { get set }
    var entries: [JournalEntry] { get set }
    var isReadOnlyDueToLoadFailure: Bool { get set }

    /// Resolves an image file's on-disk URL from its safe filename (nil when
    /// invalid). Must be the single image-URL constructor (path-traversal safe).
    func imageURL(for filename: String) -> URL?
    /// Platform persistence: commit the in-memory snapshot (writer queue etc.).
    func persistActiveJournal()
    /// Persist the catalog (journals + active id) durably; false on failure.
    @discardableResult
    func persistCatalog() -> Bool
    /// Remove one image file by its safe filename.
    func removeImageFile(_ filename: String)
    /// Publish the typed remote-apply event so editors rebase clean drafts.
    func sendRemoteApply(_ apply: JournalRemoteApply)
    /// Ask editors to commit their drafts before a remote apply overwrites.
    func flushEditorDrafts()

    /// macOS: bump the active journal's catalog metadata after a content change.
    func touchActiveJournalMetadata()
    /// macOS: drop a selection that no longer points at a real entry.
    func reconcileSelectionAfterApply()
    /// macOS: repoint the selection when a sync collision merged two entries.
    func entryCollisionMerged(from oldID: UUID, to newID: UUID)
    /// macOS: notify observers that the active journal identity changed.
    func notifyActiveJournalChanged()
    /// macOS: invalidate any cached image after an image write.
    func invalidateImageCache(filename: String)
}

extension JournalSyncStoreHost {
    public func touchActiveJournalMetadata() {}
    public func reconcileSelectionAfterApply() {}
    public func entryCollisionMerged(from oldID: UUID, to newID: UUID) {}
    public func notifyActiveJournalChanged() {}
    public func invalidateImageCache(filename: String) {}
}

/// Shared implementation of the sync engine's `JournalLocalSource` surface,
/// written once in WickSync and delegated to by both platform stores (AR-01).
/// All methods run on the main actor, matching the engine and the stores.
@MainActor
public struct JournalSyncBridge {
    public let host: any JournalSyncStoreHost

    public init(host: any JournalSyncStoreHost) {
        self.host = host
    }

    public func syncEntrySnapshots() -> [UUID: JournalEntry] {
        Dictionary(uniqueKeysWithValues: host.entries.map { ($0.id, $0) })
    }

    /// Single-point read for the sync engine's freshness path (SY-09): avoids
    /// rebuilding the whole entry dictionary per decision. Still reads the
    /// current in-memory state every call — the store is the freshest source.
    public func syncEntrySnapshot(entryID: UUID) -> JournalEntry? {
        host.entries.first { $0.id == entryID }
    }

    /// Commits any in-flight editor draft before the engine's freshness check.
    public func prepareForRemoteApply(entryID: UUID) {
        host.flushEditorDrafts()
    }

    /// Applies a whole cycle's remote changes in ONE pass (PF-01): one sort,
    /// one persist, one catalog touch, one selection reconcile, one UI publish.
    /// Re-verifies each mutation against its decision-time hash (AC-P1-05).
    @discardableResult
    public func applySyncedChanges(_ changes: [JournalSyncMutation], journalID: UUID) -> Set<UUID> {
        guard journalID == host.activeJournalID else { return [] }
        guard !host.isReadOnlyDueToLoadFailure else { return [] }
        guard !changes.isEmpty else { return [] }
        host.flushEditorDrafts()

        var applied: Set<UUID> = []
        var appliedEvents: [JournalRemoteApply] = []
        for change in changes {
            let entryID = change.entryID
            guard localEntryStillMatches(entryID: entryID, expectedHash: change.expectedLocalHash) else { continue }
            switch change {
            case .upsert(let entry, _):
                var appliedEntry = entry
                if appliedEntry.items.isEmpty {
                    appliedEntry.items = [JournalItem()]
                }
                if let index = host.entries.firstIndex(where: { $0.id == appliedEntry.id }) {
                    host.entries[index] = appliedEntry
                } else {
                    appliedEntry = mergeSyncedDateCollision(with: appliedEntry)
                    host.entries.append(appliedEntry)
                }
                applied.insert(entryID)
                appliedEvents.append(
                    JournalRemoteApply(journalID: journalID, entryID: appliedEntry.id)
                )
            case .remove(_, _):
                guard let index = host.entries.firstIndex(where: { $0.id == entryID }) else { continue }
                for filename in host.entries[index].allImageFilenames {
                    host.removeImageFile(filename)
                }
                host.entries.remove(at: index)
                applied.insert(entryID)
            }
        }

        guard !applied.isEmpty else { return [] }
        host.entries.sort { $0.date > $1.date }
        host.persistActiveJournal()
        host.touchActiveJournalMetadata()
        host.reconcileSelectionAfterApply()
        for apply in appliedEvents {
            host.sendRemoteApply(apply)
        }
        return applied
    }

    /// Inserts or replaces the entry with the same UUID without bumping
    /// `updatedAt`; remote timestamps drive last-writer-wins.
    public func applySyncedEntry(_ entry: JournalEntry, journalID: UUID) {
        guard journalID == host.activeJournalID else { return }
        guard !host.isReadOnlyDueToLoadFailure else { return }
        host.flushEditorDrafts()

        var applied = entry
        if applied.items.isEmpty {
            applied.items = [JournalItem()]
        }
        if let index = host.entries.firstIndex(where: { $0.id == applied.id }) {
            host.entries[index] = applied
        } else {
            applied = mergeSyncedDateCollision(with: applied)
            host.entries.append(applied)
        }
        host.entries.sort { $0.date > $1.date }
        host.persistActiveJournal()
        host.touchActiveJournalMetadata()
        host.reconcileSelectionAfterApply()
        host.sendRemoteApply(
            JournalRemoteApply(journalID: journalID, entryID: applied.id)
        )
    }

    /// Removes the entry with the given UUID together with its image files.
    public func removeSyncedEntry(entryID: UUID, journalID: UUID) {
        guard journalID == host.activeJournalID else { return }
        guard !host.isReadOnlyDueToLoadFailure else { return }
        guard let index = host.entries.firstIndex(where: { $0.id == entryID }) else { return }
        for filename in host.entries[index].allImageFilenames {
            host.removeImageFile(filename)
        }
        host.entries.remove(at: index)
        host.persistActiveJournal()
        host.touchActiveJournalMetadata()
        host.reconcileSelectionAfterApply()
    }

    /// Converges two UUIDs that independently claimed the same displayed day:
    /// the lexicographically smaller UUID survives on every device; the other
    /// becomes a normal local deletion and is tombstoned next cycle.
    public func mergeSyncedDateCollision(with incoming: JournalEntry) -> JournalEntry {
        guard let collisionIndex = host.entries.firstIndex(where: {
            $0.id != incoming.id && Calendar.current.isDate($0.date, inSameDayAs: incoming.date)
        }) else { return incoming }

        let collision = host.entries[collisionIndex]
        let incomingSurvives = incoming.id.uuidString < collision.id.uuidString
        var survivor = incomingSurvives ? incoming : collision
        let absorbed = incomingSurvives ? collision : incoming
        for item in absorbed.items where !item.isEmpty || absorbed.items.count == 1 {
            if !survivor.items.contains(where: { $0.id == item.id }) {
                survivor.items.append(item)
            }
        }
        if survivor.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            survivor.title = absorbed.title
        }
        survivor.createdAt = min(incoming.createdAt, collision.createdAt)
        survivor.updatedAt = max(incoming.updatedAt, collision.updatedAt)
        if survivor.items.isEmpty {
            survivor.items = [JournalItem()]
        }
        host.entries.remove(at: collisionIndex)
        host.entryCollisionMerged(from: collision.id, to: survivor.id)
        return survivor
    }

    /// True when the local entry still matches the decision-time hash — the
    /// final freshness gate before a queued remote mutation is committed.
    public func localEntryStillMatches(entryID: UUID, expectedHash: String?) -> Bool {
        let current = host.entries.first { $0.id == entryID }
        guard let expectedHash else { return current == nil }
        guard let current else { return false }
        return (try? JournalSyncEncoding.contentHash(for: current)) == expectedHash
    }

    /// Renames the journal to the remote manifest's name, returning the name
    /// actually applied (uniquified against OTHER local journals).
    @discardableResult
    public func applySyncedJournalName(_ name: String, journalID: UUID) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard journalID == host.activeJournalID,
              let index = host.journals.firstIndex(where: { $0.id == journalID })
        else { return host.journals.first { $0.id == journalID }?.name ?? host.activeJournalName }
        let resolved = trimmed.isEmpty
            ? host.journals[index].name
            : uniquifiedJournalName(trimmed, excluding: journalID)
        guard resolved != host.journals[index].name else { return resolved }
        host.journals[index].name = resolved
        host.journals[index].updatedAt = Date()
        _ = host.persistCatalog()
        host.notifyActiveJournalChanged()
        return resolved
    }

    /// Uniquifies a journal name against the OTHER journals in the catalog.
    public func uniquifiedJournalName(_ base: String, excluding journalID: UUID? = nil) -> String {
        let existing = Set(host.journals.filter { journalID == nil || $0.id != journalID }
            .map { $0.name.lowercased() })
        guard existing.contains(base.lowercased()) else { return base }
        var index = 2
        while existing.contains("\(base) \(index)".lowercased()) {
            index += 1
        }
        return "\(base) \(index)"
    }

    // MARK: - Images

    public func syncedImageFilenames() -> Set<String> {
        Set(host.entries.flatMap(\.allImageFilenames))
    }

    public func syncedImageData(filename: String) -> Data? {
        guard let url = host.imageURL(for: filename) else { return nil }
        return try? Data(contentsOf: url)
    }

    public func hasSyncedImage(filename: String) -> Bool {
        guard let url = host.imageURL(for: filename) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    public func storeSyncedImage(filename: String, data: Data, journalID: UUID) {
        guard journalID == host.activeJournalID else { return }
        guard !host.isReadOnlyDueToLoadFailure else { return }
        guard let url = host.imageURL(for: filename) else { return }
        try? data.write(to: url, options: .atomic)
        host.invalidateImageCache(filename: filename)
    }
}
