import AppKit
import SwiftUI
import XCTest
import WickSync
@testable import WickCore

@MainActor
final class JournalEditorAndPreviewTests: XCTestCase {

    // MARK: - Image Preview State Tests

    func testImagePreviewStateCurrentFilename() {
        let filenames = ["photo1.jpg", "photo2.png", "photo3.jpg"]
        var state = JournalImagePreviewState(filenames: filenames, currentIndex: 0)

        XCTAssertEqual(state.currentFilename, "photo1.jpg")

        state.currentIndex = 1
        XCTAssertEqual(state.currentFilename, "photo2.png")

        state.currentIndex = 2
        XCTAssertEqual(state.currentFilename, "photo3.jpg")

        state.currentIndex = 99
        XCTAssertNil(state.currentFilename)
    }

    func testImagePreviewStateEmpty() {
        let state = JournalImagePreviewState(filenames: [], currentIndex: 0)
        XCTAssertNil(state.currentFilename)
    }

    // MARK: - IMESafeTextEditor Dynamic Height Tests

    func testTextEditorCoordinatorHeightCalculationExpandsWithLines() {
        let editor1 = IMESafeTextEditor(
            text: .constant("Single line of text"),
            minHeight: 48
        )
        let coordinator1 = editor1.makeCoordinator()
        let textView1 = IMETextView(frame: NSRect(x: 0, y: 0, width: 400, height: 48))
        textView1.string = "Single line of text"
        textView1.font = WickPrintFont.songti(13.5)
        coordinator1.textView = textView1

        let height1 = coordinator1.calculateHeight(for: 400)
        XCTAssertEqual(height1, 48, "Single short line should clamp to minHeight (48)")

        let multiLineText = """
        Line 1: 為這個應用寫點什麼。
        Line 2: 首先還是吃自己的狗糧。
        Line 3: 第三行測試內容。
        Line 4: 第四行測試內容。
        Line 5: 第五行測試內容。
        Line 6: 第六行測試內容。
        """
        let editor2 = IMESafeTextEditor(
            text: .constant(multiLineText),
            minHeight: 48
        )
        let coordinator2 = editor2.makeCoordinator()
        let textView2 = IMETextView(frame: NSRect(x: 0, y: 0, width: 400, height: 48))
        textView2.string = multiLineText
        textView2.font = WickPrintFont.songti(13.5)
        coordinator2.textView = textView2

        let height2 = coordinator2.calculateHeight(for: 400)
        XCTAssertGreaterThan(height2, 100, "Multi-line text height must be significantly larger than minHeight (48)")
        XCTAssertGreaterThan(height2, height1, "Height should grow as content lines increase")
    }

    // MARK: - Localization Tests

    func testImagePreviewLocalizationKeys() {
        for lang in [AppLanguage.chinese, AppLanguage.english] {
            XCTAssertFalse(L10n.string(.journalPreviewImage, language: lang).isEmpty)
            XCTAssertFalse(L10n.string(.journalOpenInPreview, language: lang).isEmpty)
            XCTAssertFalse(L10n.string(.journalCopyImage, language: lang).isEmpty)
            XCTAssertFalse(L10n.string(.journalRevealInFinder, language: lang).isEmpty)
            XCTAssertFalse(L10n.string(.journalImagePreviewHint, language: lang).isEmpty)
            XCTAssertFalse(L10n.string(.journalImageZoomIn, language: lang).isEmpty)
            XCTAssertFalse(L10n.string(.journalImageZoomOut, language: lang).isEmpty)
            XCTAssertFalse(L10n.string(.journalImageActualSize, language: lang).isEmpty)
            XCTAssertFalse(L10n.string(.journalImageFit, language: lang).isEmpty)
        }
    }
}
