import AppKit
import Foundation
import UniformTypeIdentifiers

/// Points at one item inside a day journal. Used when the timeline is item-scoped
/// (tag filter / text search).
struct JournalItemRef: Hashable, Identifiable {
    let entryID: UUID
    let itemID: UUID

    var id: String { "\(entryID.uuidString)_\(itemID.uuidString)" }
}

/// A timeline row for a single item (decoupled from sibling items on the same day).
struct JournalTimelineItem: Identifiable, Hashable {
    var id: String { ref.id }
    let ref: JournalItemRef
    let date: Date
    let entryTitle: String
    let entryUpdatedAt: Date
    let item: JournalItem
}

/// What the editor is focused on.
enum JournalSelection: Hashable {
    /// Full day journal (all items).
    case day(UUID)
    /// Single item only (used under tag / search filtering).
    case item(JournalItemRef)
}

/// File-backed journal store under Application Support.
/// Layout:
///   ~/Library/Application Support/Wick/Journal/
///     journal.json
///     journal.json.bak
///     backups/journal-*.json  (rolling)
///     images/<uuid>.png|jpg|...
@MainActor
final class JournalStore: ObservableObject {
    static let shared = JournalStore()

    @Published private(set) var entries: [JournalEntry] = []
    @Published var selection: JournalSelection?
    @Published var selectedTagFilter: String?
    @Published var searchText: String = ""

    /// When true, persistence is blocked so a failed load cannot wipe the on-disk file.
    @Published private(set) var isReadOnlyDueToLoadFailure = false
    @Published private(set) var loadFailureMessage: String?
    @Published private(set) var lastPersistError: String?
    @Published private(set) var didRestoreFromBackup = false

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let rootDirectory: URL
    private let imagesDirectory: URL
    private let databaseURL: URL
    private let backupURL: URL
    private let backupsDirectory: URL

    private let maxRollingBackups = 5
    private var lastRollingBackupAt: Date?

    /// Testing / custom root initializer.
    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
        imagesDirectory = rootDirectory.appendingPathComponent("images", isDirectory: true)
        databaseURL = rootDirectory.appendingPathComponent("journal.json", isDirectory: false)
        backupURL = rootDirectory.appendingPathComponent("journal.json.bak", isDirectory: false)
        backupsDirectory = rootDirectory.appendingPathComponent("backups", isDirectory: true)

