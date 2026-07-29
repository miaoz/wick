import AppKit
import Foundation
import SwiftUI

/// Owns the journal `NSWindow` so it can be opened from the menu bar, settings, or notifications
/// without depending on SwiftUI `openWindow` (which is only available while a scene view is mounted).
@MainActor
final class JournalWindowController: NSObject, NSWindowDelegate {
    static let shared = JournalWindowController()

    private var window: NSWindow?
    private var languageObserver: NSObjectProtocol?
    private let legacyToolbarDelegate = LegacyJournalToolbarDelegate()

    private override init() {
        super.init()
    }

    func openJournal(createTodayIfNeeded: Bool = false) {
        if createTodayIfNeeded {
            _ = JournalStore.shared.openOrCreateToday()
        }

        let journalWindow = ensureWindow()
        updateTitle(for: journalWindow)
        // MenuBarExtra `.window` does not auto-dismiss when another window of this app
        // becomes key; close it explicitly so it does not float over the journal.
        MenuBarExtraPanel.dismiss(excluding: [journalWindow])
        journalWindow.makeKeyAndOrderFront(nil)
        // Show a Dock icon (and Cmd+Tab presence) while the journal is open so
        // the user can switch back to it; restored to accessory on close.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
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

        let root = JournalRootView()
            .environmentObject(AppSettings.shared)
            .environmentObject(JournalStore.shared)

        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.title = L10n.string(.journalTitle, language: AppSettings.shared.language)
        window.setContentSize(NSSize(width: 980, height: 640))
        window.minSize = NSSize(width: 720, height: 480)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("WickJournalWindow")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        applyWindowTheme(to: window)
        if journalNeedsInViewTopBar {
            installLegacyToolbar(on: window)
        }

        self.window = window

        languageObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let window = self.window else { return }
                self.updateTitle(for: window)
                self.applyWindowTheme(to: window)
            }
        }

        return window
    }

    private func updateTitle(for window: NSWindow) {
        window.title = L10n.string(.journalTitle, language: AppSettings.shared.language)
    }

    /// Syncs the window chrome (background behind the titlebar area) with the
    /// current day-arc palette. Called on open and on settings changes; the
    /// palette drifts slowly, so per-minute accuracy is not needed here.
    private func applyWindowTheme(to window: NSWindow) {
        let appearance = NSApplication.shared.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let palette = DayArcEngine.palette(
            at: DayArcEngine.currentDate(),
            scheme: isDark ? .dark : .light
        )
        window.backgroundColor = palette.backgroundBottom.nsColor
    }

    /// macOS 13-only chrome: SwiftUI installs no toolbar in this manually
    /// created window, so we install a real AppKit one — its items are laid
    /// out by the system, level with the traffic lights by construction.
    private func installLegacyToolbar(on window: NSWindow) {
        let toolbar = NSToolbar(identifier: "WickJournalToolbar")
        toolbar.delegate = legacyToolbarDelegate
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // Clicking an already-open journal should also dismiss the menu-bar panel.
        let keyWindow = (notification.object as? NSWindow) ?? window
        if let keyWindow {
            MenuBarExtraPanel.dismiss(excluding: [keyWindow])
        }
    }

    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.post(name: .wickWillFlushJournalDrafts, object: nil)
        JournalStore.shared.flushPendingWrites()
        // Back to menu-bar-only presence once the journal window is gone.
        NSApp.setActivationPolicy(.accessory)
    }
}

