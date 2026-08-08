import AppKit
import SwiftUI

/// Borderless, transparent window that behaves like an object on the desk — clicks
/// outside the pad fall through to whatever is underneath (ported from himekuri).
final class TradingCalendarWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Hosting view that only accepts clicks within the pad (top-left origin coords).
final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    /// Region (top-left origin coordinates) that accepts mouse events.
    var interactiveRect: CGRect = .zero

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @objc required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        let topLeft = isFlipped ? p : NSPoint(x: p.x, y: bounds.height - p.y)
        guard interactiveRect.contains(topLeft) else { return nil }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the trading-calendar window so it can be opened from the menu bar panel.
/// Mirrors `JournalWindowController` activation policy; the window itself is a
/// transparent, click-through pad exactly like himekuri's.
@MainActor
final class TradingCalendarWindowController: NSObject, NSWindowDelegate {
    static let shared = TradingCalendarWindowController()

    private(set) var window: NSWindow?

    private override init() {
        super.init()
    }

    var hasOpenWindow: Bool {
        guard let window else { return false }
        return window.isVisible || window.isMiniaturized
    }

    func openCalendar() {
        NSApp.setActivationPolicy(.regular)

        let calendarWindow = ensureWindow()
        MenuBarExtraPanel.dismiss(excluding: [calendarWindow])

        if calendarWindow.isMiniaturized {
            calendarWindow.deminiaturize(nil)
        }
        calendarWindow.makeKeyAndOrderFront(nil)
        calendarWindow.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSApp.setActivationPolicy(.regular)
            if let window = self.window {
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func closeCalendar() {
        window?.close()
    }

    private func ensureWindow() -> NSWindow {
        if let window, window.isVisible || window.isMiniaturized {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            return window
        }
        if let window {
            return window
        }

        let root = TradingCalendarRootView()
            .environmentObject(AppSettings.shared)
            .environmentObject(MacroCalendarStore.shared)

        let rect = NSRect(
            x: 0, y: 0,
            width: TradingCalendarGeometry.windowW,
            height: TradingCalendarGeometry.windowH
        )
        let window = TradingCalendarWindow(
            contentRect: rect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.delegate = self

        let host = PassThroughHostingView(rootView: root)
        host.frame = rect
        let margin: CGFloat = 14
        host.interactiveRect = CGRect(
            x: (TradingCalendarGeometry.windowW - TradingCalendarGeometry.pageW) / 2 - margin,
            y: TradingCalendarGeometry.blockTopPad - 8,
            width: TradingCalendarGeometry.pageW + 2 * margin,
            height: TradingCalendarGeometry.bindingH + TradingCalendarGeometry.pageH + 44
        )
        window.contentView = host

        if !window.setFrameUsingName("WickTradingCalendarWindow"), let screen = NSScreen.main {
            let v = screen.visibleFrame
            window.setFrameOrigin(NSPoint(
                x: v.maxX - TradingCalendarGeometry.windowW - 36,
                y: v.maxY - TradingCalendarGeometry.windowH + 40
            ))
        }
        window.setFrameAutosaveName("WickTradingCalendarWindow")

        self.window = window
        return window
    }

    func windowDidBecomeKey(_ notification: Notification) {
        let keyWindow = (notification.object as? NSWindow) ?? window
        if let keyWindow {
            MenuBarExtraPanel.dismiss(excluding: [keyWindow])
        }
    }

    func windowWillClose(_ notification: Notification) {
        // Back to menu-bar-only presence unless the journal window is still open.
        if !JournalWindowController.shared.hasOpenJournalWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
