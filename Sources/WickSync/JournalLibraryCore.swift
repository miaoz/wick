import Foundation

/// Opaque snapshot of a journal store's active session, captured before a
/// mutating catalog transaction and restored on rollback. The core never
/// inspects its contents — the host captures/restores whatever platform state
/// it needs (entries, paths, read-only flags, and on macOS the selection /
/// tag filter / search text / backups directory via `platformState`).
@MainActor
public struct JournalSessionSnapshot: Sendable {
    public let journalDirectory: URL
    public let imagesDirectory: URL
    public let databaseURL: URL
    public let backupURL: URL
    public let entries: [JournalEntry]
    public let isReadOnlyDueToLoadFailure: Bool
    public let lastPersistError: String?
    /// Opaque platform extras (macOS session state). Never inspected by the core.
    public let platformState: (any Sendable)?

    public init(
        journalDirectory: URL,
        imagesDirectory: URL,
        databaseURL: URL,
        backupURL: URL,
        entries: [JournalEntry],
        isReadOnlyDueToLoadFailure: Bool,
        lastPersistError: String?,
        platformState: (any Sendable)? = nil
    ) {
        self.journalDirectory = journalDirectory
        self.imagesDirectory = imagesDirectory
        self.databaseURL = databaseURL
        self.backupURL = backupURL
        self.entries = entries
        self.isReadOnlyDueToLoadFailure = isReadOnlyDueToLoadFailure
        self.lastPersistError = lastPersistError
        self.platformState = platformState
    }
}

/// The primitive surface a journal store exposes so the shared multi-journal
/// catalog + lifecycle + delete/rollback logic (`JournalLibraryCore`) can be
/// written ONCE in WickSync instead of being duplicated by the macOS and iOS
/// stores (AR-01). Inherits `JournalSyncStoreHost` so the sync-bridge and
/// catalog layers share one state surface and one set of hooks. All methods
/// run on the main actor.
@MainActor
public protocol JournalLibraryHost: JournalSyncStoreHost {
    // State the core mutates directly.
    var isCatalogReadOnly: Bool { get set }
    var didRestoreFromBackup: Bool { get set }
    var persistBlocked: Bool { get set }
    var loadFailureMessage: String? { get set }
    var lastPersistError: String? { get set }

    // Paths.
    var librariesRoot: URL { get }
    var catalogURL: URL { get }

    /// Bind the store's active paths to `journalID`.
    func bindPaths(for journalID: UUID)
    /// Ensure the active journal's directories exist.
    func ensureDirectories()
    /// Make the given journal directory exist (seeding when brand new).
    func ensureJournalDirectory(for id: UUID)
    /// Seed a brand-new journal directory on disk.
    func seedJournalDirectory(for id: UUID)
    /// Load the active journal's content from disk (and reset per-platform state).
    func loadActiveContent()
    /// Reset the per-platform session (macOS clears selection/tag/search/cache).
    func resetSessionState()
    /// Flush editor drafts + the current journal before switching.
    func flushActiveJournalSession()
    /// Capture the full platform session (opaque to the core).
    func captureSession() -> JournalSessionSnapshot
    /// Restore a previously captured session (rollback).
    func restoreSession(_ snapshot: JournalSessionSnapshot)
    /// Default name for a freshly seeded library.
    func defaultJournalName() -> String
    /// macOS: notify observers that the active journal identity changed.
    func notifyActiveJournalChanged()
    /// Publish that the catalog changed (objectWillChange).
    func publishObjectWillChange()
}

extension JournalLibraryHost {
    public func ensureDirectories() {}
    public func ensureJournalDirectory(for id: UUID) {}
    public func resetSessionState() {}
    public func notifyActiveJournalChanged() {}
    public func publishObjectWillChange() {}
}

/// Result of applying a peer's deletion of a journal (shared by both stores).
public enum JournalRemoteDeleteResult: Equatable, Sendable {
    case deleted
    case notFound
    case refusedReadOnly
    case ioFailure
}

/// Shared multi-journal catalog + lifecycle + delete/rollback implementation,
/// written once in WickSync and driven by a `JournalLibraryHost` (AR-01).
@MainActor
public struct JournalLibraryCore {
    public let host: any JournalLibraryHost

    public init(host: any JournalLibraryHost) {
        self.host = host
    }

    #if DEBUG
    /// Test seam shared by both stores (each store's `failCatalogPersistOverride`
    /// forwards here so existing test references keep working).
    public nonisolated(unsafe) static var failCatalogPersistOverride = false
    #endif

