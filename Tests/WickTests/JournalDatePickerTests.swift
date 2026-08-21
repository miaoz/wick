import SwiftUI
import XCTest
import WickSync
@testable import WickCore

@MainActor
final class JournalDatePickerTests: XCTestCase {
    func testDatePickerSelection() {
        var selected = Date(timeIntervalSince1970: 1755734400) // 2025-08-21
        var selectedResult: Date?

        let binding = Binding<Date>(
            get: { selected },
            set: { selected = $0 }
        )

        let picker = JournalDatePickerView(
            selectedDate: binding,
            onSelectDate: { date in
                selectedResult = date
            }
        )

        XCTAssertNotNil(picker)
        _ = selectedResult
    }

    func testDesiredWindowStart() {
        let calendar = Calendar.current
        let now = Date(timeIntervalSince1970: 1755734400) // 2025-08-21 00:00:00 UTC

        // 1. When entries is empty, window start is start of today (now)
        let emptyStart = ExchangePositionCoordinator.desiredWindowStart(entries: [], now: now)
        XCTAssertEqual(emptyStart, calendar.startOfDay(for: now))

        // 2. When entries has a 06-25 entry, window start is 06-25
        let june25 = Date(timeIntervalSince1970: 1750809600) // 2025-06-25
        let entry1 = JournalEntry(date: june25, items: [])
        let start1 = ExchangePositionCoordinator.desiredWindowStart(entries: [entry1], now: now)
        XCTAssertEqual(start1, calendar.startOfDay(for: june25))

        // 3. When user later writes an earlier entry (05-10), window start moves to 05-10
        let may10 = Date(timeIntervalSince1970: 1746835200) // 2025-05-10
        let entry2 = JournalEntry(date: may10, items: [])
        let start2 = ExchangePositionCoordinator.desiredWindowStart(entries: [entry1, entry2], now: now)
        XCTAssertEqual(start2, calendar.startOfDay(for: may10))
    }

    func testRenderSettingsSnapshot() {
        let settings = AppSettings.shared
        let journalStore = JournalStore.shared
        let theme = PanelTheme.resolve(at: Date(), scheme: .light)

        let view = ProgressPanelView(showsSettings: true)
            .environmentObject(settings)
            .environmentObject(journalStore)
            .environment(\.wickPalette, theme.palette)
            .environment(\.colorScheme, .light)
            .preferredColorScheme(.light)

        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: CGSize(width: 360, height: max(size.height, 680)))
        hosting.layoutSubtreeIfNeeded()

        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)

        if let png = bitmap.representation(using: .png, properties: [:]) {
            let outURL = URL(fileURLWithPath: "/Users/miaoz/.gemini/antigravity-cli/brain/f0101f4b-9e7e-4e18-bbbc-06335f70d25a/scratch/settings_preview.png")
            try? png.write(to: outURL)
        }
    }
}
