import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers
import WickSync

// MARK: - Content queries & mutations
//
// Item/timeline queries, mutations, and selection helpers, split out of the
// store god-file (DS-07). Pure behavior-preserving move.

extension JournalStore {
    // MARK: - Queries

    /// True when results should be item-scoped (not whole days).
    var isItemScoped: Bool {
        selectedTagFilter != nil
            || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var selectedEntryID: UUID? {
        switch selection {
        case .day(let id):
            return id
        case .item(let ref):
            return ref.entryID
        case nil:
            return nil
        }
    }

    var selectedItemID: UUID? {
        if case .item(let ref) = selection {
            return ref.itemID
        }
        return nil
    }

    var selectedEntry: JournalEntry? {
        guard let selectedEntryID else { return nil }
        return entries.first { $0.id == selectedEntryID }
    }

    /// Day-level list (no tag/search filter).
    var filteredEntries: [JournalEntry] {
        entries.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date > rhs.date
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    /// Item-level list for tag / text search. Sibling items on the same day are not included
    /// unless they also match.
    var filteredTimelineItems: [JournalTimelineItem] {
        let tagNeedle = selectedTagFilter?.lowercased()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var results: [JournalTimelineItem] = []
        for entry in entries {
            for item in entry.items {
                if let tagNeedle {
                    let tag = item.tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    guard tag == tagNeedle else { continue }
                }

                if !query.isEmpty {
                    let haystack = (
                        entry.title + " " + item.tag + " " + item.body + " " + (item.review?.note ?? "")
                    ).lowercased()
                    guard haystack.contains(query) else { continue }
                }

                results.append(
                    JournalTimelineItem(
                        ref: JournalItemRef(entryID: entry.id, itemID: item.id),
                        date: entry.date,
                        entryTitle: entry.title,
                        entryUpdatedAt: entry.updatedAt,
                        item: item
                    )
                )
            }
        }

        return results.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date > rhs.date
            }
            if lhs.entryUpdatedAt != rhs.entryUpdatedAt {
                return lhs.entryUpdatedAt > rhs.entryUpdatedAt
            }
            return lhs.item.tag.localizedCaseInsensitiveCompare(rhs.item.tag) == .orderedAscending
        }
    }

    /// All distinct tags from items, case-preserved by first occurrence.
    var allTags: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for entry in entries {
            for tag in entry.tags {
                let key = tag.lowercased()
                if seen.insert(key).inserted {
                    result.append(tag)
                }
            }
        }
        return result.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    // MARK: - Mutations

    /// Opens the journal for `date` if one exists; otherwise creates it.
    /// Enforces one journal document per calendar day.
    @discardableResult
    func createEntry(on date: Date = Date()) -> JournalEntry {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        if let existing = entry(on: day) {
            selectedTagFilter = nil
            searchText = ""
            selection = .day(existing.id)
            return existing
        }

        let entry = JournalEntry(date: day, items: [JournalItem()])
        entries.insert(entry, at: 0)
        selectedTagFilter = nil
        searchText = ""
        selection = .day(entry.id)
        persist()
        touchActiveJournalMetadata()
        return entry
    }

    /// Create today's entry if none exists for today, otherwise select it as a full day.
    @discardableResult
    func openOrCreateToday() -> JournalEntry {
        createEntry(on: Date())
    }

    /// Ensures exchange-planned items exist without rewriting any existing
    /// tag or content. Missing days are created; existing days receive only
    /// items whose deterministic ids are not already present. One persist for
    /// the whole batch, without changing selection or filters.
    @discardableResult
    func ensurePositionEntries(_ skeletons: [(day: Date, items: [JournalItem])]) -> [Date] {
        guard !isReadOnlyDueToLoadFailure, !skeletons.isEmpty else { return [] }

        let changed = Self.applyPositionSkeletons(
            skeletons,
            to: &entries,
            calendar: .current,
            now: Date()
        )
        guard !changed.isEmpty else { return [] }

        persist()
        touchActiveJournalMetadata()
        objectWillChange.send()
        guard let activeJournalID else { return changed.map(\.day) }
        for change in changed {
            remoteEntryDidApply.send(
                JournalRemoteApply(
                    journalID: activeJournalID,
                    entryID: change.entry.id
                )
            )
        }
        return changed.map(\.day)
    }