        ensureDirectories()
        load()
    }

    /// Shared app store under Application Support.
    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let root = support.appendingPathComponent("Wick/Journal", isDirectory: true)
        self.rootDirectory = root
        imagesDirectory = root.appendingPathComponent("images", isDirectory: true)
        databaseURL = root.appendingPathComponent("journal.json", isDirectory: false)
        backupURL = root.appendingPathComponent("journal.json.bak", isDirectory: false)
        backupsDirectory = root.appendingPathComponent("backups", isDirectory: true)

        ensureDirectories()
        load()
    }

    var dataDirectoryURL: URL { rootDirectory }

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
        return entry
    }

    /// Create today's entry if none exists for today, otherwise select it as a full day.
    @discardableResult
    func openOrCreateToday() -> JournalEntry {
        createEntry(on: Date())
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

        updated.updatedAt = Date()
        entries[index] = updated
        persist()
        reconcileSelectionAfterChange()
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
            let orphaned = entries[entryIndex]
            for filename in orphaned.allImageFilenames {
                removeImageFile(filename)
            }
            entries.remove(at: entryIndex)
            selection = defaultSelection()
        } else {
            entries[entryIndex].updatedAt = Date()
            if case .item(let ref) = selection, ref.itemID == itemID {
                selection = defaultSelection()
            }
        }
        persist()
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

    // MARK: - Images

    func imageURL(for filename: String) -> URL {
        imagesDirectory.appendingPathComponent(filename)
    }

    func loadNSImage(filename: String) -> NSImage? {
        let url = imageURL(for: filename)
        return NSImage(contentsOf: url)
    }

    func loadThumbnail(filename: String, maxPixel: CGFloat = 320) -> NSImage? {
        JournalThumbnailCache.shared.thumbnail(
            filename: filename,
            url: imageURL(for: filename),
            maxPixel: maxPixel
        )
    }

    @discardableResult
    func addImage(
        from data: Data,
        to entryID: UUID,
        itemID: UUID,
        preferredExtension: String = "png"
    ) -> String? {
        guard !isReadOnlyDueToLoadFailure else { return nil }
        guard let entryIndex = entries.firstIndex(where: { $0.id == entryID }),
              let itemIndex = entries[entryIndex].items.firstIndex(where: { $0.id == itemID })
        else {
            return nil
        }

        let processed = JournalImageProcessing.process(data: data, preferredExtension: preferredExtension)
        let payload: Data
        let ext: String
        if let processed {
            payload = processed.data
            ext = processed.fileExtension
        } else {
            payload = data
            ext = sanitizedExtension(preferredExtension)
        }

        let filename = "\(UUID().uuidString).\(ext)"
        let destination = imageURL(for: filename)

        do {
            try payload.write(to: destination, options: .atomic)
        } catch {
            return nil
        }

        entries[entryIndex].items[itemIndex].imageFilenames.append(filename)
        entries[entryIndex].updatedAt = Date()
        persist()
        return filename
    }

    @discardableResult
    func addImage(from fileURL: URL, to entryID: UUID, itemID: UUID) -> String? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        let ext = fileURL.pathExtension.isEmpty ? "png" : fileURL.pathExtension
        return addImage(from: data, to: entryID, itemID: itemID, preferredExtension: ext)
    }

    @discardableResult
    func addImage(from nsImage: NSImage, to entryID: UUID, itemID: UUID) -> String? {
        if let processed = JournalImageProcessing.process(nsImage: nsImage) {
            return addImage(
                from: processed.data,
                to: entryID,
                itemID: itemID,
                preferredExtension: processed.fileExtension
            )
        }
        guard let data = pngData(from: nsImage) else {
            return nil
        }
        return addImage(from: data, to: entryID, itemID: itemID, preferredExtension: "png")
    }

    func removeImage(filename: String, from entryID: UUID, itemID: UUID) {
        guard !isReadOnlyDueToLoadFailure else { return }
        guard let entryIndex = entries.firstIndex(where: { $0.id == entryID }),
              let itemIndex = entries[entryIndex].items.firstIndex(where: { $0.id == itemID })
        else {
            return
        }
        entries[entryIndex].items[itemIndex].imageFilenames.removeAll { $0 == filename }
        entries[entryIndex].updatedAt = Date()
        removeImageFile(filename)
        persist()
    }

    func pasteImageFromClipboard(to entryID: UUID, itemID: UUID) -> Bool {
        let pasteboard = NSPasteboard.general

        if let image = NSImage(pasteboard: pasteboard) {
            return addImage(from: image, to: entryID, itemID: itemID) != nil
        }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]) as? [URL] {
            var added = false
            for url in urls {
                if addImage(from: url, to: entryID, itemID: itemID) != nil {
                    added = true
                }
            }
            return added
        }

        return false
    }

    // MARK: - Export / Import / Reveal

    func revealDataDirectoryInFinder() {
        NSWorkspace.shared.open(rootDirectory)
    }

    /// Exports `journal.json` + `images/` into a zip at `destinationURL`.
    func exportArchive(to destinationURL: URL) throws {
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("WickExport-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let payloadDir = tempRoot.appendingPathComponent("Wick-Journal", isDirectory: true)
        try fileManager.createDirectory(at: payloadDir, withIntermediateDirectories: true)

        // Ensure latest snapshot is on disk when writable.
        if !isReadOnlyDueToLoadFailure {
            persist()
        }

        if fileManager.fileExists(atPath: databaseURL.path) {
            try fileManager.copyItem(
                at: databaseURL,
                to: payloadDir.appendingPathComponent("journal.json")
            )
        } else {
            let snapshot = JournalSnapshot(version: JournalSnapshot.currentVersion, entries: entries)
            let data = try encoder.encode(snapshot)
            try data.write(to: payloadDir.appendingPathComponent("journal.json"), options: .atomic)
        }

        let imagesDest = payloadDir.appendingPathComponent("images", isDirectory: true)
        try fileManager.createDirectory(at: imagesDest, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: imagesDirectory.path) {
            let imageFiles = try fileManager.contentsOfDirectory(
                at: imagesDirectory,
                includingPropertiesForKeys: nil
            )
            for file in imageFiles where !file.hasDirectoryPath {
                try fileManager.copyItem(
                    at: file,
                    to: imagesDest.appendingPathComponent(file.lastPathComponent)
                )
            }
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try runZip(sourceDirectory: payloadDir, destinationZip: destinationURL)
    }

    /// Imports a previously exported zip or a bare `journal.json`.
    /// Replaces current data after writing a backup of the existing store.
    func importArchive(from sourceURL: URL) throws {
        // Import is an explicit recovery path — clear read-only so we can replace data.
        breakReadOnlyIfImporting()

        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("WickImport-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempRoot) }
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let jsonURL: URL
        let importedImages: URL?

        if sourceURL.pathExtension.lowercased() == "json" {
            jsonURL = sourceURL
            importedImages = nil
        } else {
            try runUnzip(zipURL: sourceURL, destinationDirectory: tempRoot)
            if let found = findJournalJSON(under: tempRoot) {
                jsonURL = found
            } else {
                throw JournalStoreError.importMissingJournalJSON
            }
            let siblingImages = jsonURL
                .deletingLastPathComponent()
                .appendingPathComponent("images", isDirectory: true)
            importedImages = fileManager.fileExists(atPath: siblingImages.path) ? siblingImages : nil
        }

        let data = try Data(contentsOf: jsonURL)
        let snapshot = try decoder.decode(JournalSnapshot.self, from: data)

        // Backup current store before replacing.
        if fileManager.fileExists(atPath: databaseURL.path) {
            copyDatabaseToSidecarBackup(includeRolling: true)
        }

        // Replace images directory.
        if fileManager.fileExists(atPath: imagesDirectory.path) {
            try fileManager.removeItem(at: imagesDirectory)
        }
        try fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)

        if let importedImages {
            let files = try fileManager.contentsOfDirectory(
                at: importedImages,
                includingPropertiesForKeys: nil
            )
            for file in files where !file.hasDirectoryPath {
                let dest = imagesDirectory.appendingPathComponent(file.lastPathComponent)
                try fileManager.copyItem(at: file, to: dest)
            }
        }

        entries = snapshot.entries.sorted { $0.date > $1.date }
        selection = entries.first.map { .day($0.id) }
        isReadOnlyDueToLoadFailure = false
        loadFailureMessage = nil
        didRestoreFromBackup = false
        lastPersistError = nil
        JournalThumbnailCache.shared.removeAll()
        persist()
    }

    /// Forces a synchronous write of the in-memory snapshot (used on quit).
    func flushPendingWrites() {
        guard !isReadOnlyDueToLoadFailure else { return }
        persist()
    }

    /// Clears read-only mode after the user explicitly chooses to start fresh
    /// (existing on-disk file is first moved aside).
    func abandonCorruptDatabaseAndStartFresh() throws {
        if fileManager.fileExists(atPath: databaseURL.path) {
            let quarantine = rootDirectory.appendingPathComponent(
                "journal.corrupt-\(Int(Date().timeIntervalSince1970)).json"
            )
            try? fileManager.moveItem(at: databaseURL, to: quarantine)
        }
        entries = []
        selection = nil
        isReadOnlyDueToLoadFailure = false
        loadFailureMessage = nil
        didRestoreFromBackup = false
        persist()
    }

    // MARK: - Selection helpers

    private func defaultSelection() -> JournalSelection? {
        if isItemScoped {
            return filteredTimelineItems.first.map { .item($0.ref) }
        }
        return filteredEntries.first.map { .day($0.id) }
    }

    private func reconcileSelectionAfterChange() {
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

    private func entry(on day: Date) -> JournalEntry? {
        let calendar = Calendar.current
        return entries
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
    }

    /// Merge source entry into the destination day entry, using `preferring` as the latest
    /// field values for the source.
    private func merge(entryAt sourceIndex: Int, into destinationIndex: Int, preferring source: JournalEntry) {
        let destID = entries[destinationIndex].id
        var dest = entries[destinationIndex]
        for item in source.items where !item.isEmpty || source.items.count == 1 {
            if !dest.items.contains(where: { $0.id == item.id }) {
                dest.items.append(item)
            }
        }
        if dest.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            dest.title = source.title
        }
        dest.updatedAt = Date()
        if dest.items.isEmpty {
            dest.items = [JournalItem()]
        }

        let sourceID = entries[sourceIndex].id
        entries.removeAll { $0.id == sourceID }
        if let newDest = entries.firstIndex(where: { $0.id == destID }) {
            entries[newDest] = dest
        } else {
            entries.insert(dest, at: 0)
        }
        selection = .day(destID)
        persist()
        reconcileSelectionAfterChange()
    }

    // MARK: - Persistence

    private func ensureDirectories() {
        try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
    }

    private func load() {
        isReadOnlyDueToLoadFailure = false
        loadFailureMessage = nil
        didRestoreFromBackup = false

        guard fileManager.fileExists(atPath: databaseURL.path) else {
            // Try backup if primary missing.
            if let restored = loadSnapshot(from: backupURL) {
                entries = restored.entries.sorted { $0.date > $1.date }
                selection = entries.first.map { .day($0.id) }
                didRestoreFromBackup = true
                persist()
                return
            }
            entries = []
            return
        }

        do {
            let data = try Data(contentsOf: databaseURL)
            let snapshot = try decoder.decode(JournalSnapshot.self, from: data)
            entries = snapshot.entries.sorted { $0.date > $1.date }
            selection = entries.first.map { .day($0.id) }
        } catch {
            NSLog("Wick journal load failed: \(error.localizedDescription)")
            if let restored = loadSnapshot(from: backupURL) {
                entries = restored.entries.sorted { $0.date > $1.date }
                selection = entries.first.map { .day($0.id) }
                didRestoreFromBackup = true
                // Quarantine corrupt primary, then rewrite from backup.
                let quarantine = rootDirectory.appendingPathComponent(
                    "journal.corrupt-\(Int(Date().timeIntervalSince1970)).json"
                )
                try? fileManager.moveItem(at: databaseURL, to: quarantine)
                isReadOnlyDueToLoadFailure = false
                persist()
                return
            }

            // Do not clear on-disk file. Block writes.
            entries = []
            selection = nil
            isReadOnlyDueToLoadFailure = true
            loadFailureMessage = error.localizedDescription
        }
    }

    private func loadSnapshot(from url: URL) -> JournalSnapshot? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(JournalSnapshot.self, from: data)
        } catch {
            return nil
        }
    }

    private func persist() {
        guard !isReadOnlyDueToLoadFailure else {
            return
        }
        ensureDirectories()

        // Keep a single sidecar `.bak` of the last good on-disk snapshot before overwrite.
        // Rolling backups are throttled so typing does not flood the backups folder.
        if fileManager.fileExists(atPath: databaseURL.path),
           loadSnapshot(from: databaseURL) != nil
        {
            let shouldRoll: Bool
            if let last = lastRollingBackupAt {
                shouldRoll = Date().timeIntervalSince(last) >= 60 * 30
            } else {
                shouldRoll = true
            }
            copyDatabaseToSidecarBackup(includeRolling: shouldRoll)
        }

        let snapshot = JournalSnapshot(version: JournalSnapshot.currentVersion, entries: entries)
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: databaseURL, options: .atomic)
            lastPersistError = nil
        } catch {
            lastPersistError = error.localizedDescription
            NSLog("Wick journal persist failed: \(error.localizedDescription)")
        }
    }

    private func copyDatabaseToSidecarBackup(includeRolling: Bool) {
        guard fileManager.fileExists(atPath: databaseURL.path) else { return }
        try? fileManager.removeItem(at: backupURL)
        try? fileManager.copyItem(at: databaseURL, to: backupURL)

        guard includeRolling else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "journal-\(formatter.string(from: Date())).json"
        let rolling = backupsDirectory.appendingPathComponent(name)
        try? fileManager.copyItem(at: databaseURL, to: rolling)
        lastRollingBackupAt = Date()
        pruneRollingBackups()
    }

    private func pruneRollingBackups() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: backupsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        let jsons = files.filter { $0.pathExtension.lowercased() == "json" }
        let sorted = jsons.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return l > r
        }
        for obsolete in sorted.dropFirst(maxRollingBackups) {
            try? fileManager.removeItem(at: obsolete)
        }
    }

    private func breakReadOnlyIfImporting() {
        isReadOnlyDueToLoadFailure = false
        loadFailureMessage = nil
    }

    private func removeImageFile(_ filename: String) {
        try? fileManager.removeItem(at: imageURL(for: filename))
        JournalThumbnailCache.shared.invalidate(filename: filename)
    }

    private func sanitizedExtension(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        let allowed = Set(["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp"])
        if allowed.contains(trimmed) {
            return trimmed == "jpeg" ? "jpg" : trimmed
        }
        return "png"
    }

    private func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else {
            return nil
        }
        return rep.representation(using: .png, properties: [:])
    }

    private func findJournalJSON(under directory: URL) -> URL? {
        let fm = fileManager
        if let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for case let file as URL in enumerator {
                if file.lastPathComponent == "journal.json" {
                    return file
                }
            }
        }
        return nil
    }

    private func runZip(sourceDirectory: URL, destinationZip: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", sourceDirectory.path, destinationZip.path]
        let err = Pipe()
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw JournalStoreError.exportFailed(message)
        }
    }

    private func runUnzip(zipURL: URL, destinationDirectory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, destinationDirectory.path]
        let err = Pipe()
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw JournalStoreError.importFailed(message)
        }
    }
}

enum JournalStoreError: LocalizedError {
    case exportFailed(String)
    case importFailed(String)
    case importMissingJournalJSON

    var errorDescription: String? {
        switch self {
        case .exportFailed(let message):
            return message.isEmpty ? "Export failed" : message
        case .importFailed(let message):
            return message.isEmpty ? "Import failed" : message
        case .importMissingJournalJSON:
            return "Archive does not contain journal.json"
        }
    }
}
