import SwiftUI
import UIKit
import XCTest
import WickCalendarKit
import WickSync
@testable import WickPhone

final class PhoneTextEditorTests: XCTestCase {

    @MainActor
    func testTextEditorHeightCalculationClampsToMinHeight() {
        let editor = PhoneTextEditor(
            text: .constant("Short note"),
            minHeight: 56
        )
        let coordinator = editor.makeCoordinator()
        let textView = AutoHeightUITextView(frame: CGRect(x: 0, y: 0, width: 320, height: 56))
        textView.text = "Short note"
        textView.font = PhoneFont.paperUIFont(13.5)

        let height = coordinator.calculateHeight(for: 320, textView: textView)
        XCTAssertEqual(height, 56, "Single short line should clamp to minHeight (56)")
    }

    @MainActor
    func testTextEditorHeightCalculationExpandsWithMultiLineText() {
        let editor1 = PhoneTextEditor(
            text: .constant("Single line"),
            minHeight: 56
        )
        let coordinator1 = editor1.makeCoordinator()
        let textView1 = AutoHeightUITextView(frame: CGRect(x: 0, y: 0, width: 320, height: 56))
        textView1.text = "Single line"
        textView1.font = PhoneFont.paperUIFont(13.5)
        let height1 = coordinator1.calculateHeight(for: 320, textView: textView1)

        let multiLineText = """
        Line 1: 秉烛日记，一天一页纸。
        Line 2: 记录每一笔交易的想法与复盘。
        Line 3: 严格执行风控计划。
        Line 4: 不在冲动时开仓，不在恐慌时割肉。
        Line 5: 市场永远有机会，保住本金第一。
        Line 6: 保持平和的心态面对波动。
        Line 7: 总结今日得失，明日继续精进。
        """

        let editor2 = PhoneTextEditor(
            text: .constant(multiLineText),
            minHeight: 56
        )
        let coordinator2 = editor2.makeCoordinator()
        let textView2 = AutoHeightUITextView(frame: CGRect(x: 0, y: 0, width: 320, height: 56))
        textView2.text = multiLineText
        textView2.font = PhoneFont.paperUIFont(13.5)
        let height2 = coordinator2.calculateHeight(for: 320, textView: textView2)

        XCTAssertGreaterThan(height2, 100, "Multi-line text height must be significantly larger than minHeight (56)")
        XCTAssertGreaterThan(height2, height1, "Height should grow as content lines increase")
    }

    @MainActor
    func testTextEditorHeightCalculationClampsToMaxHeight() {
        let multiLineText = (1...20).map { "Line \($0): 测试内容" }.joined(separator: "\n")
        let editor = PhoneTextEditor(
            text: .constant(multiLineText),
            minHeight: 56,
            maxHeight: 120
        )
        let coordinator = editor.makeCoordinator()
        let textView = AutoHeightUITextView(frame: CGRect(x: 0, y: 0, width: 320, height: 56))
        textView.text = multiLineText
        textView.font = PhoneFont.paperUIFont(13.5)

        let height = coordinator.calculateHeight(for: 320, textView: textView)
        XCTAssertEqual(height, 120, "Height should be capped at maxHeight (120)")
    }

    @MainActor
    func testAutoHeightUITextViewIntrinsicContentSize() {
        let textView = AutoHeightUITextView(frame: CGRect(x: 0, y: 0, width: 320, height: 56))
        textView.minHeight = 56
        textView.text = "Hello"
        textView.font = PhoneFont.paperUIFont(13.5)

        let intrinsic = textView.intrinsicContentSize
        XCTAssertEqual(intrinsic.width, UIView.noIntrinsicMetric)
        XCTAssertGreaterThanOrEqual(intrinsic.height, 56)
    }
}
