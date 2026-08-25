import XCTest
import WickSync
@testable import WickCore

/// Sync-bridge APIs (`JournalLocalSource`) and snapshot-version gating.
@MainActor
final class JournalStoreSyncTests: XCTestCase {
    private var tempRoot: URL!
    private var store: JournalStore!

    private func testDate(_ value: String) -> Date {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        return Calendar.current.date(from: DateComponents(
            year: parts[0], month: parts[1], day: parts[2]
        ))!
    }

    override func setUp() async throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("WickSyncStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        store = JournalStore(rootDirectory: tempRoot)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
        store = nil
        tempRoot = nil
    }

    // MARK: - Version gate

    func testNewerSnapshotVersionGoesReadOnlyAndKeepsFileUntouched() throws {
        let payload = Data(#"{"version":99,"entries":[]}"#.utf8)
        try payload.write(to: store.databaseURL, options: .atomic)

        let reloaded = JournalStore(rootDirectory: tempRoot)

        XCTAssertTrue(reloaded.isReadOnlyDueToLoadFailure)
        XCTAssertTrue(reloaded.entries.isEmpty)
        XCTAssertEqual(reloaded.loadFailureMessage?.isEmpty, false)
        // The newer-format file must survive exactly as-is.
        XCTAssertEqual(try Data(contentsOf: store.databaseURL), payload)
    }

    func testNewerVersionBackupIsNotRestored() throws {
        // Primary is corrupt, sidecar backup is a valid but newer-format file:
        // the restore path must reject it and keep read-only protection.
        try Data("not-json".utf8).write(to: store.databaseURL, options: .atomic)
        try Data(#"{"version":99,"entries":[]}"#.utf8).write(to: store.backupURL, options: .atomic)

        let reloaded = JournalStore(rootDirectory: tempRoot)

        XCTAssertTrue(reloaded.isReadOnlyDueToLoadFailure)
        XCTAssertFalse(reloaded.didRestoreFromBackup)
        XCTAssertTrue(reloaded.entries.isEmpty)
        XCTAssertEqual(try Data(contentsOf: store.databaseURL), Data("not-json".utf8))
    }

    func testCurrentVersionLoadsNormally() throws {
        _ = store.createEntry()
        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertFalse(reloaded.isReadOnlyDueToLoadFailure)
        XCTAssertEqual(reloaded.entries.count, 1)
    }

    // MARK: - DS-01 image path safety

    func testImageURLRejectsTraversalAndAnythingOutsideImagesDirectory() throws {
        let sentinel = tempRoot.appendingPathComponent("sentinel.txt")
        try Data("keep me".utf8).write(to: sentinel)

        XCTAssertNil(store.imageURL(for: "../outside.png"))
        XCTAssertNil(store.imageURL(for: "../../sentinel.txt"))
        XCTAssertNil(store.imageURL(for: "a/b.png"))
        XCTAssertNil(store.imageURL(for: "a\\b.png"))
        XCTAssertNil(store.imageURL(for: ".."))
        XCTAssertNil(store.imageURL(for: "."))
        XCTAssertNil(store.imageURL(for: ""))

        let safe = store.imageURL(for: "abc 1.png")
        XCTAssertNotNil(safe)
        XCTAssertTrue(safe!.path.hasPrefix(store.imagesDirectory.path + "/"))
    }

    func testUnsafeImageReferenceInSnapshotGoesReadOnlyAndSentinelsSurvive() throws {
        // A traversal delete would target this file outside the journal folder.
        let sentinel = tempRoot.appendingPathComponent("sentinel.txt")
        try Data("keep me".utf8).write(to: sentinel)

        let entryID = UUID().uuidString
        let itemID = UUID().uuidString
        let json = """
        {"version":1,"entries":[{"id":"\(entryID)","date":"2026-01-15T00:00:00Z","title":"t",\
        "items":[{"id":"\(itemID)","tag":"","body":"b","imageFilenames":["../sentinel.txt"]}],\
        "createdAt":"2026-01-15T00:00:00Z","updatedAt":"2026-01-15T00:00:00Z"}]}
        """
        try Data(json.utf8).write(to: store.databaseURL, options: .atomic)

        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertTrue(reloaded.isReadOnlyDueToLoadFailure)
        XCTAssertTrue(reloaded.entries.isEmpty)
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep me".utf8))
        XCTAssertEqual(try Data(contentsOf: reloaded.databaseURL), Data(json.utf8))
    }

    func testDeletePathsNeverTouchFilesOutsideImagesDirectory() throws {
        // Sentinel next to the journal folder - a traversal delete must miss it.
        let sentinel = tempRoot.appendingPathComponent("sentinel.txt")
        try Data("keep me".utf8).write(to: sentinel)

        let entry = store.createEntry()
        let itemID = entry.items[0].id
        if let filename = store.addImage(
            from: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
            to: entry.id,
            itemID: itemID,
            preferredExtension: "png"
        ) {
            // Remove image, then delete the entry and the day.
            store.removeImage(filename: filename, from: entry.id, itemID: itemID)
            store.deleteItem(itemID: itemID, from: entry.id)
            store.removeSyncedEntry(entryID: entry.id)
        } else {
            store.deleteItem(itemID: itemID, from: entry.id)
        }
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep me".utf8))
    }

    // MARK: - PF-01 batch apply

    func testApplySyncedChangesPersistsOnceForWholeBatch() throws {
        let startCount = store.persistCount
        var changes: [JournalSyncMutation] = []
        for day in 1...50 {
            changes.append(
                .upsert(
                    JournalEntry(date: testDate(String(format: "2026-03-%02d", day)), title: "d\(day)"),
                    expectedLocalHash: nil
                )
            )
        }
        store.applySyncedChanges(changes, journalID: store.activeJournalID!)
        XCTAssertEqual(store.persistCount, startCount + 1, "one batch apply must persist exactly once")
        XCTAssertEqual(store.entries.count, 50)

        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertEqual(reloaded.entries.count, 50)
        XCTAssertEqual(reloaded.entries.first { Calendar.current.isDate($0.date, inSameDayAs: testDate("2026-03-25")) }?.title, "d25")
    }

    func testApplySyncedChangesBatchRemove() throws {
        let a = JournalEntry(date: testDate("2026-03-01"), title: "a")
        let b = JournalEntry(date: testDate("2026-03-02"), title: "b")
        store.applySyncedChanges(
            [.upsert(a, expectedLocalHash: nil), .upsert(b, expectedLocalHash: nil)],
            journalID: store.activeJournalID!
        )
        XCTAssertEqual(store.entries.count, 2)

        let aHash = try JournalSyncEncoding.contentHash(for: a)
        store.applySyncedChanges(
            [.remove(entryID: a.id, expectedLocalHash: aHash)],
            journalID: store.activeJournalID!
        )
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertTrue(Calendar.current.isDate(store.entries.first!.date, inSameDayAs: testDate("2026-03-02")))
    }

    func testSameDateDifferentUUIDsConvergeOnDeterministicSurvivor() throws {
        let rootB = FileManager.default.temporaryDirectory
            .appendingPathComponent("WickSyncStorePeer-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootB) }
        let storeB = JournalStore(rootDirectory: rootB)
        let day = testDate("2026-03-03")
        let lowerID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let higherID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let lower = JournalEntry(id: lowerID, date: day, items: [JournalItem(tag: "A", body: "one")])
        let higher = JournalEntry(id: higherID, date: day, items: [JournalItem(tag: "B", body: "two")])
        store.applySyncedEntry(lower)
        storeB.applySyncedEntry(higher)

        store.applySyncedEntry(higher)
        storeB.applySyncedEntry(lower)

        XCTAssertEqual(store.entries.map(\.id), [lowerID])
        XCTAssertEqual(storeB.entries.map(\.id), [lowerID])
        XCTAssertEqual(Set(store.entries[0].items.map(\.body)), ["one", "two"])
        XCTAssertEqual(Set(storeB.entries[0].items.map(\.body)), ["one", "two"])
    }

    func testApplySyncedChangesIgnoresNonActiveJournal() {
        let original = store.activeJournalID!
        let second = store.createJournal(name: "Second")
        store.switchToJournal(id: original)
        let before = store.persistCount

        store.applySyncedChanges(
            [.upsert(JournalEntry(date: testDate("2026-09-01"), title: "no"), expectedLocalHash: nil)],
            journalID: second.id
        )
        XCTAssertEqual(store.persistCount, before)
        XCTAssertTrue(store.entries.isEmpty)
    }

    // MARK: - AC-P1-05 final freshness re-verification

    func testApplySyncedChangesSkipsEditedDay() throws {
        let entry = JournalEntry(date: testDate("2026-04-01"), title: "local v1")
        store.applySyncedEntry(entry)
        let staleHash = try JournalSyncEncoding.contentHash(for: entry)
        var edited = entry
        edited.title = "local v2"
        store.applySyncedEntry(edited)

        let remote = JournalEntry(id: entry.id, date: entry.date, title: "remote")
        let applied = store.applySyncedChanges(
            [.upsert(remote, expectedLocalHash: staleHash)],
            journalID: store.activeJournalID!
        )
        XCTAssertTrue(applied.isEmpty, "a stale mutation must be skipped")
        XCTAssertEqual(store.entries.first?.title, "local v2", "the edit must not be clobbered")

        // A matching mutation (fresh hash) commits.
        let freshHash = try JournalSyncEncoding.contentHash(for: edited)
        let applied2 = store.applySyncedChanges(
            [.upsert(remote, expectedLocalHash: freshHash)],
            journalID: store.activeJournalID!
        )
        XCTAssertEqual(applied2, [remote.id])
        XCTAssertEqual(store.entries.first?.title, "remote")
    }

    // MARK: - DS-04 consistent export

    private func unzipArchive(_ zipURL: URL, to dir: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, dir.path]
        try process.run()
        process.waitUntilExit()
    }

    private func decodedExport(at dest: URL) throws -> JournalSnapshot {
        let unzipDir = tempRoot.appendingPathComponent("unzip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: unzipDir) }
        try unzipArchive(dest, to: unzipDir)
        let jsonURL = unzipDir.appendingPathComponent("Wick-Journal/journal.json", isDirectory: false)
        return try JournalSyncEncoding.decoder.decode(JournalSnapshot.self, from: Data(contentsOf: jsonURL))
    }

    func testExportEncodesLatestInMemorySnapshotNotStaleDiskFile() throws {
        let entry = store.createEntry()
        var draft = entry
        draft.title = "Exported Latest"
        draft.items[0].body = "fresh body"
        store.updateEntry(draft)

        // Make the on-disk main file stale: export must use the frozen
        // in-memory snapshot, not copy databaseURL.
        let stale = JournalSnapshot(
            version: 1,
            entries: [JournalEntry(date: testDate("2026-01-01"), title: "STALE")]
        )
        try JournalSyncEncoding.encoder.encode(stale).write(to: store.databaseURL, options: .atomic)

        let dest = tempRoot.appendingPathComponent("export.zip", isDirectory: false)
        try store.exportArchive(to: dest)

        let decoded = try decodedExport(at: dest)
        XCTAssertEqual(decoded.entries.first?.title, "Exported Latest")
        XCTAssertEqual(decoded.entries.first?.items.first?.body, "fresh body")
    }

    func testEditThenExportImmediatelyIsLatest() throws {
        let entry = store.createEntry()
        var draft = entry
        draft.items[0].body = "typed now"
        store.updateEntry(draft)

        let dest = tempRoot.appendingPathComponent("export2.zip", isDirectory: false)
        try store.exportArchive(to: dest)

        let decoded = try decodedExport(at: dest)
        XCTAssertEqual(decoded.entries.first?.items.first?.body, "typed now")
    }

    func testExportFailureKeepsPreviousDestination() throws {
        _ = store.createEntry()
        let dest = tempRoot.appendingPathComponent("backup.zip", isDirectory: false)
        try store.exportArchive(to: dest)
        let oldBytes = try Data(contentsOf: dest)
        XCTAssertFalse(oldBytes.isEmpty)

        // The temp archive is built successfully, then the FINAL replace fails
        // (the exact window the old remove-then-move implementation lost data).
        JournalStore.failExportReplaceOverride = true
        defer { JournalStore.failExportReplaceOverride = false }

        XCTAssertThrowsError(try store.exportArchive(to: dest))
        XCTAssertEqual(
            try Data(contentsOf: dest),
            oldBytes,
            "a failed replace must keep the previous archive byte-for-byte"
        )
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: tempRoot.path)
            .filter { $0.hasPrefix(".Wick-export-") }
        XCTAssertTrue(leftovers.isEmpty, "the temp archive must be cleaned up on failure")
    }

    func testExportOnlyContainsActiveJournal() throws {
        let firstID = store.activeJournalID!
        _ = store.createEntry()
        var draft = store.entries[0]
        draft.title = "Only From First"
        store.updateEntry(draft)

        _ = store.createJournal(name: "Second")
        _ = store.createEntry()
        var draft2 = store.entries[0]
        draft2.title = "From Second"
        store.updateEntry(draft2)

        // Export while the SECOND journal is active — must not leak the first.
        let dest = tempRoot.appendingPathComponent("export3.zip", isDirectory: false)
        try store.exportArchive(to: dest)
        let decoded = try decodedExport(at: dest)
        XCTAssertEqual(decoded.entries.first?.title, "From Second")
        XCTAssertFalse(decoded.entries.contains { $0.title == "Only From First" })
        _ = firstID
    }

    // MARK: - applySyncedEntry

    func testApplySyncedEntryInsertsThenReplacesByUUID() {
        let first = JournalEntry(date: testDate("2026-08-01"), title: "v1")
        store.applySyncedEntry(first)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.title, "v1")

        let replacement = JournalEntry(id: first.id, date: first.date, title: "v2")
        store.applySyncedEntry(replacement)

        XCTAssertEqual(store.entries.count, 1, "same day key must replace, not duplicate")
        XCTAssertEqual(store.entries.first?.title, "v2")
        XCTAssertEqual(store.entries.first?.id, replacement.id)
    }

    func testApplySyncedEntryKeepsRemoteUpdatedAt() {
        let remoteStamp = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = JournalEntry(date: testDate("2026-08-02"), updatedAt: remoteStamp)
        store.applySyncedEntry(entry)
        XCTAssertEqual(store.entries.first?.updatedAt, remoteStamp)
    }

    func testApplySyncedEntryMovesSelectionWhenIdentityChanges() {
        let local = store.createEntry()
        store.selectDay(local.id)

        let remote = JournalEntry(id: local.id, date: local.date, title: "from other device")
        store.applySyncedEntry(remote)

        XCTAssertEqual(store.selection, .day(remote.id))
        XCTAssertEqual(store.selectedEntry?.title, "from other device")
    }

    func testApplySyncedEntryPersistsAcrossReload() {
        store.applySyncedEntry(JournalEntry(date: testDate("2026-08-03"), title: "persisted"))
        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertEqual(reloaded.entries.count, 1)
        XCTAssertTrue(Calendar.current.isDate(reloaded.entries.first!.date, inSameDayAs: testDate("2026-08-03")))
    }

    func testApplySyncedEntryIsBlockedInReadOnlyMode() throws {
        try Data(#"{"version":99,"entries":[]}"#.utf8).write(to: store.databaseURL, options: .atomic)
        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertTrue(reloaded.isReadOnlyDueToLoadFailure)

        reloaded.applySyncedEntry(JournalEntry(date: testDate("2026-08-04"), title: "nope"))
        XCTAssertTrue(reloaded.entries.isEmpty)
    }

    // MARK: - removeSyncedEntry

    func testRemoveSyncedDayDeletesEntryAndItsImages() {
        let entry = store.createEntry()
        let filename = store.addImage(from: Data([0x89, 0x50, 0x4E, 0x47]), to: entry.id, itemID: entry.items[0].id)
        XCTAssertNotNil(filename)
        let imagePath = store.imageURL(for: filename!)!.path
        XCTAssertTrue(FileManager.default.fileExists(atPath: imagePath))

        store.removeSyncedEntry(entryID: entry.id)

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: imagePath))
    }

