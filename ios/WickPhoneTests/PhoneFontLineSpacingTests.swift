import UIKit
import XCTest
@testable import WickPhone

final class PhoneFontLineSpacingTests: XCTestCase {
    @MainActor
    func testAdaptiveLineSpacingClampsToMinimum() {
        let font = UIFont(name: "Songti SC", size: 13.5) ?? UIFont.systemFont(ofSize: 13.5)
        let spacing = PhoneFont.adaptiveLineSpacing(for: font, targetMultiplier: 1.55, minSpacing: 2.5)
        XCTAssertGreaterThanOrEqual(spacing, 2.5)
    }

    @MainActor
    func testAdaptiveLineSpacingCompensatesTightFonts() {
        let font = UIFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
        let natural = font.lineHeight
        let spacing = PhoneFont.adaptiveLineSpacing(for: font, targetMultiplier: 1.55, minSpacing: 2.5)
        let total = natural + spacing
        let target = font.pointSize * 1.55
        XCTAssertGreaterThanOrEqual(total, target - 0.5)
    }

    @MainActor
    func testPaperLineSpacingMatchesAdaptiveCalculation() {
        let size: CGFloat = 13.5
        let font = PhoneFont.paperUIFont(size)
        let expected = PhoneFont.adaptiveLineSpacing(for: font)
        let actual = PhoneFont.paperLineSpacing(size)
        XCTAssertEqual(actual, expected)
    }
}
