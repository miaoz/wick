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

    #if DEBUG
    /// Test-only failure injection for catalog transaction rollback tests.
    static var failCatalogPersistOverride = false
    #endif

    @Published private(set) var journals: [JournalInfo] = []
    @Published private(set) var activeJournalID: UUID?
    /// Kept sorted newest-first — DayListView renders the array as-is.
    @Published private(set) var entries: [JournalEntry] = []
    @Published private(set) var isReadOnlyDueToLoadFailure = false
    /// Library-level protection: the catalog failed to load (corrupt or newer
    /// format). Journal creation and catalog mutations are disabled.
    @Published private(set) var isCatalogReadOnly = false
    /// Fires after a remote day entry is successfully applied; editors rebase
    /// their clean drafts onto the fresh store value.
    let remoteEntryDidApply = PassthroughSubject<JournalRemoteApply, Never>()

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
    private var persistBlocked = false
    @Published private(set) var lastPersistError: String?

    private struct JournalSessionSnapshot {
        let journalDirectory: URL
        let imagesDirectory: URL
        let databaseURL: URL
        let backupURL: URL
        let entries: [JournalEntry]
        let isReadOnlyDueToLoadFailure: Bool
        let lastPersistError: String?
    }

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

    #if DEBUG
    /// Test-only: build a store rooted at an isolated directory so first-launch
    /// and corruption fixtures can be exercised without Application Support.
    init(rootDirectory: URL) {
        librariesRoot = rootDirectory
        catalogURL = rootDirectory.appendingPathComponent("catalog.json", isDirectory: false)
        let placeholder = rootDirectory.appendingPathComponent("_pending", isDirectory: true)
        journalDirectory = placeholder
        imagesDirectory = placeholder.appendingPathComponent("images", isDirectory: true)
        databaseURL = placeholder.appendingPathComponent("journal.json", isDirectory: false)
        backupURL = placeholder.appendingPathComponent("journal.json.bak", isDirectory: false)
        bootstrap()
    }
    #endif

    // MARK: - Bootstrap

    private func bootstrap() {
        try? fileManager.createDirectory(at: librariesRoot, withIntermediateDirectories: true)
        loadOrCreateCatalog()
        migrateJournalSnapshotsToCurrentVersion()
        if let activeJournalID {
            bindPaths(for: activeJournalID)
            ensureDirectories()
            load()
        }
    }

    private func loadOrCreateCatalog() {
        let backupURL = librariesRoot.appendingPathComponent("catalog.json.bak", isDirectory: false)
        switch JournalCatalogLoader.load(
            primaryURL: catalogURL,
            backupURL: backupURL,
            currentVersion: JournalCatalogSnapshot.currentVersion
        ) {
        case .missing:
            // The ONLY case that may first-create a library.
            let info = JournalInfo(name: "日记")
            journals = [info]
            activeJournalID = info.id
            bindPaths(for: info.id)
            _ = persistCatalog()
        case .loaded(let catalog):
            applyCatalog(catalog)
        case .restoredFromBackup(let catalog):
            applyCatalog(catalog)
            // Persist the restored catalog as the new primary; the valid
            // backup is preserved until this write succeeds.
            _ = persistCatalog()
        case .corrupt, .unsupportedVersion:
            // Never degrade corruption into a fresh install.
            isCatalogReadOnly = true
            journals = []
            activeJournalID = nil
        }
    }

    private func applyCatalog(_ catalog: JournalCatalogSnapshot) {
        isCatalogReadOnly = false
        journals = catalog.journals.sorted { $0.createdAt < $1.createdAt }
        activeJournalID = catalog.journals.contains(where: { $0.id == catalog.activeJournalID })
            ? catalog.activeJournalID
            : journals.first?.id
    }

    /// Hard-cuts supported v1 snapshots to UUID-only v2 while preserving the
    /// original primary as `journal.json.bak` before the atomic replacement.
    private func migrateJournalSnapshotsToCurrentVersion() {
        guard !isCatalogReadOnly else { return }
        for journal in journals {
            let directory = librariesRoot.appendingPathComponent(journal.id.uuidString, isDirectory: true)
            let url = directory.appendingPathComponent("journal.json", isDirectory: false)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            do {
                let data = try Data(contentsOf: url)
                let snapshot = try JournalSyncEncoding.decoder.decode(JournalSnapshot.self, from: data)
                guard snapshot.version < JournalSnapshot.currentVersion else { continue }
                let upgraded = JournalSnapshot(
                    version: JournalSnapshot.currentVersion,
                    entries: snapshot.entries
                )
                let upgradedData = try JournalSyncEncoding.encoder.encode(upgraded)
                let backup = directory.appendingPathComponent("journal.json.bak", isDirectory: false)
                try? fileManager.removeItem(at: backup)
                try fileManager.copyItem(at: url, to: backup)
                try upgradedData.write(to: url, options: .atomic)
            } catch {
                NSLog("Wick iOS journal v2 migration skipped for %@: %@", journal.id.uuidString, error.localizedDescription)
            }
        }
    }

    /// Explicit recovery: quarantine a corrupt/newer-format catalog, seed a
    /// fresh default library, and only leave read-only once the new catalog is
    /// durably written. Throws and rolls back (restoring the quarantined file)
    /// when the fresh-start write fails.
    func abandonCatalogAndStartFresh() throws {
        guard isCatalogReadOnly else { return }
        let info = JournalInfo(name: "日记")
        try recoverCatalog(
            JournalCatalogSnapshot(
                version: JournalCatalogSnapshot.currentVersion,
                activeJournalID: info.id,
                journals: [info]
            )
        )
    }

    /// Restores the last valid catalog sidecar without discarding its journal
    /// names, ordering, active ID, or exchange bindings.
    func restoreCatalogFromBackup() throws {
        guard isCatalogReadOnly else { return }
        let backupURL = librariesRoot.appendingPathComponent("catalog.json.bak", isDirectory: false)
        let data = try Data(contentsOf: backupURL)
        let catalog = try JournalCatalogCodec.decode(
            data,
            currentVersion: JournalCatalogSnapshot.currentVersion
        )
        try recoverCatalog(catalog)
    }

    /// Imports a validated bare journal.json. iOS uses JSON imports because it
    /// has no process-based unzip facility; macOS continues to support zip.
    func importJournalJSON(from sourceURL: URL) throws {
        let data = try Data(contentsOf: sourceURL)
        let snapshot = try JournalSyncEncoding.decoder.decode(JournalSnapshot.self, from: data)
        guard snapshot.version <= JournalSnapshot.currentVersion else {
            throw PhoneJournalStoreError.unsupportedSnapshotVersion(snapshot.version)
        }

        if isCatalogReadOnly {
            let info = JournalInfo(name: "日记")
            try recoverCatalog(
                JournalCatalogSnapshot(
                    version: JournalCatalogSnapshot.currentVersion,
                    activeJournalID: info.id,
                    journals: [info]
                )
            )
        }
        guard !isCatalogReadOnly else { throw PhoneJournalStoreError.catalogRecoveryFailed }

        let previousEntries = entries
        entries = snapshot.entries.sorted { $0.date > $1.date }
        persist()
        guard flushPendingWrites() else {
            entries = previousEntries
            throw PhoneJournalStoreError.writeFailed
        }
    }

    /// Encodes the active journal's snapshot as JSON data for export.
    func exportJournalData() -> Data? {
        flushPendingWrites()
        let snapshot = JournalSnapshot(version: JournalSnapshot.currentVersion, entries: entries)
        return try? JournalSyncEncoding.encoder.encode(snapshot)
    }

    private func recoverCatalog(_ recoveredCatalog: JournalCatalogSnapshot) throws {
        guard !recoveredCatalog.journals.isEmpty else {
            throw PhoneJournalStoreError.catalogRecoveryFailed
        }
        let originalJournals = journals
        let originalActive = activeJournalID
        let originalSession = captureJournalSession()
        let originalJournalIDs = Set(journals.map(\.id))
        let quarantine = librariesRoot.appendingPathComponent(
            "catalog.corrupt-\(UUID().uuidString).json",
            isDirectory: false
        )
        let hadPrimary = fileManager.fileExists(atPath: catalogURL.path)
        if hadPrimary {
            try fileManager.moveItem(at: catalogURL, to: quarantine)
        }

        isCatalogReadOnly = false
        journals = recoveredCatalog.journals.sorted { $0.createdAt < $1.createdAt }
        activeJournalID = journals.contains(where: { $0.id == recoveredCatalog.activeJournalID })
            ? recoveredCatalog.activeJournalID
            : journals.first?.id
        for journal in journals {
            ensureJournalDirectory(for: journal.id)
        }
        if let activeJournalID {
            bindPaths(for: activeJournalID)
            ensureDirectories()
            entries = []
            load()
        }

        guard persistCatalog() else {
            if hadPrimary, fileManager.fileExists(atPath: quarantine.path) {
                try? fileManager.moveItem(at: quarantine, to: catalogURL)
            }
            let createdIDs = Set(journals.map(\.id)).subtracting(originalJournalIDs)
            for id in createdIDs {
                try? fileManager.removeItem(
                    at: librariesRoot.appendingPathComponent(id.uuidString, isDirectory: true)
                )
            }
            journals = originalJournals
            activeJournalID = originalActive
            isCatalogReadOnly = true
            restoreJournalSession(originalSession)
            throw PhoneJournalStoreError.catalogRecoveryFailed
        }
        if hadPrimary {
            try? fileManager.removeItem(at: quarantine)
        }
    }

    @discardableResult
    private func persistCatalog() -> Bool {
        guard !isCatalogReadOnly else { return false }
        guard let activeJournalID, !journals.isEmpty else { return false }
        #if DEBUG
        if Self.failCatalogPersistOverride {
            NSLog("Wick iOS catalog persist failed (test override)")
            return false
        }
        #endif
        let catalog = JournalCatalogSnapshot(
            version: JournalCatalogSnapshot.currentVersion,
            activeJournalID: activeJournalID,
            journals: journals
        )
        do {
            let data = try JournalSyncEncoding.encoder.encode(catalog)
            try fileManager.createDirectory(at: librariesRoot, withIntermediateDirectories: true)
            // Sidecar backup of the valid primary before every overwrite,
            // matching the macOS catalog protection level.
            if fileManager.fileExists(atPath: catalogURL.path) {
                let backupURL = librariesRoot.appendingPathComponent("catalog.json.bak", isDirectory: false)
                try? fileManager.removeItem(at: backupURL)
                try? fileManager.copyItem(at: catalogURL, to: backupURL)
            }
            try data.write(to: catalogURL, options: .atomic)
            return true
        } catch {
            NSLog("Wick iOS catalog persist failed: \(error.localizedDescription)")
            return false
        }
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

    private func ensureJournalDirectory(for id: UUID) {
        let dir = librariesRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            seedJournalDirectory(for: id)
            return
        }
        try? fileManager.createDirectory(
            at: dir.appendingPathComponent("images", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    private func captureJournalSession() -> JournalSessionSnapshot {
        JournalSessionSnapshot(
            journalDirectory: journalDirectory,
            imagesDirectory: imagesDirectory,
            databaseURL: databaseURL,
            backupURL: backupURL,
            entries: entries,
            isReadOnlyDueToLoadFailure: isReadOnlyDueToLoadFailure,
            lastPersistError: lastPersistError
        )
    }

    private func restoreJournalSession(_ snapshot: JournalSessionSnapshot) {
        journalDirectory = snapshot.journalDirectory
        imagesDirectory = snapshot.imagesDirectory
        databaseURL = snapshot.databaseURL
        backupURL = snapshot.backupURL
        entries = snapshot.entries
        isReadOnlyDueToLoadFailure = snapshot.isReadOnlyDueToLoadFailure
        lastPersistError = snapshot.lastPersistError
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

    // MARK: - Journal switching / registration

    func switchToJournal(id: UUID) {
        guard id != activeJournalID, journals.contains(where: { $0.id == id }) else { return }
        flushPendingWrites()
        persistBlocked = true
        activeJournalID = id
        bindPaths(for: id)
        ensureDirectories()
        isReadOnlyDueToLoadFailure = false
        load()
        persistBlocked = false
        persistCatalog()
    }

    /// Registers a journal discovered on another device under the same id
    /// (see the macOS store for the full explanation). Does not switch.
    @discardableResult
    func registerRemoteJournal(id: UUID, name: String) -> JournalInfo {
        guard !isCatalogReadOnly else { return JournalInfo(name: name) }
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
        guard !isCatalogReadOnly else { return JournalInfo(name: name) }
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
        guard !isCatalogReadOnly else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = journals.firstIndex(where: { $0.id == id })
        else { return }
        journals[index].name = trimmed
        journals[index].updatedAt = Date()
        persistCatalog()
    }

    /// Binds (or clears) the exchange account for one journal.
    func setExchangeBinding(_ binding: JournalExchangeBinding?, for id: UUID) {
        guard !isCatalogReadOnly else { return }
        guard let index = journals.firstIndex(where: { $0.id == id }) else { return }
        journals[index].exchangeBinding = binding
        journals[index].updatedAt = Date()
        persistCatalog()
        objectWillChange.send()
    }

    /// Deletes a journal and its on-disk folder. Refuses to delete the last one.
    @discardableResult
    func deleteJournal(id: UUID) -> Bool {
        guard !isCatalogReadOnly else { return false }
        guard journals.count > 1, journals.contains(where: { $0.id == id }) else { return false }
        let wasActive = id == activeJournalID
        if wasActive {
            flushPendingWrites()
        }
        let originalJournals = journals
        let originalActive = activeJournalID
        let originalSession = captureJournalSession()
        let originalJournalIDs = Set(journals.map(\.id))
        let dir = librariesRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        let quarantine = librariesRoot
            .appendingPathComponent("WickJournalQuarantine-\(UUID().uuidString)", isDirectory: true)
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
            let next = journals.sorted { $0.updatedAt > $1.updatedAt }.first ?? journals.first
            persistBlocked = true
            activeJournalID = next?.id
            if let nextID = activeJournalID {
                bindPaths(for: nextID)
                ensureDirectories()
                isReadOnlyDueToLoadFailure = false
                load()
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
        return true
    }

    /// Result of applying a peer's deletion of a journal (mirrors macOS).
    enum RemoteJournalDeleteResult: Equatable {
        case deleted
        case notFound
        case refusedReadOnly
        case ioFailure
    }

    /// Applies a deletion that originated on ANOTHER device: deletes even the
    /// last journal and seeds a fresh, pure-local default so the app always
    /// has an active book. The new default is a new UUID — it inherits neither
    /// the deleted journal's sync state nor its exchange binding.
    ///
    /// The folder is moved aside on the same volume first; a failed catalog
    /// write rolls back the folder and in-memory catalog and returns
    /// `.ioFailure` so the coordinator never acknowledges (AC-P1-04).
    @discardableResult
    func deleteJournalFromRemote(id: UUID) -> RemoteJournalDeleteResult {
        guard !isCatalogReadOnly else { return .refusedReadOnly }
        guard journals.contains(where: { $0.id == id }) else { return .notFound }

        let wasActive = id == activeJournalID
        if wasActive {
            flushPendingWrites()
        }

        let originalJournals = journals
        let originalActive = activeJournalID
        let originalSession = captureJournalSession()
        let originalJournalIDs = Set(journals.map(\.id))
        let dir = librariesRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        let quarantine = librariesRoot
            .appendingPathComponent("WickJournalQuarantine-\(UUID().uuidString)", isDirectory: true)
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
            let info = makeDefaultJournal()
            journals = [info]
            activeJournalID = info.id
            bindPaths(for: info.id)
            ensureDirectories()
            isReadOnlyDueToLoadFailure = false
            entries = []
        } else if wasActive {
            let next = journals.sorted { $0.updatedAt > $1.updatedAt }.first ?? journals.first
            persistBlocked = true
            activeJournalID = next?.id
            if let nextID = activeJournalID {
                bindPaths(for: nextID)
                ensureDirectories()
                isReadOnlyDueToLoadFailure = false
                load()
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
                movedAside: dirMovedAside
            )
            return .ioFailure
        }

        if dirMovedAside {
            try? fileManager.removeItem(at: quarantine)
        }
        return .deleted
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

    private func makeDefaultJournal() -> JournalInfo {
        let info = JournalInfo(name: uniquifiedJournalName("日记"))
        seedJournalDirectory(for: info.id)
        return info
    }

    // MARK: - Entries

    /// Opens today's entry if present, otherwise creates it.
    @discardableResult
    func openOrCreateToday() -> JournalEntry {
        if let existing = entries.first(where: { Calendar.current.isDateInToday($0.date) }) {
            return existing
        }
        let entry = JournalEntry(date: Calendar.current.startOfDay(for: Date()))
        entries.insert(entry, at: 0)
        persist()
        return entry
    }

    /// Updates an entry by permanent UUID; bumps updatedAt.
    func updateEntry(_ entry: JournalEntry) {
        guard !isReadOnlyDueToLoadFailure else { return }
        var updated = entry
        updated.updatedAt = Date()
        if updated.items.isEmpty {
            updated.items = [JournalItem()]
        }
        updated.date = Calendar.current.startOfDay(for: updated.date)
        mergeLocalDateCollision(into: &updated)
        if let index = entries.firstIndex(where: { $0.id == updated.id }) {
            entries[index] = updated
        } else {
            entries.insert(updated, at: 0)
        }
        persist()
    }

    func deleteEntry(entryID: UUID) {
        guard !isReadOnlyDueToLoadFailure else { return }
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        for filename in entries[index].allImageFilenames {
            removeImageFile(filename)
        }
        entries.remove(at: index)
        persist()
    }

    // MARK: - Images

    /// The only image URL constructor in the app — mirrors the macOS store's
    /// two boundaries: a safe single-level filename AND a resolve location
    /// inside the images directory.
    func imageURL(for filename: String) -> URL? {
        guard JournalImageFilename.isValid(filename) else { return nil }
        let url = imagesDirectory.appendingPathComponent(filename)
        let standard = url.standardizedFileURL
        let imagesStandard = imagesDirectory.standardizedFileURL
        guard standard.path.hasPrefix(imagesStandard.path + "/") else { return nil }
        return url
    }

    private func removeImageFile(_ filename: String) {
        guard let url = imageURL(for: filename) else { return }
        try? fileManager.removeItem(at: url)
    }

    // MARK: - Persistence

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

    // MARK: - Serial background writer (AC-P2-02)

    /// Serial writer so full-snapshot encode + atomic write never run on the
    /// main thread for large journals.
    private let persistQueue = DispatchQueue(label: "com.miaoz.wick.ios-persist")
    private struct PendingSnapshot: Sendable {
        let journalID: UUID
        let databaseURL: URL
        let snapshot: JournalSnapshot
        let generation: UInt64
    }

    private final class WriteResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var message: String?

        func set(error: Error?) {
            lock.lock()
            message = error?.localizedDescription
            lock.unlock()
        }

        func get() -> String? {
            lock.lock()
            defer { lock.unlock() }
            return message
        }
    }

    private struct InFlightWrite {
        let generation: UInt64
        let semaphore: DispatchSemaphore
        let result: WriteResultBox
    }

    /// The latest snapshot awaiting a write ("latest pending generation").
    /// It always carries the journal identity and URL captured on the main
    /// actor, so a later journal switch cannot redirect the write.
    private var latestSnapshot: PendingSnapshot?
    private var isWriting = false
    private var nextGeneration: UInt64 = 0
    private var inFlightWrite: InFlightWrite?

    /// Snapshots the current entries and hands the encode + atomic write to the
    /// serial writer, coalescing rapid edits into the latest pending snapshot
    /// ("currently writing + latest pending" two-generation model).
    private func persist() {
        guard !persistBlocked else { return }
        guard !isReadOnlyDueToLoadFailure else { return }
        ensureDirectories()
        // Sidecar backup of the current primary before the overwrite, matching
        // the macOS backup semantics.
        if fileManager.fileExists(atPath: databaseURL.path),
           loadSnapshot(from: databaseURL) != nil
        {
            try? fileManager.removeItem(at: backupURL)
            try? fileManager.copyItem(at: databaseURL, to: backupURL)
        }
        nextGeneration &+= 1
        latestSnapshot = PendingSnapshot(
            journalID: activeJournalID ?? UUID(),
            databaseURL: databaseURL,
            snapshot: JournalSnapshot(version: JournalSnapshot.currentVersion, entries: entries),
            generation: nextGeneration
        )
        lastPersistError = nil
        drainWriterIfIdle()
    }

    private func drainWriterIfIdle() {
        guard !isWriting, let pending = latestSnapshot else { return }
        isWriting = true
        latestSnapshot = nil
        let semaphore = DispatchSemaphore(value: 0)
        let result = WriteResultBox()
        inFlightWrite = InFlightWrite(
            generation: pending.generation,
            semaphore: semaphore,
            result: result
        )
        persistQueue.async { [weak self] in
            do {
                let data = try JournalSyncEncoding.encoder.encode(pending.snapshot)
                try data.write(to: pending.databaseURL, options: .atomic)
                result.set(error: nil)
            } catch {
                result.set(error: error)
            }
            semaphore.signal()
            DispatchQueue.main.async {
                self?.completeWrite(
                    generation: pending.generation,
                    result: result
                )
            }
        }
    }

    private func completeWrite(generation: UInt64, result: WriteResultBox) {
        guard inFlightWrite?.generation == generation else { return }
        inFlightWrite = nil
        isWriting = false
        lastPersistError = result.get()
        // A newer snapshot may have arrived while writing — drain it.
        drainWriterIfIdle()
    }

    /// Waits for the serial writer to drain to the final generation.
    @discardableResult
    func flushPendingWrites() -> Bool {
        guard !isReadOnlyDueToLoadFailure else { return false }
        var succeeded = true
        while true {
            if !isWriting, latestSnapshot != nil {
                drainWriterIfIdle()
            }
            guard isWriting, let inFlightWrite else { break }

            // The worker never waits for the main actor, so it is safe to wait
            // here. This closes the gap where the queue is empty but the main
            // callback has not yet drained the latest pending generation.
            inFlightWrite.semaphore.wait()
            let error = inFlightWrite.result.get()
            if error != nil { succeeded = false }
            if self.inFlightWrite?.generation == inFlightWrite.generation {
                self.inFlightWrite = nil
                isWriting = false
                lastPersistError = error
            }
        }
        return succeeded && lastPersistError == nil
    }
}

// MARK: - Sync engine bridge

extension PhoneJournalStore: JournalLocalSource {
    var syncJournalID: UUID? { activeJournalID }

    var syncJournalName: String { activeJournal?.name ?? "" }

    var syncIsWritable: Bool { !isReadOnlyDueToLoadFailure }

    func syncEntrySnapshots() -> [UUID: JournalEntry] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    }

    /// Commits the currently open editor page's draft before the sync engine's
    /// freshness check, mirroring the macOS store.
    func prepareForRemoteApply(entryID: UUID) {
        NotificationCenter.default.post(name: .wickWillFlushJournalDrafts, object: nil)
    }

    /// Applies a whole cycle's remote changes in ONE pass (one persist). Each
    /// mutation is re-verified against its decision-time local hash right
    /// before committing; an entry edited since the decision is skipped and only
    /// actually-applied entry ids are returned (AC-P1-05).
    @discardableResult
    func applySyncedChanges(_ changes: [JournalSyncMutation], journalID: UUID) -> Set<UUID> {
        guard journalID == activeJournalID else { return [] }
        guard !isReadOnlyDueToLoadFailure else { return [] }
        guard !changes.isEmpty else { return [] }
        NotificationCenter.default.post(name: .wickWillFlushJournalDrafts, object: nil)

        var applied: Set<UUID> = []
        var appliedEvents: [JournalRemoteApply] = []
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
                appliedEvents.append(
                    JournalRemoteApply(journalID: journalID, entryID: appliedEntry.id)
                )
            case .remove(_, _):
                guard let index = entries.firstIndex(where: { $0.id == entryID }) else { continue }
                for filename in entries[index].allImageFilenames {
                    removeImageFile(filename)
                }
                entries.remove(at: index)
                applied.insert(entryID)
            }
        }
        guard !applied.isEmpty else { return [] }
        entries.sort { $0.date > $1.date }
        persist()
        for apply in appliedEvents {
            remoteEntryDidApply.send(apply)
        }
        return applied
    }

    /// Local date edits keep the UUID of the entry the user moved.
    private func mergeLocalDateCollision(into incoming: inout JournalEntry) {
        guard let collisionIndex = entries.firstIndex(where: {
            $0.id != incoming.id && Calendar.current.isDate($0.date, inSameDayAs: incoming.date)
        }) else { return }
        let collision = entries[collisionIndex]
        for item in collision.items where !item.isEmpty || collision.items.count == 1 {
            if !incoming.items.contains(where: { $0.id == item.id }) {
                incoming.items.append(item)
            }
        }
        if incoming.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            incoming.title = collision.title
        }
        incoming.createdAt = min(incoming.createdAt, collision.createdAt)
        incoming.updatedAt = max(incoming.updatedAt, collision.updatedAt)
        entries.remove(at: collisionIndex)
    }

    /// Sync collisions converge on the same survivor across devices.
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
        return survivor
    }

    private func localEntryStillMatches(entryID: UUID, expectedHash: String?) -> Bool {
        let current = entries.first { $0.id == entryID }
        guard let expectedHash else { return current == nil }
        guard let current else { return false }
        return (try? JournalSyncEncoding.contentHash(for: current)) == expectedHash
    }

    func applySyncedEntry(_ entry: JournalEntry, journalID: UUID) {
        guard journalID == activeJournalID else { return }
        guard !isReadOnlyDueToLoadFailure else { return }
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
        // Applies arrive in ascending day order; the day list is newest-first.
        entries.sort { $0.date > $1.date }
        persist()
        remoteEntryDidApply.send(
            JournalRemoteApply(journalID: journalID, entryID: applied.id)
        )
    }

    /// Renames the active journal to the remote manifest's name, returning the
    /// name actually applied (uniquified against OTHER local journals). The
    /// engine records the result as its rename baseline.
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
        return resolved
    }

    func removeSyncedEntry(entryID: UUID, journalID: UUID) {
        guard journalID == activeJournalID else { return }
        guard !isReadOnlyDueToLoadFailure else { return }
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
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
        guard let url = imageURL(for: filename) else { return nil }
        return try? Data(contentsOf: url)
    }

    func hasSyncedImage(filename: String) -> Bool {
        guard let url = imageURL(for: filename) else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    func storeSyncedImage(filename: String, data: Data, journalID: UUID) {
        guard journalID == activeJournalID else { return }
        guard !isReadOnlyDueToLoadFailure else { return }
        guard let url = imageURL(for: filename) else { return }
        try? data.write(to: url, options: .atomic)
    }

    var syncTradingSnapshotEnabled: Bool {
        PhoneExchangeCoordinator.shared.cloudSyncEnabled
    }

    func syncedTradingSnapshot(journalID: UUID) -> JournalTradingSnapshotDocument? {
        PhoneExchangeCoordinator.shared.cloudSnapshotDocument(for: journalID)
    }

    func applySyncedTradingSnapshot(_ document: JournalTradingSnapshotDocument, journalID: UUID) {
        PhoneExchangeCoordinator.shared.applyCloudSnapshotDocument(document, journalID: journalID)
    }

    func removeSyncedTradingSnapshot(journalID: UUID) {
        PhoneExchangeCoordinator.shared.removeCloudSnapshot(for: journalID)
    }
}

/// Errors from the iPhone journal store's explicit recovery paths.
enum PhoneJournalStoreError: LocalizedError {
    case freshStartWriteFailed
    case importInvalid
    case unsupportedSnapshotVersion(Int)
    case catalogRecoveryFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .freshStartWriteFailed:
            return "无法写入新的日记库，已保持只读保护"
        case .importInvalid:
            return "导入文件无效，日记库保持只读保护"
        case .unsupportedSnapshotVersion(let version):
            return "导入文件由更新版本写入（v\(version)），无法覆盖当前数据"
        case .catalogRecoveryFailed:
            return "无法恢复日记库，原数据保持只读保护"
        case .writeFailed:
            return "无法写入导入内容，原日记仍保留"
        }
    }
}
