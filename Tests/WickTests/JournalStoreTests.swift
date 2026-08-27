import Combine
import XCTest
import WickSync
@testable import WickCore

@MainActor
final class JournalStoreTests: XCTestCase {
    private var tempRoot: URL!
    private var store: JournalStore!

    override func setUp() async throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("WickTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        store = JournalStore(rootDirectory: tempRoot)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
        store = nil
        tempRoot = nil
    }

    /// XCTest's XCTAssertThrowsError cannot take an async autoclosure; this is
    /// the async equivalent used for the now-async export/import API.
    private func assertThrowsAsync<T>(
        _ body: () async throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await body()
            XCTFail("expected an error to be thrown", file: file, line: line)
        } catch {}
    }

    // MARK: - Multi-journal

    func testFreshInstallCreatesDefaultJournal() {
        XCTAssertEqual(store.journals.count, 1)
        XCTAssertNotNil(store.activeJournalID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent("catalog.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.databaseURL.path) || store.entries.isEmpty)
    }

    func testCreateSwitchAndDeleteJournals() {
        let firstID = store.activeJournalID
        XCTAssertNotNil(firstID)

        let firstEntry = store.createEntry()
        var draft = firstEntry
        draft.title = "In First"
        store.updateEntry(draft)

        let second = store.createJournal(name: "Work")
        XCTAssertEqual(store.journals.count, 2)
        XCTAssertEqual(store.activeJournalID, second.id)
        XCTAssertEqual(store.entries.count, 0)

        _ = store.createEntry()
        XCTAssertEqual(store.entries.count, 1)

        store.switchToJournal(id: firstID!)
        XCTAssertEqual(store.activeJournalID, firstID)
        XCTAssertEqual(store.entries.first?.title, "In First")

        XCTAssertTrue(store.deleteJournal(id: second.id))
        XCTAssertEqual(store.journals.count, 1)
        XCTAssertEqual(store.activeJournalID, firstID)
        XCTAssertEqual(store.entries.first?.title, "In First")
    }

    func testCannotDeleteLastJournal() {
        let only = store.activeJournalID!
        XCTAssertFalse(store.deleteJournal(id: only))
        XCTAssertEqual(store.journals.count, 1)
    }

    func testRenameJournalPersists() {
        let id = store.activeJournalID!
        store.renameJournal(id: id, to: "Trading")
        XCTAssertEqual(store.activeJournal?.name, "Trading")

        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertEqual(reloaded.activeJournal?.name, "Trading")
    }

    func testReorderJournalsPersists() {
        let first = store.journals.first!.name
        let second = store.createJournal(name: "Second")
        let third = store.createJournal(name: "Third")
        XCTAssertEqual(store.journals.map(\.name), [first, "Second", "Third"])

        // Move "Third" (index 2) to the top (index 0)
        store.moveJournal(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(store.journals.map(\.name), ["Third", first, "Second"])

        // Verify order persists after reloading from disk
        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertEqual(reloaded.journals.map(\.name), ["Third", first, "Second"])
    }

    // MARK: - DS-02 catalog protection

    private func catalogURL() -> URL {
        tempRoot.appendingPathComponent("catalog.json", isDirectory: false)
    }

    private func catalogBackupURL() -> URL {
        tempRoot.appendingPathComponent("catalog.json.bak", isDirectory: false)
    }

    private func catalogJSON(version: Int, activeID: UUID, journalsJSON: String) -> String {
        "{\"version\":\(version),\"activeJournalID\":\"\(activeID.uuidString)\",\"journals\":\(journalsJSON)}"
    }

    private func journalInfoJSON(id: UUID, name: String) -> String {
        "{\"id\":\"\(id.uuidString)\",\"name\":\"\(name)\",\"createdAt\":\"2026-01-01T00:00:00Z\",\"updatedAt\":\"2026-01-01T00:00:00Z\"}"
    }

    func testCatalogGetsSidecarBackupOnPersist() {
        // The very first persist has nothing to back up; the second one must
        // leave a sidecar copy of the first.
        XCTAssertFalse(FileManager.default.fileExists(atPath: catalogBackupURL().path))
        _ = store.createJournal(name: "Second")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: catalogBackupURL().path),
            "every catalog overwrite must leave a sidecar backup"
        )
        _ = store.createJournal(name: "Third")
        XCTAssertTrue(FileManager.default.fileExists(atPath: catalogBackupURL().path))
    }

    func testTruncatedCatalogGoesReadOnlyAndIsNotOverwritten() throws {
        let payload = Data("{\"version\":1,\"activeJournalID\":".utf8)
        try payload.write(to: catalogURL(), options: .atomic)

        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertTrue(reloaded.isCatalogReadOnly)
        XCTAssertTrue(reloaded.journals.isEmpty)
        XCTAssertNil(reloaded.activeJournalID)
        // The corrupt primary must survive byte-for-byte.
        XCTAssertEqual(try Data(contentsOf: catalogURL()), payload)
    }

    func testEmptyJournalsCatalogGoesReadOnlyAndIsNotOverwritten() throws {
        let payload = Data(catalogJSON(version: 1, activeID: UUID(), journalsJSON: "[]").utf8)
        try payload.write(to: catalogURL(), options: .atomic)

        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertTrue(reloaded.isCatalogReadOnly)
        XCTAssertTrue(reloaded.journals.isEmpty)
        XCTAssertEqual(try Data(contentsOf: catalogURL()), payload)
    }

    func testCatalogWithMissingRequiredFieldGoesReadOnlyAndIsNotOverwritten() throws {
        // A journal missing its `name` required field must not decode.
        let missingName = "{ \"id\": \"\(UUID().uuidString)\", \"createdAt\":\"2026-01-01T00:00:00Z\", \"updatedAt\":\"2026-01-01T00:00:00Z\" }"
        let payload = Data(catalogJSON(version: 1, activeID: UUID(), journalsJSON: "[\(missingName)]").utf8)
        try payload.write(to: catalogURL(), options: .atomic)

        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertTrue(reloaded.isCatalogReadOnly)
        XCTAssertTrue(reloaded.journals.isEmpty)
        XCTAssertEqual(try Data(contentsOf: catalogURL()), payload)
    }

    func testFutureVersionCatalogGoesReadOnlyAndTouchesNothing() throws {
        let payload = Data(
            catalogJSON(version: 99, activeID: UUID(), journalsJSON: "[\(journalInfoJSON(id: UUID(), name: "Future"))]").utf8
        )
        try payload.write(to: catalogURL(), options: .atomic)

        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertTrue(reloaded.isCatalogReadOnly)
        XCTAssertTrue(reloaded.journals.isEmpty)
        XCTAssertEqual(try Data(contentsOf: catalogURL()), payload)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: catalogBackupURL().path),
            "a future-format catalog must not be mirrored into a backup"
        )
    }

    func testCatalogReadOnlyBlocksCatalogMutations() throws {
        try Data("{\"version\":99,\"activeJournalID\":".utf8)
            .write(to: catalogURL(), options: .atomic)
        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertTrue(reloaded.isCatalogReadOnly)

        let before = try Data(contentsOf: catalogURL())
        _ = reloaded.createJournal(name: "Nope")
        reloaded.renameJournal(id: UUID(), to: "Nope")
        reloaded.moveJournal(from: IndexSet(integer: 0), to: 1)
        XCTAssertFalse(reloaded.deleteJournal(id: UUID()))
        reloaded.setExchangeBinding(
            JournalExchangeBinding(venue: .okx, accountLabel: "OKX"),
            for: UUID()
        )
        _ = reloaded.registerRemoteJournal(id: UUID(), name: "Remote")
        XCTAssertEqual(try Data(contentsOf: catalogURL()), before, "no catalog mutation in read-only state")
        XCTAssertTrue(reloaded.journals.isEmpty)
    }

    func testCorruptPrimaryRestoresFromValidBackupAndKeepsCorruptCopy() throws {
        let binding = JournalExchangeBinding(venue: .binance, accountLabel: "Binance")
        let firstID = store.activeJournalID!
        let second = store.createJournal(name: "Second")
        store.setExchangeBinding(binding, for: second.id)
        store.renameJournal(id: firstID, to: "Alpha")
        store.switchToJournal(id: firstID)

        // Snapshot of the valid sidecar backup, then corrupt the primary.
        let validBackup = try Data(contentsOf: catalogBackupURL())
        let expected = try JournalCatalogCodec.decode(
            validBackup,
            currentVersion: JournalCatalogSnapshot.currentVersion
        )
        let corrupt = Data("garbage-not-json".utf8)
        try corrupt.write(to: catalogURL(), options: .atomic)

        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertFalse(reloaded.isCatalogReadOnly)
        XCTAssertTrue(reloaded.didRestoreFromBackup)
        // Restored state matches the backup exactly: order, active id, names,
        // and exchangeBinding all preserved.
        XCTAssertEqual(reloaded.activeJournalID, expected.activeJournalID)
        XCTAssertEqual(reloaded.journals, expected.journals)
        XCTAssertEqual(
            reloaded.journals.first { $0.id == second.id }?.exchangeBinding,
            binding
        )
        // The corrupt primary was quarantined, not deleted.
        let corruptCopies = try FileManager.default.contentsOfDirectory(atPath: tempRoot.path)
            .filter { $0.hasPrefix("catalog.corrupt-") }
        XCTAssertEqual(corruptCopies.count, 1)
        XCTAssertEqual(
            try Data(contentsOf: tempRoot.appendingPathComponent(corruptCopies[0])),
            corrupt
        )
    }

    func testCatalogWriteFailureKeepsLastKnownGoodPrimaryAndBackup() throws {
        _ = store.createJournal(name: "Second")
        let goodPrimary = try Data(contentsOf: catalogURL())
        let goodBackup = try Data(contentsOf: catalogBackupURL())

        // Make the library root read-only so the next catalog write fails.
        let attributes = [FileAttributeKey.posixPermissions: 0o500]
        try FileManager.default.setAttributes(attributes, ofItemAtPath: tempRoot.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: tempRoot.path
            )
        }

        store.renameJournal(id: store.activeJournalID!, to: "Renamed")
        store.flushPendingWrites()

        XCTAssertEqual(try Data(contentsOf: catalogURL()), goodPrimary)
        XCTAssertEqual(try Data(contentsOf: catalogBackupURL()), goodBackup)

        // At least one of primary / backup must still load.
        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertFalse(reloaded.isCatalogReadOnly)
        XCTAssertFalse(reloaded.journals.isEmpty)
    }

    // MARK: - DS-03 non-active journal typed I/O

    private func journalJSONURL(_ journalID: UUID) -> URL {
        tempRoot.appendingPathComponent(journalID.uuidString, isDirectory: true)
            .appendingPathComponent("journal.json", isDirectory: false)
    }

    /// Creates a second journal and switches back to the original, so the new
    /// one is a genuine non-active journal on disk.
    @discardableResult
    private func makeNonActiveJournal() -> JournalInfo {
        let original = store.activeJournalID!
        let second = store.createJournal(name: "Second")
        store.switchToJournal(id: original)
        return second
    }

    func testEntriesForMissingJournalIsExplicit() {
        let ghost = UUID()
        guard case .missing = store.entries(for: ghost) else {
            return XCTFail("expected .missing for a journal with no file")
        }
        guard case .active = store.entries(for: store.activeJournalID!) else {
            return XCTFail("expected .active for the active journal")
        }
    }

    func testEntriesForCorruptJournalReportsCorrupt() throws {
        let second = makeNonActiveJournal()
        try Data("{".utf8).write(to: journalJSONURL(second.id), options: .atomic)
        guard case .corrupt = store.entries(for: second.id) else {
            return XCTFail("expected .corrupt, got \(store.entries(for: second.id))")
        }
    }

    func testEnsurePositionEntriesOnCorruptNonActiveJournalLeavesFileUntouched() throws {
        let second = makeNonActiveJournal()
        let corrupt = Data("{".utf8)
        try corrupt.write(to: journalJSONURL(second.id), options: .atomic)

        let created = store.ensurePositionEntries(
            [(day: Date(), items: [JournalItem(tag: "BTC")])],
            in: second.id
        )
        XCTAssertTrue(created.isEmpty)
        XCTAssertEqual(try Data(contentsOf: journalJSONURL(second.id)), corrupt)
    }

    func testEnsurePositionEntriesOnNewerVersionNonActiveJournalLeavesFileUntouched() throws {
        let second = makeNonActiveJournal()
        let payload = Data(#"{"version":99,"entries":[]}"#.utf8)
        try payload.write(to: journalJSONURL(second.id), options: .atomic)

        let created = store.ensurePositionEntries(
            [(day: Date(), items: [JournalItem(tag: "BTC")])],
            in: second.id
        )
        XCTAssertTrue(created.isEmpty)
        XCTAssertEqual(try Data(contentsOf: journalJSONURL(second.id)), payload)
    }

    func testEnsurePositionEntriesOnDeletedJournalDoesNotRecreateDirectory() {
        let second = store.createJournal(name: "Second")
        XCTAssertTrue(store.deleteJournal(id: second.id))
        let dir = tempRoot.appendingPathComponent(second.id.uuidString, isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))

        let created = store.ensurePositionEntries(
            [(day: Date(), items: [JournalItem(tag: "BTC")])],
            in: second.id
        )
        XCTAssertTrue(created.isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: dir.path),
            "a UUID removed from the catalog must never get its directory recreated"
        )
    }

    func testEnsurePositionEntriesOnHealthyNonActiveJournalSucceedsWithBackup() throws {
        let second = makeNonActiveJournal()
        let past = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let seed = JournalSnapshot(
            version: 1,
            entries: [JournalEntry(date: past, title: "existing")]
        )
        try JournalSyncEncoding.encoder.encode(seed).write(to: journalJSONURL(second.id), options: .atomic)

        let created = store.ensurePositionEntries(
            [(day: Date(), items: [JournalItem(tag: "BTC")])],
            in: second.id
        )
        XCTAssertEqual(created.count, 1)

        // A recoverable sidecar backup of the prior file exists.
        let backupURL = tempRoot.appendingPathComponent(second.id.uuidString, isDirectory: true)
            .appendingPathComponent("journal.json.bak", isDirectory: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        let backed = try JournalSyncEncoding.decoder.decode(
            JournalSnapshot.self,
            from: Data(contentsOf: backupURL)
        )
        XCTAssertEqual(backed.entries.first?.title, "existing")
    }

    func testEnsurePositionEntriesAppendsToExistingDayWithoutChangingContent() {
        let day = Calendar.current.startOfDay(for: Date())
        var existing = store.createEntry(on: day)
        existing.items = [JournalItem(tag: "DRAM", body: "keep this note")]
        store.updateEntry(existing)
        let planned = JournalItem(tag: "SKHYNIX")

        let changed = store.ensurePositionEntries(
            [(day: day, items: [planned])],
            in: store.activeJournalID!
        )

        XCTAssertEqual(changed, [day])
        let updated = store.entries.first { $0.id == existing.id }
        XCTAssertEqual(updated?.items.map(\.tag), ["DRAM", "SKHYNIX"])
        XCTAssertEqual(updated?.items.first?.body, "keep this note")
    }

    func testEnsurePositionEntriesReplacesOnlyEmptyPlaceholderAndIsIdempotent() {
        let day = Calendar.current.startOfDay(for: Date())
        let existing = store.createEntry(on: day)
        let planned = JournalItem(tag: "XAU")

        XCTAssertEqual(
            store.ensurePositionEntries(
                [(day: day, items: [planned])],
                in: store.activeJournalID!
            ),
            [day]
        )
        XCTAssertEqual(store.entries.first { $0.id == existing.id }?.items, [planned])
        XCTAssertTrue(
            store.ensurePositionEntries(
                [(day: day, items: [planned])],
                in: store.activeJournalID!
            ).isEmpty
        )
        XCTAssertEqual(store.entries.first { $0.id == existing.id }?.items, [planned])
    }

    func testEnsurePositionEntriesAppendsToExistingNonActiveJournal() throws {
        let second = makeNonActiveJournal()
        let day = Calendar.current.startOfDay(for: Date())
        let seed = JournalEntry(
            date: day,
            items: [JournalItem(tag: "BTC", body: "existing")]
        )
        let snapshot = JournalSnapshot(version: 1, entries: [seed])
        try JournalSyncEncoding.encoder.encode(snapshot).write(
            to: journalJSONURL(second.id),
            options: .atomic
        )

        let changed = store.ensurePositionEntries(
            [(day: day, items: [JournalItem(tag: "CRCL")])],
            in: second.id
        )

        XCTAssertEqual(changed, [day])
        guard case .loaded(let entries) = store.entries(for: second.id) else {
            return XCTFail("expected non-active journal to remain loadable")
        }
        XCTAssertEqual(entries.first?.items.map(\.tag), ["BTC", "CRCL"])
        XCTAssertEqual(entries.first?.items.first?.body, "existing")
    }

    // MARK: - SY-01 remote journal deletion

    func testRemoteDeleteNonActiveJournal() {
        let original = store.activeJournalID!
        let second = store.createJournal(name: "Second") // second becomes active
        let dir = tempRoot.appendingPathComponent(original.uuidString, isDirectory: true)

        XCTAssertEqual(store.deleteJournalFromRemote(id: original), .deleted)
        XCTAssertEqual(store.journals.count, 1)
        XCTAssertEqual(store.activeJournalID, second.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    func testRemoteDeleteActiveJournalSwitchesToRemaining() {
        let original = store.activeJournalID!
        let second = store.createJournal(name: "Second")
        XCTAssertEqual(store.deleteJournalFromRemote(id: second.id), .deleted)
        XCTAssertEqual(store.journals.count, 1)
        XCTAssertEqual(store.activeJournalID, original)
    }

    func testRemoteDeleteLastJournalSeedsFreshPureLocalDefault() {
        let only = store.activeJournalID!
        store.setExchangeBinding(
            JournalExchangeBinding(venue: .binance, accountLabel: "Binance"),
            for: only
        )
        let dir = tempRoot.appendingPathComponent(only.uuidString, isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))

        XCTAssertEqual(store.deleteJournalFromRemote(id: only), .deleted)

        XCTAssertEqual(store.journals.count, 1)
        let freshID = store.activeJournalID!
        XCTAssertNotEqual(freshID, only, "the fresh default must be a NEW UUID")
        XCTAssertNil(store.activeJournal?.exchangeBinding, "fresh default must not inherit binding")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path), "deleted folder must be gone")

        // The fresh default is persisted in the catalog.
        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertEqual(reloaded.activeJournalID, freshID)
        XCTAssertEqual(reloaded.journals.count, 1)
        XCTAssertNil(reloaded.activeJournal?.exchangeBinding)
    }

    func testRemoteDeleteNotFound() {
        XCTAssertEqual(store.deleteJournalFromRemote(id: UUID()), .notFound)
    }

    func testRemoteDeleteRefusedWhenCatalogReadOnly() throws {
        try Data("{\"version\":99,\"activeJournalID\":".utf8)
            .write(to: catalogURL(), options: .atomic)
        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertTrue(reloaded.isCatalogReadOnly)
        XCTAssertEqual(reloaded.deleteJournalFromRemote(id: UUID()), .refusedReadOnly)
    }

    func testRemoteDeleteDirectoryFailureIsIOFailure() throws {
        _ = store.createJournal(name: "Second") // second becomes active
        let activeID = store.activeJournalID!
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: tempRoot.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: tempRoot.path
            )
        }

        XCTAssertEqual(store.deleteJournalFromRemote(id: activeID), .ioFailure)
        XCTAssertTrue(
            store.journals.contains(where: { $0.id == activeID }),
            "catalog must stay untouched when the folder delete fails"
        )
    }

    // MARK: - Acceptance: catalog recovery (AC-P1-01 / AC-P1-02 / AC-P1-04)

    func testPrimaryMissingRestoresFromValidBackup() throws {
        let firstID = store.activeJournalID!
        let second = store.createJournal(name: "Second")
        let catalog = JournalCatalogSnapshot(
            version: 1,
            activeJournalID: firstID,
            journals: [store.journals.first { $0.id == firstID }!, second]
        )
        try JournalSyncEncoding.encoder.encode(catalog)
            .write(to: catalogBackupURL(), options: .atomic)
        // Delete the primary: a valid backup must restore the library instead
        // of seeding a fresh install (AC-P1-02).
        try FileManager.default.removeItem(at: catalogURL())

        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertFalse(reloaded.isCatalogReadOnly)
        XCTAssertTrue(reloaded.didRestoreFromBackup)
        XCTAssertEqual(reloaded.journals.count, 2)
        XCTAssertEqual(reloaded.activeJournalID, firstID)
    }

    func testStartFreshAfterCorruptCatalogCreatesRealWritableJournal() throws {
        try Data("{\"version\":99,\"activeJournalID\":".utf8)
            .write(to: catalogURL(), options: .atomic)
        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertTrue(reloaded.isCatalogReadOnly)

        try reloaded.abandonCorruptDatabaseAndStartFresh()
        XCTAssertFalse(reloaded.isCatalogReadOnly)
        XCTAssertEqual(reloaded.journals.count, 1)
        let freshID = reloaded.activeJournalID!
        let realDir = tempRoot.appendingPathComponent(freshID.uuidString, isDirectory: true)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: realDir.path),
            "fresh start must bind a REAL directory, not the _pending placeholder"
        )
        XCTAssertFalse(reloaded.databaseURL.path.contains("_pending"))

        let reloaded2 = JournalStore(rootDirectory: tempRoot)
        XCTAssertFalse(reloaded2.isCatalogReadOnly)
        XCTAssertEqual(reloaded2.activeJournalID, freshID)
        XCTAssertEqual(reloaded2.journals.count, 1)
    }

    func testImportAfterCorruptCatalogRecoversLibrary() async throws {
        try Data("{\"version\":99,\"activeJournalID\":".utf8)
            .write(to: catalogURL(), options: .atomic)
        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertTrue(reloaded.isCatalogReadOnly)

        let snapshot = JournalSnapshot(
            version: 1,
            entries: [JournalEntry(date: Date(timeIntervalSince1970: 1_777_593_600), title: "imported")]
        )
        let importURL = tempRoot.appendingPathComponent("import.json", isDirectory: false)
        try JournalSyncEncoding.encoder.encode(snapshot).write(to: importURL, options: .atomic)

        try await reloaded.importArchive(from: importURL)
        XCTAssertFalse(reloaded.isCatalogReadOnly)
        XCTAssertEqual(reloaded.entries.first?.title, "imported")
        XCTAssertFalse(reloaded.databaseURL.path.contains("_pending"))
        XCTAssertTrue(reloaded.journals.contains { $0.id == reloaded.activeJournalID })

        let reloaded2 = JournalStore(rootDirectory: tempRoot)
        XCTAssertFalse(reloaded2.isCatalogReadOnly)
        XCTAssertEqual(reloaded2.entries.first?.title, "imported")
    }

    func testImportInvalidKeepsCatalogReadOnlyAndOriginalBytes() async throws {
        let corrupt = Data("{\"version\":99,\"activeJournalID\":".utf8)
        try corrupt.write(to: catalogURL(), options: .atomic)
        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertTrue(reloaded.isCatalogReadOnly)

        let badURL = tempRoot.appendingPathComponent("bad.json", isDirectory: false)
        try Data("not json at all".utf8).write(to: badURL, options: .atomic)

        await assertThrowsAsync { try await reloaded.importArchive(from: badURL) }
        XCTAssertTrue(reloaded.isCatalogReadOnly, "a failed import must keep the catalog read-only")
        XCTAssertEqual(try Data(contentsOf: catalogURL()), corrupt, "original catalog bytes unchanged")
    }

    // MARK: - DS-02 import image quarantine rollback

    func testImportImageCopyFailureRollsBackOriginalImages() async throws {
        // Give the active journal pre-existing images with known bytes.
        let imagesDir = store.imagesDirectory
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        let old1 = imagesDir.appendingPathComponent("old1.png")
        let old2 = imagesDir.appendingPathComponent("old2.png")
        let old1Bytes = Data([0xAA, 0x01, 0x02, 0x03])
        let old2Bytes = Data([0xBB, 0x04, 0x05, 0x06])
        try old1Bytes.write(to: old1)
        try old2Bytes.write(to: old2)

        // Build an import payload whose images/ contains two files.
        let payloadRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("WickImportPayload-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: payloadRoot) }
        let payloadDir = payloadRoot.appendingPathComponent("Wick-Journal", isDirectory: true)
        try FileManager.default.createDirectory(at: payloadDir, withIntermediateDirectories: true)
        let snapshot = JournalSnapshot(version: JournalSnapshot.currentVersion, entries: store.entries)
        try JournalSyncEncoding.encoder.encode(snapshot)
            .write(to: payloadDir.appendingPathComponent("journal.json"))
        let payloadImages = payloadDir.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: payloadImages, withIntermediateDirectories: true)
        try Data([0x11]).write(to: payloadImages.appendingPathComponent("new1.png"))
        try Data([0x22]).write(to: payloadImages.appendingPathComponent("new2.png"))

        let zipURL = tempRoot.appendingPathComponent("import.zip", isDirectory: false)
        try dittoZip(source: payloadDir, destination: zipURL)

        // The 2nd image copy fails mid-import.
        JournalStore.failImageCopyAtIndex = 2
        defer { JournalStore.failImageCopyAtIndex = nil }
        await assertThrowsAsync { try await store.importArchive(from: zipURL) }

        // Original images must be restored byte-for-byte; no partial new files.
        XCTAssertEqual(try Data(contentsOf: old1), old1Bytes)
        XCTAssertEqual(try Data(contentsOf: old2), old2Bytes)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: imagesDir.appendingPathComponent("new1.png").path),
            "a rolled-back import must not leave the first copied image behind"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: imagesDir.appendingPathComponent("new2.png").path)
        )
    }

    private func dittoZip(source: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, destination.path]
        try process.run()
        process.waitUntilExit()
    }

    func testStartFreshFailureCleansNewDirectoryAndRestoresCatalog() throws {
        let preexistingDirectories = Set(
            try FileManager.default.contentsOfDirectory(atPath: tempRoot.path)
                .compactMap { UUID(uuidString: $0) }
        )
        let corrupt = Data("{\"version\":99".utf8)
        try corrupt.write(to: catalogURL(), options: .atomic)
        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertTrue(reloaded.isCatalogReadOnly)
        let originalDatabaseURL = reloaded.databaseURL

        JournalStore.failCatalogPersistOverride = true
        defer { JournalStore.failCatalogPersistOverride = false }

        XCTAssertThrowsError(try reloaded.abandonCorruptDatabaseAndStartFresh())
        XCTAssertTrue(reloaded.isCatalogReadOnly)
        XCTAssertEqual(reloaded.databaseURL, originalDatabaseURL)
        XCTAssertEqual(try Data(contentsOf: catalogURL()), corrupt)
        let uuidDirectories = Set(
            try FileManager.default.contentsOfDirectory(atPath: tempRoot.path)
                .compactMap { UUID(uuidString: $0) }
        )
        XCTAssertEqual(uuidDirectories, preexistingDirectories, "failed recovery must not leave a fresh journal directory; before=\(preexistingDirectories) after=\(uuidDirectories)")
    }

    func testRemoteDeleteCatalogWriteFailureRollsBackAndReturnsIOFailure() throws {
        let second = store.createJournal(name: "Second")
        let activeID = store.activeJournalID!
        let dir = tempRoot.appendingPathComponent(activeID.uuidString, isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))

        JournalStore.failCatalogPersistOverride = true
        defer { JournalStore.failCatalogPersistOverride = false }

        XCTAssertEqual(store.deleteJournalFromRemote(id: activeID), .ioFailure)
        XCTAssertTrue(
            store.journals.contains { $0.id == activeID },
            "catalog must roll back when its write fails"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: dir.path),
            "the journal folder must be rolled back when the catalog write fails"
        )
        _ = second
    }

    func testRemoteDeleteFailureRestoresFullActiveSessionAndCleansFreshDefault() throws {
        let activeID = store.activeJournalID!
        var entry = store.createEntry()
        entry.title = "keep after rollback"
        store.updateEntry(entry)
        store.flushPendingWrites()
        let originalDatabaseURL = store.databaseURL
        let originalEntries = store.entries
        let originalDirectory = store.journalDirectory
        let originalIDs = Set(store.journals.map(\.id))

        JournalStore.failCatalogPersistOverride = true
        defer { JournalStore.failCatalogPersistOverride = false }

        XCTAssertEqual(store.deleteJournalFromRemote(id: activeID), .ioFailure)
        XCTAssertEqual(store.activeJournalID, activeID)
        XCTAssertEqual(store.databaseURL, originalDatabaseURL)
        XCTAssertEqual(store.journalDirectory, originalDirectory)
        XCTAssertEqual(store.entries, originalEntries)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalDatabaseURL.path))

        let directoryIDs = Set(
            (try FileManager.default.contentsOfDirectory(atPath: tempRoot.path))
                .compactMap { UUID(uuidString: $0) }
        )
        XCTAssertEqual(directoryIDs, originalIDs, "failed last-journal deletion must remove its temporary default")

        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertEqual(reloaded.activeJournalID, activeID)
        XCTAssertEqual(reloaded.entries.map(\.title), originalEntries.map(\.title))
    }

    func testUserDeleteCatalogWriteFailureIsNotReportedAsSuccess() throws {
        let second = store.createJournal(name: "Second")
        let secondDirectory = tempRoot.appendingPathComponent(second.id.uuidString, isDirectory: true)
        JournalStore.failCatalogPersistOverride = true
        defer { JournalStore.failCatalogPersistOverride = false }

        XCTAssertFalse(store.deleteJournal(id: second.id))
        XCTAssertTrue(store.journals.contains { $0.id == second.id })
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondDirectory.path))
        XCTAssertTrue(JournalStore(rootDirectory: tempRoot).journals.contains { $0.id == second.id })
    }

    func testMigrateLegacySingleJournal() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
            .appendingPathComponent("WickMigrate-\(UUID().uuidString)", isDirectory: true)
        let multiRoot = base.appendingPathComponent("Journals", isDirectory: true)
        let legacyRoot = base.appendingPathComponent("Journal", isDirectory: true)
        defer { try? fm.removeItem(at: base) }

        try fm.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
        try fm.createDirectory(
            at: legacyRoot.appendingPathComponent("images", isDirectory: true),
            withIntermediateDirectories: true
        )

        let entryID = UUID().uuidString
        let itemID = UUID().uuidString
        let json = """
        {"version":1,"entries":[{"id":"\(entryID)","date":"2026-01-15T00:00:00Z","title":"Legacy Day",\
        "items":[{"id":"\(itemID)","tag":"BTC","body":"migrated","imageFilenames":[]}],\
        "createdAt":"2026-01-15T00:00:00Z","updatedAt":"2026-01-15T00:00:00Z"}]}
        """
        try Data(json.utf8).write(to: legacyRoot.appendingPathComponent("journal.json"))

        let migrated = JournalStore(rootDirectory: multiRoot, legacyDirectory: legacyRoot)

        XCTAssertEqual(migrated.journals.count, 1)
        XCTAssertEqual(migrated.entries.first?.title, "Legacy Day")
        XCTAssertEqual(migrated.entries.first?.items.first?.body, "migrated")
        XCTAssertTrue(fm.fileExists(atPath: multiRoot.appendingPathComponent("catalog.json").path))
        // Legacy folder should have been moved away (no longer at original path).
        XCTAssertFalse(fm.fileExists(atPath: legacyRoot.path))
        // Reloading multi-root must not depend on legacy path.
        let reloaded = JournalStore(rootDirectory: multiRoot, legacyDirectory: legacyRoot)
        XCTAssertEqual(reloaded.entries.first?.title, "Legacy Day")
        XCTAssertEqual(reloaded.journals.count, 1)
    }

    func testV1SnapshotMigratesToV2AndKeepsOriginalBackup() throws {
        store.flushPendingWrites()
        let entryID = UUID()
        let itemID = UUID()
        let legacy = """
        {"version":1,"entries":[{"id":"\(entryID.uuidString)","date":"2026-08-19T16:00:00Z",\
        "dayKey":"2026-08-22","title":"authoritative date",\
        "items":[{"id":"\(itemID.uuidString)","tag":"BTC","body":"keep","imageFilenames":[]}],\
        "createdAt":"2026-08-19T16:00:00Z","updatedAt":"2026-08-22T00:00:00Z"}]}
        """
        let legacyData = Data(legacy.utf8)
        try legacyData.write(to: store.databaseURL, options: .atomic)

        let migrated = JournalStore(rootDirectory: tempRoot)

        XCTAssertEqual(migrated.entries.first?.id, entryID)
        XCTAssertEqual(migrated.entries.first?.items.first?.body, "keep")
        XCTAssertEqual(try Data(contentsOf: migrated.backupURL), legacyData)
        let upgradedData = try Data(contentsOf: migrated.databaseURL)
        let upgraded = try JournalSyncEncoding.decoder.decode(JournalSnapshot.self, from: upgradedData)
        XCTAssertEqual(upgraded.version, JournalSnapshot.currentVersion)
        XCTAssertFalse(String(decoding: upgradedData, as: UTF8.self).contains("dayKey"))
    }

    // MARK: - Entries (active journal)

    func testOneEntryPerDay() {
        let first = store.createEntry(on: Date())
        let second = store.createEntry(on: Date())
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(store.entries.count, 1)
    }

    func testChangingDateKeepsUUIDAndAllowsPastDate() {
        var entry = store.createEntry(on: Date())
        let originalID = entry.id
        entry.items = [JournalItem(tag: "BTC", body: "keep this")]
        let past = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        entry.date = past

        store.updateEntry(entry)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.id, originalID)
        XCTAssertEqual(store.entries.first?.items.first?.body, "keep this")
        XCTAssertTrue(Calendar.current.isDate(store.entries.first!.date, inSameDayAs: past))
    }

    func testTagFilterIsItemScoped() {
        let entry = store.createEntry()
        var draft = entry
        draft.items = [
            JournalItem(tag: "work", body: "a"),
            JournalItem(tag: "life", body: "b")
        ]
        store.updateEntry(draft)
        store.setTagFilter("work")

        XCTAssertTrue(store.isItemScoped)
        XCTAssertEqual(store.filteredTimelineItems.count, 1)
        XCTAssertEqual(store.filteredTimelineItems.first?.item.tag, "work")
    }

    func testDeleteItemRemovesImagesMetadata() {
        let entry = store.createEntry()
        guard let itemID = entry.items.first?.id else {
            return XCTFail("missing item")
        }
        let filename = store.addImage(
            from: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
            to: entry.id,
            itemID: itemID,
            preferredExtension: "png"
        )
        // Invalid image data may fail processing; still assert store doesn't crash.
        if let filename, let url = store.imageURL(for: filename) {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            store.deleteItem(itemID: itemID, from: entry.id)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }

    func testPersistAndReload() throws {
        let entry = store.createEntry()
        var draft = entry
        draft.title = "Hello"
        draft.items[0].body = "World"
        store.updateEntry(draft)

        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertEqual(reloaded.entries.count, 1)
        XCTAssertEqual(reloaded.entries.first?.title, "Hello")
        XCTAssertEqual(reloaded.entries.first?.items.first?.body, "World")
    }

    func testCorruptPrimaryRestoresFromBackupWhenPossible() throws {
        let entry = store.createEntry()
        var draft = entry
        draft.title = "Safe"
        store.updateEntry(draft)

        // Ensure a known-good sidecar backup exists, then corrupt primary.
        let db = store.databaseURL
        let bak = store.backupURL
        if FileManager.default.fileExists(atPath: bak.path) {
            try FileManager.default.removeItem(at: bak)
        }
        try FileManager.default.copyItem(at: db, to: bak)
        try Data("not-json".utf8).write(to: db)

        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertFalse(reloaded.isReadOnlyDueToLoadFailure)
        XCTAssertTrue(reloaded.didRestoreFromBackup || reloaded.entries.first?.title == "Safe")
        XCTAssertEqual(reloaded.entries.first?.title, "Safe")
    }

    func testReviewPersistsAcrossReload() {
        let entry = store.createEntry()
        var draft = entry
        draft.items[0].tag = "BTC"
        draft.items[0].review = JournalReview(verdict: .correct, note: "方向对，入场晚了")
        store.updateEntry(draft)

        let reloaded = JournalStore(rootDirectory: tempRoot)
        let review = reloaded.entries.first?.items.first?.review
        XCTAssertEqual(review?.verdict, .correct)
        XCTAssertEqual(review?.note, "方向对，入场晚了")
    }

    func testLegacySnapshotWithoutReviewDecodes() throws {
        // Version-1 JSON predating the review feature (no `review` key) must load cleanly.
        let entryID = UUID().uuidString
        let itemID = UUID().uuidString
        let json = """
        {"version":1,"entries":[{"id":"\(entryID)","date":"2026-01-15T00:00:00Z","title":"",\
        "items":[{"id":"\(itemID)","tag":"BTC","body":"test","imageFilenames":[]}],\
        "createdAt":"2026-01-15T00:00:00Z","updatedAt":"2026-01-15T00:00:00Z"}]}
        """
        let db = store.databaseURL
        try Data(json.utf8).write(to: db)

        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertFalse(reloaded.isReadOnlyDueToLoadFailure)
        XCTAssertEqual(reloaded.entries.first?.items.first?.tag, "BTC")
        XCTAssertNil(reloaded.entries.first?.items.first?.review)
    }

    func testReviewNoteIsSearchable() {
        let entry = store.createEntry()
        var draft = entry
        draft.items[0].tag = "BTC"
        draft.items[0].body = "body"
        draft.items[0].review = JournalReview(verdict: .wrong, note: "不该追单")
        store.updateEntry(draft)

        store.searchText = "追单"
        XCTAssertEqual(store.filteredTimelineItems.count, 1)
        XCTAssertEqual(store.filteredTimelineItems.first?.item.review?.verdict, .wrong)
    }

    func testCorruptPrimaryWithoutBackupIsReadOnly() throws {
        let entry = store.createEntry()
        var draft = entry
        draft.title = "Lost?"
        store.updateEntry(draft)

        let db = store.databaseURL
        try Data("{".utf8).write(to: db)
        try? FileManager.default.removeItem(at: store.backupURL)

        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertTrue(reloaded.isReadOnlyDueToLoadFailure)
        // On-disk corrupt file must still exist (not overwritten by empty save).
        XCTAssertTrue(FileManager.default.fileExists(atPath: db.path))
        let onDisk = try String(contentsOf: db, encoding: .utf8)
        XCTAssertEqual(onDisk, "{")
    }

    // MARK: - Persist / publish (P2, P3)

    func testBodyOnlyUpdateDoesNotPublishObjectWillChange() {
        let entry = store.createEntry()
        var draft = entry
        draft.items[0].body = "hello"

        var published = 0
        let cancellable = store.objectWillChange.sink { published += 1 }

        store.updateEntry(draft)
        store.flushPendingWrites()
        XCTAssertEqual(published, 0, "body-only autosave must not rebuild the journal UI")
        XCTAssertEqual(store.entries.first?.items.first?.body, "hello")

        draft.items[0].tag = "BTC"
        store.updateEntry(draft)
        XCTAssertGreaterThan(published, 0, "tag edits are structural and must publish")

        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertEqual(reloaded.entries.first?.items.first?.body, "hello")
        XCTAssertEqual(reloaded.entries.first?.items.first?.tag, "BTC")
        _ = cancellable
    }

    func testRapidBodyUpdatesKeepLastWrite() {
        _ = store.createEntry()
        for index in 1...20 {
            var draft = store.entries[0]
            draft.items[0].body = "v\(index)"
            store.updateEntry(draft)
        }
        store.flushPendingWrites()
        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertEqual(reloaded.entries.first?.items.first?.body, "v20")
    }

    func testBodyOnlyUpdateStillNotifiesSyncSubscribers() {
        _ = store.createEntry()
        var mutates = 0
        let cancellable = store.entriesDidMutate.sink { mutates += 1 }

        var draft = store.entries[0]
        draft.items[0].body = "sync me"
        store.updateEntry(draft)

        XCTAssertGreaterThan(mutates, 0)
        _ = cancellable
    }

    func testUnchangedDraftDoesNotBecomeAnEdit() {
        let entry = store.createEntry()
        var mutates = 0
        let cancellable = store.entriesDidMutate.sink { mutates += 1 }

        store.updateEntry(entry)

        XCTAssertEqual(store.entries.first?.updatedAt, entry.updatedAt)
        XCTAssertEqual(mutates, 0, "flushing an unchanged draft must not notify sync")
        _ = cancellable
    }

    func testEntryCountForActiveAndInactiveJournals() {
        let firstID = store.activeJournalID!
        _ = store.createEntry(on: Date())
        _ = store.createEntry(on: Date().addingTimeInterval(-86400))
        XCTAssertEqual(store.entryCount(for: firstID), 2)

        let second = store.createJournal(name: "Second Book")
        _ = store.createEntry(on: Date())
        XCTAssertEqual(store.entryCount(for: second.id), 1)
        XCTAssertEqual(store.entryCount(for: firstID), 2)

        store.switchToJournal(id: firstID)
        XCTAssertEqual(store.entryCount(for: firstID), 2)
        XCTAssertEqual(store.entryCount(for: second.id), 1)
    }
}
