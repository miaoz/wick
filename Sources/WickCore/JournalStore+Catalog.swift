import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers
import WickSync

// MARK: - Catalog / multi-journal
//
// Multi-journal catalog API + bootstrap/migration, split out of the store
// god-file (DS-07). Pure behavior-preserving move.

extension JournalStore {
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

    func uniquifiedJournalName(_ base: String) -> String {
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
    func uniquifiedJournalName(_ base: String, excluding journalID: UUID) -> String {
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

    func captureJournalSession() -> JournalSessionSnapshot {
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

    func restoreJournalSession(_ snapshot: JournalSessionSnapshot) {
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

    func rollbackJournalDeletion(
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
