import Foundation
import WickSync
import WickTrading

// MARK: - Sync engine bridge

/// The sync engine (`WickSync.JournalSyncEngine`) talks to the store only through
/// this surface: UUID-keyed snapshots in, whole-entry applies/removals out. Applies
/// replace the same UUID wholesale and never bump `updatedAt`, so remote
/// timestamps keep driving last-writer-wins decisions.
extension JournalStore: JournalLocalSource {
    var syncJournalID: UUID? { activeJournalID }

    var syncJournalName: String { activeJournal?.name ?? "" }

    var syncIsWritable: Bool { !isReadOnlyDueToLoadFailure }

    func syncEntrySnapshots() -> [UUID: JournalEntry] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    }

    /// Test helper: apply against the currently active journal.
    func applySyncedEntry(_ entry: JournalEntry) {
        guard let activeJournalID else { return }
        applySyncedEntry(entry, journalID: activeJournalID)
    }

    /// Applies a whole cycle's remote changes in ONE pass: one persist, one
    /// catalog touch, one selection reconcile, one UI publish (PF-01). Each
    /// mutation is re-verified against its decision-time local hash right
    /// before committing; an entry edited since the decision is skipped and only
    /// actually-applied entry ids are returned (AC-P1-05).
    @discardableResult
    func applySyncedChanges(_ changes: [JournalSyncMutation], journalID: UUID) -> Set<UUID> {
        guard journalID == activeJournalID else { return [] }
        guard !isReadOnlyDueToLoadFailure else { return [] }
        guard !changes.isEmpty else { return [] }
        // Commit any in-flight editor draft so the freshness re-check below
        // sees uncommitted typing before the batch overwrites it.
        NotificationCenter.default.post(name: .wickWillFlushJournalDrafts, object: nil)

        var applied: Set<UUID> = []
        var appliedEntries: [JournalRemoteApply] = []
        for change in changes {
            let entryID = change.entryID
            guard localEntryStillMatches(entryID: entryID, expectedHash: change.expectedLocalHash) else { continue }
            switch change {
            case .upsert(let entry, _):
                var appliedEntry = entry
                if appliedEntry.items.isEmpty {
                    appliedEntry.items = [JournalItem()]
                }
                if let index = entries.firstIndex(where: { $0.id == appliedEntry.id }) {
                    entries[index] = appliedEntry
                } else {
                    appliedEntry = mergeSyncedDateCollision(with: appliedEntry)
                    entries.append(appliedEntry)
                }
                applied.insert(entryID)
                appliedEntries.append(
                    JournalRemoteApply(journalID: journalID, entryID: appliedEntry.id)
                )
            case .remove(_, _):
                guard let index = entries.firstIndex(where: { $0.id == entryID }) else { continue }
                let entry = entries[index]
                for filename in entry.allImageFilenames {
                    removeImageFile(filename)
                }
                entries.remove(at: index)
                applied.insert(entryID)
                if selectedEntryID == entry.id {
                    selection = defaultSelection()
                }
            }
        }

        guard !applied.isEmpty else { return [] }
        persist()
        touchActiveJournalMetadata()
        reconcileSelectionAfterChange()
        for apply in appliedEntries {
            remoteEntryDidApply.send(apply)
        }
        return applied
    }

    /// Converges two UUIDs that independently claimed the same displayed day.
    /// The lexicographically smaller UUID survives on every device; the other
    /// UUID becomes a normal local deletion and is tombstoned next cycle.
    func mergeSyncedDateCollision(with incoming: JournalEntry) -> JournalEntry {
        guard let collisionIndex = entries.firstIndex(where: {
            $0.id != incoming.id && Calendar.current.isDate($0.date, inSameDayAs: incoming.date)
        }) else { return incoming }

        let collision = entries[collisionIndex]
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
        entries.remove(at: collisionIndex)
        switch selection {
        case .day(let id) where id == collision.id:
            selection = .day(survivor.id)
        case .item(let ref) where ref.entryID == collision.id:
            selection = .item(JournalItemRef(entryID: survivor.id, itemID: ref.itemID))
        default:
            break
        }
        return survivor
    }

    /// True when the local entry still matches the decision-time hash — the
    /// final freshness gate before a queued remote mutation is committed.
    func localEntryStillMatches(entryID: UUID, expectedHash: String?) -> Bool {
        let current = entries.first { $0.id == entryID }
        guard let expectedHash else { return current == nil }
        guard let current else { return false }
        return (try? JournalSyncEncoding.contentHash(for: current)) == expectedHash
    }

    /// Commits any in-flight editor draft so the sync engine's freshness check
    /// sees real local content instead of a stale store snapshot. Runs before
    /// the engine's per-entry freshness guard; re-hashing after the commit
    /// detects mid-cycle edits and skips the apply.
    func prepareForRemoteApply(entryID: UUID) {
        NotificationCenter.default.post(name: .wickWillFlushJournalDrafts, object: nil)
    }

    func applySyncedEntry(_ entry: JournalEntry, journalID: UUID) {
        guard journalID == activeJournalID else { return }
        guard !isReadOnlyDueToLoadFailure else { return }
        // Commit any in-flight editor draft before replacing the entry underneath it.
        NotificationCenter.default.post(name: .wickWillFlushJournalDrafts, object: nil)

        var applied = entry
        if applied.items.isEmpty {
            applied.items = [JournalItem()]
        }

        if let index = entries.firstIndex(where: { $0.id == applied.id }) {
            entries[index] = applied
        } else {
            applied = mergeSyncedDateCollision(with: applied)
            entries.append(applied)
        }

        persist()
        touchActiveJournalMetadata()
        reconcileSelectionAfterChange()
        // Typed event so editors rebase their clean drafts onto the new value.
        remoteEntryDidApply.send(
            JournalRemoteApply(journalID: journalID, entryID: applied.id)
        )
    }

    func removeSyncedEntry(entryID: UUID) {
        guard let activeJournalID else { return }
        removeSyncedEntry(entryID: entryID, journalID: activeJournalID)
    }

    func removeSyncedEntry(entryID: UUID, journalID: UUID) {
        guard journalID == activeJournalID else { return }
        guard !isReadOnlyDueToLoadFailure else { return }
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        let entry = entries[index]
        for filename in entry.allImageFilenames {
            removeImageFile(filename)
        }
        entries.remove(at: index)
        if selectedEntryID == entry.id {
            selection = defaultSelection()
        }
        persist()
        touchActiveJournalMetadata()
    }

    /// Renames the journal identified by `journalID` to the remote manifest's
    /// name, returning the name actually applied (uniquified against OTHER
    /// local journals). No-op when that journal is not the one currently
    /// bound — a cycle that outlives a user switch must not rename the
    /// newly opened journal to the previous one's remote name.
    /// Test helper: rename the currently active journal from a remote name.
    @discardableResult
    func applySyncedJournalName(_ name: String) -> String {
        guard let activeJournalID else { return name }
        return applySyncedJournalName(name, journalID: activeJournalID)
    }

    @discardableResult
    func applySyncedJournalName(_ name: String, journalID: UUID) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard journalID == activeJournalID,
              let index = journals.firstIndex(where: { $0.id == journalID })
        else { return journals.first { $0.id == journalID }?.name ?? activeJournal?.name ?? name }
        let resolved = trimmed.isEmpty
            ? journals[index].name
            : uniquifiedJournalName(trimmed, excluding: journalID)
        guard resolved != journals[index].name else { return resolved }
        journals[index].name = resolved
        journals[index].updatedAt = Date()
        persistCatalog()
        notifyActiveJournalChanged()
        return resolved
    }

    func syncedImageFilenames() -> Set<String> {
        Set(entries.flatMap(\.allImageFilenames))
    }

    func syncedImageData(filename: String) -> Data? {
        guard let url = imageURL(for: filename) else { return nil }
        return try? Data(contentsOf: url)
    }

    func hasSyncedImage(filename: String) -> Bool {
        guard let url = imageURL(for: filename) else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    func storeSyncedImage(filename: String, data: Data) {
        guard let activeJournalID else { return }
        storeSyncedImage(filename: filename, data: data, journalID: activeJournalID)
    }

    func storeSyncedImage(filename: String, data: Data, journalID: UUID) {
        guard journalID == activeJournalID else { return }
        guard !isReadOnlyDueToLoadFailure else { return }
        guard let url = imageURL(for: filename) else { return }
        try? data.write(to: url, options: .atomic)
        JournalThumbnailCache.shared.invalidate(filename: filename)
    }
}
