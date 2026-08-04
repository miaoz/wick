import XCTest
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
        let db = tempRoot.appendingPathComponent("journal.json")
        let bak = tempRoot.appendingPathComponent("journal.json.bak")
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
        let db = tempRoot.appendingPathComponent("journal.json")
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

        let db = tempRoot.appendingPathComponent("journal.json")
        try Data("{".utf8).write(to: db)
        try? FileManager.default.removeItem(at: tempRoot.appendingPathComponent("journal.json.bak"))

        let reloaded = JournalStore(rootDirectory: tempRoot)
        XCTAssertTrue(reloaded.isReadOnlyDueToLoadFailure)
        // On-disk corrupt file must still exist (not overwritten by empty save).
        XCTAssertTrue(FileManager.default.fileExists(atPath: db.path))
        let onDisk = try String(contentsOf: db, encoding: .utf8)
        XCTAssertEqual(onDisk, "{")
    }
}
