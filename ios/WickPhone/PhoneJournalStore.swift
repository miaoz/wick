import Combine
import Foundation
import WickSync

/// iPhone journal store: local source of truth, same on-disk layout as macOS
/// (catalog.json + per-journal journal.json/.bak/images) so the sync engine
/// treats both platforms identically. Slimmer than the macOS store (no rolling
/// backups, no migration) but keeps the core protections: atomic writes,
/// sidecar .bak, version gate, and read-only-on-load-failure.
@MainActor
final class PhoneJournalStore: ObservableObject {
    static let shared = PhoneJournalStore()

    @Published private(set) var journals: [JournalInfo] = []
    @Published private(set) var activeJournalID: UUID?
    /// Kept sorted newest-first — DayListView renders the array as-is.
    @Published private(set) var entries: [JournalEntry] = []
    @Published private(set) var isReadOnlyDueToLoadFailure = false

    var activeJournal: JournalInfo? {
        guard let activeJournalID else { return nil }
        return journals.first { $0.id == activeJournalID }
    }

    private let fileManager = FileManager.default
    private let librariesRoot: URL
    private let catalogURL: URL

    private(set) var journalDirectory: URL
    private(set) var imagesDirectory: URL
    private(set) var databaseURL: URL
    private(set) var backupURL: URL

    private init() {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let root = support.appendingPathComponent("Wick/Journals", isDirectory: true)
        librariesRoot = root
        catalogURL = root.appendingPathComponent("catalog.json", isDirectory: false)
        let placeholder = root.appendingPathComponent("_pending", isDirectory: true)
        journalDirectory = placeholder
        imagesDirectory = placeholder.appendingPathComponent("images", isDirectory: true)
        databaseURL = placeholder.appendingPathComponent("journal.json", isDirectory: false)
        backupURL = placeholder.appendingPathComponent("journal.json.bak", isDirectory: false)
        bootstrap()
    }

    // MARK: - Bootstrap

    private func bootstrap() {
        try? fileManager.createDirectory(at: librariesRoot, withIntermediateDirectories: true)
        loadOrCreateCatalog()
        if let activeJournalID {
            bindPaths(for: activeJournalID)
            ensureDirectories()
            load()
        }
    }

    private func loadOrCreateCatalog() {
        if let data = try? Data(contentsOf: catalogURL),
           let catalog = try? JournalSyncEncoding.decoder.decode(JournalCatalogSnapshot.self, from: data),
           !catalog.journals.isEmpty {
            journals = catalog.journals.sorted { $0.createdAt < $1.createdAt }
            activeJournalID = catalog.journals.contains(where: { $0.id == catalog.activeJournalID })
                ? catalog.activeJournalID
                : journals.first?.id
        }
        if activeJournalID == nil {
            let info = JournalInfo(name: "日记")
            journals = [info]
            activeJournalID = info.id
            persistCatalog()
        }
    }

    private func persistCatalog() {
        guard let activeJournalID, !journals.isEmpty else { return }
        let catalog = JournalCatalogSnapshot(
            version: JournalCatalogSnapshot.currentVersion,
            activeJournalID: activeJournalID,
            journals: journals
        )
        guard let data = try? JournalSyncEncoding.encoder.encode(catalog) else { return }
        try? fileManager.createDirectory(at: librariesRoot, withIntermediateDirectories: true)
        try? data.write(to: catalogURL, options: .atomic)
    }

    private func bindPaths(for journalID: UUID) {
        let dir = librariesRoot.appendingPathComponent(journalID.uuidString, isDirectory: true)
        journalDirectory = dir
        imagesDirectory = dir.appendingPathComponent("images", isDirectory: true)
        databaseURL = dir.appendingPathComponent("journal.json", isDirectory: false)
        backupURL = dir.appendingPathComponent("journal.json.bak", isDirectory: false)
    }

