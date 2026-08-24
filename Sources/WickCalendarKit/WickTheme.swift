import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import WickSync

// MARK: - RGB value type

/// Plain sRGB color used by the day-arc theme engine. Keeping palettes in a
/// framework-free value type makes interpolation and WCAG contrast math
/// unit-testable without SwiftUI.
public struct WickRGB: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public init(hex: UInt, opacity: Double = 1) {
        self.init(
            r: Double((hex >> 16) & 0xFF) / 255,
            g: Double((hex >> 8) & 0xFF) / 255,
            b: Double(hex & 0xFF) / 255,
            a: opacity
        )
    }

    public func lerped(to other: WickRGB, t: Double) -> WickRGB {
        WickRGB(
            r: r + (other.r - r) * t,
            g: g + (other.g - g) * t,
            b: b + (other.b - b) * t,
            a: a + (other.a - a) * t
        )
    }

    /// Mix toward white by `amount` (0...1), preserving alpha.
    public func lightened(by amount: Double) -> WickRGB {
        lerped(to: WickRGB(r: 1, g: 1, b: 1, a: a), t: amount)
    }

    /// Mix toward black by `amount` (0...1), preserving alpha.
    public func darkened(by amount: Double) -> WickRGB {
        lerped(to: WickRGB(r: 0, g: 0, b: 0, a: a), t: amount)
    }

    public func withAlpha(_ alpha: Double) -> WickRGB {
        WickRGB(r: r, g: g, b: b, a: alpha)
    }

    public func scaledAlpha(_ factor: Double) -> WickRGB {
        withAlpha(min(1, max(0, a * factor)))
    }

    /// Alpha-composite over an opaque background, returning an opaque color.
    public func flattened(over background: WickRGB) -> WickRGB {
        WickRGB(
            r: r * a + background.r * (1 - a),
            g: g * a + background.g * (1 - a),
            b: b * a + background.b * (1 - a)
        )
    }

    /// WCAG relative luminance (assumes an opaque color).
    public var relativeLuminance: Double {
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    public func contrastRatio(to other: WickRGB) -> Double {
        let l1 = relativeLuminance
        let l2 = other.relativeLuminance
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    public var color: Color {
        Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    #if os(macOS)
    public var nsColor: NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
    #else
    public var uiColor: UIColor {
        UIColor(red: r, green: g, blue: b, alpha: a)
    }
    #endif
}

// MARK: - Day phase

/// The four peaks of the day arc. Palettes interpolate between adjacent phase
/// anchors across a 24h cycle.
public enum DayPhase: CaseIterable, Sendable {
    case dawn
    case day
    case dusk
    case night

    /// Local clock hour where this phase peaks.
    public var anchorHour: Double {
        switch self {
        case .dawn: return 6.5
        case .day: return 12
        case .dusk: return 18
        case .night: return 22.5
        }
    }

    public func name(language: AppLanguage) -> String {
        switch self {
        case .dawn: return L10n.string(.phaseDawn, language: language)
        case .day: return L10n.string(.phaseDay, language: language)
        case .dusk: return L10n.string(.phaseDusk, language: language)
        case .night: return L10n.string(.phaseNight, language: language)
        }
    }
}

// MARK: - App Appearance

public enum AppAppearance: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var colorScheme: ColorScheme? {
        switch self {
        case .light:
            return .light
        case .dark:
            return .dark
        case .system:
            return nil
        }
    }

    public func displayName(language: AppLanguage) -> String {
        switch (self, language) {
        case (.light, .chinese):
            return "亮色"
        case (.light, .english):
            return "Light"
        case (.dark, .chinese):
            return "暗色"
        case (.dark, .english):
            return "Dark"
        case (.system, .chinese):
            return "跟随系统"
        case (.system, .english):
            return "System"
        }
    }
}

// MARK: - PnL color convention

/// Which of the two existing palette colors marks a gain.
/// Only the assignment swaps — no color values are changed.
public enum PnlColorConvention: String, CaseIterable, Identifiable, Codable, Sendable {
    /// 红涨绿跌: red = gain, green = loss.
    case redUp
    /// 绿涨红跌: green = gain, red = loss (default).
    case greenUp

    public var id: String { rawValue }

    public func displayName(language: AppLanguage) -> String {
        switch (self, language) {
        case (.redUp, .chinese):
            return "红涨绿跌"
        case (.redUp, .english):
            return "Red up"
        case (.greenUp, .chinese):
            return "绿涨红跌"
        case (.greenUp, .english):
            return "Green up"
        }
    }
}

// MARK: - Palette

/// All color roles shared by the menu-bar panel, the journal window, and iOS app.
/// 「秉烛」材料系统:paper/ink/ember/cinnabar/dai/stain/receipt。
public struct WickPalette: Equatable, Sendable {
    public var backgroundTop: WickRGB
    public var backgroundBottom: WickRGB
    public var sidebarBackground: WickRGB
    public var cardTop: WickRGB
    public var cardBottom: WickRGB
    public var cardStroke: WickRGB
    public var controlBackground: WickRGB
    public var controlBorder: WickRGB
    public var textPrimary: WickRGB
    public var textSecondary: WickRGB
    public var textTertiary: WickRGB
    public var accent: WickRGB
    /// Accent variant dark/light enough to be used as text on card fills.
    public var accentText: WickRGB
    /// Soft accent tint for selected fills.
    public var accentSoft: WickRGB
    /// Review seals: 白文朱砂方章,永远红色,靠字表意(对/错同色)。
    public var reviewCorrect: WickRGB
    public var reviewWrong: WickRGB
    public var divider: WickRGB
    public var glow: WickRGB
    /// 烛痕:烛痕条已逝部分的暖渍(浅端 → 靠烛苗一端)。
    public var stain1: WickRGB
    public var stain2: WickRGB
    /// 盈亏:红盈(A 股习惯)。
    public var pnlUp: WickRGB
    /// 盈亏:黛亏(全系统唯一的冷色)。
    public var pnlDown: WickRGB
    /// 单据物理纸:恒定,不随深浅模式反色。
    public var receipt: WickRGB
    public var receiptInk: WickRGB
    /// 烛印方砖:火苗衬底的近黑牌(品牌件,不随弧光漂移)。
    public var brandTile: WickRGB

    public init(
        backgroundTop: WickRGB,
        backgroundBottom: WickRGB,
        sidebarBackground: WickRGB,
        cardTop: WickRGB,
        cardBottom: WickRGB,
        cardStroke: WickRGB,
        controlBackground: WickRGB,
        controlBorder: WickRGB,
        textPrimary: WickRGB,
        textSecondary: WickRGB,
        textTertiary: WickRGB,
        accent: WickRGB,
        accentText: WickRGB,
        accentSoft: WickRGB,
        reviewCorrect: WickRGB,
        reviewWrong: WickRGB,
        divider: WickRGB,
        glow: WickRGB,
        stain1: WickRGB,
        stain2: WickRGB,
        pnlUp: WickRGB,
        pnlDown: WickRGB,
        receipt: WickRGB,
        receiptInk: WickRGB,
        brandTile: WickRGB
    ) {
        self.backgroundTop = backgroundTop
        self.backgroundBottom = backgroundBottom
        self.sidebarBackground = sidebarBackground
        self.cardTop = cardTop
        self.cardBottom = cardBottom
        self.cardStroke = cardStroke
        self.controlBackground = controlBackground
        self.controlBorder = controlBorder
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.textTertiary = textTertiary
        self.accent = accent
        self.accentText = accentText
        self.accentSoft = accentSoft
        self.reviewCorrect = reviewCorrect
        self.reviewWrong = reviewWrong
        self.divider = divider
        self.glow = glow
        self.stain1 = stain1
        self.stain2 = stain2
        self.pnlUp = pnlUp
        self.pnlDown = pnlDown
        self.receipt = receipt
        self.receiptInk = receiptInk
        self.brandTile = brandTile
    }

    public func lerped(to other: WickPalette, t: Double) -> WickPalette {
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
            glow: glow.lerped(to: other.glow, t: t),
            stain1: stain1.lerped(to: other.stain1, t: t),
            stain2: stain2.lerped(to: other.stain2, t: t),
            pnlUp: pnlUp.lerped(to: other.pnlUp, t: t),
            pnlDown: pnlDown.lerped(to: other.pnlDown, t: t),
            receipt: receipt.lerped(to: other.receipt, t: t),
            receiptInk: receiptInk.lerped(to: other.receiptInk, t: t),
            brandTile: brandTile.lerped(to: other.brandTile, t: t)
        )
    }
}

