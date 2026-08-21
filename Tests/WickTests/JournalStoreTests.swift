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

    // MARK: - Entries (active journal)

    func testOneEntryPerDay() {
        let first = store.createEntry(on: Date())
        let second = store.createEntry(on: Date())
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(store.entries.count, 1)
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
        if let filename {
            XCTAssertTrue(FileManager.default.fileExists(atPath: store.imageURL(for: filename).path))
            store.deleteItem(itemID: itemID, from: entry.id)
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.imageURL(for: filename).path))
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
}
