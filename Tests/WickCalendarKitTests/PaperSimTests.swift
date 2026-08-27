import SpriteKit
import XCTest
@testable import WickCalendarKit

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

    // MARK: - PF-02 sleeping / dirty warp

    @MainActor
    func testSleepingSceneBuildsNoWarpAfterInitialFrame() {
        let sim = PaperSim(layout: .desktop)
        let scene = CalendarPaperScene(layout: .desktop)
        scene.sim = sim
        scene.setPageTexture(SKTexture())

        // First frame renders the initial (rest) geometry.
        scene.update(1.0 / 60.0)
        XCTAssertEqual(scene.warpBuildCount, 1)
        let baseline = scene.warpBuildCount
        let revision = sim.geometryRevision

        // 120 consecutive sleeping frames: revision frozen, zero warp builds.
        for _ in 0..<120 {
            scene.update(1.0 / 60.0)
        }
        XCTAssertEqual(sim.geometryRevision, revision, "sleeping must freeze the geometry revision")
        XCTAssertEqual(scene.warpBuildCount, baseline, "sleeping frames must not rebuild warp")
    }

    @MainActor
    func testGrabAndSeamWakeSceneAndRebuildWarp() {
        let sim = PaperSim(layout: .desktop)
        let scene = CalendarPaperScene(layout: .desktop)
        scene.sim = sim
        scene.setPageTexture(SKTexture())

        sim.setGrab(at: CGPoint(x: 10, y: 10))
        scene.update(1.0 / 60.0)
        XCTAssertGreaterThan(scene.warpBuildCount, 0, "a grab must wake the first frame")

        // Settle back to sleep, then tear: the first frame after wakes again.
        for _ in 0..<200 { scene.update(1.0 / 60.0) }
        let settled = scene.warpBuildCount
        sim.setSeam(centerX: 150, front: 40)
        scene.update(1.0 / 60.0)
        XCTAssertGreaterThan(scene.warpBuildCount, settled, "a tear must wake the first frame")
    }

    @MainActor
    func testResetBumpsRevisionAndRebuildsWarp() {
        let sim = PaperSim(layout: .desktop)
        let scene = CalendarPaperScene(layout: .desktop)
        scene.sim = sim
        scene.setPageTexture(SKTexture())

        sim.setGrab(at: CGPoint(x: 10, y: 10))
        scene.update(1.0 / 60.0)
        let buildsBefore = scene.warpBuildCount
        let revisionBefore = sim.geometryRevision

        // Dynamic page -> reset: the next frame must redraw rest geometry even
        // if the solver would otherwise be asleep (AC-P2-01).
        sim.reset()
        XCTAssertGreaterThan(sim.geometryRevision, revisionBefore, "reset must bump the geometry revision")
        scene.update(1.0 / 60.0)
        XCTAssertGreaterThan(scene.warpBuildCount, buildsBefore, "reset must trigger a warp rebuild")
        // After the reset rebuild, the page returns to sleep (revision frozen).
        let settledRevision = sim.geometryRevision
        for _ in 0..<60 { scene.update(1.0 / 60.0) }
        XCTAssertEqual(sim.geometryRevision, settledRevision, "the reset page settles back to sleep")
    }

    @MainActor
    func testTextureReplaceMarksDirtyEvenWhileSleeping() {
        let sim = PaperSim(layout: .desktop)
        let scene = CalendarPaperScene(layout: .desktop)
        scene.sim = sim
        scene.setPageTexture(SKTexture())
        scene.update(1.0 / 60.0) // initial build
        for _ in 0..<60 { scene.update(1.0 / 60.0) } // settle into sleep
        let settled = scene.warpBuildCount

        scene.setPageTexture(SKTexture()) // texture replace while asleep
        scene.update(1.0 / 60.0)
        XCTAssertGreaterThan(scene.warpBuildCount, settled, "texture replace must mark dirty")
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

    func testPaperLayoutEventsPaneMetrics() {
        XCTAssertEqual(TradingCalendarGeometry.eventsPaneTopY, 204)
        XCTAssertEqual(PaperLayout.desktop.eventsPaneTopY, 204)

        let phoneLayout = PaperLayout.fullScreen(
            size: CGSize(width: 393, height: 852),
            safeTop: 59,
            safeBottom: 34
        )
        let s = 393.0 / 300.0
        XCTAssertEqual(phoneLayout.contentScale, s, accuracy: 0.001)
        // eventsPaneTopY should clear masthead + hero + lunar + almanac
        let expectedHeaderH = (29.0 + 82.0 + 21.0 + 46.0) * s
        XCTAssertEqual(phoneLayout.eventsPaneTopY, phoneLayout.contentTopInset + expectedHeaderH, accuracy: 0.01)
        XCTAssertGreaterThan(phoneLayout.eventPaneHeight, 150)
    }

    func testGrabAndReleaseReturnsToRest() {
        let sim = PaperSim(layout: .desktop)
        let restPos = sim.pos

        // Grab and lift
        sim.setGrab(at: CGPoint(x: 150, y: 250))
        sim.moveGrab(to: CGPoint(x: 160, y: 260), lift: 1.0)
        for _ in 0..<10 {
            sim.step(1.0 / 60.0)
        }

        // Lifted state has vertices pulled out in z
        let hasLiftedVertex = sim.pos.contains { $0.z > 5.0 }
        XCTAssertTrue(hasLiftedVertex, "grab with lift must pull vertex in z")

        // Release grab: solver should spring back towards rest plane
        sim.release()
        for _ in 0..<200 {
            sim.step(1.0 / 60.0)
        }

        // Vertices should return close to rest positions
        for i in sim.pos.indices {
            XCTAssertEqual(sim.pos[i].x, restPos[i].x, accuracy: 2.0)
            XCTAssertEqual(sim.pos[i].y, restPos[i].y, accuracy: 2.0)
            XCTAssertEqual(sim.pos[i].z, restPos[i].z, accuracy: 1.0)
        }
    }
}
