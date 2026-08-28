import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers
import WickSync

/// Points at one item inside a day journal. Used when the timeline is item-scoped
/// (tag filter / text search).
struct JournalItemRef: Hashable, Identifiable, Sendable {
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
enum JournalSelection: Hashable, Sendable {
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

    @Published var journals: [JournalInfo] = []
    @Published var activeJournalID: UUID?

    var activeJournal: JournalInfo? {
        guard let activeJournalID else { return nil }
        return journals.first { $0.id == activeJournalID }
    }

    // MARK: - Active journal content

    /// Not `@Published`: body-only autosave must not rebuild the journal window
    /// (P2). Structural mutations publish via other `@Published` fields
    /// (`selection`, `journals`) or an explicit `objectWillChange`. Sync
    /// observes `entriesDidMutate` instead of `$entries`.
    var entries: [JournalEntry] = []
    /// Fires after any in-memory entries change, including body-only persist.
    let entriesDidMutate = PassthroughSubject<Void, Never>()
    /// Fires after a remote day entry is successfully applied. Editors rebase
    /// their clean drafts onto the fresh store value when the day matches.
    let remoteEntryDidApply = PassthroughSubject<JournalRemoteApply, Never>()
    @Published var selection: JournalSelection?
    @Published var selectedTagFilter: String?
    @Published var searchText: String = ""

    /// When true, persistence is blocked so a failed load cannot wipe the on-disk file.
    @Published var isReadOnlyDueToLoadFailure = false
    @Published var loadFailureMessage: String?
    @Published var lastPersistError: String?
    @Published var didRestoreFromBackup = false
    /// Library-level protection: the catalog itself failed to load (corrupt or
    /// newer format). All catalog mutations (create/rename/reorder/delete/
    /// binding) are disabled until the user recovers via import/restore.
    @Published var isCatalogReadOnly = false
    @Published var catalogLoadMessage: String?

    #if DEBUG
    /// Test seam: force the next catalog persist to fail, deterministically
    /// exercising the AC-P1-04 rollback path. Forwards to the shared core.
    static var failCatalogPersistOverride: Bool {
        get { JournalLibraryCore.failCatalogPersistOverride }
        set { JournalLibraryCore.failCatalogPersistOverride = newValue }
    }
    /// Test seam: force the final export replace to fail after the temp
    /// archive was built, exercising the AC-P1-07 atomic-replace path.
    nonisolated(unsafe) static var failExportReplaceOverride = false
    /// Test seam: fail the Nth image copy during import (1-based), exercising
    /// the DS-02 quarantine-rollback path.
    nonisolated(unsafe) static var failImageCopyAtIndex: Int?
    #endif
    /// Last explicit-recovery failure (start fresh / import), so UI callers
    /// never silently drop a recovery error.
    @Published var recoveryErrorMessage: String?

    func dismissRecoveryError() {
        recoveryErrorMessage = nil
    }

    let fileManager = FileManager.default
    let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Root of the multi-journal library (`…/Wick/Journals`).
    let librariesRoot: URL
    /// Legacy single-journal path (`…/Wick/Journal`), only used for one-shot migration.
    let legacyRoot: URL?
    let catalogURL: URL

    // Active journal paths — recomputed on switch.
    var journalDirectory: URL
    var imagesDirectory: URL
    var databaseURL: URL
    var backupURL: URL
    var backupsDirectory: URL

    let maxRollingBackups = 5
    var lastRollingBackupAt: Date?
    /// True while switching journals, so `persist()` cannot write the previous
    /// journal's in-memory snapshot into the newly bound folder.
    var persistBlocked = false
    /// Serial disk writer so typing does not encode JSON on the main thread (P3).
    let persistQueue = DispatchQueue(label: "com.miaoz.wick.journal-persist")
    var persistGeneration: UInt64 = 0
    /// Test-observable count of full-snapshot persists (PF-01 regression guard:
    /// a batch apply must add exactly one).
    var persistCount = 0

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
    init() {
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


