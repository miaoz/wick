import AppKit
import SwiftUI
import XCTest
@testable import WickCore

@MainActor
final class MenuBarSettingsLayoutTests: XCTestCase {
    func testSettingsReportsFixedTallHeightAcrossAllProposals() {
        let view = ProgressPanelView(showsSettings: true)
            .environmentObject(AppSettings.shared)
            .environmentObject(JournalStore.shared)
        let controller = NSHostingController(rootView: view)
        let fittingHeight = controller.view.fittingSize.height
        XCTAssertGreaterThanOrEqual(fittingHeight, 600)

        for proposedHeight: CGFloat in [0, 10, 60, 100, 360, 651, 1000, .infinity] {
            let size = controller.sizeThatFits(in: CGSize(width: 360, height: proposedHeight))
            XCTAssertEqual(size.width, 360, accuracy: 1.0)
            XCTAssertEqual(size.height, fittingHeight, accuracy: 1.0, "Proposed height \(proposedHeight) must not shrink settings.")
        }
    }

    func testSettingsFitsAndScrollsToBothEndsOnShortScreen() throws {
        let view = ProgressPanelView(showsSettings: true, availableScreenHeight: 460)
            .environmentObject(AppSettings.shared)
            .environmentObject(JournalStore.shared)
        let host = NSHostingView(rootView: view)
        let fitting = host.fittingSize
        XCTAssertLessThanOrEqual(fitting.height, 460)

        let bounds = NSRect(origin: .zero, size: fitting)
        let window = NSPanel(contentRect: bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView?.addSubview(host)
        host.frame = bounds
        host.layoutSubtreeIfNeeded()

        let scroll = try XCTUnwrap(scrollView(in: host))
        let document = try XCTUnwrap(scroll.documentView)
        document.layoutSubtreeIfNeeded()
        let viewport = scroll.convert(scroll.bounds, to: host)
        XCTAssertTrue(host.bounds.contains(viewport), "The entire scrolling viewport must fit below the header.")
        XCTAssertGreaterThanOrEqual(viewport.minY, 80, "Settings header must remain visible above the scroll viewport.")
        XCTAssertGreaterThan(document.bounds.height, viewport.height)

        for y in [document.bounds.maxY - 1, document.bounds.minY] {
            let edge = NSRect(x: 0, y: y, width: 1, height: 1)
            document.scrollToVisible(edge)
            XCTAssertTrue(scroll.documentVisibleRect.contains(edge))
            XCTAssertTrue(host.bounds.contains(document.convert(edge, to: host)))
        }
    }

    func testSettingsGrowsPanelWindowFromProgressHeight() {
        let holder = PanelStateHolder()
        let controller = NSHostingController(
            rootView: PanelStateWrapper(holder: holder)
                .environmentObject(AppSettings.shared)
                .environmentObject(JournalStore.shared)
        )
        controller.sizingOptions = [.minSize, .intrinsicContentSize, .maxSize]
        let window = NSPanel(contentViewController: controller)
        window.styleMask = [.borderless, .nonactivatingPanel]
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let progressHeight = window.frame.height
        XCTAssertGreaterThan(progressHeight, 200)

        holder.showsSettings = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let settingsHeight = window.frame.height
        XCTAssertGreaterThanOrEqual(settingsHeight, 600)
        XCTAssertGreaterThan(settingsHeight, progressHeight + 150)
        XCTAssertEqual(window.contentMinSize.height, settingsHeight, accuracy: 1.0)
        XCTAssertEqual(window.contentMaxSize.height, settingsHeight, accuracy: 1.0)

        holder.showsSettings = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(window.frame.height, progressHeight, accuracy: 1.0)
    }

    func testDesiredSettingsScrollHeightClampsToShortScreen() {
        XCTAssertEqual(ProgressPanelView.desiredSettingsScrollHeight(forAvailableScreenHeight: nil), 520)
        XCTAssertEqual(ProgressPanelView.desiredSettingsScrollHeight(forAvailableScreenHeight: 985), 520)

        let shortHeight = ProgressPanelView.desiredSettingsScrollHeight(forAvailableScreenHeight: 540)
        XCTAssertLessThan(shortHeight, 520)
        XCTAssertGreaterThanOrEqual(shortHeight, 180)
        XCTAssertLessThanOrEqual(shortHeight, 540 - 28 - 140)
    }

    private func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for child in view.subviews {
            if let scroll = scrollView(in: child) { return scroll }
        }
        return nil
    }
}

@MainActor
private final class PanelStateHolder: ObservableObject {
    @Published var showsSettings = false
}

private struct PanelStateWrapper: View {
    @ObservedObject var holder: PanelStateHolder

    var body: some View {
        ProgressPanelView(showsSettings: $holder.showsSettings)
    }
}
