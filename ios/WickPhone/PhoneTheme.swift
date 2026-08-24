import SwiftUI
@_exported import WickCalendarKit
@_exported import WickSync

/// "By Candlelight" (秉烛) design system accessor on iOS.
/// Seamlessly maps all UI colors to the shared `DayArcEngine` and `WickPalette`.
public enum PhoneTheme {
    /// Resolves the current theme palette for a color scheme and time.
    public static func current(for scheme: ColorScheme = .light, at date: Date = DayArcEngine.currentDate()) -> WickPalette {
        DayArcEngine.palette(at: date, scheme: scheme)
    }

    // MARK: - Dynamic Semantic Pigments (delegating to shared DayArcEngine)

    public static var paper: Color {
        Color(uiColor: UIColor { traits in
            let scheme: ColorScheme = traits.userInterfaceStyle == .dark ? .dark : .light
            return current(for: scheme).columnPaper.uiColor
        })
    }

    public static var paperHi: Color {
        Color(uiColor: UIColor { traits in
            let scheme: ColorScheme = traits.userInterfaceStyle == .dark ? .dark : .light
            return current(for: scheme).pageSurface.uiColor
        })
    }

    public static var canvas: Color {
        Color(uiColor: UIColor { traits in
            let scheme: ColorScheme = traits.userInterfaceStyle == .dark ? .dark : .light
            return current(for: scheme).editorCanvas.uiColor
        })
    }

    public static var inkPrimary: Color {
        Color(uiColor: UIColor { traits in
            let scheme: ColorScheme = traits.userInterfaceStyle == .dark ? .dark : .light
            return current(for: scheme).textPrimary.uiColor
        })
    }

    public static var inkSecondary: Color {
        Color(uiColor: UIColor { traits in
            let scheme: ColorScheme = traits.userInterfaceStyle == .dark ? .dark : .light
            return current(for: scheme).textSecondary.uiColor
        })
    }

    public static var inkTertiary: Color {
        Color(uiColor: UIColor { traits in
            let scheme: ColorScheme = traits.userInterfaceStyle == .dark ? .dark : .light
            return current(for: scheme).textTertiary.uiColor
        })
    }

    public static var rule: Color {
        Color(uiColor: UIColor { traits in
            let scheme: ColorScheme = traits.userInterfaceStyle == .dark ? .dark : .light
            return current(for: scheme).divider.uiColor
        })
    }

    public static var cinnabar: Color {
        Color(uiColor: UIColor { traits in
            let scheme: ColorScheme = traits.userInterfaceStyle == .dark ? .dark : .light
            return current(for: scheme).pnlUp.uiColor
        })
    }

    public static var cinnabarSoft: Color {
        Color(uiColor: UIColor { traits in
            let scheme: ColorScheme = traits.userInterfaceStyle == .dark ? .dark : .light
            return current(for: scheme).pnlUp.withAlpha(0.14).uiColor
        })
    }

    public static var dai: Color {
        Color(uiColor: UIColor { traits in
            let scheme: ColorScheme = traits.userInterfaceStyle == .dark ? .dark : .light
            return current(for: scheme).pnlDown.uiColor
        })
    }

    public static var daiSoft: Color {
        Color(uiColor: UIColor { traits in
            let scheme: ColorScheme = traits.userInterfaceStyle == .dark ? .dark : .light
            return current(for: scheme).pnlDown.withAlpha(0.14).uiColor
        })
    }

    public static var ember: Color {
        Color(uiColor: UIColor { traits in
            let scheme: ColorScheme = traits.userInterfaceStyle == .dark ? .dark : .light
            return current(for: scheme).accent.uiColor
        })
    }

    public static var emberHi: Color {
        Color(uiColor: UIColor { traits in
            let scheme: ColorScheme = traits.userInterfaceStyle == .dark ? .dark : .light
            return current(for: scheme).accentText.uiColor
        })
    }

    public static var glow: Color {
        Color(uiColor: UIColor { traits in
            let scheme: ColorScheme = traits.userInterfaceStyle == .dark ? .dark : .light
            return current(for: scheme).glow.uiColor
        })
    }

    public static var char: Color {
        Color(uiColor: UIColor { traits in
            let scheme: ColorScheme = traits.userInterfaceStyle == .dark ? .dark : .light
            return current(for: scheme).brandTile.uiColor
        })
    }

    public static var stain: Color {
        Color(uiColor: UIColor { traits in
            let scheme: ColorScheme = traits.userInterfaceStyle == .dark ? .dark : .light
            return current(for: scheme).stain1.uiColor
        })
    }

    public static var receipt: Color {
        Color(uiColor: UIColor { traits in
            let scheme: ColorScheme = traits.userInterfaceStyle == .dark ? .dark : .light
            return current(for: scheme).receipt.uiColor
        })
    }

    public static var receiptInk: Color {
        Color(uiColor: UIColor { traits in
            let scheme: ColorScheme = traits.userInterfaceStyle == .dark ? .dark : .light
            return current(for: scheme).receiptInk.uiColor
        })
    }

    public static let tape = Color(red: 0.878, green: 0.808, blue: 0.686, opacity: 0.65)
}
