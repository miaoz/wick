import SwiftUI

// MARK: - Paper chrome · 秉烛系统的纸质外壳件

/// Paper slip silhouette with a hand-torn top edge (deterministic sum-of-sines)
/// and slightly rounded bottom corners. Deformation lives on the shape only —
/// content on top is never displaced.
struct TornSlipShape: Shape {
    var tearAmplitude: Double = 1.8
    var seed: Double = 4
    var cornerRadius: Double = 6

    func path(in rect: CGRect) -> Path {
        func tear(_ t: CGFloat) -> CGFloat {
            // t in 0...1 across the top edge
            sin(t * 26 + seed) * tearAmplitude * 0.55
                + sin(t * 61 + seed * 2.3) * tearAmplitude * 0.3
                + sin(t * 9 + seed * 1.1) * tearAmplitude * 0.45
        }

        var path = Path()
        let inset = tearAmplitude + 0.5
        let top = rect.minY + inset
        let steps = 36

        path.move(to: CGPoint(x: rect.minX, y: top + tear(0)))
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            path.addLine(to: CGPoint(x: rect.minX + rect.width * t, y: top + tear(t)))
        }
        // Right side down to the rounded bottom-right corner
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

/// Brand tile: the candle mark on a near-black square. The glyph colors are
/// brand artwork (same candle as the app icon), intentionally theme-exempt;
/// the tile color comes from `palette.brandTile`.
struct CandleTileView: View {
    @Environment(\.wickPalette) private var palette
    var size: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
            .fill(palette.brandTile.color)
            .frame(width: size, height: size)
            .overlay {
                CandleGlyph()
                    .padding(size * 0.24)
            }
            .shadow(color: palette.glow.color, radius: size * 0.35, y: 1)
    }
}

/// The candle glyph (flame + wick + body), drawn in brand colors.
struct CandleGlyph: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                // Flame
                TeardropGlyph()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.88, blue: 0.55),
                                Color(red: 0.94, green: 0.62, blue: 0.24),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: w * 0.46, height: h * 0.42)
                    .position(x: w * 0.5, y: h * 0.22)
                // Wick
                Rectangle()
                    .fill(Color(red: 0.79, green: 0.72, blue: 0.58))
                    .frame(width: max(1, w * 0.05), height: h * 0.12)
                    .position(x: w * 0.5, y: h * 0.5)
                // Body
                CandleBodyGlyph()
                    .fill(Color(red: 0.91, green: 0.86, blue: 0.75))
                    .frame(width: w * 0.72, height: h * 0.44)
                    .position(x: w * 0.5, y: h * 0.77)
            }
        }
    }
}

private struct TeardropGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: w * 0.5, y: 0))
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: h),
            control1: CGPoint(x: w * -0.08, y: h * 0.45),
            control2: CGPoint(x: w * 0.14, y: h * 0.82)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: 0),
            control1: CGPoint(x: w * 0.86, y: h * 0.82),
            control2: CGPoint(x: w * 1.08, y: h * 0.45)
        )
        path.closeSubpath()
        return path
    }
}

private struct CandleBodyGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: w * 0.06, y: 0))
        path.addLine(to: CGPoint(x: w * 0.94, y: 0))
        path.addLine(to: CGPoint(x: w, y: h * 0.82))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: h * 0.82),
            control: CGPoint(x: w * 0.5, y: h * 1.08)
        )
        path.closeSubpath()
        return path
    }
}

/// Receipt silhouette torn top and bottom (exchange slips are torn off a
/// roll). Deformation lives on the shape only — content stays crisp.
struct ReceiptShape: Shape {
    var tearAmplitude: Double = 1.3
    var seed: Double = 11

    func path(in rect: CGRect) -> Path {
        func tear(_ t: CGFloat, _ phase: Double) -> CGFloat {
            sin(t * 24 + phase) * tearAmplitude * 0.5
                + sin(t * 57 + phase * 2.1) * tearAmplitude * 0.32
                + sin(t * 8 + phase * 0.8) * tearAmplitude * 0.42
        }

        var path = Path()
        let inset = tearAmplitude + 0.5
        let top = rect.minY + inset
        let bottom = rect.maxY - inset
        let steps = 30

        path.move(to: CGPoint(x: rect.minX, y: top + tear(0, seed)))
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            path.addLine(to: CGPoint(x: rect.minX + rect.width * t, y: top + tear(t, seed)))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: bottom))
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            path.addLine(to: CGPoint(x: rect.maxX - rect.width * t, y: bottom + tear(t, seed + 5)))
        }
        path.closeSubpath()
        return path
    }
}

/// Translucent tape strip pasted over the receipt's top corners.
struct TapeStrip: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(Color(red: 0.93, green: 0.83, blue: 0.6).opacity(0.5))
            .overlay {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .strokeBorder(Color(red: 0.85, green: 0.72, blue: 0.45).opacity(0.35), lineWidth: 0.5)
            }
    }
}

/// 刻印小方钮:常态无框融入纸面,hover 浮起 1pt 烛火墨线并起光;`isOn` =
/// 烛火实底的点亮态(检查器开关等)。面板头部/工具性按钮统一用它。
struct InkIconButton: View {
    @Environment(\.wickPalette) private var palette
    let systemName: String
    let help: String
    var size: CGFloat = 28
    var isOn: Bool = false
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.45, weight: .medium))
                .foregroundStyle(
                    isOn ? Color(red: 1, green: 0.95, blue: 0.88)
                        : (isHovered ? palette.accent.color : palette.textSecondary.color)
                )
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isOn ? palette.accent.color : (isHovered ? palette.accentSoft.color : .clear))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(
                            isOn ? palette.accent.color : (isHovered ? palette.accent.color : .clear),
                            lineWidth: 1
                        )
                }
                .shadow(color: (isHovered || isOn) ? palette.glow.color : .clear, radius: 5)
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isOn)
    }
}