// MARK: - Paper surface mapping(秉烛 §02:同一叠纸的层级)

public extension WickPalette {
    /// 栏面纸(paper):日期列表、检查器等栏位的底,介于桌底与页纸之间。
    var columnPaper: WickRGB { cardBottom }
    /// 编辑区画布:paper 82% + 桌底 18%,比栏面略深,让纸页浮起。
    var editorCanvas: WickRGB { cardBottom.lerped(to: backgroundBottom, t: 0.18) }
    /// 编辑页纸(paper-hi):整叠纸的最上层,日记内容印在这张纸上。
    var pageSurface: WickRGB { cardTop }
    /// 纸页投影色:近黑的烟墨,亮暗两态都成立。
    var pageShadow: WickRGB { brandTile }

    /// (gain, loss) colors under a convention — picks which existing palette
    /// color is used for each; the color values themselves are untouched.
    func upDownColors(_ convention: PnlColorConvention) -> (gain: WickRGB, loss: WickRGB) {
        switch convention {
        case .redUp:
            return (pnlUp, pnlDown)
        case .greenUp:
            return (pnlDown, pnlUp)
        }
    }
}

// MARK: - Engine

/// Resolves the app's color language from the time of day. Pure computation
/// with injectable date/calendar (same pattern as `TimeProgressCalculator`).
public enum DayArcEngine {
    /// Anchor palette for a phase peak in a color scheme.
    public static func anchorPalette(_ phase: DayPhase, scheme: ColorScheme) -> WickPalette {
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
    public static func palette(
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
    public static func phase(at date: Date, calendar: Calendar = .current) -> DayPhase {
        phaseBlend(at: date, calendar: calendar).from
    }

    /// "Now" for theme resolution. Honors `WICK_ARC_TIME=HH:mm` in debug
    /// builds only (screenshots/design review); release builds always use the
    /// real current date.
    public static func currentDate(calendar: Calendar = .current) -> Date {
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

    /// Rose-dawn paper(玫瑰晨纸)。
    private static let lightDawn = WickPalette(
        backgroundTop: WickRGB(hex: 0xF0E2D4),
        backgroundBottom: WickRGB(hex: 0xE7D5C3),
        sidebarBackground: WickRGB(hex: 0xF0E3D6),
        cardTop: WickRGB(hex: 0xFFFAF1),
        cardBottom: WickRGB(hex: 0xFBF0E4),
        cardStroke: WickRGB(hex: 0x33231C, opacity: 0.16),
        controlBackground: WickRGB(hex: 0x33231C, opacity: 0.055),
        controlBorder: WickRGB(hex: 0x33231C, opacity: 0.16),
        textPrimary: WickRGB(hex: 0x33231C),
        textSecondary: WickRGB(hex: 0x715850),
        textTertiary: WickRGB(hex: 0x8D6F5F),
        accent: WickRGB(hex: 0xD26438),
        accentText: WickRGB(hex: 0xA8492C),
        accentSoft: WickRGB(hex: 0xF2DCC2, opacity: 0.9),
        reviewCorrect: WickRGB(hex: 0xC03A22),
        reviewWrong: WickRGB(hex: 0xC03A22),
        divider: WickRGB(hex: 0x33231C, opacity: 0.16),
        glow: WickRGB(hex: 0xE06A38, opacity: 0.30),
        stain1: WickRGB(hex: 0xF2DCC2),
        stain2: WickRGB(hex: 0xE6C49A),
        pnlUp: WickRGB(hex: 0xC03A22),
        pnlDown: WickRGB(hex: 0x3E5C50),
        receipt: WickRGB(hex: 0xFFFDF4),
        receiptInk: WickRGB(hex: 0x33291A),
        brandTile: WickRGB(hex: 0x191008)
    )

    /// Warm cream paper at noon(正午烛光基线)。
    private static let lightDay = WickPalette(
        backgroundTop: WickRGB(hex: 0xEAE0CB),
        backgroundBottom: WickRGB(hex: 0xE3D7BE),
        sidebarBackground: WickRGB(hex: 0xEDE3CF),
        cardTop: WickRGB(hex: 0xFFFCF2),
        cardBottom: WickRGB(hex: 0xFBF4E6),
        cardStroke: WickRGB(hex: 0x2B2014, opacity: 0.16),
        controlBackground: WickRGB(hex: 0x2B2014, opacity: 0.055),
        controlBorder: WickRGB(hex: 0x2B2014, opacity: 0.16),
        textPrimary: WickRGB(hex: 0x2B2014),
        textSecondary: WickRGB(hex: 0x6B5942),
        textTertiary: WickRGB(hex: 0x82705A),
        accent: WickRGB(hex: 0xD96E14),
        accentText: WickRGB(hex: 0xA85A0E),
        accentSoft: WickRGB(hex: 0xF0DFB6, opacity: 0.9),
        reviewCorrect: WickRGB(hex: 0xC03A22),
        reviewWrong: WickRGB(hex: 0xC03A22),
        divider: WickRGB(hex: 0x2B2014, opacity: 0.16),
        glow: WickRGB(hex: 0xE8791C, opacity: 0.32),
        stain1: WickRGB(hex: 0xF0DFB6),
        stain2: WickRGB(hex: 0xE2C282),
        pnlUp: WickRGB(hex: 0xC03A22),
        pnlDown: WickRGB(hex: 0x3E5C50),
        receipt: WickRGB(hex: 0xFFFDF4),
        receiptInk: WickRGB(hex: 0x33291A),
        brandTile: WickRGB(hex: 0x191008)
    )

    /// Honeyed dusk paper(蜜色黄昏纸)。
    private static let lightDusk = WickPalette(
        backgroundTop: WickRGB(hex: 0xEBDDBE),
        backgroundBottom: WickRGB(hex: 0xE2CFA6),
        sidebarBackground: WickRGB(hex: 0xF0E0C0),
        cardTop: WickRGB(hex: 0xFFF9EA),
        cardBottom: WickRGB(hex: 0xFAEEDA),
        cardStroke: WickRGB(hex: 0x2E2112, opacity: 0.16),
        controlBackground: WickRGB(hex: 0x2E2112, opacity: 0.055),
        controlBorder: WickRGB(hex: 0x2E2112, opacity: 0.16),
        textPrimary: WickRGB(hex: 0x2E2112),
        textSecondary: WickRGB(hex: 0x6B5136),
        textTertiary: WickRGB(hex: 0x816440),
        accent: WickRGB(hex: 0xCC6A10),
        accentText: WickRGB(hex: 0x9F5208),
        accentSoft: WickRGB(hex: 0xF2DCAC, opacity: 0.9),
        reviewCorrect: WickRGB(hex: 0xC03A22),
        reviewWrong: WickRGB(hex: 0xC03A22),
        divider: WickRGB(hex: 0x2E2112, opacity: 0.16),
        glow: WickRGB(hex: 0xE07412, opacity: 0.34),
        stain1: WickRGB(hex: 0xF2DCAC),
        stain2: WickRGB(hex: 0xE6C688),
        pnlUp: WickRGB(hex: 0xC03A22),
        pnlDown: WickRGB(hex: 0x3E5C50),
        receipt: WickRGB(hex: 0xFFFDF4),
        receiptInk: WickRGB(hex: 0x33291A),
        brandTile: WickRGB(hex: 0x191008)
    )

    /// Dim warm paper under weak night light(夜里弱光下的纸)。
    private static let lightNight = WickPalette(
        backgroundTop: WickRGB(hex: 0xDFDACC),
        backgroundBottom: WickRGB(hex: 0xD6D0C2),
        sidebarBackground: WickRGB(hex: 0xE1DCD0),
        cardTop: WickRGB(hex: 0xF5F1E6),
        cardBottom: WickRGB(hex: 0xEDE8DB),
        cardStroke: WickRGB(hex: 0x29241B, opacity: 0.16),
        controlBackground: WickRGB(hex: 0x29241B, opacity: 0.05),
        controlBorder: WickRGB(hex: 0x29241B, opacity: 0.16),
        textPrimary: WickRGB(hex: 0x29241B),
        textSecondary: WickRGB(hex: 0x5E5747),
        textTertiary: WickRGB(hex: 0x7D7465),
        accent: WickRGB(hex: 0xC96F1C),
        accentText: WickRGB(hex: 0x96550F),
        accentSoft: WickRGB(hex: 0xEBDCB8, opacity: 0.9),
        reviewCorrect: WickRGB(hex: 0xC03A22),
        reviewWrong: WickRGB(hex: 0xC03A22),
        divider: WickRGB(hex: 0x29241B, opacity: 0.16),
        glow: WickRGB(hex: 0xE8862B, opacity: 0.30),
        stain1: WickRGB(hex: 0xEBDCB8),
        stain2: WickRGB(hex: 0xDCC896),
        pnlUp: WickRGB(hex: 0xC03A22),
        pnlDown: WickRGB(hex: 0x3E5C50),
        receipt: WickRGB(hex: 0xFFFDF4),
        receiptInk: WickRGB(hex: 0x33291A),
        brandTile: WickRGB(hex: 0x191008)
    )

    // MARK: Anchor palettes — dark scheme

    /// Indigo pre-dawn with an ember accent(拂晓余烬)。
    private static let darkDawn = WickPalette(
        backgroundTop: WickRGB(hex: 0x1B1310),
        backgroundBottom: WickRGB(hex: 0x16100C),
        sidebarBackground: WickRGB(hex: 0x211812),
        cardTop: WickRGB(hex: 0x35291C),
        cardBottom: WickRGB(hex: 0x2B2118),
        cardStroke: WickRGB(hex: 0xF0E3C6, opacity: 0.12),
        controlBackground: WickRGB(hex: 0xF0E3C6, opacity: 0.06),
        controlBorder: WickRGB(hex: 0xF0E3C6, opacity: 0.14),
        textPrimary: WickRGB(hex: 0xF0E3C6),
        textSecondary: WickRGB(hex: 0xF0E3C6, opacity: 0.64),
        textTertiary: WickRGB(hex: 0xF0E3C6, opacity: 0.42),
        accent: WickRGB(hex: 0xF0A368),
        accentText: WickRGB(hex: 0xF5BE8A),
        accentSoft: WickRGB(hex: 0x4E3C24, opacity: 0.9),
        reviewCorrect: WickRGB(hex: 0xE06A4C),
        reviewWrong: WickRGB(hex: 0xE06A4C),
        divider: WickRGB(hex: 0xF0E3C6, opacity: 0.14),
        glow: WickRGB(hex: 0xF0A368, opacity: 0.42),
        stain1: WickRGB(hex: 0x4E3C24),
        stain2: WickRGB(hex: 0x6E562C),
        pnlUp: WickRGB(hex: 0xE06A4C),
        pnlDown: WickRGB(hex: 0x8FAE9E),
        receipt: WickRGB(hex: 0xF5EEDC),
        receiptInk: WickRGB(hex: 0x33291A),
        brandTile: WickRGB(hex: 0x0C0703)
    )

    /// Brighter umber at midday(正午暖赭)。
    private static let darkDay = WickPalette(
        backgroundTop: WickRGB(hex: 0x1E150B),
        backgroundBottom: WickRGB(hex: 0x15100A),
        sidebarBackground: WickRGB(hex: 0x221A0F),
        cardTop: WickRGB(hex: 0x362A18),
        cardBottom: WickRGB(hex: 0x2C2214),
        cardStroke: WickRGB(hex: 0xF0E3C6, opacity: 0.12),
        controlBackground: WickRGB(hex: 0xF0E3C6, opacity: 0.06),
        controlBorder: WickRGB(hex: 0xF0E3C6, opacity: 0.14),
        textPrimary: WickRGB(hex: 0xF0E3C6),
        textSecondary: WickRGB(hex: 0xF0E3C6, opacity: 0.64),
        textTertiary: WickRGB(hex: 0xF0E3C6, opacity: 0.42),
        accent: WickRGB(hex: 0xF5A83C),
        accentText: WickRGB(hex: 0xFFC882),
        accentSoft: WickRGB(hex: 0x4A3820, opacity: 0.9),
        reviewCorrect: WickRGB(hex: 0xE06A4C),
        reviewWrong: WickRGB(hex: 0xE06A4C),
        divider: WickRGB(hex: 0xF0E3C6, opacity: 0.14),
        glow: WickRGB(hex: 0xF59A3C, opacity: 0.42),
        stain1: WickRGB(hex: 0x4A3820),
        stain2: WickRGB(hex: 0x6B5226),
        pnlUp: WickRGB(hex: 0xE06A4C),
        pnlDown: WickRGB(hex: 0x8FAE9E),
        receipt: WickRGB(hex: 0xF5EEDC),
        receiptInk: WickRGB(hex: 0x33291A),
        brandTile: WickRGB(hex: 0x0C0703)
    )

    /// Burnt amber evening(焦琥珀傍晚)。
    private static let darkDusk = WickPalette(
        backgroundTop: WickRGB(hex: 0x1E1409),
        backgroundBottom: WickRGB(hex: 0x181006),
        sidebarBackground: WickRGB(hex: 0x241A0E),
        cardTop: WickRGB(hex: 0x382712),
        cardBottom: WickRGB(hex: 0x2E2010),
        cardStroke: WickRGB(hex: 0xF0E3C6, opacity: 0.12),
        controlBackground: WickRGB(hex: 0xF0E3C6, opacity: 0.06),
        controlBorder: WickRGB(hex: 0xF0E3C6, opacity: 0.14),
        textPrimary: WickRGB(hex: 0xF0E3C6),
        textSecondary: WickRGB(hex: 0xF0E3C6, opacity: 0.64),
        textTertiary: WickRGB(hex: 0xF0E3C6, opacity: 0.42),
        accent: WickRGB(hex: 0xF08A2B),
        accentText: WickRGB(hex: 0xF7AB5E),
        accentSoft: WickRGB(hex: 0x523F22, opacity: 0.9),
        reviewCorrect: WickRGB(hex: 0xE06A4C),
        reviewWrong: WickRGB(hex: 0xE06A4C),
        divider: WickRGB(hex: 0xF0E3C6, opacity: 0.14),
        glow: WickRGB(hex: 0xF08A2B, opacity: 0.44),
        stain1: WickRGB(hex: 0x523F22),
        stain2: WickRGB(hex: 0x74592C),
        pnlUp: WickRGB(hex: 0xE06A4C),
        pnlDown: WickRGB(hex: 0x8FAE9E),
        receipt: WickRGB(hex: 0xF5EEDC),
        receiptInk: WickRGB(hex: 0x33291A),
        brandTile: WickRGB(hex: 0x0C0703)
    )

    /// Deep umber midnight(子夜深赭,火苗最亮)。
    private static let darkNight = WickPalette(
        backgroundTop: WickRGB(hex: 0x150E07),
        backgroundBottom: WickRGB(hex: 0x100B06),
        sidebarBackground: WickRGB(hex: 0x1C140B),
        cardTop: WickRGB(hex: 0x2C2214),
        cardBottom: WickRGB(hex: 0x241C10),
        cardStroke: WickRGB(hex: 0xF0E3C6, opacity: 0.12),
        controlBackground: WickRGB(hex: 0xF0E3C6, opacity: 0.06),
        controlBorder: WickRGB(hex: 0xF0E3C6, opacity: 0.14),
        textPrimary: WickRGB(hex: 0xF0E3C6),
        textSecondary: WickRGB(hex: 0xF0E3C6, opacity: 0.64),
        textTertiary: WickRGB(hex: 0xF0E3C6, opacity: 0.42),
        accent: WickRGB(hex: 0xF5A83C),
        accentText: WickRGB(hex: 0xFFCE8C),
        accentSoft: WickRGB(hex: 0x46351E, opacity: 0.9),
        reviewCorrect: WickRGB(hex: 0xE06A4C),
        reviewWrong: WickRGB(hex: 0xE06A4C),
        divider: WickRGB(hex: 0xF0E3C6, opacity: 0.14),
        glow: WickRGB(hex: 0xF5A83C, opacity: 0.50),
        stain1: WickRGB(hex: 0x46351E),
        stain2: WickRGB(hex: 0x665026),
        pnlUp: WickRGB(hex: 0xE06A4C),
        pnlDown: WickRGB(hex: 0x8FAE9E),
        receipt: WickRGB(hex: 0xF5EEDC),
        receiptInk: WickRGB(hex: 0x33291A),
        brandTile: WickRGB(hex: 0x0C0703)
    )
}

// MARK: - SwiftUI environment

public struct WickPaletteEnvironmentKey: EnvironmentKey {
    public static let defaultValue = DayArcEngine.anchorPalette(.day, scheme: .light)
}

public extension EnvironmentValues {
    var wickPalette: WickPalette {
        get { self[WickPaletteEnvironmentKey.self] }
        set { self[WickPaletteEnvironmentKey.self] = newValue }
    }
}
