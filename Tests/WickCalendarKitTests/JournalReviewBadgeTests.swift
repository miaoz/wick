import XCTest
@testable import WickCalendarKit
import WickSync

final class JournalReviewBadgeTests: XCTestCase {
    func testReviewSealGlyphsAreLanguageNeutralSymbols() {
        XCTAssertEqual(JournalReviewVerdict.correct.reviewSealGlyph, "✓")
        XCTAssertEqual(JournalReviewVerdict.wrong.reviewSealGlyph, "✗")
    }

    func testReviewSealInkFollowsPnlConvention() {
        let palette = DayArcEngine.anchorPalette(.day, scheme: .light)

        XCTAssertEqual(
            JournalReviewVerdict.correct.inkColor(in: palette, convention: .redUp),
            palette.pnlUp
        )
        XCTAssertEqual(
            JournalReviewVerdict.wrong.inkColor(in: palette, convention: .redUp),
            palette.pnlDown
        )
        XCTAssertEqual(
            JournalReviewVerdict.correct.inkColor(in: palette, convention: .greenUp),
            palette.pnlDown
        )
        XCTAssertEqual(
            JournalReviewVerdict.wrong.inkColor(in: palette, convention: .greenUp),
            palette.pnlUp
        )
    }
}
