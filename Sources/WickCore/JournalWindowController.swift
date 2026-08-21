import AppKit
import Foundation
import SwiftUI

/// Owns the journal `NSWindow` so it can be opened from the menu bar, settings, or notifications
/// without depending on SwiftUI `openWindow` (which is only available while a scene view is mounted).
@MainActor
final class JournalWindowController: NSObject, NSWindowDelegate {
    static let shared = JournalWindowController()

    private var window: NSWindow?
    private var hostingController: NSViewController?
    private var languageObserver: NSObjectProtocol?
    private var activeJournalObserver: NSObjectProtocol?
    private var toolbarPin: NSKeyValueObservation?

    private override init() {
        super.init()
    }

    /// True while the journal window exists and is on-screen (or miniaturized).
    /// Used so launch-time accessory policy does not stomp a notification-driven open.
    var hasOpenJournalWindow: Bool {
        guard let window else { return false }
        return window.isVisible || window.isMiniaturized
    }

    func openJournal(createTodayIfNeeded: Bool = false) {
        if createTodayIfNeeded {
            _ = JournalStore.shared.openOrCreateToday()
        }
        // Opening the journal is the natural moment to top up position data.
        ExchangePositionCoordinator.shared.refreshIfStale()

        // For LSUIElement / accessory apps, promote activation policy *before*
        // keying the window — otherwise notification taps often open the
        // journal behind other apps without focus.
        NSApp.setActivationPolicy(.regular)

        let journalWindow = ensureWindow()
        updateTitle(for: journalWindow)
        // MenuBarExtra `.window` does not auto-dismiss when another window of this app
        // becomes key; close it explicitly so it does not float over the journal.
        MenuBarExtraPanel.dismiss(excluding: [journalWindow])

        if journalWindow.isMiniaturized {
            journalWindow.deminiaturize(nil)
        }
        journalWindow.makeKeyAndOrderFront(nil)
        journalWindow.orderFrontRegardless()
        // Show a Dock icon (and Cmd+Tab presence) while the journal is open so
        // the user can switch back to it; restored to accessory on close.
        NSApp.activate(ignoringOtherApps: true)

        // Cold-start from a notification can race with AppDelegate setting
        // `.accessory` in the same launch turn — re-assert focus next tick.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSApp.setActivationPolicy(.regular)
            if let window = self.window {
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
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

        let root = JournalRootView()
            .environmentObject(AppSettings.shared)
            .environmentObject(JournalStore.shared)

        let hosting = NSHostingController(rootView: root)
        // The window's size is owned by this controller (autosave + minSize
        // floor), never by the SwiftUI content — see the container note below.
        hosting.sizingOptions = []
        // Content must reach the window's top edge so the in-view top bar
        // (JournalRootView.topBar) shares one row with the traffic lights;
        // the default titlebar safe area would push it into a second row.
        if #available(macOS 13.3, *) {
            hosting.safeAreaRegions = []
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // Wrap the hosting view in a plain container instead of assigning
        // `contentViewController`: NSHostingView.windowDidLayout calls
        // `updateAnimatedWindowSize` for the window's DIRECT content view,
        // and the editor ScrollView's ideal height is the full unrolled
        // timeline — the window then grows a step per layout pass until it
        // fills the screen's visible height. (Verified: sizingOptions alone
        // does not stop it; the indirection does.)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 980, height: 640))
        container.autoresizingMask = [.width, .height]
        hosting.view.autoresizingMask = [.width, .height]
        hosting.view.frame = container.bounds
        container.addSubview(hosting.view)
        window.contentView = container
        hostingController = hosting
        window.title = L10n.string(.journalTitle, language: AppSettings.shared.language)
        window.setContentSize(NSSize(width: 980, height: 640))
        window.isReleasedWhenClosed = false
        window.delegate = self

        let autosaveName = "WickJournalWindow"
        let hasSavedFrame = UserDefaults.standard.object(forKey: "NSWindow Frame \(autosaveName)") != nil
        window.setFrameAutosaveName(autosaveName)
        // minSize/grow AFTER the autosave restore — the restored frame wins
        // over anything applied earlier, and its own width may sit below the
        // editor floor.
        updateMinSize(for: window)
        if hasSavedFrame {
            // The restored frame keeps the user's size AND position; only
            // rescue it when it stranded off every screen (disconnected
            // display), where it would be unreachable.
            if !isMostlyOnScreen(window.frame) {
                window.center()
            }
        } else {
            // First launch: no autosave frame yet — open at a landscape size
            // scaled to the screen instead of the bare 980x640 above.
            window.setContentSize(defaultContentSize(for: NSScreen.main))
            updateMinSize(for: window)
            window.center()
        }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        applyWindowTheme(to: window)
        // Run toolbar-less on every macOS version: NavigationSplitView (14+)
        // force-installs a SwiftUI toolbar — an empty band holding only the
        // system sidebar toggle, and every custom item gets a glass bezel on
        // macOS 26. The in-content full-width top bar provides the window
        // controls instead (JournalRootView.topBar). SwiftUI re-installs its
        // toolbar on layout, so pin window.toolbar to nil.
        toolbarPin = window.observe(\.toolbar, options: [.initial, .new]) { win, _ in
            if win.toolbar != nil { win.toolbar = nil }
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
                // 栏位/检查器开关也走 UserDefaults——窗口最小宽跟着变。
                self.updateMinSize(for: window)
            }
        }

        activeJournalObserver = NotificationCenter.default.addObserver(
            forName: .wickActiveJournalDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let window = self.window else { return }
                self.updateTitle(for: window)
            }
        }

