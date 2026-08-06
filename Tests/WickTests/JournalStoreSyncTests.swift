import XCTest
import WickSync
@testable import WickCore

/// Sync-bridge APIs (`JournalLocalSource`) and snapshot-version gating.
@MainActor
final class JournalStoreSyncTests: XCTestCase {
    private var tempRoot: URL!
    private var store: JournalStore!

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

    // MARK: - applySyncedEntry

    func testApplySyncedEntryInsertsThenReplacesByDayKey() {
        let first = JournalEntry(dayKey: "2026-08-01", title: "v1")
        store.applySyncedEntry(first)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.title, "v1")

        let replacement = JournalEntry(dayKey: "2026-08-01", title: "v2")
        store.applySyncedEntry(replacement)

        XCTAssertEqual(store.entries.count, 1, "same day key must replace, not duplicate")
        XCTAssertEqual(store.entries.first?.title, "v2")
        XCTAssertEqual(store.entries.first?.id, replacement.id)
    }

    func testApplySyncedEntryKeepsRemoteUpdatedAt() {
        let remoteStamp = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = JournalEntry(dayKey: "2026-08-02", updatedAt: remoteStamp)
        store.applySyncedEntry(entry)
        XCTAssertEqual(store.entries.first?.updatedAt, remoteStamp)
    }

    func testApplySyncedEntryMovesSelectionWhenIdentityChanges() {
        let local = store.createEntry()
        store.selectDay(local.id)

        let remote = JournalEntry(dayKey: local.dayKey, title: "from other device")
        store.applySyncedEntry(remote)

        XCTAssertEqual(store.selection, .day(remote.id))
        XCTAssertEqual(store.selectedEntry?.title, "from other device")
    }

    func testApplySyncedEntryPersistsAcrossReload() {
        store.applySyncedEntry(JournalEntry(dayKey: "2026-08-03", title: "persisted"))
        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertEqual(reloaded.entries.count, 1)
        XCTAssertEqual(reloaded.entries.first?.dayKey, "2026-08-03")
    }

    func testApplySyncedEntryIsBlockedInReadOnlyMode() throws {
        try Data(#"{"version":99,"entries":[]}"#.utf8).write(to: store.databaseURL, options: .atomic)
        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertTrue(reloaded.isReadOnlyDueToLoadFailure)

        reloaded.applySyncedEntry(JournalEntry(dayKey: "2026-08-04", title: "nope"))
        XCTAssertTrue(reloaded.entries.isEmpty)
    }

    // MARK: - removeSyncedDay

    func testRemoveSyncedDayDeletesEntryAndItsImages() {
        let entry = store.createEntry()
        let filename = store.addImage(from: Data([0x89, 0x50, 0x4E, 0x47]), to: entry.id, itemID: entry.items[0].id)
        XCTAssertNotNil(filename)
        let imagePath = store.imageURL(for: filename!).path
        XCTAssertTrue(FileManager.default.fileExists(atPath: imagePath))

        store.removeSyncedDay(dayKey: entry.dayKey)

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

    func testSyncDaySnapshotsKeyedByDayKey() {
        let a = store.createEntry()
        store.applySyncedEntry(JournalEntry(dayKey: "2026-01-01", title: "old"))
        let snapshots = store.syncDaySnapshots()
        XCTAssertEqual(Set(snapshots.keys), Set([a.dayKey, "2026-01-01"]))
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
}
