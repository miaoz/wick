import XCTest
@testable import WickCore

final class PaperSimTests: XCTestCase {
    func testRestLayoutGeometry() {
        let layout = PaperSim.restLayout()
        XCTAssertEqual(layout.count, PaperSim.cols * PaperSim.rows)

        // Row 0 sits at the very top; row 1 at the tear line; the last row at page bottom.
        for c in 0..<PaperSim.cols {
            XCTAssertEqual(layout[c].y, 0, "row 0")
        }
        for c in 0..<PaperSim.cols {
            XCTAssertEqual(
                layout[PaperSim.cols + c].y,
                Float(TradingCalendarGeometry.tearY),
                "row 1 (tear line)"
            )
        }
        let lastRow = (PaperSim.rows - 1) * PaperSim.cols
        XCTAssertEqual(layout[lastRow].y, Float(TradingCalendarGeometry.pageH), accuracy: 0.01)
    }

    func testStepStaysFiniteAtRest() {
        let sim = PaperSim()
        sim.reset()
        for _ in 0..<60 {
            sim.step(1.0 / 60.0)
        }
        for p in sim.pos {
            XCTAssertTrue(p.x.isFinite && p.y.isFinite && p.z.isFinite)
        }
    }

    func testSetSeamBreaksColumnsNearCenter() {
        let sim = PaperSim()
        let center: CGFloat = 150
        let front: CGFloat = 40
        sim.setSeam(centerX: center, front: front)

        let width = Float(TradingCalendarGeometry.pageW)
        for c in 0..<PaperSim.cols {
            let x = Float(c) / Float(PaperSim.cols - 1) * width
            let shouldBeBroken = abs(x - Float(center)) < Float(front)
            XCTAssertEqual(sim.fiberIntact[c], !shouldBeBroken, "column \(c)")
        }
    }

    func testTornColumnsDroopBelowTeerUnderGravity() {
        let sim = PaperSim()
        // Tear every column so the whole sheet below the tear line is free.
        sim.setSeam(centerX: TradingCalendarGeometry.pageW / 2, front: 400)
        // Pin nothing via grab; let gravity pull the freed sheet down.
        for _ in 0..<40 {
            sim.step(1.0 / 60.0)
        }
        // The bottom of the freed sheet should hang lower than its rest position.
        let lastRow = (PaperSim.rows - 1) * PaperSim.cols
        XCTAssertGreaterThan(sim.pos[lastRow].y, Float(TradingCalendarGeometry.pageH) - 1)
    }
}
