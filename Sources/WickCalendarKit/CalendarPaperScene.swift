import SpriteKit

/// SpriteKit rendering for the simulated sheet (ported from himekuri's `PaperScene`):
/// the printed day page is a texture warped every frame by an `SKWarpGeometryGrid`
/// driven from the solver's grid positions. Only the *top* page is warped here —
/// the pad, next page, binding and gesture live in SwiftUI (`TradingCalendarRootView`).
@MainActor
final class CalendarPaperScene: SKScene {
    var sim: PaperSim?
    private var sprite: SKSpriteNode?
    private var sourcePositions: [vector_float2] = []
    private var lastTime: TimeInterval = 0

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        sourcePositions = Self.warpPositions(for: PaperSim.restLayout())
    }

    required init?(coder: NSCoder) { fatalError() }

    func setPageTexture(_ texture: SKTexture) {
        if sprite == nil {
            let node = SKSpriteNode(texture: texture)
            node.anchorPoint = .zero
            node.size = CGSize(
                width: TradingCalendarGeometry.pageW,
                height: TradingCalendarGeometry.pageH
            )
            node.position = CGPoint(
                x: TradingCalendarGeometry.overhangX,
                y: TradingCalendarGeometry.overhangBottom
            )
            addChild(node)
            sprite = node
        } else {
            sprite?.texture = texture
        }
    }

    override func update(_ currentTime: TimeInterval) {
        guard let sim, let sprite else { return }
        let dt = lastTime == 0 ? 1.0 / 60.0 : currentTime - lastTime
        lastTime = currentTime
        sim.step(Float(dt))

        sprite.warpGeometry = SKWarpGeometryGrid(
            columns: PaperSim.cols - 1,
            rows: PaperSim.rows - 1,
            sourcePositions: sourcePositions,
            destinationPositions: Self.warpPositions(for: sim.pos)
        )
    }

    /// Solver grid (page coords, y down, row-major from the top) → warp grid
    /// (normalized sprite coords, y up, row-major from the BOTTOM-left).
    private nonisolated static func warpPositions(for grid: [SIMD3<Float>]) -> [vector_float2] {
        var out = [vector_float2](repeating: .zero, count: grid.count)
        for r in 0..<PaperSim.rows {
            for c in 0..<PaperSim.cols {
                let p = grid[r * PaperSim.cols + c]
                let gi = (PaperSim.rows - 1 - r) * PaperSim.cols + c
                out[gi] = vector_float2(
                    p.x / Float(TradingCalendarGeometry.pageW),
                    1 - p.y / Float(TradingCalendarGeometry.pageH)
                )
            }
        }
        return out
    }
}
