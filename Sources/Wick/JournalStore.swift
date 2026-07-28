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
///     images/<uuid>.png|jpg|...
@MainActor
final class JournalStore: ObservableObject {
    static let shared = JournalStore()

    @Published private(set) var entries: [JournalEntry] = []
    @Published var selection: JournalSelection?
    @Published var selectedTagFilter: String?
    @Published var searchText: String = ""

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

    private init() {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        rootDirectory = support.appendingPathComponent("Wick/Journal", isDirectory: true)
        imagesDirectory = rootDirectory.appendingPathComponent("images", isDirectory: true)
        databaseURL = rootDirectory.appendingPathComponent("journal.json", isDirectory: false)

        ensureDirectories()
        load()
    }

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
                        entry.title + " " + item.tag + " " + item.body
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

    @discardableResult
    func createEntry(on date: Date = Date()) -> JournalEntry {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let entry = JournalEntry(date: day, items: [JournalItem()])
        entries.insert(entry, at: 0)
        // Creating always opens the full day editor.
        selectedTagFilter = nil
        searchText = ""
        selection = .day(entry.id)
        persist()
        return entry
    }

    /// Create today's entry if none exists for today, otherwise select it as a full day.
    @discardableResult
    func openOrCreateToday() -> JournalEntry {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        if let existing = entries
            .filter({ calendar.isDate($0.date, inSameDayAs: today) })
            .sorted(by: { $0.updatedAt > $1.updatedAt })
            .first
        {
            selection = .day(existing.id)
            return existing
        }
        return createEntry(on: today)
    }

    func updateEntry(_ entry: JournalEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else {
            return
        }
        var updated = entry
        if updated.items.isEmpty {
            updated.items = [JournalItem()]
        }
        updated.updatedAt = Date()
        entries[index] = updated
        persist()
        // If we're item-scoped and the focused item no longer matches the filter, resync selection.
        reconcileSelectionAfterChange()
    }

    func deleteEntry(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            return
        }
        let entry = entries[index]
        for filename in entry.allImageFilenames {
            try? fileManager.removeItem(at: imageURL(for: filename))
        }
        entries.remove(at: index)
        if selectedEntryID == id {
            selection = defaultSelection()
        }
        persist()
    }

    @discardableResult
    func addItem(to entryID: UUID) -> JournalItem? {
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
        guard let entryIndex = entries.firstIndex(where: { $0.id == entryID }) else {
            return
        }
        guard let itemIndex = entries[entryIndex].items.firstIndex(where: { $0.id == itemID }) else {
            return
        }

        let item = entries[entryIndex].items[itemIndex]
        for filename in item.imageFilenames {
            try? fileManager.removeItem(at: imageURL(for: filename))
        }

        entries[entryIndex].items.remove(at: itemIndex)
        if entries[entryIndex].items.isEmpty {
            // Remove the empty day journal entirely.
            let orphaned = entries[entryIndex]
            for filename in orphaned.allImageFilenames {
                try? fileManager.removeItem(at: imageURL(for: filename))
            }
            entries.remove(at: entryIndex)
            selection = defaultSelection()
        } else {
            entries[entryIndex].updatedAt = Date()
            if case .item(let ref) = selection, ref.itemID == itemID {
                selection = defaultSelection()
            } else if case .day(let id) = selection, id == entryID {
                // stay on day
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

    @discardableResult
    func addImage(
        from data: Data,
        to entryID: UUID,
        itemID: UUID,
        preferredExtension: String = "png"
    ) -> String? {
        guard let entryIndex = entries.firstIndex(where: { $0.id == entryID }),
              let itemIndex = entries[entryIndex].items.firstIndex(where: { $0.id == itemID })
        else {
            return nil
        }

        let ext = sanitizedExtension(preferredExtension)
        let filename = "\(UUID().uuidString).\(ext)"
        let destination = imageURL(for: filename)

        do {
            try data.write(to: destination, options: .atomic)
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
        guard let data = pngData(from: nsImage) else {
            return nil
        }
        return addImage(from: data, to: entryID, itemID: itemID, preferredExtension: "png")
    }

    func removeImage(filename: String, from entryID: UUID, itemID: UUID) {
        guard let entryIndex = entries.firstIndex(where: { $0.id == entryID }),
              let itemIndex = entries[entryIndex].items.firstIndex(where: { $0.id == itemID })
        else {
            return
        }
        entries[entryIndex].items[itemIndex].imageFilenames.removeAll { $0 == filename }
        entries[entryIndex].updatedAt = Date()
        try? fileManager.removeItem(at: imageURL(for: filename))
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

    // MARK: - Persistence

    private func ensureDirectories() {
        try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
    }

    private func load() {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
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
            entries = []
        }
    }

    private func persist() {
        ensureDirectories()
        let snapshot = JournalSnapshot(version: JournalSnapshot.currentVersion, entries: entries)
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: databaseURL, options: .atomic)
        } catch {
            NSLog("Wick journal persist failed: \(error.localizedDescription)")
        }
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
}
