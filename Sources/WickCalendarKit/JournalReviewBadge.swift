import SwiftUI
import WickSync

// MARK: - Review seal · 对错方章

/// Verdict mark for a reviewed journal item — a square white-character seal
/// (白文篆刻). The ink follows the 涨跌配色 convention: 对 = the gain color,
/// 错 = the loss color (red-up: 对 red / 错 green; green-up: reversed).
/// Three layers: distressed seal body (silhouette-only wobble), uneven ink
/// shading, crisp character. Stamps in with a 0.3s slam on appear.
public struct JournalReviewBadge: View {
    public enum Style {
        case seal
        case mini
    }

    @Environment(\.wickPalette) private var palette
    @Environment(\.pnlColorConvention) private var envConvention

    public let verdict: JournalReviewVerdict
    public var style: Style
    public var size: CGFloat
    public var convention: PnlColorConvention?
    public var language: AppLanguage

    @State private var stamped = false

    public init(
        verdict: JournalReviewVerdict,
        style: Style = .seal,
        size: CGFloat = 52,
        convention: PnlColorConvention? = nil,
        language: AppLanguage = .system
    ) {
        self.verdict = verdict
        self.style = style
        self.size = size
        self.convention = convention
        self.language = language
    }

    public var body: some View {
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

    private var glyph: String {
        let isChinese = (language == .chinese) || (language == .system && Locale.current.language.languageCode?.identifier == "zh")
        switch verdict {
        case .correct: return isChinese ? "对" : "✓"
        case .wrong: return isChinese ? "错" : "✗"
        }
    }

    private var glyphFont: Font {
        let isChinese = (language == .chinese) || (language == .system && Locale.current.language.languageCode?.identifier == "zh")
        if isChinese {
            return TradingCalendarTheme.kanji(size * 0.46, weight: .bold)
        }
        return TradingCalendarTheme.kanji(size * 0.44, weight: .heavy)
    }

    private var inkColor: WickRGB {
        verdict.inkColor(in: palette, convention: convention ?? envConvention)
    }
    private var charColor: Color { Color(red: 0.97, green: 0.91, blue: 0.84) }

    private var accessibilityText: String {
        switch verdict {
        case .correct: return L10n.string(.journalReviewCorrect, language: language)
        case .wrong: return L10n.string(.journalReviewWrong, language: language)
        }
    }
}

/// Square seal silhouette with a hand-chipped edge. Deterministic per seal;
/// displacement applies to the ink body only, the character stays crisp.
public struct SealBodyShape: Shape {
    public var seed: Double

    public init(seed: Double = 9) {
        self.seed = seed
    }

    public func path(in rect: CGRect) -> Path {
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

public extension JournalReviewVerdict {
    /// 对 = 涨色、错 = 跌色 —— 印章颜色跟随「涨跌配色」配置。
    func inkColor(in palette: WickPalette, convention: PnlColorConvention = .redUp) -> WickRGB {
        let pair = palette.upDownColors(convention)
        switch self {
        case .correct: return pair.gain
        case .wrong: return pair.loss
        }
    }
}
