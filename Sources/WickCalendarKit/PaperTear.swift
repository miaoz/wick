import SwiftUI

/// Generates the jagged tear-line y offsets for a given seed and width (ported from himekuri).
///
/// Every tear is different: about a third are *perfect* - the fibers part right along the
/// binding and leave nothing visible - while the rest leave ragged remnants in patches,
/// the way real paper lets go unevenly. `base` is the page-local tear-line y.
func tearEdgePoints(seed: UInt64, width: CGFloat, base: CGFloat) -> [CGPoint] {
    var rng = SeededRandom(seed: seed)
    let clean = rng.unit() < 0.35

    var y = base + (clean ? rng.cg(-2...1) : rng.cg(-3...5))
    var points: [CGPoint] = [CGPoint(x: 0, y: min(y, base + 9))]
    var inPatch = rng.unit() < 0.5
    var x: CGFloat = 0
    while x < width {
        x = min(x + rng.cg(6...16), width)
        if clean {
            y = base + rng.cg(-2...2)
        } else {
            if rng.unit() < 0.12 { inPatch.toggle() }
            let target = inPatch ? base + rng.cg(4...9) : base + rng.cg(-4...1)
            y = (y + target) / 2 + rng.cg(-1.5...1.5)
        }
        points.append(CGPoint(x: x, y: min(y, base + 9)))
    }
    return points
}

/// The piece that falls: full page below a jagged top edge.
struct TornPieceShape: Shape {
    let seed: UInt64
    let base: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let edge = tearEdgePoints(seed: seed, width: rect.width, base: base)
        p.move(to: edge[0])
        for pt in edge.dropFirst() { p.addLine(to: pt) }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// The remnant left under the staples: jagged bottom edge, same seed.
struct StubShape: Shape {
    let seed: UInt64
    let base: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let edge = tearEdgePoints(seed: seed, width: rect.width, base: base)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: edge[0])
        for pt in edge.dropFirst() { p.addLine(to: pt) }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// Just the torn edge polyline - stroked to catch the light on loose fibers.
struct TearEdgeLine: Shape {
    let seed: UInt64
    let base: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let edge = tearEdgePoints(seed: seed, width: rect.width, base: base)
        p.move(to: edge[0])
        for pt in edge.dropFirst() { p.addLine(to: pt) }
        return p
    }
}