        return window
    }

    private func updateTitle(for window: NSWindow) {
        let language = AppSettings.shared.language
        let fallback = L10n.string(.journalTitle, language: language)
        if let name = JournalStore.shared.activeJournal?.name,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            window.title = name
        } else {
            window.title = fallback
        }
    }

    /// The minimum window width follows the visible columns: nav/list minimums
    /// (JournalRootView.navWidthRange/listWidthRange) + the 440pt editor floor
    /// + the 288pt inspector, plus divider widths. When a toggle raises the
    /// floor past the current width (e.g. opening the inspector on a narrow
    /// window), grow the window so the editor page never deforms.
    private func updateMinSize(for window: NSWindow) {
        let width = requiredMinWidth()
        window.minSize = NSSize(width: width, height: 480)
        if window.frame.width < width {
            var frame = window.frame
            frame.size.width = width
            window.setFrame(frame, display: true, animate: true)
        }
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

    func windowDidBecomeKey(_ notification: Notification) {
        // Clicking an already-open journal should also dismiss the menu-bar panel.
        let keyWindow = (notification.object as? NSWindow) ?? window
        if let keyWindow {
            MenuBarExtraPanel.dismiss(excluding: [keyWindow])
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              !window.styleMask.contains(.fullScreen)
        else { return }
        // Programmatic sizing passes (autosave restore, content-size tracking)
        // do NOT respect minSize — enforce the editor floor after the fact.
        // Note this fires for the autosave restore itself, which lands while
        // self.window is still nil (restore happens mid-ensureWindow).
        let required = requiredMinWidth()
        if window.frame.width < required - 0.5 {
            var frame = window.frame
            frame.size.width = required
            window.setFrame(frame, display: true, animate: false)
        }
    }

    /// Column-aware width floor shared by minSize and the resize enforcer.
    /// Uses the CURRENT persisted column widths (not the range minimums):
    /// columns dragged wider than their minimum must not eat the editor floor.
    private func requiredMinWidth() -> CGFloat {
        let settings = AppSettings.shared
        var width = JournalRootView.editorMinWidth
        switch settings.journalColumnMode {
        case 0:
            width += JournalRootView.currentNavWidth
                + JournalRootView.currentListWidth
                + 14 // two 7pt divider hit areas
        case 1:
            width += JournalRootView.currentListWidth + 7
        default:
            break
        }
        if !settings.physicalCalendarEnabled && settings.journalInspectorVisible {
            width += 288 + 1
        }
        return width
    }

    /// Current width of the journal window's content area (0 while no window
    /// exists). Column drags clamp against it so the editor page keeps its
    /// floor instead of being squeezed mid-drag.
    var contentWidth: CGFloat {
        window?.contentView?.frame.width ?? 0
    }

    /// First-launch content size: a landscape four-column proportion scaled to
    /// the screen's visible area. Width aims at the editor's COMFORT width
    /// (single-row page header), clamped between the editor floor and what
    /// the display actually fits.
    private func defaultContentSize(for screen: NSScreen?) -> NSSize {
        let visible = (screen ?? NSScreen.main)?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let height = min(max(visible.height * 0.78, 640), 940, visible.height - 60)
        let comfortable = requiredMinWidth()
            - JournalRootView.editorMinWidth
            + JournalRootView.editorComfortWidth
        let width = min(max(height * 1.6, comfortable), 1500, visible.width - 60)
        return NSSize(width: width.rounded(), height: height.rounded())
    }

    /// True when a usable chunk of the frame lands on some screen's visible
    /// area; autosave-restored frames can strand on a disconnected display.
    private func isMostlyOnScreen(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { screen in
            let intersection = frame.intersection(screen.visibleFrame)
            return intersection.width > 120 && intersection.height > 120
        }
    }

    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.post(name: .wickWillFlushJournalDrafts, object: nil)
        JournalStore.shared.flushPendingWrites()
        // Back to menu-bar-only presence once the journal window is gone.
        NSApp.setActivationPolicy(.accessory)
    }

    #if DEBUG
    /// DEBUG-only UI-check helper: captures the journal window (including the
    /// title bar / toolbar chrome) to a PNG. An app capturing its own window
    /// needs no Screen Recording consent.
    func snapshotWindowToPNG(path: String) {
        guard let window, window.isVisible else {
            NSLog("Wick: snapshot failed, no visible journal window")
            return
        }
        if let toolbar = window.toolbar {
            for item in toolbar.visibleItems ?? [] {
                let frame = item.view?.frame ?? .zero
                let inWindow = item.view?.window != nil
                NSLog(
                    "Wick: toolbar item %@ frame=%@ inWindow=%@ hidden=%@",
                    item.itemIdentifier.rawValue,
                    NSStringFromRect(frame),
                    inWindow ? "yes" : "no",
                    item.view?.isHidden == true ? "yes" : "no"
                )
            }
        }
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            CGWindowID(window.windowNumber),
            [.bestResolution]
        ) else {
            NSLog("Wick: snapshot failed, CGWindowListCreateImage returned nil")
            return
        }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            NSLog("Wick: snapshot failed, PNG encoding failed")
            return
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            NSLog("Wick: journal snapshot written to %@", path)
        } catch {
            NSLog("Wick: snapshot failed, %@", error.localizedDescription)
        }
    }
    #endif
}

