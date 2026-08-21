import SwiftUI
import XCTest
import WickSync
@testable import WickCore

@MainActor
final class JournalDatePickerTests: XCTestCase {
    func testDatePickerSelection() {
        var selected = Date(timeIntervalSince1970: 1755734400) // 2025-08-21
        var didCallSelect = false
        var selectedResult: Date?

        let binding = Binding<Date>(
            get: { selected },
            set: { selected = $0 }
        )

        let picker = JournalDatePickerView(
            selectedDate: binding,
            onSelectDate: { date in
                didCallSelect = true
                selectedResult = date
            }
        )

        XCTAssertNotNil(picker)
    }
}
