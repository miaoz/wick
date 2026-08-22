import Foundation
import XCTest
import WickSync
@testable import WickPhone

final class PhoneJournalStoreTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WickPhoneTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        MainActor.assumeIsolated {
            PhoneJournalStore.failCatalogPersistOverride = false
        }
        super.tearDown()
    }

    @MainActor
    func testWriterKeepsEditsWithOriginalJournalAcrossImmediateSwitch() {
        let store = PhoneJournalStore(rootDirectory: root)
        let firstID = store.journals[0].id
        let second = store.createJournal(name: "Second")

        store.switchToJournal(id: firstID)
        var firstEntry = store.openOrCreateToday()
        firstEntry.title = "written to first"
        store.updateEntry(firstEntry)

        // The switch flushes the current writer generation before changing the
        // active database URL. A reload must keep each journal isolated.
        store.switchToJournal(id: second.id)
        var secondEntry = store.openOrCreateToday()
        secondEntry.title = "written to second"
        store.updateEntry(secondEntry)
        XCTAssertTrue(store.flushPendingWrites())

        let reloaded = PhoneJournalStore(rootDirectory: root)
        reloaded.switchToJournal(id: firstID)
        XCTAssertEqual(reloaded.entries.map(\.title), ["written to first"])
        reloaded.switchToJournal(id: second.id)
        XCTAssertEqual(reloaded.entries.map(\.title), ["written to second"])
    }

    @MainActor
    func testUserDeleteCatalogFailureRestoresDirectoryAndCatalog() {
        let store = PhoneJournalStore(rootDirectory: root)
        let second = store.createJournal(name: "Second")
        let directory = root.appendingPathComponent(second.id.uuidString, isDirectory: true)

        PhoneJournalStore.failCatalogPersistOverride = true
        XCTAssertFalse(store.deleteJournal(id: second.id))
        XCTAssertTrue(store.journals.contains { $0.id == second.id })
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertTrue(PhoneJournalStore(rootDirectory: root).journals.contains { $0.id == second.id })
    }

    @MainActor
    func testRemoteDeleteLastCatalogFailureRestoresSessionAndCleansFreshDefault() {
        let store = PhoneJournalStore(rootDirectory: root)
        let activeID = store.activeJournalID!
        var entry = store.openOrCreateToday()
        entry.title = "keep after rollback"
        store.updateEntry(entry)
        XCTAssertTrue(store.flushPendingWrites())
        let originalEntries = store.entries
        let originalDatabaseURL = store.databaseURL
        let originalDirectoryIDs = Set(store.journals.map(\.id))

        PhoneJournalStore.failCatalogPersistOverride = true
        XCTAssertEqual(store.deleteJournalFromRemote(id: activeID), .ioFailure)
        XCTAssertEqual(store.activeJournalID, activeID)
        XCTAssertEqual(store.entries, originalEntries)
        XCTAssertEqual(store.databaseURL, originalDatabaseURL)

        let directoryIDs = Set(
            (try! FileManager.default.contentsOfDirectory(atPath: root.path))
                .compactMap { UUID(uuidString: $0) }
        )
        XCTAssertEqual(directoryIDs, originalDirectoryIDs)
        let reloaded = PhoneJournalStore(rootDirectory: root)
        XCTAssertEqual(reloaded.entries.map(\.title), originalEntries.map(\.title))
    }

    @MainActor
    func testCorruptCatalogCanRestoreFromBackup() throws {
        let store = PhoneJournalStore(rootDirectory: root)
        let second = store.createJournal(name: "Second")
        let catalogURL = root.appendingPathComponent("catalog.json")
        let futureCatalog = JournalCatalogSnapshot(
            version: JournalCatalogSnapshot.currentVersion + 1,
            activeJournalID: second.id,
            journals: store.journals
        )
        let futureData = try JournalSyncEncoding.encoder.encode(futureCatalog)
        try futureData.write(to: catalogURL, options: .atomic)

        let reloaded = PhoneJournalStore(rootDirectory: root)
        XCTAssertTrue(reloaded.isCatalogReadOnly)
        XCTAssertNoThrow(try reloaded.restoreCatalogFromBackup())
        XCTAssertFalse(reloaded.isCatalogReadOnly)
        XCTAssertEqual(reloaded.journals.count, 1)
    }
}
