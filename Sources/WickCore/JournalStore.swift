import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers
import WickSync

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

/// File-backed multi-journal store under Application Support.
///
/// Layout (multi-journal only — legacy single-journal is migrated once and discarded):
///   ~/Library/Application Support/Wick/Journals/
///     catalog.json
///     <journal-uuid>/
///       journal.json
///       journal.json.bak
///       backups/journal-*.json  (rolling)
///       images/<uuid>.png|jpg|...
@MainActor
final class JournalStore: ObservableObject {
    static let shared = JournalStore()

    // MARK: - Catalog (multi-journal)

    @Published private(set) var journals: [JournalInfo] = []
    @Published private(set) var activeJournalID: UUID?

    var activeJournal: JournalInfo? {
        guard let activeJournalID else { return nil }
        return journals.first { $0.id == activeJournalID }
    }

    // MARK: - Active journal content

    /// Not `@Published`: body-only autosave must not rebuild the journal window
    /// (P2). Structural mutations publish via other `@Published` fields
    /// (`selection`, `journals`) or an explicit `objectWillChange`. Sync
    /// observes `entriesDidMutate` instead of `$entries`.
    private(set) var entries: [JournalEntry] = []
    /// Fires after any in-memory entries change, including body-only persist.
    let entriesDidMutate = PassthroughSubject<Void, Never>()
    /// Fires after a remote day entry is successfully applied. Editors rebase
    /// their clean drafts onto the fresh store value when the day matches.
    let remoteEntryDidApply = PassthroughSubject<JournalRemoteApply, Never>()
    @Published var selection: JournalSelection?
    @Published var selectedTagFilter: String?
    @Published var searchText: String = ""

    /// When true, persistence is blocked so a failed load cannot wipe the on-disk file.
    @Published private(set) var isReadOnlyDueToLoadFailure = false
    @Published private(set) var loadFailureMessage: String?
    @Published private(set) var lastPersistError: String?
    @Published private(set) var didRestoreFromBackup = false
    /// Library-level protection: the catalog itself failed to load (corrupt or
    /// newer format). All catalog mutations (create/rename/reorder/delete/
    /// binding) are disabled until the user recovers via import/restore.
    @Published private(set) var isCatalogReadOnly = false
    @Published private(set) var catalogLoadMessage: String?

    #if DEBUG
    /// Test seam: force the next catalog persist to fail, deterministically
    /// exercising the AC-P1-04 rollback path.
    nonisolated(unsafe) static var failCatalogPersistOverride = false
    /// Test seam: force the final export replace to fail after the temp
    /// archive was built, exercising the AC-P1-07 atomic-replace path.
    nonisolated(unsafe) static var failExportReplaceOverride = false
    /// Test seam: fail the Nth image copy during import (1-based), exercising
    /// the DS-02 quarantine-rollback path.
    nonisolated(unsafe) static var failImageCopyAtIndex: Int?
    #endif
    /// Last explicit-recovery failure (start fresh / import), so UI callers
    /// never silently drop a recovery error.
    @Published private(set) var recoveryErrorMessage: String?

    func dismissRecoveryError() {
        recoveryErrorMessage = nil
    }

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

    /// Root of the multi-journal library (`…/Wick/Journals`).
    private let librariesRoot: URL
    /// Legacy single-journal path (`…/Wick/Journal`), only used for one-shot migration.
    private let legacyRoot: URL?
    private let catalogURL: URL

    // Active journal paths — recomputed on switch.
    private(set) var journalDirectory: URL
    private(set) var imagesDirectory: URL
    private(set) var databaseURL: URL
    private(set) var backupURL: URL
    private var backupsDirectory: URL

    private let maxRollingBackups = 5
    private var lastRollingBackupAt: Date?
    /// True while switching journals, so `persist()` cannot write the previous
    /// journal's in-memory snapshot into the newly bound folder.
    private var persistBlocked = false
    /// Serial disk writer so typing does not encode JSON on the main thread (P3).
    private let persistQueue = DispatchQueue(label: "com.miaoz.wick.journal-persist")
    private var persistGeneration: UInt64 = 0
    /// Test-observable count of full-snapshot persists (PF-01 regression guard:
    /// a batch apply must add exactly one).
    private(set) var persistCount = 0

    private struct JournalSessionSnapshot {
        let journalDirectory: URL
        let imagesDirectory: URL
        let databaseURL: URL
        let backupURL: URL
        let backupsDirectory: URL
        let entries: [JournalEntry]
        let selection: JournalSelection?
        let selectedTagFilter: String?
        let searchText: String
        let isReadOnlyDueToLoadFailure: Bool
        let loadFailureMessage: String?
        let lastPersistError: String?
        let didRestoreFromBackup: Bool
        let lastRollingBackupAt: Date?
    }

    // MARK: - Init

    /// Testing / custom multi-journal root.
    /// - Parameters:
    ///   - rootDirectory: Multi-journal library root (`catalog.json` + per-journal folders).
    ///   - legacyDirectory: Optional legacy single-journal folder to migrate once (tests).
    init(rootDirectory: URL, legacyDirectory: URL? = nil) {
        self.librariesRoot = rootDirectory
        self.legacyRoot = legacyDirectory
        self.catalogURL = rootDirectory.appendingPathComponent("catalog.json", isDirectory: false)

        // Placeholder paths; `bootstrapLibrary` sets real ones.
        let placeholder = rootDirectory.appendingPathComponent("_pending", isDirectory: true)
        self.journalDirectory = placeholder
        self.imagesDirectory = placeholder.appendingPathComponent("images", isDirectory: true)
        self.databaseURL = placeholder.appendingPathComponent("journal.json", isDirectory: false)
        self.backupURL = placeholder.appendingPathComponent("journal.json.bak", isDirectory: false)
        self.backupsDirectory = placeholder.appendingPathComponent("backups", isDirectory: true)

        bootstrapLibrary()
    }

    /// Shared app store under Application Support.
    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let wickRoot = support.appendingPathComponent("Wick", isDirectory: true)
        let libraries = wickRoot.appendingPathComponent("Journals", isDirectory: true)
        let legacy = wickRoot.appendingPathComponent("Journal", isDirectory: true)

        self.librariesRoot = libraries
        self.legacyRoot = legacy
        self.catalogURL = libraries.appendingPathComponent("catalog.json", isDirectory: false)

