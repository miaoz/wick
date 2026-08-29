import AppKit

/// Helpers for dismissing SwiftUI `MenuBarExtra` when using `.menuBarExtraStyle(.window)`.
///
/// SwiftUI does not expose an API to close the status-item panel. Same-app window activation
/// (e.g. focusing the journal) also does not dismiss it the way an outside click does — so we
/// close matching transient windows ourselves.
///
/// Safety: the status item's button window also shows up in `NSApp.windows` on some macOS
/// versions (notably 13), and ordering it out removes the menu-bar icon for good. Never touch
/// small (menu-bar-sized) windows — the panel is always hundreds of points tall.
@MainActor
enum MenuBarExtraPanel {
    /// Hides the open menu-bar panel, if any, without touching normal app windows.
    static func dismiss(excluding excludedWindows: [NSWindow] = []) {
        let excluded = Set(excludedWindows.map { ObjectIdentifier($0) })
        var dismissedAny = false

        for window in NSApp.windows where window.isVisible {
            if excluded.contains(ObjectIdentifier(window)) {
                continue
            }
            guard isMenuBarExtraPanel(window) else {
                continue
            }
            window.orderOut(nil)
            dismissedAny = true
        }

        // The panel's SwiftUI scene survives the orderOut; tell it to stop
        // ticking and breathing before the visibility probe's KVO catches up.
        if dismissedAny {
            NotificationCenter.default.post(name: .wickMenuBarPanelDidDismiss, object: nil)
        }
    }

    /// Heuristic: MenuBarExtra `.window` panels are transient panels, never the
    /// tiny status-item button window or a full-chrome document window.
    private static func isMenuBarExtraPanel(_ window: NSWindow) -> Bool {
        // The status item's button window is menu-bar-sized; ordering it out
        // destroys the icon (seen on macOS 13). The panel is always large.
        let frame = window.frame
        if frame.height <= 30 || frame.width <= 60 {
            return false
        }

        let className = window.className
        if className.contains("MenuBarExtra") || className.contains("StatusBar") {
            return true
        }

        // Keep standard app windows (journal uses titled + closable + miniaturizable).
        let mask = window.styleMask
        if mask.contains(.titled), mask.contains(.closable), mask.contains(.miniaturizable) {
            return false
        }

        // Remaining transient hosts of the panel are NSPanels. A bare
        // "not titled" match is deliberately not enough (see icon note above).
        return window is NSPanel
    }
}
