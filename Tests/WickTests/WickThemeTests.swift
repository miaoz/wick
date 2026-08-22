import SwiftUI
import XCTest
@testable import WickCore

final class WickThemeTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func date(hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 15
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    // MARK: WickRGB math

    func testLuminanceAndContrastBasics() {
        let white = WickRGB(r: 1, g: 1, b: 1)
        let black = WickRGB(r: 0, g: 0, b: 0)
        XCTAssertEqual(white.relativeLuminance, 1, accuracy: 0.0001)
        XCTAssertEqual(black.relativeLuminance, 0, accuracy: 0.0001)
        XCTAssertEqual(white.contrastRatio(to: black), 21, accuracy: 0.01)
    }

    func testLerpMidpoint() {
        let a = WickRGB(r: 0.2, g: 0.4, b: 0.6, a: 0.8)
        let b = WickRGB(r: 0.8, g: 0.2, b: 0.4, a: 0.4)
        let mid = a.lerped(to: b, t: 0.5)
        XCTAssertEqual(mid.r, 0.5, accuracy: 0.0001)
        XCTAssertEqual(mid.g, 0.3, accuracy: 0.0001)
        XCTAssertEqual(mid.b, 0.5, accuracy: 0.0001)
        XCTAssertEqual(mid.a, 0.6, accuracy: 0.0001)
    }

    // MARK: Phase assignment

    func testPhaseAtAnchorPeaks() {
        XCTAssertEqual(DayArcEngine.phase(at: date(hour: 6, minute: 30), calendar: calendar), .dawn)
        XCTAssertEqual(DayArcEngine.phase(at: date(hour: 12), calendar: calendar), .day)
        XCTAssertEqual(DayArcEngine.phase(at: date(hour: 18), calendar: calendar), .dusk)
        XCTAssertEqual(DayArcEngine.phase(at: date(hour: 22, minute: 30), calendar: calendar), .night)
    }

    func testPhaseAcrossSegments() {
        // Deep night is still night (not pre-dawn).
        XCTAssertEqual(DayArcEngine.phase(at: date(hour: 3), calendar: calendar), .night)
        XCTAssertEqual(DayArcEngine.phase(at: date(hour: 5, minute: 59), calendar: calendar), .night)
        XCTAssertEqual(DayArcEngine.phase(at: date(hour: 9), calendar: calendar), .dawn)
        XCTAssertEqual(DayArcEngine.phase(at: date(hour: 15), calendar: calendar), .day)
        XCTAssertEqual(DayArcEngine.phase(at: date(hour: 21), calendar: calendar), .dusk)
        XCTAssertEqual(DayArcEngine.phase(at: date(hour: 23, minute: 30), calendar: calendar), .night)
    }

    // MARK: Interpolation

    func testPaletteInterpolationMidpoint() {
        // 09:15 is exactly halfway between the dawn (06:30) and day (12:00) anchors.
        let resolved = DayArcEngine.palette(at: date(hour: 9, minute: 15), scheme: .light, calendar: calendar)
        let expected = DayArcEngine.anchorPalette(.dawn, scheme: .light)
            .lerped(to: DayArcEngine.anchorPalette(.day, scheme: .light), t: 0.5)
        XCTAssertEqual(resolved.backgroundTop.r, expected.backgroundTop.r, accuracy: 0.0001)
        XCTAssertEqual(resolved.backgroundTop.g, expected.backgroundTop.g, accuracy: 0.0001)
        XCTAssertEqual(resolved.accent.b, expected.accent.b, accuracy: 0.0001)
    }

    func testPaletteInterpolationWrapsPastMidnight() {
        // 00:15 lies in the night → dawn segment: t = (24.25 - 22.5) / 8 = 0.21875.
        let resolved = DayArcEngine.palette(at: date(hour: 0, minute: 15), scheme: .dark, calendar: calendar)
        let expected = DayArcEngine.anchorPalette(.night, scheme: .dark)
            .lerped(to: DayArcEngine.anchorPalette(.dawn, scheme: .dark), t: 0.21875)
        XCTAssertEqual(resolved.backgroundBottom.r, expected.backgroundBottom.r, accuracy: 0.0001)
        XCTAssertEqual(resolved.textPrimary.a, expected.textPrimary.a, accuracy: 0.0001)
    }

    // MARK: Contrast guardrails

    /// Samples every 15 minutes of the day in both schemes and asserts WCAG-ish
    /// floors, so interpolated in-between states can never become unreadable.
    func testContrastGuardrailsAcrossWholeDay() {
        for scheme in [ColorScheme.light, ColorScheme.dark] {
            for minutes in stride(from: 0, through: 1439, by: 15) {
                let sample = date(hour: minutes / 60, minute: minutes % 60)
                let palette = DayArcEngine.palette(at: sample, scheme: scheme, calendar: calendar)
                let whereAmI = "\(scheme) @ \(minutes / 60):\(String(format: "%02d", minutes % 60))"

                let primaryOverBottom = palette.textPrimary.flattened(over: palette.backgroundBottom)
                XCTAssertGreaterThanOrEqual(
                    primaryOverBottom.contrastRatio(to: palette.backgroundBottom), 4.5, "textPrimary/bgBottom \(whereAmI)"
                )
                let primaryOverTop = palette.textPrimary.flattened(over: palette.backgroundTop)
                XCTAssertGreaterThanOrEqual(
                    primaryOverTop.contrastRatio(to: palette.backgroundTop), 4.5, "textPrimary/bgTop \(whereAmI)"
                )
                let primaryOverCard = palette.textPrimary.flattened(over: palette.cardTop)
                XCTAssertGreaterThanOrEqual(
                    primaryOverCard.contrastRatio(to: palette.cardTop), 4.5, "textPrimary/cardTop \(whereAmI)"
                )

                let secondary = palette.textSecondary.flattened(over: palette.backgroundBottom)
                XCTAssertGreaterThanOrEqual(
                    secondary.contrastRatio(to: palette.backgroundBottom), 3.2, "textSecondary \(whereAmI)"
                )

                let tertiary = palette.textTertiary.flattened(over: palette.backgroundBottom)
                XCTAssertGreaterThanOrEqual(
                    tertiary.contrastRatio(to: palette.backgroundBottom), 2.8, "textTertiary \(whereAmI)"
                )

                let accentText = palette.accentText.flattened(over: palette.cardTop)
                XCTAssertGreaterThanOrEqual(
                    accentText.contrastRatio(to: palette.cardTop), 4.0, "accentText/cardTop \(whereAmI)"
                )

                // Accent is a graphic tint (toggles, icon gradient), not body text.
                let accent = palette.accent.flattened(over: palette.backgroundTop)
                XCTAssertGreaterThanOrEqual(
                    accent.contrastRatio(to: palette.backgroundTop), 2.5, "accent/bgTop \(whereAmI)"
                )

                // Review verdict glyphs on card fills (graphics floor: 3.0).
                let reviewCorrect = palette.reviewCorrect.flattened(over: palette.cardTop)
                XCTAssertGreaterThanOrEqual(
                    reviewCorrect.contrastRatio(to: palette.cardTop), 3.0, "reviewCorrect/cardTop \(whereAmI)"
                )
                let reviewWrong = palette.reviewWrong.flattened(over: palette.cardTop)
                XCTAssertGreaterThanOrEqual(
                    reviewWrong.contrastRatio(to: palette.cardTop), 3.0, "reviewWrong/cardTop \(whereAmI)"
                )
            }
        }
    }

    private func rgbString(_ color: Color) -> String {
        guard let nsColor = NSColor(color).usingColorSpace(.sRGB) else { return "?" }
        return [nsColor.redComponent, nsColor.greenComponent, nsColor.blueComponent]
            .map { String(format: "%.3f", $0) }
            .joined(separator: ",")
    }

    // MARK: PnL color convention

    /// The convention only swaps WHICH existing palette color is used for
    /// gain/loss — the underlying color values are untouched.
    func testUpDownColorsSwapsAssignmentNotValues() {
        let palette = DayArcEngine.anchorPalette(.day, scheme: .light)

        let redUp = palette.upDownColors(.redUp)     // 红涨绿跌
        XCTAssertEqual(redUp.gain, palette.pnlUp)
        XCTAssertEqual(redUp.loss, palette.pnlDown)

        let greenUp = palette.upDownColors(.greenUp) // 绿涨红跌
        XCTAssertEqual(greenUp.gain, palette.pnlDown)
        XCTAssertEqual(greenUp.loss, palette.pnlUp)
    }
}