        let placeholder = libraries.appendingPathComponent("_pending", isDirectory: true)
        self.journalDirectory = placeholder
        self.imagesDirectory = placeholder.appendingPathComponent("images", isDirectory: true)
        self.databaseURL = placeholder.appendingPathComponent("journal.json", isDirectory: false)
        self.backupURL = placeholder.appendingPathComponent("journal.json.bak", isDirectory: false)
        self.backupsDirectory = placeholder.appendingPathComponent("backups", isDirectory: true)

        bootstrapLibrary()
    }

    /// Multi-journal library root (contains `catalog.json` and per-journal folders).
    var dataDirectoryURL: URL { librariesRoot }

    /// Directory of the currently active journal.
    var activeJournalDirectoryURL: URL { journalDirectory }

    // MARK: - Multi-journal API

    /// Switch the active journal. Flushes editor drafts + the current store first.
    func switchToJournal(id: UUID) {
        guard !isCatalogReadOnly else { return }
        guard id != activeJournalID else { return }
        guard journals.contains(where: { $0.id == id }) else { return }

        flushActiveJournalSession()
        // Block persist until the new journal is loaded so a stray write
        // cannot dump the previous journal's in-memory entries into the
        // newly bound directory (and then sync them up as that journal).
        persistBlocked = true
        activeJournalID = id
        bindPaths(for: id)
        resetSessionState()
        loadActiveJournalContent()
        persistBlocked = false
        persistCatalog()
        notifyActiveJournalChanged()
    }

    /// Creates a new empty journal, switches to it, and returns its metadata.
    @discardableResult
    func createJournal(name: String) -> JournalInfo {
        guard !isCatalogReadOnly else { return activeJournal ?? JournalInfo(name: "") }
        flushActiveJournalSession()

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmed.isEmpty ? defaultJournalName() : trimmed
        let info = JournalInfo(name: resolvedName)
        let dir = librariesRoot.appendingPathComponent(info.id.uuidString, isDirectory: true)

        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(
            at: dir.appendingPathComponent("images", isDirectory: true),
            withIntermediateDirectories: true
        )
        try? fileManager.createDirectory(
            at: dir.appendingPathComponent("backups", isDirectory: true),
            withIntermediateDirectories: true
        )

        // Seed an empty snapshot on disk so load has a primary file.
        let empty = JournalSnapshot.empty
        if let data = try? encoder.encode(empty) {
            try? data.write(
                to: dir.appendingPathComponent("journal.json", isDirectory: false),
                options: .atomic
            )
        }

        journals.append(info)
        activeJournalID = info.id
        bindPaths(for: info.id)
        resetSessionState()
        entries = []
        selection = nil
        isReadOnlyDueToLoadFailure = false
        loadFailureMessage = nil
        didRestoreFromBackup = false
        lastPersistError = nil
        JournalThumbnailCache.shared.removeAll()
        persistCatalog()
        notifyActiveJournalChanged()
        return info
    }

    /// Reorders journals in the catalog (e.g. from drag-and-drop) and persists the new order.
    func moveJournal(from source: IndexSet, to destination: Int) {
        guard !isCatalogReadOnly else { return }
        journals.move(fromOffsets: source, toOffset: destination)
        persistCatalog()
    }

    /// Binds (or clears) the exchange account for one journal. Secrets are
    /// not stored here — only the venue + display label.
    func setExchangeBinding(_ binding: JournalExchangeBinding?, for id: UUID) {
        guard !isCatalogReadOnly else { return }
        guard let index = journals.firstIndex(where: { $0.id == id }) else { return }
        journals[index].exchangeBinding = binding
        journals[index].updatedAt = Date()
        persistCatalog()
        objectWillChange.send()
    }

    /// Renames a journal in the catalog.
    func renameJournal(id: UUID, to name: String) {
        guard !isCatalogReadOnly else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = journals.firstIndex(where: { $0.id == id }) else { return }

        journals[index].name = trimmed
        journals[index].updatedAt = Date()
        persistCatalog()
        if id == activeJournalID {
            notifyActiveJournalChanged()
        }
    }

    /// Deletes a journal and its on-disk folder. Refuses to delete the last journal.
    @discardableResult
    func deleteJournal(id: UUID) -> Bool {
        guard !isCatalogReadOnly else { return false }
        guard journals.count > 1 else { return false }
        guard journals.contains(where: { $0.id == id }) else { return false }

        let wasActive = id == activeJournalID
        if wasActive {
            flushActiveJournalSession()
        }

        let originalJournals = journals
        let originalActive = activeJournalID
        let originalSession = captureJournalSession()
        let originalJournalIDs = Set(journals.map(\.id))
        let dir = librariesRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        let quarantine = librariesRoot
            .appendingPathComponent(".WickJournalQuarantine-\(UUID().uuidString)", isDirectory: true)
        let movedAside = fileManager.fileExists(atPath: dir.path)
        if movedAside {
            do {
                try fileManager.moveItem(at: dir, to: quarantine)
            } catch {
                return false
            }
        }

        journals.removeAll { $0.id == id }

        if wasActive {
            let next = journals.sorted { $0.updatedAt > $1.updatedAt }.first
                ?? journals.first
            persistBlocked = true
            activeJournalID = next?.id
            if let nextID = activeJournalID {
                bindPaths(for: nextID)
                resetSessionState()
                loadActiveJournalContent()
            }
            persistBlocked = false
        }

        guard persistCatalog() else {
            rollbackJournalDeletion(
                originalJournals: originalJournals,
                originalActiveJournalID: originalActive,
                originalSession: originalSession,
                originalJournalIDs: originalJournalIDs,
                quarantine: quarantine,
                originalDirectory: dir,
                movedAside: movedAside
            )
            return false
        }
        if movedAside {
            try? fileManager.removeItem(at: quarantine)
        }
        notifyActiveJournalChanged()
        return true
    }

    /// Result of applying a peer's deletion of a journal.
    enum RemoteJournalDeleteResult: Equatable {
        case deleted
        case notFound
        case refusedReadOnly
        case ioFailure
    }

    /// Applies a deletion that originated on ANOTHER device. Unlike
    /// `deleteJournal` (the user-facing API that must keep at least one
    /// journal), this deletes even the last journal and seeds a fresh,
    /// pure-local default so the app always has an active book. The new
    /// default must not inherit the deleted journal's Dropbox state or
    /// exchange binding (a new UUID means neither exists).
    ///
    /// The folder is moved aside on the same volume first; if the catalog write
    /// fails, the folder and in-memory catalog are rolled back and `.ioFailure`
    /// is returned so the coordinator does NOT acknowledge the remote tombstone
    /// (AC-P1-04).
    @discardableResult
    func deleteJournalFromRemote(id: UUID) -> RemoteJournalDeleteResult {
        guard !isCatalogReadOnly else { return .refusedReadOnly }
        guard journals.contains(where: { $0.id == id }) else { return .notFound }

        let wasActive = id == activeJournalID
        if wasActive {
            flushActiveJournalSession()
        }

        let originalJournals = journals
        let originalActive = activeJournalID
        let originalSession = captureJournalSession()
        let originalJournalIDs = Set(journals.map(\.id))
        let dir = librariesRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        let quarantine = librariesRoot
            .appendingPathComponent(".WickJournalQuarantine-\(UUID().uuidString)", isDirectory: true)
        let dirMovedAside = fileManager.fileExists(atPath: dir.path)
        if dirMovedAside {
            do {
                try fileManager.moveItem(at: dir, to: quarantine)
            } catch {
                return .ioFailure
            }
        }

        journals.removeAll { $0.id == id }

        if journals.isEmpty {
            // Last journal deleted by a peer: seed a fresh default and switch.
            let info = makeDefaultJournal()
            journals = [info]
            activeJournalID = info.id
            if let newID = activeJournalID {
                bindPaths(for: newID)
                resetSessionState()
                loadActiveJournalContent()
            }
        } else if wasActive {
            let next = journals.sorted { $0.updatedAt > $1.updatedAt }.first
                ?? journals.first
            persistBlocked = true
            activeJournalID = next?.id
            if let nextID = activeJournalID {
                bindPaths(for: nextID)
                resetSessionState()
                loadActiveJournalContent()
            }
            persistBlocked = false
        }

        // Only a durable catalog commit makes the deletion real.
        guard persistCatalog() else {
            rollbackJournalDeletion(
                originalJournals: originalJournals,
                originalActiveJournalID: originalActive,
                originalSession: originalSession,
                originalJournalIDs: originalJournalIDs,
                quarantine: quarantine,
                originalDirectory: dir,
                movedAside: dirMovedAside
            )
            return .ioFailure
        }

        if dirMovedAside {
            try? fileManager.removeItem(at: quarantine)
        }
        notifyActiveJournalChanged()
        return .deleted
    }

    /// Suggested default name for a newly created journal (language-aware).
    func defaultJournalName(for language: AppLanguage? = nil) -> String {
        let language = language ?? AppSettings.shared.language
        let base = L10n.string(.journalLibraryDefaultName, language: language)
        return uniquifiedJournalName(base)
    }

    private func uniquifiedJournalName(_ base: String) -> String {
        let existing = Set(journals.map { $0.name.lowercased() })
        if !existing.contains(base.lowercased()) {
            return base
        }
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
        if !existing.contains(base.lowercased()) {
            return base
        }
        var index = 2
        while existing.contains("\(base) \(index)".lowercased()) {
            index += 1
        }
        return "\(base) \(index)"
    }

    /// Adopts a journal discovered on another sync device: registers it locally
    /// under the SAME id (the remote folder's identity) and switches to it.
    /// The sync engine then pulls its contents down.
    @discardableResult
    func adoptRemoteJournal(id: UUID, name: String) -> JournalInfo {
        let info = registerRemoteJournal(id: id, name: name)
        if activeJournalID != info.id {
            switchToJournal(id: info.id)
        }
        return info
    }

    /// Registers a remote journal locally under its remote id WITHOUT switching
    /// to it (the auto-import path). The local snapshot starts empty on
    /// purpose — the engine applies remote days onto it, never the reverse.
    /// Callers must reset the journal's sync state first: a state file left
    /// from a deleted past life would make "empty local" look like "deleted
    /// everywhere" and tombstone the remote content.
    @discardableResult
    func registerRemoteJournal(id: UUID, name: String) -> JournalInfo {
        guard !isCatalogReadOnly else { return JournalInfo(name: name) }
        if let existing = journals.first(where: { $0.id == id }) {
            return existing
        }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let info = JournalInfo(
            id: id,
            name: uniquifiedJournalName(trimmed.isEmpty ? defaultJournalName() : trimmed)
        )
        let dir = librariesRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(
            at: dir.appendingPathComponent("images", isDirectory: true),
            withIntermediateDirectories: true
        )
        try? fileManager.createDirectory(
            at: dir.appendingPathComponent("backups", isDirectory: true),
            withIntermediateDirectories: true
        )
        // Seed an empty snapshot so load has a primary file.
        if let data = try? encoder.encode(JournalSnapshot.empty) {
            try? data.write(
                to: dir.appendingPathComponent("journal.json", isDirectory: false),
                options: .atomic
            )
        }

        journals.append(info)
        persistCatalog()
        return info
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

    private static func applyPositionSkeletons(
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

    private func loadEntriesFromDisk(journalID: UUID) -> JournalEntriesLoadResult {
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
    private func persistEntries(_ entries: [JournalEntry], journalID: UUID) throws {
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
    private static func hasContentChange(from old: JournalEntry, to new: JournalEntry) -> Bool {
        old.date != new.date
            || old.title != new.title
            || old.items != new.items
    }

    /// True when the change should rebuild the journal UI (list, tags, seals).
    /// Body-only typing stays in drafts + disk and must not fan out (P2).
    private static func isStructuralChange(from old: JournalEntry, to new: JournalEntry) -> Bool {
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

    // MARK: - Images

    /// The only image URL constructor in the app. Returns nil for any name
    /// that is not a safe single-level filename or that would resolve outside
    /// the images directory (a second boundary past model-level validation).
    func imageURL(for filename: String) -> URL? {
        guard JournalImageFilename.isValid(filename) else { return nil }
        let url = imagesDirectory.appendingPathComponent(filename)
        let standard = url.standardizedFileURL
        let imagesStandard = imagesDirectory.standardizedFileURL
        guard standard.path.hasPrefix(imagesStandard.path + "/") else { return nil }
        return url
    }

    func loadNSImage(filename: String) -> NSImage? {
        guard let url = imageURL(for: filename) else { return nil }
        return NSImage(contentsOf: url)
    }

    func loadThumbnail(filename: String, maxPixel: CGFloat = 320) -> NSImage? {
        guard let url = imageURL(for: filename) else { return nil }
        return JournalThumbnailCache.shared.thumbnail(
            filename: filename,
            url: url,
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
        guard let destination = imageURL(for: filename) else { return nil }

        do {
            try payload.write(to: destination, options: .atomic)
        } catch {
            return nil
        }

        entries[entryIndex].items[itemIndex].imageFilenames.append(filename)
        entries[entryIndex].updatedAt = Date()
        persist()
        touchActiveJournalMetadata()
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
        touchActiveJournalMetadata()
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
        NSWorkspace.shared.open(librariesRoot)
    }

    /// Exports the active journal's `journal.json` + `images/` into a zip at
    /// `destinationURL`. The export is consistent: editor drafts are flushed
    /// first, the frozen in-memory snapshot is encoded (never the possibly
    /// stale main file), and the destination is only replaced after the new
    /// archive is fully built.
    func exportArchive(to destinationURL: URL) async throws {
        // A load-failure read-only store has already emptied `entries`; encoding
        // that empty snapshot would atomically overwrite a previous good export.
        // "No writes while read-only" must cover the export artifact too.
        guard !isReadOnlyDueToLoadFailure else {
            throw JournalStoreError.exportFailed(
                "The journal is under read-only protection after a load failure; export is disabled."
            )
        }

        // 1. Unified flush protocol: editors commit drafts, then the store's
        // writer drains so the in-memory snapshot below is the final state.
        flushActiveJournalSession()

        // 2. Freeze identity + content on the main actor, then hand the heavy
        // encode/copy/ditto/replace to a background task (UI-06) so a large
        // journal does not freeze the menu-bar panel.
        let snapshot = JournalSnapshot(version: JournalSnapshot.currentVersion, entries: entries)
        let frozenImagesDirectory = imagesDirectory
        try await Self.performExport(
            snapshot: snapshot,
            imagesDirectory: frozenImagesDirectory,
            destinationURL: destinationURL
        )
    }

    /// Builds the export archive off the main thread: encode the frozen
    /// snapshot, copy images, run ditto, and atomically replace the target.
    private nonisolated static func performExport(
        snapshot: JournalSnapshot,
        imagesDirectory: URL,
        destinationURL: URL
    ) async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("WickExport-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempRoot) }
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let payloadDir = tempRoot.appendingPathComponent("Wick-Journal", isDirectory: true)
        try fileManager.createDirectory(at: payloadDir, withIntermediateDirectories: true)

        // 3. Encode the frozen in-memory snapshot into the temp payload.
        let data = try JournalSyncEncoding.encoder.encode(snapshot)
        try data.write(to: payloadDir.appendingPathComponent("journal.json"), options: .atomic)

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

        // 4. Build the archive to a temp file in the DESTINATION directory
        // (same volume), then atomically replace the target. A failed build or
        // a failed replace leaves the previous archive intact (AC-P1-07).
        let destDir = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)
        let tempZip = destDir.appendingPathComponent(".Wick-export-\(UUID().uuidString).tmp", isDirectory: false)
        defer { try? fileManager.removeItem(at: tempZip) }
        try runZip(sourceDirectory: payloadDir, destinationZip: tempZip)
        try replaceDestination(destinationURL, with: tempZip, fileManager: fileManager)
    }

    /// Atomic swap of the freshly built archive over the target. Wrapped so a
    /// deterministic failure can be injected for tests.
    private nonisolated static func replaceDestination(_ destinationURL: URL, with tempZip: URL, fileManager: FileManager) throws {
        #if DEBUG
        if Self.failExportReplaceOverride {
            throw CocoaError(.fileWriteUnknown)
        }
        #endif
        _ = try fileManager.replaceItemAt(destinationURL, withItemAt: tempZip)
    }

    /// Imports a previously exported zip or a bare `journal.json` into the
    /// **active** journal, or (when the catalog itself is read-only) recovers
    /// the library with the imported content as its first journal.
    ///
    /// The input is fully validated BEFORE any read-only flag or file is
    /// touched; an invalid archive leaves the store and on-disk files exactly
    /// as they were (AC-P1-01). The unzip + decode run off the main thread so
    /// a large archive does not freeze the menu-bar panel (UI-06).
    func importArchive(from sourceURL: URL) async throws {
        // 1. Validate the input completely in a temp area — no state change.
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("WickImport-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempRoot) }
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let (snapshot, importedImages) = try await Self.prepareImport(
            from: sourceURL,
            tempRoot: tempRoot
        )

        // 2. If the LIBRARY is read-only, recover a real catalog first; only a
        //    durable catalog write lets the import proceed.
        if isCatalogReadOnly {
            try recoverCatalogForImport()
        }
        guard !isCatalogReadOnly else {
            throw JournalStoreError.catalogRecoveryFailed
        }

        // 3. Now the active journal is real and writable; clear content-level
        //    read-only and replace its data.
        isReadOnlyDueToLoadFailure = false
        loadFailureMessage = nil

        // Backup current store before replacing.
        if fileManager.fileExists(atPath: databaseURL.path) {
            Self.copyDatabaseToSidecarBackup(
                databaseURL: databaseURL,
                backupURL: backupURL,
                backupsDirectory: backupsDirectory,
                includeRolling: true,
                maxRollingBackups: maxRollingBackups
            )
            lastRollingBackupAt = Date()
        }

        // Replace images directory transactionally (DS-02): move the existing
        // images aside into a same-volume quarantine, copy the imported images
        // into a fresh directory, and only delete the quarantine once every
        // copy succeeded. If a copy fails, the quarantine is moved back, so an
        // interrupted import never loses the pre-existing images.
        var imagesQuarantine: URL?
        var imagesMovedAside = false
        if fileManager.fileExists(atPath: imagesDirectory.path) {
            let quarantine = journalDirectory.appendingPathComponent(
                ".WickImagesQuarantine-\(UUID().uuidString)", isDirectory: true
            )
            do {
                try fileManager.moveItem(at: imagesDirectory, to: quarantine)
                imagesQuarantine = quarantine
                imagesMovedAside = true
            } catch {
                // Can't move the old images aside; keep them and merge the
                // imported files instead of deleting anything.
                imagesQuarantine = nil
            }
        }

        do {
            try fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            if let importedImages {
                let files = try fileManager.contentsOfDirectory(
                    at: importedImages,
                    includingPropertiesForKeys: nil
                )
                var copied = 0
                for file in files where !file.hasDirectoryPath {
                    #if DEBUG
                    if copied + 1 == Self.failImageCopyAtIndex {
                        throw CocoaError(.fileWriteUnknown)
                    }
                    #endif
                    let dest = imagesDirectory.appendingPathComponent(file.lastPathComponent)
                    try fileManager.copyItem(at: file, to: dest)
                    copied += 1
                }
            }
        } catch {
            if imagesMovedAside {
                try? fileManager.removeItem(at: imagesDirectory)
                if let imagesQuarantine {
                    try? fileManager.moveItem(at: imagesQuarantine, to: imagesDirectory)
                }
            }
            throw error
        }

        if let imagesQuarantine {
            try? fileManager.removeItem(at: imagesQuarantine)
        }

        entries = snapshot.entries.sorted { $0.date > $1.date }
        selection = entries.first.map { .day($0.id) }
        isReadOnlyDueToLoadFailure = false
        loadFailureMessage = nil
        didRestoreFromBackup = false
        lastPersistError = nil
        JournalThumbnailCache.shared.removeAll()
        persist()
        touchActiveJournalMetadata()
    }

    /// Unzips (if needed), decodes and validates the import payload on a
    /// background thread. Throws before any store state is touched (AC-P1-01).
    private nonisolated static func prepareImport(
        from sourceURL: URL,
        tempRoot: URL
    ) async throws -> (snapshot: JournalSnapshot, importedImages: URL?) {
        let fileManager = FileManager.default
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
        let snapshot = try JournalSyncEncoding.decoder.decode(JournalSnapshot.self, from: data)
        guard snapshot.version <= JournalSnapshot.currentVersion else {
            throw JournalStoreError.unsupportedSnapshotVersion(snapshot.version)
        }
        return (snapshot, importedImages)
    }

    /// Forces a synchronous write of the in-memory snapshot (used on quit).
    func flushPendingWrites() {
        guard !isReadOnlyDueToLoadFailure else { return }
        persist()
        persistQueue.sync {}
    }

    /// Ask editors to commit drafts, then persist the active journal.
    private func flushActiveJournalSession() {
        NotificationCenter.default.post(name: .wickWillFlushJournalDrafts, object: nil)
        flushPendingWrites()
    }

    /// Explicit user recovery. When the LIBRARY (catalog) is read-only, it
    /// quarantines the corrupt/newer-format catalog, seeds a fresh default
    /// journal in a REAL directory, writes the catalog, and only then exits
    /// read-only — throwing and rolling back if any step fails. When only the
    /// active journal's content failed to load, it clears that content-level
    /// read-only after moving the bad file aside.
    func abandonCorruptDatabaseAndStartFresh() throws {
        recoveryErrorMessage = nil
        if isCatalogReadOnly {
            do {
                try recoverCatalogFromScratch()
            } catch {
                recoveryErrorMessage = error.localizedDescription
                throw error
            }
            return
        }
        if fileManager.fileExists(atPath: databaseURL.path) {
            let quarantine = journalDirectory.appendingPathComponent(
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

    /// Rebuilds a healthy library after the user chooses to start fresh:
    /// quarantine the bad catalog, create a new UUID with real directories,
    /// write the catalog, and only leave read-only once the write succeeds.
    private func recoverCatalogFromScratch() throws {
        let originalJournals = journals
        let originalActive = activeJournalID
        let originalSession = captureJournalSession()
        let quarantine = librariesRoot.appendingPathComponent(
            "catalog.corrupt-\(UUID().uuidString).json",
            isDirectory: false
        )
        if fileManager.fileExists(atPath: catalogURL.path) {
            try fileManager.moveItem(at: catalogURL, to: quarantine)
        }
        isCatalogReadOnly = false
        let info = JournalInfo(name: defaultJournalName())
        let dir = librariesRoot.appendingPathComponent(info.id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: dir.appendingPathComponent("images", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: dir.appendingPathComponent("backups", isDirectory: true),
            withIntermediateDirectories: true
        )
        journals = [info]
        activeJournalID = info.id
        bindPaths(for: info.id)
        resetSessionState()
        entries = []
        guard persistCatalog() else {
            // Roll back every in-memory and on-disk session component.
            try? fileManager.moveItem(at: quarantine, to: catalogURL)
            try? fileManager.removeItem(at: dir)
            isCatalogReadOnly = true
            journals = originalJournals
            activeJournalID = originalActive
            restoreJournalSession(originalSession)
            throw JournalStoreError.catalogRecoveryFailed
        }
        notifyActiveJournalChanged()
    }

    /// Catalog recovery used by import: same as `recoverCatalogFromScratch`,
    /// so the imported content lands in a real journal (never `_pending`).
    private func recoverCatalogForImport() throws {
        try recoverCatalogFromScratch()
    }

    // MARK: - Bootstrap / migration

    private func bootstrapLibrary() {
        try? fileManager.createDirectory(at: librariesRoot, withIntermediateDirectories: true)
        migrateLegacySingleJournalIfNeeded()
        loadOrCreateCatalog()
        migrateJournalSnapshotsToCurrentVersion()
        guard let activeID = activeJournalID else { return }
        bindPaths(for: activeID)
        ensureDirectories()
        loadActiveJournalContent()
    }

    /// One-shot migration: move `…/Wick/Journal` → `…/Wick/Journals/<uuid>/` and write catalog.
    /// After this, the legacy path is never read again.
    private func migrateLegacySingleJournalIfNeeded() {
        guard let legacyRoot else { return }
        guard !fileManager.fileExists(atPath: catalogURL.path) else { return }
        guard fileManager.fileExists(atPath: legacyRoot.path) else { return }

        // Only migrate if the legacy folder looks like a journal store.
        let legacyDB = legacyRoot.appendingPathComponent("journal.json", isDirectory: false)
        let legacyBak = legacyRoot.appendingPathComponent("journal.json.bak", isDirectory: false)
        let legacyImages = legacyRoot.appendingPathComponent("images", isDirectory: true)
        let hasLegacyContent = fileManager.fileExists(atPath: legacyDB.path)
            || fileManager.fileExists(atPath: legacyBak.path)
            || fileManager.fileExists(atPath: legacyImages.path)

        guard hasLegacyContent else {
            // Empty leftover folder — quarantine it so we never re-scan.
            quarantineLegacyRoot(legacyRoot)
            return
        }

        let journalID = UUID()
        let destination = librariesRoot.appendingPathComponent(journalID.uuidString, isDirectory: true)

        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: legacyRoot, to: destination)

            let info = JournalInfo(
                id: journalID,
                name: defaultMigratedJournalName()
            )
            let catalog = JournalCatalogSnapshot(
                version: JournalCatalogSnapshot.currentVersion,
                activeJournalID: journalID,
                journals: [info]
            )
            let data = try encoder.encode(catalog)
            try data.write(to: catalogURL, options: .atomic)
            NSLog("Wick: migrated legacy single journal to multi-journal layout (\(journalID.uuidString))")
        } catch {
            NSLog("Wick: legacy journal migration failed: \(error.localizedDescription)")
            // Best-effort: if move succeeded but catalog write failed, try to leave data recoverable.
        }
    }

    /// Rewrites every supported pre-v2 journal before normal loading. The
    /// standard writer first copies the original primary to `journal.json.bak`
    /// and then atomically writes UUID-only entries, so the hard cut remains
    /// recoverable if the process is interrupted.
    private func migrateJournalSnapshotsToCurrentVersion() {
        guard !isCatalogReadOnly else { return }
        for journal in journals {
            let url = librariesRoot
                .appendingPathComponent(journal.id.uuidString, isDirectory: true)
                .appendingPathComponent("journal.json", isDirectory: false)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            do {
                let data = try Data(contentsOf: url)
                let snapshot = try decoder.decode(JournalSnapshot.self, from: data)
                guard snapshot.version < JournalSnapshot.currentVersion else { continue }
                try persistEntries(snapshot.entries, journalID: journal.id)
            } catch {
                // Normal load applies the existing corrupt/future-version
                // read-only protections if this is the active journal.
                NSLog("Wick journal v2 migration skipped for %@: %@", journal.id.uuidString, error.localizedDescription)
            }
        }
    }

    private func quarantineLegacyRoot(_ legacyRoot: URL) {
        let stamp = Int(Date().timeIntervalSince1970)
        let quarantine = legacyRoot
            .deletingLastPathComponent()
            .appendingPathComponent("Journal.migrated-\(stamp)", isDirectory: true)
        try? fileManager.moveItem(at: legacyRoot, to: quarantine)
    }

    private func defaultMigratedJournalName() -> String {
        L10n.string(.journalLibraryDefaultName, language: AppSettings.shared.language)
    }

    private func loadOrCreateCatalog() {
        switch loadCatalog() {
        case .missing:
            // The ONLY path that first-creates a library is an absent catalog.
            seedDefaultJournal()
        case .loaded(let catalog):
            applyCatalog(catalog, restoredFromBackup: false)
        case .restoredFromBackup(let catalog):
            applyCatalog(catalog, restoredFromBackup: true)
        case .corrupt(let error):
            enterCatalogReadOnly(error)
        case .unsupportedVersion(let version):
            enterCatalogReadOnly(JournalCatalogCodec.LoadError.unsupportedVersion(version))
        }
    }

    private func applyCatalog(_ catalog: JournalCatalogSnapshot, restoredFromBackup: Bool) {
        isCatalogReadOnly = false
        catalogLoadMessage = nil
        didRestoreFromBackup = restoredFromBackup
        journals = catalog.journals
        if journals.contains(where: { $0.id == catalog.activeJournalID }) {
            activeJournalID = catalog.activeJournalID
        } else {
            activeJournalID = journals.first?.id
        }
        // Ensure every catalog entry has a directory (valid catalog only).
        for info in journals {
            let dir = librariesRoot.appendingPathComponent(info.id.uuidString, isDirectory: true)
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if activeJournalID == nil {
            seedDefaultJournal()
        } else if activeJournalID != catalog.activeJournalID || restoredFromBackup {
            persistCatalog()
        }
    }

    private func enterCatalogReadOnly(_ error: Error) {
        isCatalogReadOnly = true
        catalogLoadMessage = loadFailureMessage(for: error)
        journals = []
        activeJournalID = nil
        entries = []
        selection = nil
        isReadOnlyDueToLoadFailure = true
        loadFailureMessage = catalogLoadMessage
        didRestoreFromBackup = false
        NSLog("Wick catalog load failed: \(error.localizedDescription)")
    }

    private func loadCatalog() -> CatalogLoadResult {
        let backupURL = Self.catalogBackupURL(in: librariesRoot)
        switch JournalCatalogLoader.load(
            primaryURL: catalogURL,
            backupURL: backupURL,
            currentVersion: JournalCatalogSnapshot.currentVersion
        ) {
        case .missing:
            return .missing
        case .loaded(let catalog):
            return .loaded(catalog)
        case .restoredFromBackup(let catalog):
            // Quarantine a corrupt primary so the damaged file is kept;
            // nothing to quarantine when the primary was simply absent.
            if fileManager.fileExists(atPath: catalogURL.path) {
                quarantineCorruptCatalog()
            }
            return .restoredFromBackup(catalog)
        case .corrupt:
            return .corrupt(JournalCatalogCodec.LoadError.corrupt)
        case .unsupportedVersion(let version):
            return .unsupportedVersion(version)
        }
    }

    private func quarantineCorruptCatalog() {
        let quarantine = librariesRoot.appendingPathComponent(
            "catalog.corrupt-\(Int(Date().timeIntervalSince1970)).json",
            isDirectory: false
        )
        try? fileManager.moveItem(at: catalogURL, to: quarantine)
    }

    private static func catalogBackupURL(in librariesRoot: URL) -> URL {
        librariesRoot.appendingPathComponent("catalog.json.bak", isDirectory: false)
    }

    private func seedDefaultJournal() {
        let info = makeDefaultJournal()
        journals = [info]
        activeJournalID = info.id
        persistCatalog()
    }

    /// Creates the on-disk directory for a default journal without touching
    /// the catalog. Transactional deletion uses this form so a failed final
    /// catalog commit can remove the new directory cleanly.
    private func makeDefaultJournal() -> JournalInfo {
        let info = JournalInfo(name: defaultJournalName())
        let dir = librariesRoot.appendingPathComponent(info.id.uuidString, isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(
            at: dir.appendingPathComponent("images", isDirectory: true),
            withIntermediateDirectories: true
        )
        try? fileManager.createDirectory(
            at: dir.appendingPathComponent("backups", isDirectory: true),
            withIntermediateDirectories: true
        )

        return info
    }

    @discardableResult
    private func persistCatalog() -> Bool {
        guard !isCatalogReadOnly else { return false }
        guard let activeJournalID, !journals.isEmpty else { return false }
        let catalog = JournalCatalogSnapshot(
            version: JournalCatalogSnapshot.currentVersion,
            activeJournalID: activeJournalID,
            journals: journals
        )
        #if DEBUG
        if Self.failCatalogPersistOverride {
            NSLog("Wick catalog persist failed (test override)")
            return false
        }
        #endif
        do {
            let data = try encoder.encode(catalog)
            try fileManager.createDirectory(at: librariesRoot, withIntermediateDirectories: true)
            // Sidecar backup of the valid primary before every overwrite,
            // matching the journal.json.bak protection level.
            if fileManager.fileExists(atPath: catalogURL.path) {
                let backupURL = Self.catalogBackupURL(in: librariesRoot)
                try? fileManager.removeItem(at: backupURL)
                try? fileManager.copyItem(at: catalogURL, to: backupURL)
            }
            try data.write(to: catalogURL, options: .atomic)
            return true
        } catch {
            NSLog("Wick catalog persist failed: \(error.localizedDescription)")
            return false
        }
    }

    private func bindPaths(for journalID: UUID) {
        let dir = librariesRoot.appendingPathComponent(journalID.uuidString, isDirectory: true)
        journalDirectory = dir
        imagesDirectory = dir.appendingPathComponent("images", isDirectory: true)
        databaseURL = dir.appendingPathComponent("journal.json", isDirectory: false)
        backupURL = dir.appendingPathComponent("journal.json.bak", isDirectory: false)
        backupsDirectory = dir.appendingPathComponent("backups", isDirectory: true)
        lastRollingBackupAt = nil
    }

    private func resetSessionState() {
        selectedTagFilter = nil
        searchText = ""
        selection = nil
        isReadOnlyDueToLoadFailure = false
        loadFailureMessage = nil
        didRestoreFromBackup = false
        lastPersistError = nil
        JournalThumbnailCache.shared.removeAll()
    }

    private func captureJournalSession() -> JournalSessionSnapshot {
        JournalSessionSnapshot(
            journalDirectory: journalDirectory,
            imagesDirectory: imagesDirectory,
            databaseURL: databaseURL,
            backupURL: backupURL,
            backupsDirectory: backupsDirectory,
            entries: entries,
            selection: selection,
            selectedTagFilter: selectedTagFilter,
            searchText: searchText,
            isReadOnlyDueToLoadFailure: isReadOnlyDueToLoadFailure,
            loadFailureMessage: loadFailureMessage,
            lastPersistError: lastPersistError,
            didRestoreFromBackup: didRestoreFromBackup,
            lastRollingBackupAt: lastRollingBackupAt
        )
    }

    private func restoreJournalSession(_ snapshot: JournalSessionSnapshot) {
        journalDirectory = snapshot.journalDirectory
        imagesDirectory = snapshot.imagesDirectory
        databaseURL = snapshot.databaseURL
        backupURL = snapshot.backupURL
        backupsDirectory = snapshot.backupsDirectory
        entries = snapshot.entries
        selection = snapshot.selection
        selectedTagFilter = snapshot.selectedTagFilter
        searchText = snapshot.searchText
        isReadOnlyDueToLoadFailure = snapshot.isReadOnlyDueToLoadFailure
        loadFailureMessage = snapshot.loadFailureMessage
        lastPersistError = snapshot.lastPersistError
        didRestoreFromBackup = snapshot.didRestoreFromBackup
        lastRollingBackupAt = snapshot.lastRollingBackupAt
    }

    private func rollbackJournalDeletion(
        originalJournals: [JournalInfo],
        originalActiveJournalID: UUID?,
        originalSession: JournalSessionSnapshot,
        originalJournalIDs: Set<UUID>,
        quarantine: URL,
        originalDirectory: URL,
        movedAside: Bool
    ) {
        let createdIDs = Set(journals.map(\.id)).subtracting(originalJournalIDs)
        for id in createdIDs {
            let createdDirectory = librariesRoot.appendingPathComponent(id.uuidString, isDirectory: true)
            try? fileManager.removeItem(at: createdDirectory)
        }
        if movedAside, fileManager.fileExists(atPath: quarantine.path) {
            try? fileManager.moveItem(at: quarantine, to: originalDirectory)
        }
        journals = originalJournals
        activeJournalID = originalActiveJournalID
        restoreJournalSession(originalSession)
    }

    private func loadActiveJournalContent() {
        load()
    }

    private func touchActiveJournalMetadata() {
        guard let activeJournalID,
              let index = journals.firstIndex(where: { $0.id == activeJournalID })
        else { return }
        journals[index].updatedAt = Date()
        persistCatalog()
    }

    private func notifyActiveJournalChanged() {
        NotificationCenter.default.post(name: .wickActiveJournalDidChange, object: self)
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

    /// Merge the destination day's contents into the source entry while keeping
    /// the source UUID. Moving an entry never changes its identity.
    private func merge(entryAt sourceIndex: Int, into destinationIndex: Int, preferring source: JournalEntry) {
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

    // MARK: - Persistence (active journal)

    private func ensureDirectories() {
        try? fileManager.createDirectory(at: journalDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
    }

    private func load() {
        isReadOnlyDueToLoadFailure = false
        loadFailureMessage = nil
        // Note: `didRestoreFromBackup` is intentionally NOT reset here — a
        // catalog restore (set by `applyCatalog`) must survive the active
        // journal load that follows in bootstrap. `resetSessionState` /
        // `createJournal` clear it on navigation.
        ensureDirectories()

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
            selection = nil
            return
        }

        do {
            let data = try Data(contentsOf: databaseURL)
            let snapshot = try decoder.decode(JournalSnapshot.self, from: data)
            // Newer format (written by a newer app on another device): go read-only
            // rather than strip unknown fields by re-encoding and persisting.
            guard snapshot.version <= JournalSnapshot.currentVersion else {
                entries = []
                selection = nil
                isReadOnlyDueToLoadFailure = true
                loadFailureMessage = L10n.string(
                    .journalNewerVersionRequired,
                    language: AppSettings.shared.language
                )
                return
            }
            entries = snapshot.entries.sorted { $0.date > $1.date }
            selection = entries.first.map { .day($0.id) }
        } catch {
            NSLog("Wick journal load failed: \(error.localizedDescription)")
            if let restored = loadSnapshot(from: backupURL) {
                entries = restored.entries.sorted { $0.date > $1.date }
                selection = entries.first.map { .day($0.id) }
                didRestoreFromBackup = true
                // Quarantine corrupt primary, then rewrite from backup.
                let quarantine = journalDirectory.appendingPathComponent(
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
            loadFailureMessage = loadFailureMessage(for: error)
        }
    }

    private func loadFailureMessage(for error: Error) -> String {
        if error is JournalImageFilename.InvalidReference {
            return L10n.string(.journalUnsafeImageReferences, language: AppSettings.shared.language)
        }
        return error.localizedDescription
    }

    private func loadSnapshot(from url: URL) -> JournalSnapshot? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let snapshot = try decoder.decode(JournalSnapshot.self, from: data)
            // Treat newer-format files as unreadable so restore paths never
            // re-encode (and strip) data written by a newer app version.
            guard snapshot.version <= JournalSnapshot.currentVersion else { return nil }
            return snapshot
        } catch {
            return nil
        }
    }

    private func persist() {
        guard !persistBlocked else { return }
        guard !isReadOnlyDueToLoadFailure else {
            return
        }
        ensureDirectories()
        entriesDidMutate.send()

        persistCount += 1
        persistGeneration += 1
        let generation = persistGeneration
        let snapshot = JournalSnapshot(version: JournalSnapshot.currentVersion, entries: entries)
        let databaseURL = self.databaseURL
        let backupURL = self.backupURL
        let backupsDirectory = self.backupsDirectory
        let maxRollingBackups = self.maxRollingBackups
        let fileExists = fileManager.fileExists(atPath: databaseURL.path)
        let shouldRoll: Bool
        if let last = lastRollingBackupAt {
            shouldRoll = Date().timeIntervalSince(last) >= 60 * 30
        } else {
            shouldRoll = true
        }
        if fileExists, shouldRoll {
            lastRollingBackupAt = Date()
        }

        let snapshotCopy = snapshot
        let copyExistingToBackup = fileExists
        let includeRolling = fileExists && shouldRoll

        // XCTest reloads the file immediately; keep that path synchronous.
        if NSClassFromString("XCTestCase") != nil {
            let error = Self.writeSnapshot(
                snapshotCopy,
                to: databaseURL,
                backupURL: backupURL,
                backupsDirectory: backupsDirectory,
                copyExistingToBackup: copyExistingToBackup,
                includeRolling: includeRolling,
                maxRollingBackups: maxRollingBackups
            )
            applyPersistResult(error, generation: generation)
            return
        }

        persistQueue.async { [weak self] in
            let error = Self.writeSnapshot(
                snapshotCopy,
                to: databaseURL,
                backupURL: backupURL,
                backupsDirectory: backupsDirectory,
                copyExistingToBackup: copyExistingToBackup,
                includeRolling: includeRolling,
                maxRollingBackups: maxRollingBackups
            )
            DispatchQueue.main.async {
                self?.applyPersistResult(error, generation: generation)
            }
        }
    }

    private func applyPersistResult(_ error: String?, generation: UInt64) {
        guard generation == persistGeneration else { return }
        if let error {
            lastPersistError = error
            NSLog("Wick journal persist failed: \(error)")
        } else if lastPersistError != nil {
            lastPersistError = nil
        }
    }

    /// Encode + atomic write off the main thread. Encoding options stay
    /// `prettyPrinted + sortedKeys` to match `JournalSyncEncoding` (P3).
    /// Does **not** re-decode the previous file to decide whether to copy `.bak`.
    private nonisolated static func writeSnapshot(
        _ snapshot: JournalSnapshot,
        to databaseURL: URL,
        backupURL: URL,
        backupsDirectory: URL,
        copyExistingToBackup: Bool,
        includeRolling: Bool,
        maxRollingBackups: Int
    ) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            if copyExistingToBackup {
                Self.copyDatabaseToSidecarBackup(
                    databaseURL: databaseURL,
                    backupURL: backupURL,
                    backupsDirectory: backupsDirectory,
                    includeRolling: includeRolling,
                    maxRollingBackups: maxRollingBackups
                )
            }
            let data = try encoder.encode(snapshot)
            try data.write(to: databaseURL, options: .atomic)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private nonisolated static func copyDatabaseToSidecarBackup(
        databaseURL: URL,
        backupURL: URL,
        backupsDirectory: URL,
        includeRolling: Bool,
        maxRollingBackups: Int
    ) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: databaseURL.path) else { return }
        try? fileManager.removeItem(at: backupURL)
        try? fileManager.copyItem(at: databaseURL, to: backupURL)

        guard includeRolling else { return }
        try? fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "journal-\(formatter.string(from: Date())).json"
        let rolling = backupsDirectory.appendingPathComponent(name)
        try? fileManager.copyItem(at: databaseURL, to: rolling)
        Self.pruneRollingBackups(in: backupsDirectory, keeping: maxRollingBackups)
    }

    private nonisolated static func pruneRollingBackups(in backupsDirectory: URL, keeping maxRollingBackups: Int) {
        let fileManager = FileManager.default
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

    private func removeImageFile(_ filename: String) {
        guard let url = imageURL(for: filename) else { return }
        try? fileManager.removeItem(at: url)
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

    private nonisolated static func findJournalJSON(under directory: URL) -> URL? {
        let fm = FileManager.default
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

    private nonisolated static func runZip(sourceDirectory: URL, destinationZip: URL) throws {
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

    private nonisolated static func runUnzip(zipURL: URL, destinationDirectory: URL) throws {
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

/// Explicit outcome of loading the multi-journal catalog. Only `.missing` may
/// first-create the library; every failure state blocks catalog mutations.
enum CatalogLoadResult {
    case missing
    case loaded(JournalCatalogSnapshot)
    case restoredFromBackup(JournalCatalogSnapshot)
    case corrupt(Error)
    case unsupportedVersion(Int)
}

/// Explicit outcome of loading a (possibly non-active) journal's entries.
/// Load failure is never expressed as an empty array — callers decide how to
/// react to corrupt or newer-format data.
enum JournalEntriesLoadResult {
    /// The requested journal is the currently active one; in-memory entries.
    case active([JournalEntry])
    /// Read cleanly from disk.
    case loaded([JournalEntry])
    /// No `journal.json` exists (a legitimately new journal).
    case missing
    case corrupt(Error)
    case unsupportedVersion(Int)
}

enum JournalStoreError: LocalizedError {
    case exportFailed(String)
    case importFailed(String)
    case importMissingJournalJSON
    case unsupportedSnapshotVersion(Int)
    case catalogRecoveryFailed

    var errorDescription: String? {
        switch self {
        case .exportFailed(let message):
            return message.isEmpty ? "Export failed" : message
        case .importFailed(let message):
            return message.isEmpty ? "Import failed" : message
        case .importMissingJournalJSON:
            return "Archive does not contain journal.json"
        case .unsupportedSnapshotVersion(let version):
            return "Archive was written by a newer Wick version (snapshot v\(version))"
        case .catalogRecoveryFailed:
            return "The journal library could not be rebuilt; read-only protection was kept."
        }
    }
}


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
    private func mergeSyncedDateCollision(with incoming: JournalEntry) -> JournalEntry {
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
    private func localEntryStillMatches(entryID: UUID, expectedHash: String?) -> Bool {
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
