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
final class TradingCalendarWindowController: NSObject, NSWindowDelegate, ObservableObject {
    static let shared = TradingCalendarWindowController()

    private(set) var window: NSWindow?
    /// True while the pad is on the desk. Drives the journal top-bar toggle.
    @Published private(set) var isPresented = false
    /// Bumps on each open/close so a deferred `orderFront` from an earlier
    /// `openCalendar` cannot resurrect the pad after the user dismissed it.
    private var presentGeneration = 0

    /// Local input monitors translating arrow keys / scroll gestures into
    /// events-page flips. Installed once at window creation; every handler
    /// re-checks `event.window`, so they only act when the calendar itself is
    /// the target (key for keys, under the pointer for scrolls).
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    /// Mutable scroll state for the monitor handler. AppKit delivers local
    /// monitors on the main thread only, so a plain box is safe here — and
    /// unlike the controller itself it can be touched from a non-isolated
    /// closure without violating actor rules.
    private let scrollState = ScrollAccumulator()

    /// Scroll-wheel accumulation shared with the monitor closure.
    private final class ScrollAccumulator {
        var total: CGFloat = 0
        var cooldownUntil = Date.distantPast
    }

    private override init() {
        super.init()
    }

    var hasOpenWindow: Bool {
        guard let window else { return false }
        return window.isVisible || window.isMiniaturized
    }

    /// Journal top-bar control: show the pad if it is hidden, dismiss it if it
    /// is already on the desk. Miniaturized counts as hidden (restore, don't close).
    func toggleCalendar() {
        if isPresented || (window?.isVisible == true && window?.isMiniaturized != true) {
            closeCalendar()
        } else {
            openCalendar()
        }
    }

    func openCalendar() {
        presentGeneration += 1
        let generation = presentGeneration
        NSApp.setActivationPolicy(.regular)

        let calendarWindow = ensureWindow()
        MenuBarExtraPanel.dismiss(excluding: [calendarWindow])

        if calendarWindow.isMiniaturized {
            calendarWindow.deminiaturize(nil)
        }
        calendarWindow.makeKeyAndOrderFront(nil)
        calendarWindow.orderFrontRegardless()
        isPresented = true
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async { [weak self] in
            guard let self, self.presentGeneration == generation, self.isPresented else { return }
            NSApp.setActivationPolicy(.regular)
            if let window = self.window {
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func closeCalendar() {
        // Borderless windows often ignore `close()` once they are not key
        // (the journal top-bar click keys the journal first). `orderOut`
        // hides them regardless of key status.
        presentGeneration += 1
        window?.orderOut(nil)
        markDismissed()
    }

    private func markDismissed() {
        isPresented = false
        if !JournalWindowController.shared.hasOpenJournalWindow {
            NSApp.setActivationPolicy(.accessory)
        }
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

        let root = TradingCalendarHostView(
            onClose: { [weak self] in self?.closeCalendar() },
            onPageTorn: { [weak self] piece in
                guard let window = self?.window else { return }
                FallingPageOverlay.spawn(piece, from: window)
            }
        )

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
        installInputMonitors()
        return window
    }

    func windowDidBecomeKey(_ notification: Notification) {
        let keyWindow = (notification.object as? NSWindow) ?? window
        if let keyWindow {
            MenuBarExtraPanel.dismiss(excluding: [keyWindow])
        }
    }

    func windowWillClose(_ notification: Notification) {
        markDismissed()
    }

    // MARK: - Event-page input

    /// Arrow keys (↑ ↓ flip a page; ← → switch the macro/earnings tab) and the
    /// scroll wheel drive the events pane. `event.window` does all the scoping:
    /// keys only reach us while the calendar is key, scrolls only while the
    /// pointer is over the pad (everything outside it is click-through). The
    /// handlers stay non-isolated (NotificationCenter is thread-safe) because
    /// `NSEvent` is non-Sendable.
    private func installInputMonitors() {
        guard let window else { return }
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak window] event in
                guard event.window === window else { return event }
                switch event.keyCode {
                case 125: Self.postEventsPageCommand(userInfo: ["direction": 1], object: event.window)   // ↓
                case 126: Self.postEventsPageCommand(userInfo: ["direction": -1], object: event.window)  // ↑
                case 123, 124: Self.postEventsPageCommand(userInfo: ["tabSwitch": true], object: event.window) // ← →
                default: return event
                }
                return nil
            }
        }
        if scrollMonitor == nil {
            let scrollState = self.scrollState
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak window] event in
                guard event.window === window else { return event }
                let now = Date()
                if now >= scrollState.cooldownUntil {
                    scrollState.total += event.scrollingDeltaY
                    // A fixed distance per flip keeps trackpads and wheel mice
                    // calm; the cooldown absorbs trackpad momentum.
                    if abs(scrollState.total) >= 32 {
                        Self.postEventsPageFlip(scrollState.total < 0 ? 1 : -1, object: event.window)
                        scrollState.total = 0
                        scrollState.cooldownUntil = now.addingTimeInterval(0.35)
                    }
                }
                if event.phase == .ended || event.phase == .cancelled {
                    scrollState.total = 0
                }
                return event
            }
        }
    }

    private nonisolated static func postEventsPageFlip(_ direction: Int, object: Any?) {
        postEventsPageCommand(userInfo: ["direction": direction], object: object)
    }

    private nonisolated static func postEventsPageCommand(userInfo: [AnyHashable: Any], object: Any?) {
        NotificationCenter.default.post(
            name: .wickCalendarFlipEventsPage,
            object: object,
            userInfo: userInfo
        )
    }
}

/// Dynamic hosting wrapper that forwards active PnL convention and language into SwiftUI environment.
private struct TradingCalendarHostView: View {
    @ObservedObject private var settings = AppSettings.shared
    let onClose: () -> Void
    let onPageTorn: (FallingPage) -> Void

    var body: some View {
        TradingCalendarRootView(
            language: settings.language,
            onClose: onClose,
            onPageTorn: onPageTorn
        )
        .environment(\.pnlColorConvention, settings.pnlColorConvention)
        .environment(\.appLanguage, settings.language)
    }
}

