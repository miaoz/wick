import AppKit

/// Helpers for dismissing SwiftUI `MenuBarExtra` when using `.menuBarExtraStyle(.window)`.
///
/// SwiftUI does not expose an API to close the status-item panel. Same-app window activation
/// (e.g. focusing the journal) also does not dismiss it the way an outside click does — so we
/// close matching transient windows ourselves.
@MainActor
enum MenuBarExtraPanel {
    /// Hides the open menu-bar panel, if any, without touching normal app windows.
    static func dismiss(excluding excludedWindows: [NSWindow] = []) {
        let excluded = Set(excludedWindows.map { ObjectIdentifier($0) })

        for window in NSApp.windows where window.isVisible {
            if excluded.contains(ObjectIdentifier(window)) {
                continue
            }
            guard isMenuBarExtraPanel(window) else {
                continue
            }
            window.orderOut(nil)
        }
    }

    /// Heuristic: MenuBarExtra `.window` panels are not full chrome document windows.
    private static func isMenuBarExtraPanel(_ window: NSWindow) -> Bool {
        let className = window.className
        if className.contains("StatusBar")
            || className.contains("MenuBarExtra")
            || className.contains("Popover")
        {
            return true
        }

        // Keep standard app windows (journal uses titled + closable + miniaturizable).
        let mask = window.styleMask
        if mask.contains(.titled), mask.contains(.closable), mask.contains(.miniaturizable) {
            return false
        }

        // Transient panels / borderless hosts used by the status-item popover.
        if window is NSPanel {
            return true
        }
        if !mask.contains(.titled) {
            return true
        }

        return false
    }
}