    /// Encodes the catalog to `catalog.json` with a `.bak` sidecar of the
    /// previous primary before the atomic overwrite. False when read-only,
    /// empty, or the write fails.
    @discardableResult
    public func persistCatalog() -> Bool {
        guard !host.isCatalogReadOnly else { return false }
        guard let activeJournalID = host.activeJournalID, !host.journals.isEmpty else { return false }
        #if DEBUG
        if Self.failCatalogPersistOverride {
            NSLog("Wick catalog persist failed (test override)")
            return false
        }
        #endif
        let catalog = JournalCatalogSnapshot(
            version: JournalCatalogSnapshot.currentVersion,
            activeJournalID: activeJournalID,
            journals: host.journals
        )
        do {
            let data = try JournalSyncEncoding.encoder.encode(catalog)
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: host.librariesRoot, withIntermediateDirectories: true)
            // Sidecar backup of the valid primary before every overwrite.
            if fileManager.fileExists(atPath: host.catalogURL.path) {
                let backupURL = host.librariesRoot.appendingPathComponent("catalog.json.bak", isDirectory: false)
                try? fileManager.removeItem(at: backupURL)
                try? fileManager.copyItem(at: host.catalogURL, to: backupURL)
            }
            try data.write(to: host.catalogURL, options: .atomic)
            return true
        } catch {
            NSLog("Wick catalog persist failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Switch the active journal: flush, bind, load, persist, notify.
    public func switchToJournal(id: UUID) {
        guard !host.isCatalogReadOnly else { return }
        guard id != host.activeJournalID else { return }
        guard host.journals.contains(where: { $0.id == id }) else { return }

        host.flushActiveJournalSession()
        activateJournal(id)
        _ = persistCatalog()
        host.notifyActiveJournalChanged()
    }

    /// Creates a new empty journal, switches to it, and returns its metadata.
    @discardableResult
    public func createJournal(name: String) -> JournalInfo {
        guard !host.isCatalogReadOnly else { return host.journals.first { $0.id == host.activeJournalID } ?? JournalInfo(name: "") }
        host.flushActiveJournalSession()

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmed.isEmpty ? host.defaultJournalName() : trimmed
        let info = JournalInfo(name: resolvedName)
        host.seedJournalDirectory(for: info.id)

        host.journals.append(info)
        host.activeJournalID = info.id
        host.entries = []
        activateJournal(info.id)
        _ = persistCatalog()
        host.notifyActiveJournalChanged()
        return info
    }

    /// Reorders journals in the catalog (SwiftUI's `move(fromOffsets:)` is not
    /// available in this pure-Foundation module, so replicate its semantics).
    public func moveJournal(from source: IndexSet, to destination: Int) {
        guard !host.isCatalogReadOnly else { return }
        let moving = host.journals.enumerated()
            .filter { source.contains($0.offset) }
            .map { $0.element }
        let targetIndex = destination > (source.min() ?? 0)
            ? destination - source.count
            : destination
        // Remove highest-first so earlier indices stay valid.
        for index in source.sorted(by: >) {
            host.journals.remove(at: index)
        }
        host.journals.insert(contentsOf: moving, at: targetIndex)
        _ = persistCatalog()
    }

    /// Binds (or clears) the exchange account for one journal.
    public func setExchangeBinding(_ binding: JournalExchangeBinding?, for id: UUID) {
        guard !host.isCatalogReadOnly else { return }
        guard let index = host.journals.firstIndex(where: { $0.id == id }) else { return }
        host.journals[index].exchangeBinding = binding
        host.journals[index].updatedAt = Date()
        _ = persistCatalog()
        host.publishObjectWillChange()
    }

    /// Renames a journal in the catalog.
    public func renameJournal(id: UUID, to name: String) {
        guard !host.isCatalogReadOnly else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = host.journals.firstIndex(where: { $0.id == id }) else { return }

        host.journals[index].name = trimmed
        host.journals[index].updatedAt = Date()
        _ = persistCatalog()
        if id == host.activeJournalID {
            host.notifyActiveJournalChanged()
        }
    }

    /// Registers a journal discovered on another device under the same id.
    @discardableResult
    public func registerRemoteJournal(id: UUID, name: String) -> JournalInfo {
        guard !host.isCatalogReadOnly else { return JournalInfo(name: name) }
        if let existing = host.journals.first(where: { $0.id == id }) {
            return existing
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let info = JournalInfo(
            id: id,
            name: uniquifiedJournalName(trimmed.isEmpty ? host.defaultJournalName() : trimmed)
        )
        host.seedJournalDirectory(for: id)
        host.journals.append(info)
        _ = persistCatalog()
        return info
    }

    /// Deletes a journal and its on-disk folder; refuses the last journal.
    @discardableResult
    public func deleteJournal(id: UUID) -> Bool {
        guard !host.isCatalogReadOnly else { return false }
        guard host.journals.count > 1, host.journals.contains(where: { $0.id == id }) else { return false }

        let originalJournals = host.journals
        let originalActive = host.activeJournalID
        let originalSession = host.captureSession()
        let originalJournalIDs = Set(host.journals.map(\.id))
        let dir = host.librariesRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        let quarantine = host.librariesRoot
            .appendingPathComponent(".WickJournalQuarantine-\(UUID().uuidString)", isDirectory: true)
        let fileManager = FileManager.default
        let movedAside = fileManager.fileExists(atPath: dir.path)
        if movedAside {
            do {
                try fileManager.moveItem(at: dir, to: quarantine)
            } catch {
                return false
            }
        }

        host.journals.removeAll { $0.id == id }
        if id == originalActive {
            let next = host.journals.sorted { $0.updatedAt > $1.updatedAt }.first ?? host.journals.first
            activateJournal(next?.id)
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
        host.notifyActiveJournalChanged()
        return true
    }

    /// Applies a deletion that originated on ANOTHER device: deletes even the
    /// last journal and seeds a fresh, pure-local default (AC-P1-04).
    @discardableResult
    public func deleteJournalFromRemote(id: UUID) -> JournalRemoteDeleteResult {
        guard !host.isCatalogReadOnly else { return .refusedReadOnly }
        guard host.journals.contains(where: { $0.id == id }) else { return .notFound }

        let originalJournals = host.journals
        let originalActive = host.activeJournalID
        let originalSession = host.captureSession()
        let originalJournalIDs = Set(host.journals.map(\.id))
        let dir = host.librariesRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        let quarantine = host.librariesRoot
            .appendingPathComponent(".WickJournalQuarantine-\(UUID().uuidString)", isDirectory: true)
        let fileManager = FileManager.default
        let dirMovedAside = fileManager.fileExists(atPath: dir.path)
        if dirMovedAside {
            do {
                try fileManager.moveItem(at: dir, to: quarantine)
            } catch {
                return .ioFailure
            }
        }

        host.journals.removeAll { $0.id == id }

        if host.journals.isEmpty {
            // Last journal deleted by a peer: seed a fresh default and switch.
            let info = JournalInfo(name: host.defaultJournalName())
            host.seedJournalDirectory(for: info.id)
            host.journals = [info]
            host.activeJournalID = info.id
            host.entries = []
            activateJournal(info.id)
        } else if id == originalActive {
            let next = host.journals.sorted { $0.updatedAt > $1.updatedAt }.first ?? host.journals.first
            activateJournal(next?.id)
        }

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
        host.notifyActiveJournalChanged()
        return .deleted
    }

    /// Uniquifies a journal name against the OTHER journals in the catalog.
    public func uniquifiedJournalName(_ base: String) -> String {
        let existing = Set(host.journals.map { $0.name.lowercased() })
        guard existing.contains(base.lowercased()) else { return base }
        var index = 2
        while existing.contains("\(base) \(index)".lowercased()) {
            index += 1
        }
        return "\(base) \(index)"
    }

    /// Uniquifies a journal name, excluding the journal being renamed.
    public func uniquifiedJournalName(_ base: String, excluding journalID: UUID) -> String {
        let existing = Set(host.journals.filter { $0.id != journalID }.map { $0.name.lowercased() })
        guard existing.contains(base.lowercased()) else { return base }
        var index = 2
        while existing.contains("\(base) \(index)".lowercased()) {
            index += 1
        }
        return "\(base) \(index)"
    }

    // MARK: - Private

    /// Binds + loads the given journal as active, guarding the writer against a
    /// stray flush of the previous journal's in-memory entries.
    private func activateJournal(_ id: UUID?) {
        host.persistBlocked = true
        host.activeJournalID = id
        if let id {
            host.bindPaths(for: id)
            host.loadActiveContent()
        }
        host.persistBlocked = false
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
        let createdIDs = Set(host.journals.map(\.id)).subtracting(originalJournalIDs)
        for id in createdIDs {
            let createdDirectory = host.librariesRoot.appendingPathComponent(id.uuidString, isDirectory: true)
            try? FileManager.default.removeItem(at: createdDirectory)
        }
        if movedAside, FileManager.default.fileExists(atPath: quarantine.path) {
            try? FileManager.default.moveItem(at: quarantine, to: originalDirectory)
        }
        host.journals = originalJournals
        host.activeJournalID = originalActiveJournalID
        host.restoreSession(originalSession)
    }
}