    /// Entries of any journal. The active book's in-memory copy wins; others
    /// are read from disk so exchange sync can bind a non-open journal. Load
    /// failure is explicit — callers must not treat an empty array as "empty".
    func entries(for journalID: UUID) -> JournalEntriesLoadResult {
        if journalID == activeJournalID {
            return .active(entries)
        }
        return loadEntriesFromDisk(journalID: journalID)
    }

    /// Number of day entries in a journal.
    func entryCount(for journalID: UUID) -> Int {
        if journalID == activeJournalID {
            return entries.count
        }
        switch loadEntriesFromDisk(journalID: journalID) {
        case .active(let entries), .loaded(let entries):
            return entries.count
        default:
            return 0
        }
    }

    /// Same as `ensurePositionEntries`, but can target a journal that is not open.
    /// Only runs on a loaded journal or a legitimately new one; corrupt,
    /// newer-format, and deleted-from-catalog journals are skipped without
    /// touching the file on disk.
    @discardableResult
    func ensurePositionEntries(
        _ skeletons: [(day: Date, items: [JournalItem])],
        in journalID: UUID
    ) -> [Date] {
        if journalID == activeJournalID {
            return ensurePositionEntries(skeletons)
        }
        guard !isCatalogReadOnly else { return [] }
        guard !skeletons.isEmpty else { return [] }
        // A journal removed from the catalog must never have its directory
        // recreated (a stale exchange job could otherwise resurrect it).
        guard journals.contains(where: { $0.id == journalID }) else { return [] }

        var stored: [JournalEntry]
        switch loadEntriesFromDisk(journalID: journalID) {
        case .active(let entries), .loaded(let entries):
            stored = entries
        case .missing:
            stored = []
        case .corrupt(let error):
            // Non-destructive skip: the original file must stay byte-for-byte.
            lastPersistError = "journal \(journalID.uuidString) not writable: \(error.localizedDescription)"
            NSLog("Wick exchange: auto-create skipped for unreadable journal %@ (%@)", journalID.uuidString, error.localizedDescription)
            return []
        case .unsupportedVersion(let version):
            lastPersistError = "journal \(journalID.uuidString) has unsupported format v\(version)"
            NSLog("Wick exchange: auto-create skipped for journal %@ (unsupported v%ld)", journalID.uuidString, version)
            return []
        }

        let changed = Self.applyPositionSkeletons(
            skeletons,
            to: &stored,
            calendar: .current,
            now: Date()
        )
        guard !changed.isEmpty else { return [] }
        do {
            try persistEntries(stored, journalID: journalID)
        } catch {
            lastPersistError = error.localizedDescription
            NSLog("Wick exchange: auto-create persist failed for %@: %@", journalID.uuidString, error.localizedDescription)
            return []
        }
        return changed.map(\.day)
    }

    static func applyPositionSkeletons(
        _ skeletons: [(day: Date, items: [JournalItem])],
        to stored: inout [JournalEntry],
        calendar: Calendar,
        now: Date
    ) -> [(day: Date, entry: JournalEntry)] {
        var changed: [(day: Date, entry: JournalEntry)] = []
        for skeleton in skeletons where !skeleton.items.isEmpty {
            let day = calendar.startOfDay(for: skeleton.day)
            if let index = stored.firstIndex(where: {
                calendar.isDate($0.date, inSameDayAs: day)
            }) {
                let existingIDs = Set(stored[index].items.map(\.id))
                let additions = skeleton.items.filter { !existingIDs.contains($0.id) }
                guard !additions.isEmpty else { continue }
                if stored[index].items.allSatisfy(\.isEmpty) {
                    stored[index].items = []
                }
                stored[index].items.append(contentsOf: additions)
                stored[index].updatedAt = now
                changed.append((day, stored[index]))
            } else {
                let entry = JournalEntry(
                    date: day,
                    items: skeleton.items,
                    createdAt: now,
                    updatedAt: now
                )
                stored.insert(entry, at: 0)
                changed.append((day, entry))
            }
        }
        return changed
    }

