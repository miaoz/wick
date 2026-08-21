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
