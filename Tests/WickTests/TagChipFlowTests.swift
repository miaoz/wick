import XCTest
@testable import WickCore

final class TagChipFlowTests: XCTestCase {
    private func items(_ widths: [CGFloat]) -> [TagChipItem] {
        widths.enumerated().map { TagChipItem(id: "c\($0.offset)", width: $0.element) }
    }

    func testRowsWrapGreedy() {
        // 50+6+50 = 106 fits 120; adding a third (162) wraps.
        let rows = TagChipFlow.rows(items: items([50, 50, 50, 50]), availableWidth: 120)
        XCTAssertEqual(rows.map { $0.map(\.id) }, [["c0", "c1"], ["c2", "c3"]])
    }

    func testRowsSingleItemWiderThanRowGetsOwnRow() {
        let rows = TagChipFlow.rows(items: items([80, 200, 80]), availableWidth: 120)
        XCTAssertEqual(rows.map { $0.map(\.id) }, [["c0"], ["c1"], ["c2"]])
    }

    func testRowsEverythingFitsOneRow() {
        let rows = TagChipFlow.rows(items: items([30, 30, 30]), availableWidth: 200)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].count, 3)
    }

    func testCollapsedRowIsNilWhenEverythingFits() {
        let collapsed = TagChipFlow.collapsedRow(items: items([30, 30]), availableWidth: 200) { _ in 40 }
        XCTAssertNil(collapsed)
    }

    func testCollapsedRowTrimsUntilToggleFits() {
        // Full-width packing puts c0,c1 in row 1 (60+6+60=126 ≤ 130), c2 in row 2.
        // 126+6+40 > 130, so c1 is dropped to make room for the toggle.
        let collapsed = TagChipFlow.collapsedRow(items: items([60, 60, 60]), availableWidth: 130) { _ in 40 }
        XCTAssertEqual(collapsed?.row.map(\.id), ["c0"])
        XCTAssertEqual(collapsed?.hiddenCount, 2)
    }

    func testCollapsedRowCanEmptyCompletely() {
        // 100+6+50 > 110 even for the first chip, so nothing stays in row 1.
        let collapsed = TagChipFlow.collapsedRow(items: items([100, 100]), availableWidth: 110) { _ in 50 }
        XCTAssertEqual(collapsed?.row.count, 0)
        XCTAssertEqual(collapsed?.hiddenCount, 2)
    }

    func testCollapsedRowToggleWidthDependsOnHiddenCount() {
        // A wider toggle (two-digit count) must be accounted for.
        let collapsed = TagChipFlow.collapsedRow(items: items([40, 40, 40, 40]), availableWidth: 120) { hidden in
            hidden >= 10 ? 70 : 40
        }
        XCTAssertNotNil(collapsed)
        if let collapsed {
            let used = TagChipFlow.rowWidth(of: collapsed.row)
            let toggle: CGFloat = collapsed.hiddenCount >= 10 ? 70 : 40
            XCTAssertLessThanOrEqual(used + TagChipFlow.spacing + toggle, 120)
        }
    }
}
