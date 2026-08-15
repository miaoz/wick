import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Page metrics, matching himekuri's geometry. These are the *desktop widget*
/// values; presentations that size the pad differently describe themselves with a
/// `PaperLayout` built from them.
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
    /// Pull needed to *initiate* the tear (finger travel, not page coordinates).
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

/// Metrics for one presentation of the pad. `.desktop` reproduces the original
/// 300×400 himekuri widget exactly; `.fullScreen` is the iPhone app, where the
/// page itself is the screen - cream paper edge-to-edge, the stapled binding
/// spanning the notch row, and printed matter clear of the safe areas. Every
/// constant that used to be baked into `TradingCalendarGeometry` lives here so
/// the solver, the scene and the SwiftUI layers can share one coordinate space.
public struct PaperLayout: Sendable, Equatable, Hashable {
    /// Printed page size; also the solver's coordinate space.
    public let pageW: CGFloat
    public let pageH: CGFloat
    /// Page-local y of the tear line (the paper above it stays under the staples).
    public let tearY: CGFloat
    /// Full height of the binding strip at the top of the pad (on a full-bleed
    /// layout this includes the notch row the strip spans).
    public let bindingH: CGFloat
    /// Top part of the binding strip hidden by the notch/status area (0 on macOS).
    public let bindingSafeTop: CGFloat
    /// Gap between the top of the window and the top of the pad.
    public let blockTopPad: CGFloat
    /// Offset of the page top below the binding.
    public let pageTopInset: CGFloat
    /// Transparent margins around the top page so the sheet can swing unclipped.
    public let overhangX: CGFloat
    public let overhangBottom: CGFloat
    /// Host container size.
    public let windowW: CGFloat
    public let windowH: CGFloat
    /// Typography scale relative to the 300pt-wide desktop design.
    public let contentScale: CGFloat
    /// Page-content padding: printed matter must clear these (tear line/binding
    /// above, home indicator below).
    public let contentTopInset: CGFloat
    public let contentBottomInset: CGFloat
    /// Insets of the printed double-rule frame from the page edges. The desktop
    /// page frames its fixed sheet at 7pt all round; a full-bleed page keeps
    /// the frame clear of the notch row above and the rounded corners / home
    /// indicator below, like a real pad's printed margin.
    public let frameTopInset: CGFloat
    public let frameBottomInset: CGFloat
    public let frameSideInset: CGFloat
    /// Fraction of the page (from the bottom) that responds to the tear gesture.
    public let tearZone: CGFloat
    /// Page-local y where the events compartment begins (tap hit-testing only).
    public let eventsPaneTopY: CGFloat
    /// Event rows printed per events page.
    public let rowsPerPage: Int
    /// Estimated height of the events pane (drives full-bleed row print sizes).
    public let eventPaneHeight: CGFloat
    /// Full-bleed: the page fills its container, so sections distribute the extra
    /// height instead of leaving fixed-design whitespace.
    public let isFullBleed: Bool
    /// The pad hangs on a wall (shadow beneath it, dark surround).
    public let hasWall: Bool
    public let showsHangingHole: Bool

    var sceneW: CGFloat { pageW + 2 * overhangX }
    var sceneH: CGFloat { pageH + overhangBottom }

    /// The desktop widget: the original fixed 300×400 design in a 480×690 window.
    public static let desktop = PaperLayout(
        pageW: TradingCalendarGeometry.pageW,
        pageH: TradingCalendarGeometry.pageH,
        tearY: TradingCalendarGeometry.tearY,
        bindingH: TradingCalendarGeometry.bindingH,
        bindingSafeTop: 0,
        blockTopPad: TradingCalendarGeometry.blockTopPad,
        pageTopInset: TradingCalendarGeometry.pageTopInset,
        overhangX: TradingCalendarGeometry.overhangX,
        overhangBottom: TradingCalendarGeometry.overhangBottom,
        windowW: TradingCalendarGeometry.windowW,
        windowH: TradingCalendarGeometry.windowH,
        contentScale: 1,
        contentTopInset: 26,
        contentBottomInset: 12,
        frameTopInset: 7,
        frameBottomInset: 7,
        frameSideInset: 7,
        tearZone: TradingCalendarGeometry.tearZone,
        eventsPaneTopY: TradingCalendarGeometry.eventsPaneTopY,
        rowsPerPage: MacroEventPaging.rowsPerPage,
        eventPaneHeight: TradingCalendarGeometry.pageH
            - TradingCalendarGeometry.eventsPaneTopY
            - 20
            - 12,
        isFullBleed: false,
        hasWall: true,
        showsHangingHole: true
    )

    /// The iPhone app: the page fills the screen. `safeTop`/`safeBottom` are the
    /// device insets (notch / home indicator); typography and spacing scale with
    /// the screen width so the page reads the same from SE to Pro Max.
    public static func fullScreen(size: CGSize, safeTop: CGFloat, safeBottom: CGFloat) -> PaperLayout {
        // A full-screen cover animates in from a zero-size layout proposal;
        // clamp degenerate metrics so every ratio below stays finite (an `Int(∞)`
        // conversion traps the process) until the real dimensions arrive.
        let width = max(size.width, 120)
        let height = max(size.height, 240)
        let s = width / TradingCalendarGeometry.pageW
        let bindingSafeTop = max(0, safeTop)
        // The visible band of the strip hugs the bottom of the Dynamic Island,
        // so the pad reads as stapled right under the notch.
        let bindingH = bindingSafeTop + 12 * s
        // The fibers part just below the staples, which sit in the visible band
        // of the strip (under the binding, clear of the notch).
        let tearY = bindingH + 4 * s
        // The printed frame starts almost right under the notch (just past the
        // binding), and stops above the rounded corners / home indicator;
        // content pads further inside the frame so the sheet gets breathing
        // room at the bottom and on the sides.
        let frameTop = bindingH + 6 * s
        let frameBottom = max(0, safeBottom) + 14 * s
        let contentTopInset = frameTop + 10 * s
        let contentBottomInset = frameBottom + 10 * s
        let frameSide = 12 * s
        // Printed matter above the events pane (masthead + hero + lunar line),
        // estimated in desktop units - only used for tap hit-testing.
        let headerH = (24.5 + 82 + 30) * s
        let footerH = 20 * s
        let paneH = height - contentTopInset - headerH - footerH - contentBottomInset
        // One printed row (meta + title + values at full-bleed print) runs
        // ~51 desktop-units tall (the desktop page's rhythm); rows-per-page
        // follow from it.
        let rows = paneH > 0 ? Int(paneH / (51 * s)) : MacroEventPaging.rowsPerPage
        return PaperLayout(
            pageW: width,
            pageH: height,
            tearY: tearY,
            bindingH: bindingH,
            bindingSafeTop: bindingSafeTop,
            blockTopPad: 0,
            pageTopInset: 0,
            overhangX: TradingCalendarGeometry.overhangX * s,
            overhangBottom: TradingCalendarGeometry.overhangBottom * s,
            windowW: width,
            windowH: height,
            contentScale: s,
            contentTopInset: contentTopInset,
            contentBottomInset: contentBottomInset,
            frameTopInset: frameTop,
            frameBottomInset: frameBottom,
            frameSideInset: frameSide,
            tearZone: max(0.5, 1 - (bindingH + 10 * s) / height),
            eventsPaneTopY: contentTopInset + headerH,
            rowsPerPage: min(8, max(MacroEventPaging.rowsPerPage, rows)),
            eventPaneHeight: max(paneH, 0),
            isFullBleed: true,
            hasWall: false,
            showsHangingHole: false
        )
    }
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
