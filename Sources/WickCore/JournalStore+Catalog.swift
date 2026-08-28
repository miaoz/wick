import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers
import WickSync

// MARK: - Catalog / multi-journal
//
// Multi-journal catalog API + bootstrap/migration, split out of the store
// god-file (DS-07). Pure behavior-preserving move.

extension JournalStore: JournalLibraryHost {
    private var libraryCore: JournalLibraryCore { JournalLibraryCore(host: self) }

    func seedJournalDirectory(for id: UUID) {
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
        if let data = try? encoder.encode(JournalSnapshot.empty) {
            try? data.write(
                to: dir.appendingPathComponent("journal.json", isDirectory: false),
                options: .atomic
            )
        }
    }

    func loadActiveContent() {
        loadActiveJournalContent()
    }

    func defaultJournalName() -> String {
        defaultJournalName(for: nil)
    }

    func publishObjectWillChange() {
        objectWillChange.send()
    }

    func captureSession() -> JournalSessionSnapshot {
        JournalSessionSnapshot(
            journalDirectory: journalDirectory,
            imagesDirectory: imagesDirectory,
            databaseURL: databaseURL,
            backupURL: backupURL,
            entries: entries,
            isReadOnlyDueToLoadFailure: isReadOnlyDueToLoadFailure,
            lastPersistError: lastPersistError,
            platformState: MacSessionExtras(
                backupsDirectory: backupsDirectory,
                selection: selection,
                selectedTagFilter: selectedTagFilter,
                searchText: searchText,
                loadFailureMessage: loadFailureMessage,
                didRestoreFromBackup: didRestoreFromBackup,
                lastRollingBackupAt: lastRollingBackupAt
            )
        )
    }

    func restoreSession(_ snapshot: JournalSessionSnapshot) {
        journalDirectory = snapshot.journalDirectory
        imagesDirectory = snapshot.imagesDirectory
        databaseURL = snapshot.databaseURL
        backupURL = snapshot.backupURL
        entries = snapshot.entries
        isReadOnlyDueToLoadFailure = snapshot.isReadOnlyDueToLoadFailure
        lastPersistError = snapshot.lastPersistError
        if let extras = snapshot.platformState as? MacSessionExtras {
            backupsDirectory = extras.backupsDirectory
            selection = extras.selection
            selectedTagFilter = extras.selectedTagFilter
            searchText = extras.searchText
            loadFailureMessage = extras.loadFailureMessage
            didRestoreFromBackup = extras.didRestoreFromBackup
            lastRollingBackupAt = extras.lastRollingBackupAt
        }
    }
}

/// Opaque macOS session extras carried in the shared `JournalSessionSnapshot`.
private struct MacSessionExtras: Sendable {
    let backupsDirectory: URL
    let selection: JournalSelection?
    let selectedTagFilter: String?
    let searchText: String
    let loadFailureMessage: String?
    let didRestoreFromBackup: Bool
    let lastRollingBackupAt: Date?
}

extension JournalStore {

    // MARK: - Multi-journal API

    /// Switch the active journal. Flushes editor drafts + the current store first.
    func switchToJournal(id: UUID) {
        libraryCore.switchToJournal(id: id)
    }

    /// Creates a new empty journal, switches to it, and returns its metadata.
    @discardableResult
    func createJournal(name: String) -> JournalInfo {
        libraryCore.createJournal(name: name)
    }

    /// Reorders journals in the catalog (e.g. from drag-and-drop) and persists the new order.
    func moveJournal(from source: IndexSet, to destination: Int) {
        libraryCore.moveJournal(from: source, to: destination)
    }

    /// Binds (or clears) the exchange account for one journal. Secrets are
    /// not stored here — only the venue + display label.
    func setExchangeBinding(_ binding: JournalExchangeBinding?, for id: UUID) {
        libraryCore.setExchangeBinding(binding, for: id)
    }

    /// Renames a journal in the catalog.
    func renameJournal(id: UUID, to name: String) {
        libraryCore.renameJournal(id: id, to: name)
    }

    /// Deletes a journal and its on-disk folder. Refuses to delete the last journal.
    @discardableResult
    func deleteJournal(id: UUID) -> Bool {
        libraryCore.deleteJournal(id: id)
    }

