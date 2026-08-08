import SwiftUI

/// Page metrics, matching himekuri's geometry.
enum TradingCalendarGeometry {
    static let pageW: CGFloat = 300
    static let pageH: CGFloat = 400
    static let bindingH: CGFloat = 26
    /// Page-local y of the tear line (the paper above this stays under the staples).
    static let tearY: CGFloat = 20
    static let pageTopInset: CGFloat = 6
    static let blockTopPad: CGFloat = 26
    static let windowW: CGFloat = 480
    static let windowH: CGFloat = 690
    /// Pull needed to *initiate* the tear.
    static let tearThreshold: CGFloat = 118
    /// Fraction of the page (from the bottom) that responds to the tear gesture.
    static let tearZone: CGFloat = 0.93
    /// Page-local y where the events compartment begins (≈ top pad + masthead +
    /// hero + lunar line). Only used to hit-test taps that flip event pages.
    static let eventsPaneTopY: CGFloat = 170
    /// Transparent margin around the top page so the sheet can swing/droop unclipped.
    static let overhangX: CGFloat = 70
    static let overhangBottom: CGFloat = 210
}

/// Palette + typography for the trading calendar, modelled on himekuri's「黄历」
/// theme: green ink on cream paper, red used only for rules/seals/labels.
struct TradingCalendarTheme {
    static let paper = Color(red: 0.985, green: 0.982, blue: 0.972)   // #FBFBF8
    static let ink = Color(red: 0.086, green: 0.514, blue: 0.286)     // #168349 green
    static let red = Color(red: 0.82, green: 0.22, blue: 0.13)        // #D13821
    static let grain = Color(red: 0.45, green: 0.38, blue: 0.28)      // #736147 (fibre tint)
    static let paperEdge = Color(red: 0.82, green: 0.80, blue: 0.72)  // stacked-sheet edge tint
    static let dimInk = ink.opacity(0.75)
    static let faintInk = ink.opacity(0.5)

    // MARK: - Type

    /// Heavy gothic kanji (HiraginoSans-W7).
    static func kanji(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .custom("HiraginoSans-W7", size: size)
    }

    /// Serif mincho for small traditional text (HiraMinProN-W6).
    static func mincho(_ size: CGFloat) -> Font {
        .custom("HiraMinProN-W6", size: size)
    }

    /// The fat slab day numeral.
    static func numeral(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .serif)
    }

}

extension Color {
    /// Linearly interpolates two sRGB colors by `amount` (0 = self, 1 = other).
    func blended(with other: Color, by amount: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB)
        let b = NSColor(other).usingColorSpace(.sRGB)
        guard let a, let b else { return self }
        let t = CGFloat(amount)
        return Color(
            red: a.redComponent + (b.redComponent - a.redComponent) * t,
            green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
            blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t,
            opacity: a.alphaComponent + (b.alphaComponent - a.alphaComponent) * t
        )
    }
}
