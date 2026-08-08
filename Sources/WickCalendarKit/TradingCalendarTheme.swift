import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Page metrics, matching himekuri's geometry.
public enum TradingCalendarGeometry {
    public static let pageW: CGFloat = 300
    public static let pageH: CGFloat = 400
    public static let bindingH: CGFloat = 26
    /// Page-local y of the tear line (the paper above this stays under the staples).
    public static let tearY: CGFloat = 20
    public static let pageTopInset: CGFloat = 6
    public static let blockTopPad: CGFloat = 26
    public static let windowW: CGFloat = 480
    public static let windowH: CGFloat = 690
    /// Pull needed to *initiate* the tear.
    public static let tearThreshold: CGFloat = 118
    /// Fraction of the page (from the bottom) that responds to the tear gesture.
    public static let tearZone: CGFloat = 0.93
    /// Page-local y where the events compartment begins (≈ top pad + masthead +
    /// hero + lunar line). Only used to hit-test taps that flip event pages.
    public static let eventsPaneTopY: CGFloat = 170
    /// Transparent margin around the top page so the sheet can swing/droop unclipped.
    public static let overhangX: CGFloat = 70
    public static let overhangBottom: CGFloat = 210
}

/// Palette + typography for the trading calendar, modelled on himekuri's「黄历」
/// theme: green ink on cream paper, red used only for rules/seals/labels.
public enum TradingCalendarTheme {
    public static let paper = Color(red: 0.985, green: 0.982, blue: 0.972)   // #FBFBF8
    public static let ink = Color(red: 0.086, green: 0.514, blue: 0.286)     // #168349 green
    public static let red = Color(red: 0.82, green: 0.22, blue: 0.13)        // #D13821
    public static let grain = Color(red: 0.45, green: 0.38, blue: 0.28)      // #736147 (fibre tint)
    public static let paperEdge = Color(red: 0.82, green: 0.80, blue: 0.72)  // stacked-sheet edge tint
    public static let dimInk = ink.opacity(0.75)
    public static let faintInk = ink.opacity(0.5)

    // MARK: - Type

    /// Heavy gothic kanji (HiraginoSans-W7).
    public static func kanji(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .custom("HiraginoSans-W7", size: size)
    }

    /// Serif mincho for small traditional text (HiraMinProN-W6).
    public static func mincho(_ size: CGFloat) -> Font {
        .custom("HiraMinProN-W6", size: size)
    }

    /// The fat slab day numeral.
    public static func numeral(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .serif)
    }
}

extension Color {
    /// Linearly interpolates two sRGB colors by `amount` (0 = self, 1 = other).
    func blended(with other: Color, by amount: Double) -> Color {
        guard let a = Self.components(of: self), let b = Self.components(of: other) else { return self }
        let t = CGFloat(amount)
        return Color(
            red: a.r + (b.r - a.r) * t,
            green: a.g + (b.g - a.g) * t,
            blue: a.b + (b.b - a.b) * t,
            opacity: a.a + (b.a - a.a) * t
        )
    }

    private static func components(of color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)? {
        #if os(macOS)
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return (r, g, b, a)
        #endif
    }
}
