import SwiftUI

// MARK: - Burn strip · 烛痕条

/// The signature component of the「秉烛」system: elapsed time is a warm stain
/// left by candlelight, the frontier is a thin ember line with a small flame,
/// the future is clean ruled paper. Tick semantics: day 24 / week 7 /
/// month = days in month / year 12.
public struct BurnStripView: View {
    @Environment(\.wickPalette) private var palette

    /// 0...1, fraction already elapsed.
    public var elapsed: Double
    /// Tick segment count (24 / 7 / 28...31 / 12).
    public var ticks: Int
    /// Show the flame dot (hero tier only).
    public var showsFlame: Bool

    public init(elapsed: Double, ticks: Int = 24, showsFlame: Bool = false) {
        self.elapsed = elapsed
        self.ticks = ticks
        self.showsFlame = showsFlame
    }

    private var fraction: Double { min(1, max(0, elapsed)) }

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let frontier = size.width * fraction
            ZStack(alignment: .leading) {
                // 1. Unburnt ruled paper: background + vertical tick divisions
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(palette.cardTop.color)

                TickMarksShape(ticks: ticks)
                    .stroke(palette.divider.color, lineWidth: 0.75)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

                // 2. Candle stain (elapsed) with an irregular edge
                StainShape(fraction: fraction)
                    .fill(
                        LinearGradient(
                            colors: [palette.stain1.color, palette.stain2.color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

                // 3. Outer enclosing rule frame (1px border wrapping both elapsed and remaining slots)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(palette.divider.color, lineWidth: 1)

                // 4. Warm halo hugging the frontier
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [palette.accent.color.opacity(0.4), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: size.height * 1.4
                        )
                    )
                    .frame(width: size.height * 2.8, height: size.height * 2.8)
                    .position(x: frontier, y: size.height / 2)
                    .opacity(fraction > 0.002 ? 1 : 0)

                // 5. Ember line at the frontier
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [palette.accent.color.opacity(0.25), palette.accent.color, palette.accentText.color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 2.5, height: size.height + 2)
                    .position(x: frontier, y: size.height / 2)
                    .shadow(color: palette.glow.color, radius: 4)
                    .opacity(fraction > 0.002 ? 1 : 0)

                // 6. Flame dot (hero tier)
                if showsFlame, fraction > 0.002 {
                    FlameDot()
                        .frame(width: 8, height: 8)
                        .position(x: frontier, y: size.height / 2)
                        .shadow(color: palette.glow.color, radius: 5)
                }
            }
        }
        .accessibilityElement(children: .ignore)
    }
}

/// Vertical hairlines dividing the strip into `ticks` segments.
public struct TickMarksShape: Shape {
    public var ticks: Int

    public init(ticks: Int) {
        self.ticks = ticks
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let count = max(1, ticks)
        for index in 1..<count {
            let x = rect.width * CGFloat(index) / CGFloat(count)
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
        }
        return path
    }
}

/// The elapsed area; its right (frontier) edge wobbles with a deterministic
/// sum-of-sines so every strip has a hand-torn, candle-warmed edge.
public struct StainShape: Shape {
    public var fraction: Double
    public var seed: Double

    public init(fraction: Double, seed: Double = 7) {
        self.fraction = fraction
        self.seed = seed
    }

    public func path(in rect: CGRect) -> Path {
        let fx = rect.width * min(1, max(0, fraction))
        guard fx > 0.5 else { return Path() }

        func wobble(_ t: CGFloat) -> CGFloat {
            sin(t * 9 + seed) * 1.05 + sin(t * 23 + seed * 3.1) * 0.65 + sin(t * 41 + seed * 1.7) * 0.35
        }

        var path = Path()
        let steps = 24
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: fx + wobble(0), y: 0))
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            path.addLine(to: CGPoint(x: fx + wobble(t), y: rect.height * t))
        }
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}

/// The small flame at the burn frontier.
public struct FlameDot: View {
    @Environment(\.wickPalette) private var palette
    @State private var breathing = false

    public init() {}

    public var body: some View {
        TeardropShape()
            .fill(
                RadialGradient(
                    colors: [
                        Color(red: 1.0, green: 0.94, blue: 0.78),
                        palette.accent.lightened(by: 0.25).color,
                        palette.accent.color,
                    ],
                    center: .init(x: 0.5, y: 0.35),
                    startRadius: 0,
                    endRadius: 6
                )
            )
            .opacity(breathing ? 0.72 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
    }
}

/// Upright flame teardrop, normalized to its bounding box.
public struct TeardropShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: w * 0.5, y: 0))
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: h),
            control1: CGPoint(x: w * -0.05, y: h * 0.42),
            control2: CGPoint(x: w * 0.12, y: h * 0.8)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: 0),
            control1: CGPoint(x: w * 0.88, y: h * 0.8),
            control2: CGPoint(x: w * 1.05, y: h * 0.42)
        )
        path.closeSubpath()
        return path
    }
}