    // MARK: - Image bridge

    func testSyncedImageRoundTripAndTraversalGuard() {
        let payload = Data([1, 2, 3])
        store.storeSyncedImage(filename: "abc.png", data: payload)
        XCTAssertTrue(store.hasSyncedImage(filename: "abc.png"))
        XCTAssertEqual(store.syncedImageData(filename: "abc.png"), payload)

        XCTAssertFalse(store.hasSyncedImage(filename: "../escape.png"))
        XCTAssertNil(store.syncedImageData(filename: ".."))
        store.storeSyncedImage(filename: "../evil.png", data: payload)
        XCTAssertFalse(store.hasSyncedImage(filename: "../evil.png"))
    }

    func testSyncEntrySnapshotsKeyedByUUID() {
        let a = store.createEntry()
        let old = JournalEntry(date: testDate("2026-01-01"), title: "old")
        store.applySyncedEntry(old)
        let snapshots = store.syncEntrySnapshots()
        XCTAssertEqual(Set(snapshots.keys), Set([a.id, old.id]))
    }

    // MARK: - adoptRemoteJournal

    func testAdoptRemoteJournalRegistersProvidedIDAndSwitches() {
        let remoteID = UUID()
        let info = store.adoptRemoteJournal(id: remoteID, name: "From Other Mac")

        XCTAssertEqual(info.id, remoteID)
        XCTAssertEqual(store.activeJournalID, remoteID)
        XCTAssertEqual(store.journals.count, 2)
        XCTAssertTrue(store.entries.isEmpty, "adopted journal starts empty; the engine fills it")

        // Directory seeded and catalog persisted across reload.
        let dir = tempRoot.appendingPathComponent(remoteID.uuidString, isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("journal.json").path))
        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertEqual(reloaded.activeJournalID, remoteID)
        XCTAssertEqual(reloaded.activeJournal?.name, "From Other Mac")
    }

    func testAdoptRemoteJournalWithKnownIDJustSwitches() {
        let originalID = store.activeJournalID!
        _ = store.createJournal(name: "Second")
        XCTAssertNotEqual(store.activeJournalID, originalID)

        let info = store.adoptRemoteJournal(id: originalID, name: "whatever")

        XCTAssertEqual(info.id, originalID)
        XCTAssertEqual(store.activeJournalID, originalID)
        XCTAssertEqual(store.journals.count, 2, "no duplicate journal for a known id")
    }

    func testAdoptRemoteJournalUniquifiesDisplayName() {
        let existing = store.activeJournal!.name
        let info = store.adoptRemoteJournal(id: UUID(), name: existing)
        XCTAssertNotEqual(info.name.lowercased(), existing.lowercased())
        XCTAssertTrue(info.name.hasPrefix(existing))
    }

    func testRegisterRemoteJournalDoesNotSwitchActive() {
        let originalID = store.activeJournalID!
        let remoteID = UUID()

        let info = store.registerRemoteJournal(id: remoteID, name: "Background Import")

        XCTAssertEqual(info.id, remoteID)
        XCTAssertEqual(store.activeJournalID, originalID, "registration must not yank the active journal")
        XCTAssertEqual(store.journals.count, 2)
        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertTrue(reloaded.journals.contains { $0.id == remoteID })
        XCTAssertEqual(reloaded.activeJournalID, originalID)
    }

    // MARK: - applySyncedJournalName

    func testApplySyncedJournalNameRenamesActiveAndPersists() {
        let applied = store.applySyncedJournalName("Renamed Remotely")

        XCTAssertEqual(applied, "Renamed Remotely")
        XCTAssertEqual(store.activeJournal?.name, "Renamed Remotely")
        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertEqual(reloaded.activeJournal?.name, "Renamed Remotely")
    }

    func testApplySyncedJournalNameUniquifiesAgainstOtherJournals() {
        let existing = store.activeJournal!.name
        _ = store.createJournal(name: "Second")

        let applied = store.applySyncedJournalName(existing)

        XCTAssertNotEqual(applied.lowercased(), existing.lowercased(),
                          "a collision with another journal must uniquify")
        XCTAssertEqual(store.activeJournal?.name, applied)

        // The applied name is the sync baseline: re-applying it is a no-op.
        XCTAssertEqual(store.applySyncedJournalName(applied), applied)
    }

    func testApplySyncedJournalNameWithCurrentNameIsNoOp() {
        let current = store.activeJournal!.name
        let updatedAt = store.activeJournal!.updatedAt

        XCTAssertEqual(store.applySyncedJournalName(current), current)
        XCTAssertEqual(store.activeJournal?.updatedAt, updatedAt, "no-op apply must not touch metadata")
    }

    func testApplySyncedMutationsIgnoreNonActiveJournal() {
        let firstID = store.activeJournalID!
        let originalFirstName = store.activeJournal!.name
        _ = store.createEntry()
        XCTAssertEqual(store.entries.count, 1)

        _ = store.createJournal(name: "Empty")
        XCTAssertEqual(store.entries.count, 0)

        store.applySyncedEntry(
            JournalEntry(date: testDate("2026-08-01"), title: "from previous"),
            journalID: firstID
        )
        XCTAssertTrue(store.entries.isEmpty, "must not write the previous journal's days into the active one")

        _ = store.applySyncedJournalName("trading", journalID: firstID)
        XCTAssertEqual(store.activeJournal?.name, "Empty")
        XCTAssertEqual(store.journals.first { $0.id == firstID }?.name, originalFirstName)

        store.switchToJournal(id: firstID)
        XCTAssertEqual(store.entries.count, 1)
    }
}