    func loadEntriesFromDisk(journalID: UUID) -> JournalEntriesLoadResult {
        let url = librariesRoot
            .appendingPathComponent(journalID.uuidString, isDirectory: true)
            .appendingPathComponent("journal.json", isDirectory: false)
        guard fileManager.fileExists(atPath: url.path) else { return .missing }
        do {
            let data = try Data(contentsOf: url)
            let snapshot = try decoder.decode(JournalSnapshot.self, from: data)
            guard snapshot.version <= JournalSnapshot.currentVersion else {
                return .unsupportedVersion(snapshot.version)
            }
            return .loaded(snapshot.entries.sorted { $0.date > $1.date })
        } catch {
            return .corrupt(error)
        }
    }

    /// Persists a non-active journal with the same protections as the active
    /// one: sidecar `.bak` before the atomic overwrite, and a thrown error
    /// instead of a swallowed `try?`.
    func persistEntries(_ entries: [JournalEntry], journalID: UUID) throws {
        let dir = librariesRoot.appendingPathComponent(journalID.uuidString, isDirectory: true)
        let url = dir.appendingPathComponent("journal.json", isDirectory: false)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let snapshot = JournalSnapshot(version: JournalSnapshot.currentVersion, entries: entries)
        let data = try encoder.encode(snapshot)
        let backupURL = dir.appendingPathComponent("journal.json.bak", isDirectory: false)
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: backupURL)
            try? fileManager.copyItem(at: url, to: backupURL)
        }
        try data.write(to: url, options: .atomic)
    }

    func updateEntry(_ entry: JournalEntry) {
        guard !isReadOnlyDueToLoadFailure else { return }
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else {
            return
        }

        var updated = entry
        if updated.items.isEmpty {
            updated.items = [JournalItem()]
        }
        updated.date = Calendar.current.startOfDay(for: updated.date)

        // One day → one document: merge if the new date collides with another entry.
        if let otherIndex = entries.firstIndex(where: {
            $0.id != updated.id && Calendar.current.isDate($0.date, inSameDayAs: updated.date)
        }) {
            merge(entryAt: index, into: otherIndex, preferring: updated)
            return
        }

        guard Self.hasContentChange(from: entries[index], to: updated) else { return }

        let structural = Self.isStructuralChange(from: entries[index], to: updated)
        updated.updatedAt = Date()
        entries[index] = updated
        persist()
        if structural {
            touchActiveJournalMetadata()
            objectWillChange.send()
            reconcileSelectionAfterChange()
        }
    }

    /// Draft timestamps are bookkeeping, not user content. An unchanged draft
    /// must not become a sync edit merely because a window or journal closed.
    static func hasContentChange(from old: JournalEntry, to new: JournalEntry) -> Bool {
        old.date != new.date
            || old.title != new.title
            || old.items != new.items
    }

    /// True when the change should rebuild the journal UI (list, tags, seals).
    /// Body-only typing stays in drafts + disk and must not fan out (P2).
    static func isStructuralChange(from old: JournalEntry, to new: JournalEntry) -> Bool {
        if old.date != new.date || old.title != new.title {
            return true
        }
        if old.items.count != new.items.count {
            return true
        }
        for (lhs, rhs) in zip(old.items, new.items) {
            if lhs.id != rhs.id
                || lhs.tag != rhs.tag
                || lhs.imageFilenames != rhs.imageFilenames
                || lhs.review != rhs.review
            {
                return true
            }
        }
        return false
    }

    func deleteEntry(id: UUID) {
        guard !isReadOnlyDueToLoadFailure else { return }
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            return
        }
        let entry = entries[index]
        for filename in entry.allImageFilenames {
            removeImageFile(filename)
        }
        entries.remove(at: index)
        if selectedEntryID == id {
            selection = defaultSelection()
        }
        persist()
        touchActiveJournalMetadata()
    }

    @discardableResult
    func addItem(to entryID: UUID) -> JournalItem? {
        guard !isReadOnlyDueToLoadFailure else { return nil }
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else {
            return nil
        }
        let item = JournalItem()
        entries[index].items.append(item)
        entries[index].updatedAt = Date()
        persist()
        touchActiveJournalMetadata()
        return item
    }

    func deleteItem(itemID: UUID, from entryID: UUID) {
        guard !isReadOnlyDueToLoadFailure else { return }
        guard let entryIndex = entries.firstIndex(where: { $0.id == entryID }) else {
            return
        }
        guard let itemIndex = entries[entryIndex].items.firstIndex(where: { $0.id == itemID }) else {
            return
        }

        let item = entries[entryIndex].items[itemIndex]
        for filename in item.imageFilenames {
            removeImageFile(filename)
        }

        entries[entryIndex].items.remove(at: itemIndex)
        if entries[entryIndex].items.isEmpty {
            // Removing the last item made the entry empty: the entry's images
            // were already deleted above (they belonged to the removed item),
            // so it collapses into a plain deletion (DS-08).
            entries.remove(at: entryIndex)
            selection = defaultSelection()
        } else {
            entries[entryIndex].updatedAt = Date()
            if case .item(let ref) = selection, ref.itemID == itemID {
                selection = defaultSelection()
            }
        }
        persist()
        touchActiveJournalMetadata()
    }

    func selectDay(_ entryID: UUID?) {
        if let entryID {
            selection = .day(entryID)
        } else {
            selection = nil
        }
    }

    func selectItem(_ ref: JournalItemRef?) {
        if let ref {
            selection = .item(ref)
        } else {
            selection = nil
        }
    }

    /// Leave item-scoped mode and open the full day that owns the current item.
    func openSelectedDayFully() {
        guard let entryID = selectedEntryID else { return }
        selectedTagFilter = nil
        searchText = ""
        selection = .day(entryID)
    }

    func setTagFilter(_ tag: String?) {
        selectedTagFilter = tag
        handleFilterChange()
    }

    func clearSearch() {
        searchText = ""
        handleFilterChange()
    }

    /// Call when tag filter or search text changes so selection stays valid and switches
    /// between day-scope and item-scope as needed.
    func handleFilterChange() {
        switch selection {
        case .day(let entryID) where isItemScoped:
            if let match = filteredTimelineItems.first(where: { $0.ref.entryID == entryID }) {
                selection = .item(match.ref)
            } else {
                selection = defaultSelection()
            }
        case .item(let ref) where !isItemScoped:
            if entries.contains(where: { $0.id == ref.entryID }) {
                selection = .day(ref.entryID)
            } else {
                selection = defaultSelection()
            }
        case .item(let ref) where isItemScoped:
            if !filteredTimelineItems.contains(where: { $0.ref == ref }) {
                selection = defaultSelection()
            }
        case .day(let entryID) where !isItemScoped:
            if !entries.contains(where: { $0.id == entryID }) {
                selection = defaultSelection()
            }
        case nil:
            selection = defaultSelection()
        default:
            break
        }
    }

    // MARK: - Selection helpers

    func defaultSelection() -> JournalSelection? {
        if isItemScoped {
            return filteredTimelineItems.first.map { .item($0.ref) }
        }
        return filteredEntries.first.map { .day($0.id) }
    }

    func reconcileSelectionAfterChange() {
        guard let selection else { return }

        switch selection {
        case .day(let entryID):
            if !entries.contains(where: { $0.id == entryID }) {
                self.selection = defaultSelection()
            }
        case .item(let ref):
            if isItemScoped {
                let stillVisible = filteredTimelineItems.contains { $0.ref == ref }
                if !stillVisible {
                    self.selection = defaultSelection()
                }
            } else if !entries.contains(where: { $0.id == ref.entryID }) {
                self.selection = defaultSelection()
            }
        }
    }

    func entry(on day: Date) -> JournalEntry? {
        let calendar = Calendar.current
        return entries
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
    }

    /// Merge the destination day's contents into the source entry while keeping
    /// the source UUID. Moving an entry never changes its identity.
    func merge(entryAt sourceIndex: Int, into destinationIndex: Int, preferring source: JournalEntry) {
        let destination = entries[destinationIndex]
        var merged = source
        for item in destination.items where !item.isEmpty || destination.items.count == 1 {
            if !merged.items.contains(where: { $0.id == item.id }) {
                merged.items.append(item)
            }
        }
        if merged.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.title = destination.title
        }
        merged.updatedAt = Date()
        if merged.items.isEmpty {
            merged.items = [JournalItem()]
        }

        let sourceID = source.id
        let destinationID = destination.id
        entries.removeAll { $0.id == destinationID }
        if let newSource = entries.firstIndex(where: { $0.id == sourceID }) {
            entries[newSource] = merged
        } else {
            entries.insert(merged, at: 0)
        }
        selection = .day(sourceID)
        persist()
        touchActiveJournalMetadata()
        reconcileSelectionAfterChange()
    }

}
