import AppKit
import SwiftUI

// MARK: - RGB value type

/// Plain sRGB color used by the day-arc theme engine. Keeping palettes in a
/// framework-free value type makes interpolation and WCAG contrast math
/// unit-testable without SwiftUI.
struct WickRGB: Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    init(hex: UInt, opacity: Double = 1) {
        self.init(
            r: Double((hex >> 16) & 0xFF) / 255,
            g: Double((hex >> 8) & 0xFF) / 255,
            b: Double(hex & 0xFF) / 255,
            a: opacity
        )
    }

    func lerped(to other: WickRGB, t: Double) -> WickRGB {
        WickRGB(
            r: r + (other.r - r) * t,
            g: g + (other.g - g) * t,
            b: b + (other.b - b) * t,
            a: a + (other.a - a) * t
        )
    }

    /// Mix toward white by `amount` (0...1), preserving alpha.
    func lightened(by amount: Double) -> WickRGB {
        lerped(to: WickRGB(r: 1, g: 1, b: 1, a: a), t: amount)
    }

    /// Mix toward black by `amount` (0...1), preserving alpha.
    func darkened(by amount: Double) -> WickRGB {
        lerped(to: WickRGB(r: 0, g: 0, b: 0, a: a), t: amount)
    }

    func withAlpha(_ alpha: Double) -> WickRGB {
        WickRGB(r: r, g: g, b: b, a: alpha)
    }

    func scaledAlpha(_ factor: Double) -> WickRGB {
        withAlpha(min(1, max(0, a * factor)))
    }

    /// Alpha-composite over an opaque background, returning an opaque color.
    func flattened(over background: WickRGB) -> WickRGB {
        WickRGB(
            r: r * a + background.r * (1 - a),
            g: g * a + background.g * (1 - a),
            b: b * a + background.b * (1 - a)
        )
    }

    /// WCAG relative luminance (assumes an opaque color).
    var relativeLuminance: Double {
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    func contrastRatio(to other: WickRGB) -> Double {
        let l1 = relativeLuminance
        let l2 = other.relativeLuminance
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    var color: Color {
        Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

// MARK: - Day phase

/// The four peaks of the day arc. Palettes interpolate between adjacent phase
/// anchors across a 24h cycle.
enum DayPhase: CaseIterable {
    case dawn
    case day
    case dusk
    case night

    /// Local clock hour where this phase peaks.
    var anchorHour: Double {
        switch self {
        case .dawn: return 6.5
        case .day: return 12
        case .dusk: return 18
        case .night: return 22.5
        }
    }

    var emoji: String {
        switch self {
        case .dawn: return "🌅"
        case .day: return "☀️"
        case .dusk: return "🌇"
        case .night: return "🌙"
        }
    }

    func name(language: AppLanguage) -> String {
        switch self {
        case .dawn: return L10n.string(.phaseDawn, language: language)
        case .day: return L10n.string(.phaseDay, language: language)
        case .dusk: return L10n.string(.phaseDusk, language: language)
        case .night: return L10n.string(.phaseNight, language: language)
        }
    }

    /// Metric-card glow intensity at this phase's peak (interpolated like colors).
    var glowScale: Double {
        switch self {
        case .dawn: return 1.0
        case .day: return 0.55
        case .dusk: return 1.15
        case .night: return 1.35
        }
    }
}

// MARK: - Palette

/// All color roles shared by the menu-bar panel and the journal window.
struct WickPalette: Equatable {
    var backgroundTop: WickRGB
    var backgroundBottom: WickRGB
    var sidebarBackground: WickRGB
    var cardTop: WickRGB
    var cardBottom: WickRGB
    var cardStroke: WickRGB
    var controlBackground: WickRGB
    var controlBorder: WickRGB
    var textPrimary: WickRGB
    var textSecondary: WickRGB
    var textTertiary: WickRGB
    var accent: WickRGB
    /// Accent variant dark/light enough to be used as text on card fills.
    var accentText: WickRGB
    /// Soft accent tint for selected fills.
    var accentSoft: WickRGB
    /// Review verdict glyphs: "correct" seal (green family, hue-stable across phases).
    var reviewCorrect: WickRGB
    /// Review verdict glyphs: "wrong" seal (vermilion family, hue-stable across phases).
    var reviewWrong: WickRGB
    var divider: WickRGB
    var glow: WickRGB

    func lerped(to other: WickPalette, t: Double) -> WickPalette {
        WickPalette(
            backgroundTop: backgroundTop.lerped(to: other.backgroundTop, t: t),
            backgroundBottom: backgroundBottom.lerped(to: other.backgroundBottom, t: t),
            sidebarBackground: sidebarBackground.lerped(to: other.sidebarBackground, t: t),
            cardTop: cardTop.lerped(to: other.cardTop, t: t),
            cardBottom: cardBottom.lerped(to: other.cardBottom, t: t),
            cardStroke: cardStroke.lerped(to: other.cardStroke, t: t),
            controlBackground: controlBackground.lerped(to: other.controlBackground, t: t),
            controlBorder: controlBorder.lerped(to: other.controlBorder, t: t),
            textPrimary: textPrimary.lerped(to: other.textPrimary, t: t),
            textSecondary: textSecondary.lerped(to: other.textSecondary, t: t),
            textTertiary: textTertiary.lerped(to: other.textTertiary, t: t),
            accent: accent.lerped(to: other.accent, t: t),
            accentText: accentText.lerped(to: other.accentText, t: t),
            accentSoft: accentSoft.lerped(to: other.accentSoft, t: t),
            reviewCorrect: reviewCorrect.lerped(to: other.reviewCorrect, t: t),
            reviewWrong: reviewWrong.lerped(to: other.reviewWrong, t: t),
            divider: divider.lerped(to: other.divider, t: t),
            glow: glow.lerped(to: other.glow, t: t)
        )
    }
}

// MARK: - Metric theme

/// Per-metric (day/week/month/year) card styling. Hue families are stable
/// identities; the engine only scales glow intensity with the day arc.
struct MetricTheme {
    let primary: Color
    let secondary: Color
    let glow: Color
    let cardTop: Color
    let cardBottom: Color
    let trackFill: Color
    let trackStroke: Color
    let spark: Color
}

// MARK: - Engine

/// Resolves the app's color language from the time of day. Pure computation
/// with injectable date/calendar (same pattern as `TimeProgressCalculator`).
enum DayArcEngine {
    /// Anchor palette for a phase peak in a color scheme. Internal (not private)
    /// so tests can verify interpolation against the raw anchors.
    static func anchorPalette(_ phase: DayPhase, scheme: ColorScheme) -> WickPalette {
        switch scheme {
        case .light:
            switch phase {
            case .dawn: return lightDawn
            case .day: return lightDay
            case .dusk: return lightDusk
            case .night: return lightNight
            }
        case .dark:
            switch phase {
            case .dawn: return darkDawn
            case .day: return darkDay
            case .dusk: return darkDusk
            case .night: return darkNight
            }
        @unknown default:
            switch phase {
            case .dawn: return darkDawn
            case .day: return darkDay
            case .dusk: return darkDusk
            case .night: return darkNight
            }
        }
    }

    /// Interpolated palette at a moment in time.
    static func palette(
        at date: Date,
        scheme: ColorScheme,
        calendar: Calendar = .current
    ) -> WickPalette {
        let blend = phaseBlend(at: date, calendar: calendar)
        return anchorPalette(blend.from, scheme: scheme)
            .lerped(to: anchorPalette(blend.to, scheme: scheme), t: blend.t)
    }

    /// The phase whose segment contains the given time. Phases switch at their
    /// anchor peaks (dawn from 06:30, day from 12:00, dusk from 18:00, night
    /// from 22:30), so deep night still reads as night rather than pre-dawn.
    static func phase(at date: Date, calendar: Calendar = .current) -> DayPhase {
        phaseBlend(at: date, calendar: calendar).from
    }

    /// Metric card themes with glow scaled by the (interpolated) day arc.
    static func metricThemes(
        at date: Date,
        scheme: ColorScheme,
        calendar: Calendar = .current
    ) -> [MetricTheme] {
        let blend = phaseBlend(at: date, calendar: calendar)
        let scale = blend.from.glowScale
            + (blend.to.glowScale - blend.from.glowScale) * blend.t
        return metricBase(for: scheme).map { base in
            MetricTheme(
                primary: base.primary.color,
                secondary: base.secondary.color,
                glow: base.glow.scaledAlpha(scale).color,
                cardTop: base.cardTop.color,
                cardBottom: base.cardBottom.color,
                trackFill: base.trackFill.color,
                trackStroke: base.trackStroke.color,
                spark: base.spark.color
            )
        }
    }

    /// "Now" for theme resolution. Honors `WICK_ARC_TIME=HH:mm` in debug
    /// builds only (screenshots/design review); release builds always use the
    /// real current date.
    static func currentDate(calendar: Calendar = .current) -> Date {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["WICK_ARC_TIME"] {
            let parts = raw.split(separator: ":")
            if parts.count == 2,
               let hour = Int(parts[0]), let minute = Int(parts[1]),
               (0..<24).contains(hour), (0..<60).contains(minute)
            {
                var components = calendar.dateComponents([.year, .month, .day], from: Date())
                components.hour = hour
                components.minute = minute
                components.second = 0
                if let date = calendar.date(from: components) {
                    return date
                }
            }
        }
        #endif
        return Date()
    }

    // MARK: Interpolation

    private struct PhaseBlend {
        let from: DayPhase
        let to: DayPhase
        let t: Double
    }

    private static func dayHours(at date: Date, calendar: Calendar) -> Double {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double(components.hour ?? 0)
            + Double(components.minute ?? 0) / 60
            + Double(components.second ?? 0) / 3600
    }

    /// Circular 24h blend: dawn(6.5) → day(12) → dusk(18) → night(22.5) → dawn.
    private static func phaseBlend(at date: Date, calendar: Calendar) -> PhaseBlend {
        let hour = dayHours(at: date, calendar: calendar)
        if hour >= DayPhase.dawn.anchorHour, hour < DayPhase.day.anchorHour {
            return PhaseBlend(from: .dawn, to: .day, t: (hour - 6.5) / 5.5)
        }
        if hour >= DayPhase.day.anchorHour, hour < DayPhase.dusk.anchorHour {
            return PhaseBlend(from: .day, to: .dusk, t: (hour - 12) / 6)
        }
        if hour >= DayPhase.dusk.anchorHour, hour < DayPhase.night.anchorHour {
            return PhaseBlend(from: .dusk, to: .night, t: (hour - 18) / 4.5)
        }
        // Night wraps past midnight toward dawn (8h span).
        let t = hour >= DayPhase.night.anchorHour
            ? (hour - 22.5) / 8
            : (hour + 24 - 22.5) / 8
        return PhaseBlend(from: .night, to: .dawn, t: t)
    }

    // MARK: Anchor palettes — light scheme

    /// Rose-gold morning haze.
    private static let lightDawn = WickPalette(
        backgroundTop: WickRGB(hex: 0xFDF1E8),
        backgroundBottom: WickRGB(hex: 0xF5DFD3),
        sidebarBackground: WickRGB(hex: 0xF7E6DA),
        cardTop: WickRGB(hex: 0xFEF4EC),
        cardBottom: WickRGB(hex: 0xF6E2D5),
        cardStroke: WickRGB(hex: 0xE3BFA8, opacity: 0.6),
        controlBackground: WickRGB(hex: 0xFFFFFF, opacity: 0.5),
        controlBorder: WickRGB(hex: 0xDCB49B, opacity: 0.7),
        textPrimary: WickRGB(hex: 0x33251F),
        textSecondary: WickRGB(hex: 0x715850),
        textTertiary: WickRGB(hex: 0x967A6E),
        accent: WickRGB(hex: 0xD96C42),
        accentText: WickRGB(hex: 0xB45237),
        accentSoft: WickRGB(hex: 0xFBDCCB, opacity: 0.9),
        reviewCorrect: WickRGB(hex: 0x3E7C4F),
        reviewWrong: WickRGB(hex: 0xB4443C),
        divider: WickRGB(hex: 0xD98A63, opacity: 0.5),
        glow: WickRGB(hex: 0xF7B28A, opacity: 0.26)
    )

    /// Clear warm paper at noon (the candlelight baseline).
    private static let lightDay = WickPalette(
        backgroundTop: WickRGB(hex: 0xFFF8F0),
        backgroundBottom: WickRGB(hex: 0xF3E6D5),
        sidebarBackground: WickRGB(hex: 0xF6ECDD),
        cardTop: WickRGB(hex: 0xFFF9F2),
        cardBottom: WickRGB(hex: 0xF7E9D7),
        cardStroke: WickRGB(hex: 0xDFC6A9, opacity: 0.65),
        controlBackground: WickRGB(hex: 0xFFFFFF, opacity: 0.55),
        controlBorder: WickRGB(hex: 0xD7B28A, opacity: 0.75),
        textPrimary: WickRGB(hex: 0x2F241B),
        textSecondary: WickRGB(hex: 0x6D5A49),
        textTertiary: WickRGB(hex: 0x917C67),
        accent: WickRGB(hex: 0xD9822B),
        accentText: WickRGB(hex: 0xB05F14),
        accentSoft: WickRGB(hex: 0xFFE8C8, opacity: 0.9),
        reviewCorrect: WickRGB(hex: 0x3E7C4F),
        reviewWrong: WickRGB(hex: 0xB4443C),
        divider: WickRGB(hex: 0xD98F44, opacity: 0.55),
        glow: WickRGB(hex: 0xFFBE66, opacity: 0.24)
    )

    /// Honeyed copper evening.
    private static let lightDusk = WickPalette(
        backgroundTop: WickRGB(hex: 0xFBEAD2),
        backgroundBottom: WickRGB(hex: 0xF0D6B8),
        sidebarBackground: WickRGB(hex: 0xF5E0C4),
        cardTop: WickRGB(hex: 0xFCEDDA),
        cardBottom: WickRGB(hex: 0xF2DABE),
        cardStroke: WickRGB(hex: 0xD9B58C, opacity: 0.65),
        controlBackground: WickRGB(hex: 0xFFFFFF, opacity: 0.45),
        controlBorder: WickRGB(hex: 0xCDA273, opacity: 0.75),
        textPrimary: WickRGB(hex: 0x2E2013),
        textSecondary: WickRGB(hex: 0x6B5136),
        textTertiary: WickRGB(hex: 0x8F7350),
        accent: WickRGB(hex: 0xC2611F),
        accentText: WickRGB(hex: 0x9F4E17),
        accentSoft: WickRGB(hex: 0xF6D9B4, opacity: 0.9),
        reviewCorrect: WickRGB(hex: 0x3E7C4F),
        reviewWrong: WickRGB(hex: 0xB4443C),
        divider: WickRGB(hex: 0xC97E3D, opacity: 0.55),
        glow: WickRGB(hex: 0xF0A050, opacity: 0.28)
    )

    /// Moonlit cool gray-blue (light scheme after dark).
    private static let lightNight = WickPalette(
        backgroundTop: WickRGB(hex: 0xE6E5EC),
        backgroundBottom: WickRGB(hex: 0xD2D1DC),
        sidebarBackground: WickRGB(hex: 0xDAD9E2),
        cardTop: WickRGB(hex: 0xEBEAF1),
        cardBottom: WickRGB(hex: 0xD8D7E2),
        cardStroke: WickRGB(hex: 0xB5B4C4, opacity: 0.65),
        controlBackground: WickRGB(hex: 0xFFFFFF, opacity: 0.45),
        controlBorder: WickRGB(hex: 0xA9A8BC, opacity: 0.7),
        textPrimary: WickRGB(hex: 0x26252E),
        textSecondary: WickRGB(hex: 0x52505F),
        textTertiary: WickRGB(hex: 0x74727F),
        accent: WickRGB(hex: 0x7A86C8),
        accentText: WickRGB(hex: 0x5560A8),
        accentSoft: WickRGB(hex: 0xD5D8EE, opacity: 0.9),
        reviewCorrect: WickRGB(hex: 0x3E7C4F),
        reviewWrong: WickRGB(hex: 0xB4443C),
        divider: WickRGB(hex: 0x8B90C0, opacity: 0.5),
        glow: WickRGB(hex: 0x9AA4E0, opacity: 0.2)
    )

    // MARK: Anchor palettes — dark scheme

    /// Indigo pre-dawn with an ember accent.
    private static let darkDawn = WickPalette(
        backgroundTop: WickRGB(hex: 0x181A2E),
        backgroundBottom: WickRGB(hex: 0x100F1C),
        sidebarBackground: WickRGB(hex: 0x131225),
        cardTop: WickRGB(hex: 0x1C1E36),
        cardBottom: WickRGB(hex: 0x141325),
        cardStroke: WickRGB(hex: 0xFFFFFF, opacity: 0.08),
        controlBackground: WickRGB(hex: 0xFFFFFF, opacity: 0.05),
        controlBorder: WickRGB(hex: 0xFFFFFF, opacity: 0.11),
        textPrimary: WickRGB(hex: 0xFFFFFF, opacity: 0.96),
        textSecondary: WickRGB(hex: 0xFFFFFF, opacity: 0.66),
        textTertiary: WickRGB(hex: 0xFFFFFF, opacity: 0.5),
        accent: WickRGB(hex: 0xF0A368),
        accentText: WickRGB(hex: 0xF5B27E),
        accentSoft: WickRGB(hex: 0xF0A368, opacity: 0.16),
        reviewCorrect: WickRGB(hex: 0x7FBF8E),
        reviewWrong: WickRGB(hex: 0xE08A7E),
        divider: WickRGB(hex: 0xE8A06A, opacity: 0.45),
        glow: WickRGB(hex: 0xF0A368, opacity: 0.2)
    )

    /// Brighter slate at midday (dark scheme).
    private static let darkDay = WickPalette(
        backgroundTop: WickRGB(hex: 0x1C2434),
        backgroundBottom: WickRGB(hex: 0x141A28),
        sidebarBackground: WickRGB(hex: 0x171E2C),
        cardTop: WickRGB(hex: 0x212A3E),
        cardBottom: WickRGB(hex: 0x182032),
        cardStroke: WickRGB(hex: 0xFFFFFF, opacity: 0.09),
        controlBackground: WickRGB(hex: 0xFFFFFF, opacity: 0.06),
        controlBorder: WickRGB(hex: 0xFFFFFF, opacity: 0.12),
        textPrimary: WickRGB(hex: 0xFFFFFF, opacity: 0.96),
        textSecondary: WickRGB(hex: 0xFFFFFF, opacity: 0.68),
        textTertiary: WickRGB(hex: 0xFFFFFF, opacity: 0.52),
        accent: WickRGB(hex: 0xF5B85C),
        accentText: WickRGB(hex: 0xF7C276),
        accentSoft: WickRGB(hex: 0xF5B85C, opacity: 0.16),
        reviewCorrect: WickRGB(hex: 0x7FBF8E),
        reviewWrong: WickRGB(hex: 0xE08A7E),
        divider: WickRGB(hex: 0xE8B96E, opacity: 0.45),
        glow: WickRGB(hex: 0xF5B85C, opacity: 0.16)
    )

    /// Burnt amber-brown evening.
    private static let darkDusk = WickPalette(
        backgroundTop: WickRGB(hex: 0x1E1722),
        backgroundBottom: WickRGB(hex: 0x130F16),
        sidebarBackground: WickRGB(hex: 0x181119),
        cardTop: WickRGB(hex: 0x241B28),
        cardBottom: WickRGB(hex: 0x191219),
        cardStroke: WickRGB(hex: 0xFFFFFF, opacity: 0.08),
        controlBackground: WickRGB(hex: 0xFFFFFF, opacity: 0.05),
        controlBorder: WickRGB(hex: 0xFFFFFF, opacity: 0.11),
        textPrimary: WickRGB(hex: 0xFFFFFF, opacity: 0.96),
        textSecondary: WickRGB(hex: 0xFFFFFF, opacity: 0.65),
        textTertiary: WickRGB(hex: 0xFFFFFF, opacity: 0.5),
        accent: WickRGB(hex: 0xF08A4B),
        accentText: WickRGB(hex: 0xF79A63),
        accentSoft: WickRGB(hex: 0xF08A4B, opacity: 0.16),
        reviewCorrect: WickRGB(hex: 0x7FBF8E),
        reviewWrong: WickRGB(hex: 0xE08A7E),
        divider: WickRGB(hex: 0xE08A52, opacity: 0.45),
        glow: WickRGB(hex: 0xF08A4B, opacity: 0.22)
    )

    /// Deep midnight blue (the midnight baseline).
    private static let darkNight = WickPalette(
        backgroundTop: WickRGB(hex: 0x101527),
        backgroundBottom: WickRGB(hex: 0x0C1019),
        sidebarBackground: WickRGB(hex: 0x0D1220),
        cardTop: WickRGB(hex: 0x171F33),
        cardBottom: WickRGB(hex: 0x101727),
        cardStroke: WickRGB(hex: 0xFFFFFF, opacity: 0.07),
        controlBackground: WickRGB(hex: 0xFFFFFF, opacity: 0.05),
        controlBorder: WickRGB(hex: 0xFFFFFF, opacity: 0.1),
        textPrimary: WickRGB(hex: 0xFFFFFF, opacity: 0.96),
        textSecondary: WickRGB(hex: 0xFFFFFF, opacity: 0.64),
        textTertiary: WickRGB(hex: 0xFFFFFF, opacity: 0.5),
        accent: WickRGB(hex: 0x9BB6FF),
        accentText: WickRGB(hex: 0xAFC4FF),
        accentSoft: WickRGB(hex: 0x9BB6FF, opacity: 0.16),
        reviewCorrect: WickRGB(hex: 0x7FBF8E),
        reviewWrong: WickRGB(hex: 0xE08A7E),
        divider: WickRGB(hex: 0x8AB4FF, opacity: 0.42),
        glow: WickRGB(hex: 0x6CA6FF, opacity: 0.18)
    )

    // MARK: Metric hue families

    private struct MetricBase {
        let primary: WickRGB
        let secondary: WickRGB
        let glow: WickRGB
        let cardTop: WickRGB
        let cardBottom: WickRGB
        let trackFill: WickRGB
        let trackStroke: WickRGB
        let spark: WickRGB
    }

    private static func metricBase(for scheme: ColorScheme) -> [MetricBase] {
        switch scheme {
        case .light:
            return lightMetricBase
        case .dark:
            return darkMetricBase
        @unknown default:
            return darkMetricBase
        }
    }

    private static let lightMetricBase: [MetricBase] = [
        MetricBase(
            primary: WickRGB(hex: 0xE2903A), secondary: WickRGB(hex: 0xF7B261),
            glow: WickRGB(hex: 0xE2903A, opacity: 0.18),
            cardTop: WickRGB(hex: 0xFFF8F0), cardBottom: WickRGB(hex: 0xF7E8D8),
            trackFill: WickRGB(hex: 0x000000, opacity: 0.06),
            trackStroke: WickRGB(hex: 0x000000, opacity: 0.05),
            spark: WickRGB(hex: 0xFFFFFF, opacity: 0.9)
        ),
        MetricBase(
            primary: WickRGB(hex: 0x4B8EF4), secondary: WickRGB(hex: 0x82B7FF),
            glow: WickRGB(hex: 0x4B8EF4, opacity: 0.14),
            cardTop: WickRGB(hex: 0xF4F8FF), cardBottom: WickRGB(hex: 0xE5EEF9),
            trackFill: WickRGB(hex: 0x000000, opacity: 0.06),
            trackStroke: WickRGB(hex: 0x000000, opacity: 0.05),
            spark: WickRGB(hex: 0xFFFFFF, opacity: 0.92)
        ),
        MetricBase(
            primary: WickRGB(hex: 0x8E6CE6), secondary: WickRGB(hex: 0xC2A6FF),
            glow: WickRGB(hex: 0x8E6CE6, opacity: 0.14),
            cardTop: WickRGB(hex: 0xF7F3FF), cardBottom: WickRGB(hex: 0xECE4FA),
            trackFill: WickRGB(hex: 0x000000, opacity: 0.06),
            trackStroke: WickRGB(hex: 0x000000, opacity: 0.05),
            spark: WickRGB(hex: 0xFFFFFF, opacity: 0.92)
        ),
        MetricBase(
            primary: WickRGB(hex: 0x2DA37C), secondary: WickRGB(hex: 0x80D8BA),
            glow: WickRGB(hex: 0x2DA37C, opacity: 0.14),
            cardTop: WickRGB(hex: 0xF2FCF8), cardBottom: WickRGB(hex: 0xE0F0E8),
            trackFill: WickRGB(hex: 0x000000, opacity: 0.06),
            trackStroke: WickRGB(hex: 0x000000, opacity: 0.05),
            spark: WickRGB(hex: 0xFFFFFF, opacity: 0.92)
        ),
    ]

    private static let darkMetricBase: [MetricBase] = [
        MetricBase(
            primary: WickRGB(hex: 0x9BB6FF), secondary: WickRGB(hex: 0x6B86F5),
            glow: WickRGB(hex: 0x7D96FF, opacity: 0.18),
            cardTop: WickRGB(hex: 0x171F33), cardBottom: WickRGB(hex: 0x101727),
            trackFill: WickRGB(hex: 0xFFFFFF, opacity: 0.08),
            trackStroke: WickRGB(hex: 0xFFFFFF, opacity: 0.05),
            spark: WickRGB(hex: 0xFFFFFF, opacity: 0.32)
        ),
        MetricBase(
            primary: WickRGB(hex: 0x79D4FF), secondary: WickRGB(hex: 0x3C9DE8),
            glow: WickRGB(hex: 0x79D4FF, opacity: 0.16),
            cardTop: WickRGB(hex: 0x132332), cardBottom: WickRGB(hex: 0x101A28),
            trackFill: WickRGB(hex: 0xFFFFFF, opacity: 0.08),
            trackStroke: WickRGB(hex: 0xFFFFFF, opacity: 0.05),
            spark: WickRGB(hex: 0xFFFFFF, opacity: 0.32)
        ),
        MetricBase(
            primary: WickRGB(hex: 0xB9A7FF), secondary: WickRGB(hex: 0x7A67E6),
            glow: WickRGB(hex: 0xB9A7FF, opacity: 0.16),
            cardTop: WickRGB(hex: 0x1A1E38), cardBottom: WickRGB(hex: 0x111427),
            trackFill: WickRGB(hex: 0xFFFFFF, opacity: 0.08),
            trackStroke: WickRGB(hex: 0xFFFFFF, opacity: 0.05),
            spark: WickRGB(hex: 0xFFFFFF, opacity: 0.32)
        ),
        MetricBase(
            primary: WickRGB(hex: 0x8AE0D0), secondary: WickRGB(hex: 0x3CB7A6),
            glow: WickRGB(hex: 0x8AE0D0, opacity: 0.15),
            cardTop: WickRGB(hex: 0x142627), cardBottom: WickRGB(hex: 0x10191B),
            trackFill: WickRGB(hex: 0xFFFFFF, opacity: 0.08),
            trackStroke: WickRGB(hex: 0xFFFFFF, opacity: 0.05),
            spark: WickRGB(hex: 0xFFFFFF, opacity: 0.32)
        ),
    ]
}

// MARK: - SwiftUI environment

private struct WickPaletteEnvironmentKey: EnvironmentKey {
    static let defaultValue = DayArcEngine.anchorPalette(.day, scheme: .light)
}

extension EnvironmentValues {
    var wickPalette: WickPalette {
        get { self[WickPaletteEnvironmentKey.self] }
        set { self[WickPaletteEnvironmentKey.self] = newValue }
    }
}
