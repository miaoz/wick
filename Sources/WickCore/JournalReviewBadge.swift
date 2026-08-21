import SwiftUI
import WickSync

// MARK: - Review seal · 朱砂方章

/// Verdict mark for a reviewed journal item — a square white-on-cinnabar seal
/// (白文篆刻). Always cinnabar; the character carries the meaning, like a real
/// chop. Three layers: distressed seal body (silhouette-only wobble), uneven
/// ink shading, crisp character. Stamps in with a 0.3s slam on appear.
struct JournalReviewBadge: View {
    enum Style {
        case seal
        case mini
    }

    @Environment(\.wickPalette) private var palette
    @EnvironmentObject private var settings: AppSettings

    let verdict: JournalReviewVerdict
    var style: Style = .seal
    /// Seal edge length in points.
    var size: CGFloat = 52

    @State private var stamped = false

    var body: some View {
        switch style {
        case .seal:
            seal
                .rotationEffect(.degrees(-6))
                .scaleEffect(stamped ? 1 : 1.7)
                .opacity(stamped ? 1 : 0)
                .onAppear {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                        stamped = true
                    }
                }
        case .mini:
            seal
        }
    }

    private var seal: some View {
        ZStack {
            // Seal body: distressed square, ink pooled unevenly
            SealBodyShape(seed: 9)
                .fill(
                    RadialGradient(
                        colors: [inkColor.lightened(by: 0.08).color, inkColor.color, inkColor.darkened(by: 0.18).color],
                        center: .init(x: 0.3, y: 0.22),
                        startRadius: 0,
                        endRadius: size * 1.15
                    )
                )
            SealBodyShape(seed: 9)
                .stroke(charColor.opacity(0.38), lineWidth: max(1, size * 0.03))
                .padding(size * 0.09)
            Text(glyph)
                .font(glyphFont)
                .foregroundStyle(charColor)
        }
        .frame(width: size, height: size)
        .shadow(color: inkColor.withAlpha(0.3).color, radius: 1.5, y: 1)
        .accessibilityLabel(accessibilityText)
    }

    /// 中文 UI 用「对/错」篆刻字;英文 UI 用 ✓/✗(同一方章,靠字表意)。
    private var glyph: String {
        let chinese = settings.language == .chinese
        switch verdict {
        case .correct: return chinese ? "对" : "✓"
        case .wrong: return chinese ? "错" : "✗"
        }
    }

    private var glyphFont: Font {
        if settings.language == .chinese {
            return .custom("Songti SC", size: size * 0.46).weight(.bold)
        }
        return .system(size: size * 0.44, weight: .heavy)
    }

    /// Both verdicts print in cinnabar — a real seal is always red.
    private var inkColor: WickRGB { palette.reviewCorrect }
    private var charColor: Color { Color(red: 0.97, green: 0.91, blue: 0.84) }

    private var accessibilityText: String {
        switch verdict {
        case .correct: return L10n.string(.journalReviewCorrect, language: settings.language)
        case .wrong: return L10n.string(.journalReviewWrong, language: settings.language)
        }
    }
}

/// Square seal silhouette with a hand-chipped edge. Deterministic per seal;
/// displacement applies to the ink body only, the character stays crisp.
private struct SealBodyShape: Shape {
    var seed: Double

    func path(in rect: CGRect) -> Path {
        func chip(_ t: CGFloat, _ phase: Double) -> CGFloat {
            sin(t * 21 + phase) * 0.9 + sin(t * 47 + phase * 2.2) * 0.55 + sin(t * 8 + phase * 0.7) * 0.8
        }

        var path = Path()
        let steps = 14
        let corner = rect.width * 0.08

        // Top edge, left → right
        path.move(to: CGPoint(x: rect.minX + corner, y: rect.minY + chip(0, seed)))
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            path.addLine(to: CGPoint(x: rect.minX + corner + (rect.width - 2 * corner) * t, y: rect.minY + chip(t, seed)))
        }
        // Right edge, top → bottom
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            path.addLine(to: CGPoint(x: rect.maxX + chip(t, seed + 3), y: rect.minY + corner + (rect.height - 2 * corner) * t))
        }
        // Bottom edge, right → left
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            path.addLine(to: CGPoint(x: rect.maxX - corner - (rect.width - 2 * corner) * t, y: rect.maxY + chip(t, seed + 6)))
        }
        // Left edge, bottom → top
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            path.addLine(to: CGPoint(x: rect.minX + chip(t, seed + 9), y: rect.maxY - corner - (rect.height - 2 * corner) * t))
        }
        path.closeSubpath()
        return path
    }
}

extension JournalReviewVerdict {
    /// Glyph color for custom chrome (e.g. the verdict picker buttons).
    func color(in palette: WickPalette) -> Color {
        switch self {
        case .correct: return palette.reviewCorrect.color
        case .wrong: return palette.reviewWrong.color
        }
    }
}