    /// Applies a deletion that originated on ANOTHER device: deletes even the
    /// last journal and seeds a fresh, pure-local default (AC-P1-04).
    @discardableResult
    func deleteJournalFromRemote(id: UUID) -> JournalRemoteDeleteResult {
        libraryCore.deleteJournalFromRemote(id: id)
    }

    /// Suggested default name for a newly created journal (language-aware).
    func defaultJournalName(for language: AppLanguage? = nil) -> String {
        let language = language ?? AppSettings.shared.language
        let base = L10n.string(.journalLibraryDefaultName, language: language)
        return uniquifiedJournalName(base)
    }

    func uniquifiedJournalName(_ base: String) -> String {
        libraryCore.uniquifiedJournalName(base)
    }

    /// Collision check for sync-applied renames: the journal being renamed must
    /// not uniquify against itself.
    func uniquifiedJournalName(_ base: String, excluding journalID: UUID) -> String {
        libraryCore.uniquifiedJournalName(base, excluding: journalID)
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
        libraryCore.registerRemoteJournal(id: id, name: name)
    }

    // MARK: - Bootstrap / migration

    func bootstrapLibrary() {
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
    func migrateLegacySingleJournalIfNeeded() {
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
    func migrateJournalSnapshotsToCurrentVersion() {
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

    func quarantineLegacyRoot(_ legacyRoot: URL) {
        let stamp = Int(Date().timeIntervalSince1970)
        let quarantine = legacyRoot
            .deletingLastPathComponent()
            .appendingPathComponent("Journal.migrated-\(stamp)", isDirectory: true)
        try? fileManager.moveItem(at: legacyRoot, to: quarantine)
    }

    func defaultMigratedJournalName() -> String {
        L10n.string(.journalLibraryDefaultName, language: AppSettings.shared.language)
    }

    func loadOrCreateCatalog() {
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

    func applyCatalog(_ catalog: JournalCatalogSnapshot, restoredFromBackup: Bool) {
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

    func enterCatalogReadOnly(_ error: Error) {
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

    func loadCatalog() -> CatalogLoadResult {
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

    func quarantineCorruptCatalog() {
        let quarantine = librariesRoot.appendingPathComponent(
            "catalog.corrupt-\(Int(Date().timeIntervalSince1970)).json",
            isDirectory: false
        )
        try? fileManager.moveItem(at: catalogURL, to: quarantine)
    }

    static func catalogBackupURL(in librariesRoot: URL) -> URL {
        librariesRoot.appendingPathComponent("catalog.json.bak", isDirectory: false)
    }

    func seedDefaultJournal() {
        let info = makeDefaultJournal()
        journals = [info]
        activeJournalID = info.id
        persistCatalog()
    }

    /// Creates the on-disk directory for a default journal without touching
    /// the catalog. Transactional deletion uses this form so a failed final
    /// catalog commit can remove the new directory cleanly.
    func makeDefaultJournal() -> JournalInfo {
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
    func persistCatalog() -> Bool {
        libraryCore.persistCatalog()
    }

    func bindPaths(for journalID: UUID) {
        let dir = librariesRoot.appendingPathComponent(journalID.uuidString, isDirectory: true)
        journalDirectory = dir
        imagesDirectory = dir.appendingPathComponent("images", isDirectory: true)
        databaseURL = dir.appendingPathComponent("journal.json", isDirectory: false)
        backupURL = dir.appendingPathComponent("journal.json.bak", isDirectory: false)
        backupsDirectory = dir.appendingPathComponent("backups", isDirectory: true)
        lastRollingBackupAt = nil
    }

    func resetSessionState() {
        selectedTagFilter = nil
        searchText = ""
        selection = nil
        isReadOnlyDueToLoadFailure = false
        loadFailureMessage = nil
        didRestoreFromBackup = false
        lastPersistError = nil
        JournalThumbnailCache.shared.removeAll()
    }

    func loadActiveJournalContent() {
        load()
    }

    func touchActiveJournalMetadata() {
        guard let activeJournalID,
              let index = journals.firstIndex(where: { $0.id == activeJournalID })
        else { return }
        journals[index].updatedAt = Date()
        persistCatalog()
    }

    func notifyActiveJournalChanged() {
        NotificationCenter.default.post(name: .wickActiveJournalDidChange, object: self)
    }

}
