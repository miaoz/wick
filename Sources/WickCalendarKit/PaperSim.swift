import Foundation
import simd

/// Real paper physics in the spirit of Ghassaei's Origami Simulator, ported from
/// himekuri's `PaperSim`: a verlet-integrated grid with inextensible distance
/// constraints, stiff bending constraints, and breakable fibers along the tear line.
/// Simulated in 3D — the bulge toward the viewer is what shortens the on-screen
/// projection, exactly like real paper.
///
/// Grid: `cols × rows`. Row 0 is the page top edge (pinned under the staples);
/// row 1 is the tear line - a column is only pinned there while its fiber is intact.
final class PaperSim {
    nonisolated static let cols = 11
    nonisolated static let rows = 14

    private let layout: PaperLayout
    private(set) var pos: [SIMD3<Float>] = []
    private var prev: [SIMD3<Float>] = []
    private var home: [SIMD3<Float>] = []

    private struct Constraint {
        let a: Int
        let b: Int
        let rest: Float
        let k: Float
    }

    private var constraints: [Constraint] = []
    /// Per-column: does the fiber at the tear line still hold the page?
    private(set) var fiberIntact = [Bool](repeating: true, count: cols)
    private var grabIndex: Int?
    private var grabTarget = SIMD3<Float>(0, 0, 0)
    private var sleeping = true

    init(layout: PaperLayout = .desktop) {
        self.layout = layout
        reset()
    }

    /// Grid vertex positions for a flat page at rest (page coordinates, z = 0).
    /// Row 0 sits at the top edge; row 1 is the tear line; the rest spread below.
    nonisolated static func restLayout(for layout: PaperLayout = .desktop) -> [SIMD3<Float>] {
        let w = Float(layout.pageW)
        var points: [SIMD3<Float>] = []
        points.reserveCapacity(rows * cols)
        for r in 0..<rows {
            let y = restRowY(r, layout: layout)
            for c in 0..<cols {
                points.append(SIMD3(Float(c) / Float(cols - 1) * w, y, 0))
            }
        }
        return points
    }

    private nonisolated static func restRowY(_ r: Int, layout: PaperLayout) -> Float {
        let h = Float(layout.pageH)
        let tearY = Float(layout.tearY)
        switch r {
        case 0: return 0
        case 1: return tearY
        default: return tearY + (h - tearY) * Float(r - 1) / Float(rows - 2)
        }
    }

    /// Rest state: a flat page hanging on the pad. Bumps the geometry revision
    /// so a renderer that skipped warps while the page slept redraws the rest
    /// geometry on the next frame (AC-P2-01).
    func reset() {
        geometryRevision += 1
        pos = Self.restLayout(for: layout)
        // A hair of z noise so in-plane compression buckles OUT (toward the viewer)
        // instead of fighting a perfect plane.
        var jitter = SeededRandom(seed: 0xC0FFEE)
        for i in pos.indices {
            pos[i].z = 0.02 + 0.02 * jitter.unit()
        }
        prev = pos
        home = pos
        fiberIntact = .init(repeating: true, count: Self.cols)
        grabIndex = nil
        sleeping = true
        if constraints.isEmpty { buildConstraints() }
    }

    private func idx(_ r: Int, _ c: Int) -> Int { r * Self.cols + c }

    private func buildConstraints() {
        func add(_ a: Int, _ b: Int, _ k: Float) {
            constraints.append(.init(a: a, b: b, rest: simd_distance(home[a], home[b]), k: k))
        }
        for r in 0..<Self.rows {
            for c in 0..<Self.cols {
                let i = idx(r, c)
                if c + 1 < Self.cols { add(i, idx(r, c + 1), 1.0) }
                if r + 1 < Self.rows { add(i, idx(r + 1, c), 1.0) }
                if c + 1 < Self.cols, r + 1 < Self.rows {
                    add(i, idx(r + 1, c + 1), 0.9)
                    add(idx(r, c + 1), idx(r + 1, c), 0.9)
                }
                if c + 2 < Self.cols { add(i, idx(r, c + 2), 0.55) }
                if r + 2 < Self.rows { add(i, idx(r + 2, c), 0.55) }
            }
        }
    }

    // MARK: - Interaction

