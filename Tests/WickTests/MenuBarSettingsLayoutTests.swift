import AppKit
import SwiftUI
import XCTest
@testable import WickCore

@MainActor
final class MenuBarSettingsLayoutTests: XCTestCase {
    func testSettingsScrollsToBothEndsWhenPanelIsShorterThanItsIdealHeight() throws {
        let view = ProgressPanelView(showsSettings: true)
            .environmentObject(AppSettings.shared)
            .environmentObject(JournalStore.shared)
        let host = NSHostingView(rootView: view)
        let bounds = NSRect(x: 0, y: 0, width: 360, height: 360)
        let window = NSPanel(contentRect: bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView?.addSubview(host)
        XCTAssertGreaterThan(host.fittingSize.height, bounds.height)
        host.frame = bounds
        host.layoutSubtreeIfNeeded()

        let scroll = try XCTUnwrap(scrollView(in: host))
        let document = try XCTUnwrap(scroll.documentView)
        document.layoutSubtreeIfNeeded()
        let viewport = scroll.convert(scroll.bounds, to: host)
        XCTAssertTrue(host.bounds.contains(viewport), "The entire scrolling viewport must fit below the header.")
        XCTAssertGreaterThan(document.bounds.height, viewport.height)

        for y in [document.bounds.maxY - 1, document.bounds.minY] {
            let edge = NSRect(x: 0, y: y, width: 1, height: 1)
            document.scrollToVisible(edge)
            XCTAssertTrue(scroll.documentVisibleRect.contains(edge))
            XCTAssertTrue(host.bounds.contains(document.convert(edge, to: host)))
        }
    }

    private func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for child in view.subviews {
            if let scroll = scrollView(in: child) { return scroll }
        }
        return nil
    }
}
