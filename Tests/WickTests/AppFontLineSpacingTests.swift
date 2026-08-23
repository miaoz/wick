import AppKit
import XCTest
@testable import WickCore

final class AppFontLineSpacingTests: XCTestCase {
    @MainActor
    func testAdaptiveLineSpacingClampsToMinimum() {
        // Songti SC already has generous line height (~18.9pt at 13.5pt size).
        // It should clamp to the minSpacing (2.5pt).
        let font = NSFont(name: "Songti SC", size: 13.5) ?? NSFont.systemFont(ofSize: 13.5)
        let spacing = AppFont.adaptiveLineSpacing(for: font, targetMultiplier: 1.55, minSpacing: 2.5)
        XCTAssertGreaterThanOrEqual(spacing, 2.5)
    }

    @MainActor
    func testAdaptiveLineSpacingCompensatesTightFonts() {
        // Tight metrics should be compensated up to target.
        let font = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
        let natural = font.ascender - font.descender + font.leading
        let spacing = AppFont.adaptiveLineSpacing(for: font, targetMultiplier: 1.55, minSpacing: 2.5)
        let total = natural + spacing
        let target = font.pointSize * 1.55
        XCTAssertGreaterThanOrEqual(total, target - 0.5)
    }

    @MainActor
    func testPaperLineSpacingMatchesAdaptiveCalculation() {
        let size: CGFloat = 13.5
        let font = AppFont.paperNSFont(size)
        let expected = AppFont.adaptiveLineSpacing(for: font)
        let actual = AppFont.paperLineSpacing(size)
        XCTAssertEqual(actual, expected)
    }
}
