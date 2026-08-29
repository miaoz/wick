import SpriteKit

/// SpriteKit rendering for the simulated sheet (ported from himekuri's `PaperScene`):
/// the printed day page is a texture warped every frame by an `SKWarpGeometryGrid`
/// driven from the solver's grid positions. Only the *top* page is warped here —
/// the pad, next page, binding and gesture live in SwiftUI (`TradingCalendarRootView`).
@MainActor
final class CalendarPaperScene: SKScene {
    var sim: PaperSim?
    private let layout: PaperLayout
    private var sprite: SKSpriteNode?
    private var sourcePositions: [vector_float2] = []
    private var lastTime: TimeInterval = 0
    /// Consecutive frames with a frozen geometry revision. SpriteKit runs its
    /// update loop at display rate even when nothing moves, so once the sheet
    /// has settled the scene (and its view) pause themselves; any drag or
    /// texture swap calls `wake()` first.
    private var idleFrameCount = 0
    /// Last `PaperSim.geometryRevision` we built a warp for; unchanged means
    /// the page is asleep and no `SKWarpGeometryGrid` is rebuilt (PF-02).
    private var lastWarpRevision = -1
    /// Test-observable count of `SKWarpGeometryGrid` constructions.
    private(set) var warpBuildCount = 0

    init(layout: PaperLayout) {
        self.layout = layout
        super.init(size: CGSize(width: layout.sceneW, height: layout.sceneH))
        backgroundColor = .clear
        scaleMode = .resizeFill
        sourcePositions = Self.warpPositions(for: PaperSim.restLayout(for: layout), layout: layout)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setPageTexture(_ texture: SKTexture) {
        if sprite == nil {
            let node = SKSpriteNode(texture: texture)
            node.anchorPoint = .zero
            node.size = CGSize(width: layout.pageW, height: layout.pageH)
            node.position = CGPoint(x: layout.overhangX, y: layout.overhangBottom)
            addChild(node)
            sprite = node
        } else {
            sprite?.texture = texture
        }
        // A texture swap is a render change even if the geometry is asleep.
        markDirty()
    }

    /// Forces the next frame to rebuild the warp grid regardless of the sim's
    /// geometry revision (texture replace / layout change).
    func markDirty() {
        lastWarpRevision = -1
        wake()
    }

    /// Resumes the update loop after an idle pause. `lastTime` is cleared so
    /// the first resumed step uses the nominal 1/60 s instead of the whole
    /// pause duration as one solver step.
    func wake() {
        isPaused = false
        view?.isPaused = false
        lastTime = 0
        idleFrameCount = 0
    }

    override func update(_ currentTime: TimeInterval) {
        guard let sim, let sprite else { return }
        // Clamped: a stray large gap must never become one giant solver step.
        let dt = min(lastTime == 0 ? 1.0 / 60.0 : currentTime - lastTime, 0.05)
        lastTime = currentTime
        sim.step(Float(dt))

        // While the page sleeps the revision is frozen, so no target arrays
        // and no `SKWarpGeometryGrid` are allocated for it. After ~1.5 s of
        // stillness the render loop stops entirely (CA-08): the pad on the
        // desk is a static bitmap until the next grab.
        guard sim.geometryRevision != lastWarpRevision else {
            idleFrameCount += 1
            if idleFrameCount >= 90 {
                isPaused = true
                view?.isPaused = true
            }
            return
        }
        idleFrameCount = 0
        lastWarpRevision = sim.geometryRevision
        warpBuildCount += 1
        sprite.warpGeometry = SKWarpGeometryGrid(
            columns: PaperSim.cols - 1,
            rows: PaperSim.rows - 1,
            sourcePositions: sourcePositions,
            destinationPositions: Self.warpPositions(for: sim.pos, layout: layout)
        )
    }

    /// Solver grid (page coords, y down, row-major from the top) -> warp grid
    /// (normalized sprite coords, y up, row-major from the BOTTOM-left).
    private nonisolated static func warpPositions(for grid: [SIMD3<Float>], layout: PaperLayout) -> [vector_float2] {
        var out = [vector_float2](repeating: .zero, count: grid.count)
        for r in 0..<PaperSim.rows {
            for c in 0..<PaperSim.cols {
                let p = grid[r * PaperSim.cols + c]
                let gi = (PaperSim.rows - 1 - r) * PaperSim.cols + c
                out[gi] = vector_float2(
                    p.x / Float(layout.pageW),
                    1 - p.y / Float(layout.pageH)
                )
            }
        }
        return out
    }
}
