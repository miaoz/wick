import XCTest
@testable import WickSync

final class JournalDayMergeTests: XCTestCase {
    private let entryID = UUID()
    private let t0 = Date(timeIntervalSince1970: 1_754_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_754_001_000)
    private let t2 = Date(timeIntervalSince1970: 1_754_002_000)

    private func entry(
        items: [JournalItem],
        title: String = "",
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) -> JournalEntry {
        JournalEntry(
            id: entryID,
            date: t0,
            title: title,
            items: items,
            createdAt: createdAt ?? t0,
            updatedAt: updatedAt ?? t1
        )
    }

    func testDisjointItemsUnion() {
        let x = JournalItem(tag: "X")
        let y = JournalItem(tag: "Y")
        let result = JournalEntryMerge.merge(local: entry(items: [x]), remote: entry(items: [y]))
        XCTAssertEqual(Set(result.merged.items.map(\.id)), Set([x.id, y.id]))
        XCTAssertTrue(result.losingItems.isEmpty)
    }

    func testIdenticalItemKeepsSingleCopy() {
        let shared = JournalItem(tag: "same", body: "b")
        let result = JournalEntryMerge.merge(local: entry(items: [shared]), remote: entry(items: [shared]))
        XCTAssertEqual(result.merged.items.count, 1)
        XCTAssertTrue(result.losingItems.isEmpty)
    }

    func testSameItemConflictNewerSideWinsAndLoserRecorded() {
        let id = UUID()
        let older = JournalItem(id: id, body: "older edit")
        let newer = JournalItem(id: id, body: "newer edit")
        let local = entry(items: [newer], updatedAt: t2)
        let remote = entry(items: [older], updatedAt: t1)

        let result = JournalEntryMerge.merge(local: local, remote: remote)

        XCTAssertEqual(result.merged.items.first?.body, "newer edit")
        XCTAssertEqual(result.losingItems.first?.body, "older edit")
    }

    func testDateMovesWithoutChangingIdentity() {
        let laterDate = t0.addingTimeInterval(86_400)
        let local = JournalEntry(id: entryID, date: laterDate, createdAt: t0, updatedAt: t2)
        let remote = JournalEntry(id: entryID, date: t0, createdAt: t0, updatedAt: t1)

        let merged = JournalEntryMerge.merge(local: local, remote: remote).merged
        XCTAssertEqual(merged.id, entryID)
        XCTAssertEqual(merged.date, laterDate)
    }

    func testTitleConflictNewerWinsAndLoserRecorded() {
        let local = entry(items: [JournalItem(body: "x")], title: "local title", updatedAt: t2)
        let remote = entry(items: [JournalItem(body: "x")], title: "remote title", updatedAt: t1)

        let result = JournalEntryMerge.merge(local: local, remote: remote)

        XCTAssertEqual(result.merged.title, "local title")
        XCTAssertEqual(result.losingTitle, "remote title")
    }

    func testOneSidedEmptyTitleFillsFromOther() {
        let local = entry(items: [JournalItem(body: "x")], title: "", updatedAt: t2)
        let remote = entry(items: [JournalItem(body: "x")], title: "theirs", updatedAt: t1)
        XCTAssertEqual(JournalEntryMerge.merge(local: local, remote: remote).merged.title, "theirs")
        XCTAssertNil(JournalEntryMerge.merge(local: local, remote: remote).losingTitle)
    }

    func testPlaceholderEmptyItemsDroppedWhenContentExists() {
        let placeholder = JournalItem()
        let real = JournalItem(body: "content")
        let result = JournalEntryMerge.merge(local: entry(items: [placeholder]), remote: entry(items: [real]))
        XCTAssertEqual(result.merged.items.count, 1)
        XCTAssertEqual(result.merged.items.first?.body, "content")
    }

    func testTimestampsUseMinCreatedAndMaxUpdated() {
        let local = entry(items: [JournalItem(body: "x")], createdAt: t1, updatedAt: t1)
        let remote = entry(items: [JournalItem(body: "y")], createdAt: t0, updatedAt: t2)
        let merged = JournalEntryMerge.merge(local: local, remote: remote).merged
        XCTAssertEqual(merged.createdAt, t0)
        XCTAssertEqual(merged.updatedAt, t2)
    }
}
