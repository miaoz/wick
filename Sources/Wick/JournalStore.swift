import AppKit
import Foundation
import UniformTypeIdentifiers

/// File-backed journal store under Application Support.
/// Layout:
///   ~/Library/Application Support/Wick/Journal/
///     journal.json
///     images/<uuid>.png|jpg|...
@MainActor
final class JournalStore: ObservableObject {
    static let shared = JournalStore()

    @Published private(set) var entries: [JournalEntry] = []
    @Published var selectedEntryID: UUID?
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

    var filteredEntries: [JournalEntry] {
        entries
            .filter { entry in
                if let selectedTagFilter {
                    let needle = selectedTagFilter.lowercased()
                    guard entry.tags.contains(where: { $0.lowercased() == needle }) else {
                        return false
                    }
                }

                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else {
                    return true
                }

                let haystack = (
                    entry.title + " " + entry.body + " " + entry.tags.joined(separator: " ")
                ).lowercased()
                return haystack.contains(query.lowercased())
            }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date {
                    return lhs.date > rhs.date
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    /// All distinct tags, case-preserved by first occurrence, sorted alphabetically.
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

    var selectedEntry: JournalEntry? {
        guard let selectedEntryID else {
            return nil
        }
        return entries.first { $0.id == selectedEntryID }
    }

    // MARK: - Mutations

    @discardableResult
    func createEntry(on date: Date = Date()) -> JournalEntry {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let entry = JournalEntry(date: day)
        entries.insert(entry, at: 0)
        selectedEntryID = entry.id
        persist()
        return entry
    }

    /// Create today's entry if none exists for today, otherwise select the latest today entry.
    @discardableResult
    func openOrCreateToday() -> JournalEntry {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        if let existing = entries
            .filter({ calendar.isDate($0.date, inSameDayAs: today) })
            .sorted(by: { $0.updatedAt > $1.updatedAt })
            .first
        {
            selectedEntryID = existing.id
            return existing
        }
        return createEntry(on: today)
    }

    func updateEntry(_ entry: JournalEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else {
            return
        }
        var updated = entry
        updated.updatedAt = Date()
        entries[index] = updated
        persist()
    }

    func deleteEntry(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            return
        }
        let entry = entries[index]
        for filename in entry.imageFilenames {
            try? fileManager.removeItem(at: imageURL(for: filename))
        }
        entries.remove(at: index)
        if selectedEntryID == id {
            selectedEntryID = filteredEntries.first?.id
        }
        persist()
    }

    func selectEntry(id: UUID?) {
        selectedEntryID = id
    }

    func setTagFilter(_ tag: String?) {
        selectedTagFilter = tag
        if let selectedEntryID,
           !filteredEntries.contains(where: { $0.id == selectedEntryID })
        {
            self.selectedEntryID = filteredEntries.first?.id
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
    func addImage(from data: Data, to entryID: UUID, preferredExtension: String = "png") -> String? {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else {
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

        entries[index].imageFilenames.append(filename)
        entries[index].updatedAt = Date()
        persist()
        return filename
    }

    @discardableResult
    func addImage(from fileURL: URL, to entryID: UUID) -> String? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        let ext = fileURL.pathExtension.isEmpty ? "png" : fileURL.pathExtension
        return addImage(from: data, to: entryID, preferredExtension: ext)
    }

    @discardableResult
    func addImage(from nsImage: NSImage, to entryID: UUID) -> String? {
        guard let data = pngData(from: nsImage) else {
            return nil
        }
        return addImage(from: data, to: entryID, preferredExtension: "png")
    }

    func removeImage(filename: String, from entryID: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else {
            return
        }
        entries[index].imageFilenames.removeAll { $0 == filename }
        entries[index].updatedAt = Date()
        try? fileManager.removeItem(at: imageURL(for: filename))
        persist()
    }

    func pasteImageFromClipboard(to entryID: UUID) -> Bool {
        let pasteboard = NSPasteboard.general

        if let image = NSImage(pasteboard: pasteboard) {
            return addImage(from: image, to: entryID) != nil
        }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]) as? [URL] {
            var added = false
            for url in urls {
                if addImage(from: url, to: entryID) != nil {
                    added = true
                }
            }
            return added
        }

        return false
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
            selectedEntryID = entries.first?.id
        } catch {
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
            // Best-effort persistence; avoid crashing the menu-bar tool.
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