    func setGrab(at p: CGPoint) {
        var best = idx(1, 0)
        var bestD = Float.greatestFiniteMagnitude
        for r in 1..<Self.rows {
            for c in 0..<Self.cols {
                let i = idx(r, c)
                let d = simd_distance_squared(
                    SIMD3(Float(p.x), Float(p.y), 0),
                    SIMD3(home[i].x, home[i].y, 0)
                )
                if d < bestD { bestD = d; best = i }
            }
        }
        grabIndex = best
        grabTarget = SIMD3(Float(p.x), Float(p.y), 16)
        sleeping = false
    }

    func moveGrab(to p: CGPoint, lift: CGFloat) {
        grabTarget = SIMD3(Float(p.x), Float(p.y), 10 + 20 * Float(lift))
        sleeping = false
    }

    func release() {
        grabIndex = nil
        sleeping = false
    }

    /// Seam state comes from the gesture's crack model: columns within `front`
    /// points of `centerX` (page x) have lost their fiber at the tear line.
    /// Fibers never reattach, so damage is cumulative.
    func setSeam(centerX: CGFloat, front: CGFloat) {
        let w = Float(layout.pageW)
        for c in 0..<Self.cols {
            let x = Float(c) / Float(Self.cols - 1) * w
            let broken = abs(x - Float(centerX)) < Float(front)
            if broken, fiberIntact[c] { sleeping = false }
            fiberIntact[c] = fiberIntact[c] && !broken
        }
    }

    // MARK: - Stepping

    /// Monotonic revision of the grid, bumped only when a step actually moves
    /// it. Rendering uses this to skip rebuilding warp geometry while the page
    /// is asleep (PF-02).
    private(set) var geometryRevision = 0

    func step(_ dt: Float) {
        guard !sleeping else { return }
        geometryRevision += 1
        let sub = 2
        let h = min(dt, 1.0 / 30.0) / Float(sub)
        for _ in 0..<sub { substep(h) }
        checkSleep()
    }

    private func pinned(_ i: Int) -> Bool {
        let r = i / Self.cols
        if r == 0 { return true }
        if r == 1 { return fiberIntact[i % Self.cols] }
        return i == grabIndex
    }

    private func substep(_ h: Float) {
        let h2 = h * h
        let held = grabIndex != nil
        // Held paper carries its momentum; released paper is spring-stiff —
        // bending energy snaps it flat against the pad with barely a bounce.
        let damp: Float = held ? 0.975 : 0.93
        for i in pos.indices where !pinned(i) {
            var v = (pos[i] - prev[i]) * damp
            v.z *= 0.9 // air resists the out-of-plane flap hardest
            prev[i] = pos[i]
            pos[i] += v
            pos[i].y += 480 * h2 // gravity down the wall
            pos[i].z += 40 * h2  // the pad nudges slack paper outward
            if !held {
                // Torn-free columns keep their hang; attached paper flattens.
                let k: Float = fiberIntact[i % Self.cols] ? 0.09 : 0.03
                pos[i] += (home[i] - pos[i]) * k
            }
        }
        if let g = grabIndex { pos[g] = grabTarget }

        for _ in 0..<7 {
            for con in constraints {
                let wa: Float = pinned(con.a) ? 0 : 1
                let wb: Float = pinned(con.b) ? 0 : 1
                let wSum = wa + wb
                if wSum == 0 { continue }
                let d = pos[con.b] - pos[con.a]
                let len = max(simd_length(d), 1e-5)
                let corr = d * ((len - con.rest) / len * con.k)
                pos[con.a] += corr * (wa / wSum)
                pos[con.b] -= corr * (wb / wSum)
            }
            // Pins never drift; the grip never slips.
            for c in 0..<Self.cols {
                pos[idx(0, c)] = home[idx(0, c)]
                if fiberIntact[c] { pos[idx(1, c)] = home[idx(1, c)] }
            }
            if let g = grabIndex { pos[g] = grabTarget }
        }

        // The pad is right behind the sheet.
        for i in pos.indices where pos[i].z < 0 { pos[i].z = 0 }
    }

    private func checkSleep() {
        guard grabIndex == nil else { return }
        var maxMove: Float = 0
        var maxVel: Float = 0
        for i in pos.indices {
            maxMove = max(maxMove, simd_distance_squared(pos[i], home[i]))
            maxVel = max(maxVel, simd_distance_squared(pos[i], prev[i]))
        }
        if maxVel < 0.0004 {
            if fiberIntact.allSatisfy({ $0 }), maxMove < 0.4 {
                pos = home
                prev = home
            }
            sleeping = true
        }
    }
}