    private func ensureDirectories() {
        try? fileManager.createDirectory(at: journalDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Journal switching / registration

    func switchToJournal(id: UUID) {
        guard id != activeJournalID, journals.contains(where: { $0.id == id }) else { return }
        flushPendingWrites()
        activeJournalID = id
        bindPaths(for: id)
        ensureDirectories()
        isReadOnlyDueToLoadFailure = false
        load()
        persistCatalog()
    }

    /// Registers a journal discovered on another device under the same id
    /// (see the macOS store for the full explanation). Does not switch.
    @discardableResult
    func registerRemoteJournal(id: UUID, name: String) -> JournalInfo {
        if let existing = journals.first(where: { $0.id == id }) {
            return existing
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let info = JournalInfo(
            id: id,
            name: uniquifiedJournalName(trimmed.isEmpty ? "日记" : trimmed)
        )
        seedJournalDirectory(for: id)
        journals.append(info)
        journals.sort { $0.createdAt < $1.createdAt }
        persistCatalog()
        return info
    }

    /// Creates a new empty journal and switches to it.
    @discardableResult
    func createJournal(name: String) -> JournalInfo {
        flushPendingWrites()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let info = JournalInfo(
            name: uniquifiedJournalName(trimmed.isEmpty ? "日记" : trimmed)
        )
        seedJournalDirectory(for: info.id)
        journals.append(info)
        journals.sort { $0.createdAt < $1.createdAt }
        activeJournalID = info.id
        bindPaths(for: info.id)
        isReadOnlyDueToLoadFailure = false
        entries = []
        persistCatalog()
        return info
    }

    func renameJournal(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = journals.firstIndex(where: { $0.id == id })
        else { return }
        journals[index].name = trimmed
        journals[index].updatedAt = Date()
        persistCatalog()
    }

    /// Deletes a journal and its on-disk folder. Refuses to delete the last one.
    @discardableResult
    func deleteJournal(id: UUID) -> Bool {
        guard journals.count > 1, journals.contains(where: { $0.id == id }) else { return false }
        let wasActive = id == activeJournalID
        if wasActive {
            flushPendingWrites()
        }
        let dir = librariesRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        try? fileManager.removeItem(at: dir)
        journals.removeAll { $0.id == id }
        if wasActive {
            let next = journals.sorted { $0.updatedAt > $1.updatedAt }.first ?? journals.first
            activeJournalID = next?.id
            if let nextID = activeJournalID {
                bindPaths(for: nextID)
                ensureDirectories()
                isReadOnlyDueToLoadFailure = false
                load()
            }
        }
        persistCatalog()
        return true
    }

    private func uniquifiedJournalName(_ base: String) -> String {
        let existing = Set(journals.map { $0.name.lowercased() })
        guard existing.contains(base.lowercased()) else { return base }
        var index = 2
        while existing.contains("\(base) \(index)".lowercased()) {
            index += 1
        }
        return "\(base) \(index)"
    }

    /// Collision check for sync-applied renames: the journal being renamed must
    /// not uniquify against itself.
    private func uniquifiedJournalName(_ base: String, excluding journalID: UUID) -> String {
        let existing = Set(journals.filter { $0.id != journalID }.map { $0.name.lowercased() })
        guard existing.contains(base.lowercased()) else { return base }
        var index = 2
        while existing.contains("\(base) \(index)".lowercased()) {
            index += 1
        }
        return "\(base) \(index)"
    }

    private func seedJournalDirectory(for id: UUID) {
        let dir = librariesRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        try? fileManager.createDirectory(
            at: dir.appendingPathComponent("images", isDirectory: true),
            withIntermediateDirectories: true
        )
        if let data = try? JournalSyncEncoding.encoder.encode(JournalSnapshot.empty) {
            try? data.write(
                to: dir.appendingPathComponent("journal.json", isDirectory: false),
                options: .atomic
            )
        }
    }

    // MARK: - Entries

    /// Opens today's entry if present, otherwise creates it.
    @discardableResult
    func openOrCreateToday() -> JournalEntry {
        let todayKey = JournalDayKey.make(from: Date())
        if let existing = entries.first(where: { $0.dayKey == todayKey }) {
            return existing
        }
        let entry = JournalEntry(date: Calendar.current.startOfDay(for: Date()))
        entries.insert(entry, at: 0)
        persist()
        return entry
    }

    /// Upserts an entry (editor save path). One entry per day key; bumps updatedAt.
    func updateEntry(_ entry: JournalEntry) {
        guard !isReadOnlyDueToLoadFailure else { return }
        var updated = entry
        updated.updatedAt = Date()
        if updated.items.isEmpty {
            updated.items = [JournalItem()]
        }
        if let index = entries.firstIndex(where: { $0.dayKey == updated.dayKey }) {
            entries[index] = updated
        } else {
            entries.insert(updated, at: 0)
        }
        persist()
    }

    func deleteEntry(dayKey: String) {
        guard !isReadOnlyDueToLoadFailure else { return }
        guard let index = entries.firstIndex(where: { $0.dayKey == dayKey }) else { return }
        for filename in entries[index].allImageFilenames {
            removeImageFile(filename)
        }
        entries.remove(at: index)
        persist()
    }

    // MARK: - Images

    func imageURL(for filename: String) -> URL {
        imagesDirectory.appendingPathComponent(filename)
    }

    private func removeImageFile(_ filename: String) {
        try? fileManager.removeItem(at: imageURL(for: filename))
    }

    // MARK: - Persistence

    func flushPendingWrites() {
        guard !isReadOnlyDueToLoadFailure else { return }
        persist()
    }

    private func load() {
        isReadOnlyDueToLoadFailure = false
        guard let data = try? Data(contentsOf: databaseURL) else {
            if let restored = loadSnapshot(from: backupURL) {
                entries = restored.entries.sorted { $0.date > $1.date }
                persist()
                return
            }
            entries = []
            return
        }
        do {
            let snapshot = try JournalSyncEncoding.decoder.decode(JournalSnapshot.self, from: data)
            // Version gate: never re-encode (and strip) newer formats.
            guard snapshot.version <= JournalSnapshot.currentVersion else {
                entries = []
                isReadOnlyDueToLoadFailure = true
                return
            }
            entries = snapshot.entries.sorted { $0.date > $1.date }
        } catch {
            if let restored = loadSnapshot(from: backupURL) {
                entries = restored.entries.sorted { $0.date > $1.date }
                let quarantine = journalDirectory.appendingPathComponent(
                    "journal.corrupt-\(Int(Date().timeIntervalSince1970)).json"
                )
                try? fileManager.moveItem(at: databaseURL, to: quarantine)
                persist()
                return
            }
            entries = []
            isReadOnlyDueToLoadFailure = true
        }
    }

    private func loadSnapshot(from url: URL) -> JournalSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JournalSyncEncoding.decoder.decode(JournalSnapshot.self, from: data),
              snapshot.version <= JournalSnapshot.currentVersion
        else { return nil }
        return snapshot
    }

    private func persist() {
        guard !isReadOnlyDueToLoadFailure else { return }
        ensureDirectories()
        if fileManager.fileExists(atPath: databaseURL.path),
           loadSnapshot(from: databaseURL) != nil
        {
            try? fileManager.removeItem(at: backupURL)
            try? fileManager.copyItem(at: databaseURL, to: backupURL)
        }
        let snapshot = JournalSnapshot(version: JournalSnapshot.currentVersion, entries: entries)
        guard let data = try? JournalSyncEncoding.encoder.encode(snapshot) else { return }
        try? data.write(to: databaseURL, options: .atomic)
    }
}

// MARK: - Sync engine bridge

extension PhoneJournalStore: JournalLocalSource {
    var syncJournalID: UUID? { activeJournalID }

    var syncJournalName: String { activeJournal?.name ?? "" }

    var syncIsWritable: Bool { !isReadOnlyDueToLoadFailure }

    func syncDaySnapshots() -> [String: JournalEntry] {
        var result: [String: JournalEntry] = [:]
        for entry in entries {
            if let existing = result[entry.dayKey], existing.updatedAt >= entry.updatedAt {
                continue
            }
            result[entry.dayKey] = entry
        }
        return result
    }

    func applySyncedEntry(_ entry: JournalEntry) {
        guard !isReadOnlyDueToLoadFailure else { return }
        var applied = entry
        if applied.items.isEmpty {
            applied.items = [JournalItem()]
        }
        if let index = entries.firstIndex(where: { $0.dayKey == applied.dayKey }) {
            entries[index] = applied
        } else {
            entries.append(applied)
        }
        // Applies arrive in ascending day order; the day list is newest-first.
        entries.sort { $0.date > $1.date }
        persist()
    }

    /// Renames the active journal to the remote manifest's name, returning the
    /// name actually applied (uniquified against OTHER local journals). The
    /// engine records the result as its rename baseline.
    @discardableResult
    func applySyncedJournalName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let activeJournalID,
              let index = journals.firstIndex(where: { $0.id == activeJournalID })
        else { return activeJournal?.name ?? name }
        let resolved = trimmed.isEmpty
            ? journals[index].name
            : uniquifiedJournalName(trimmed, excluding: activeJournalID)
        guard resolved != journals[index].name else { return resolved }
        journals[index].name = resolved
        journals[index].updatedAt = Date()
        persistCatalog()
        return resolved
    }

    func removeSyncedDay(dayKey: String) {
        guard !isReadOnlyDueToLoadFailure else { return }
        guard let index = entries.firstIndex(where: { $0.dayKey == dayKey }) else { return }
        for filename in entries[index].allImageFilenames {
            removeImageFile(filename)
        }
        entries.remove(at: index)
        persist()
    }

    func syncedImageFilenames() -> Set<String> {
        Set(entries.flatMap(\.allImageFilenames))
    }

    func syncedImageData(filename: String) -> Data? {
        guard isSafeSyncedImageFilename(filename) else { return nil }
        return try? Data(contentsOf: imageURL(for: filename))
    }

    func hasSyncedImage(filename: String) -> Bool {
        guard isSafeSyncedImageFilename(filename) else { return false }
        return fileManager.fileExists(atPath: imageURL(for: filename).path)
    }

    func storeSyncedImage(filename: String, data: Data) {
        guard !isReadOnlyDueToLoadFailure else { return }
        guard isSafeSyncedImageFilename(filename) else { return }
        try? data.write(to: imageURL(for: filename), options: .atomic)
    }

    /// Remote-supplied image names must stay plain relative filenames (no traversal).
    private func isSafeSyncedImageFilename(_ filename: String) -> Bool {
        !filename.isEmpty
            && !filename.contains("/")
            && !filename.contains("\\")
            && filename != "."
            && filename != ".."
    }
}
