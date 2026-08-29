import AppKit
import Foundation
import SwiftUI

/// Owns the journal `NSWindow` so it can be opened from the menu bar, settings, or notifications
/// without depending on SwiftUI `openWindow` (which is only available while a scene view is mounted).
@MainActor
final class JournalWindowController: NSObject, NSWindowDelegate {
    static let shared = JournalWindowController()

    private var window: NSWindow?
    /// The journal's SwiftUI content. Detached (view removed, controller
    /// dropped) whenever the window closes: the tree must not keep running —
    /// its today-row flame breathes on the display cycle and the retained
    /// hosting view held ~200 MB RSS on a 5K display — and is rebuilt on the
    /// next open.
    private var hostingController: NSHostingController<JournalRoot>?
    private var titlebarAccessoryController: NSTitlebarAccessoryViewController?
    private var titlebarBackgroundView: JournalTitlebarBackgroundView?
    private var titlebarDividerView: NSView?
    private var languageObserver: NSObjectProtocol?
    private var activeJournalObserver: NSObjectProtocol?
    /// Dedupes `UserDefaults.didChangeNotification` (P6): the notification
    /// does not name the key, so ignore bursts that do not affect chrome.
    private var lastChromeDefaultsSignature = ""

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
            // The window survived a previous close with its SwiftUI content
            // detached; rebuild the hosting tree for this session.
            attachJournalContent(on: window)
            return window
        }

        // The window's size is owned by this controller (autosave + minSize
        // floor), never by the SwiftUI content — see the container note below.
        // Keep the default safe area so the journal content starts below the
        // native titlebar accessory instead of extending behind it.
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
        // does not stop it; the indirection does.) The hosting view itself is
        // added by `attachJournalContent`, which also runs on reopen.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 980, height: 640))
        container.autoresizingMask = [.width, .height]
        window.contentView = container
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
        // The content still reaches the titlebar for the native accessory row.
        // A dedicated background view is installed in the titlebar container
        // so the traffic-light and accessory regions share Wick's fill.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        let toolbar = NSToolbar(identifier: "WickJournalToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.sizeMode = .regular
        toolbar.allowsUserCustomization = false
        toolbar.showsBaselineSeparator = false
        window.toolbarStyle = .unified
        window.toolbar = toolbar
        installTitlebarAccessory(on: window)
        applyWindowTheme(to: window)
        attachJournalContent(on: window)

        self.window = window

        languageObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyChromeFromDefaultsIfNeeded()
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

    // MARK: - Content attach / detach

    /// Builds the journal's SwiftUI tree and installs it in the window's plain
    /// container. Called on window creation and on every reopen after a close.
    /// Takes the window explicitly: on the create path `self.window` is still
    /// nil when this runs.
    private func attachJournalContent(on hostWindow: NSWindow) {
        guard hostingController == nil, let container = hostWindow.contentView else { return }
        let hosting = NSHostingController(rootView: JournalRoot())
        hosting.sizingOptions = []
        hosting.view.autoresizingMask = [.width, .height]
        hosting.view.frame = container.bounds
        container.addSubview(hosting.view)
        hostingController = hosting
    }

    /// Unmounts the journal's SwiftUI tree. `windowWillClose` calls this so a
    /// closed journal stops burning display-cycle frames (the today-row flame
    /// keeps breathing otherwise) and releases its hosting memory; the next
    /// `openJournal` rebuilds the tree fresh.
    private func detachJournalContent() {
        hostingController?.view.removeFromSuperview()
        hostingController = nil
    }

    private func installTitlebarAccessory(on window: NSWindow) {
        #if DEBUG
        let columnModeOverride = CommandLine.arguments.contains("-wick-journal-detail-only") ? 2 : nil
        #else
        let columnModeOverride: Int? = nil
        #endif
        let root = JournalTopBarView(columnModeOverride: columnModeOverride)
            .environmentObject(AppSettings.shared)
            .environmentObject(JournalStore.shared)
        let hosting = NSHostingView(rootView: root)
        let height = JournalTopBarView.preferredHeight
        hosting.frame = NSRect(x: 0, y: 0, width: window.frame.width, height: height)
        hosting.autoresizingMask = [.width]

        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .top
        accessory.view = hosting
        window.addTitlebarAccessoryViewController(accessory)
        let allocatedWidth = accessory.view.frame.width
        accessory.preferredContentSize = NSSize(width: allocatedWidth, height: height)
        accessory.view.setFrameSize(NSSize(width: allocatedWidth, height: height))
        titlebarAccessoryController = accessory

        installTitlebarBackground(on: window)
    }

    private func installTitlebarBackground(on window: NSWindow) {
        guard let contentView = window.contentView,
              let titlebarContainer = contentView.superview
        else { return }
        let height = JournalTopBarView.preferredHeight
        let background = JournalTitlebarBackgroundView(
            frame: NSRect(
                x: 0,
                y: titlebarContainer.bounds.maxY - height,
                width: titlebarContainer.bounds.width,
                height: height
            ),
            onEffectiveAppearanceChange: { [weak self] in
                self?.applyWindowThemeIfPresent()
            }
        )
        background.autoresizingMask = [.width, .minYMargin]
        background.wantsLayer = true
        background.layer?.backgroundColor = window.backgroundColor?.cgColor
        let divider = NSView(frame: NSRect(x: 0, y: 0, width: background.bounds.width, height: 1))
        divider.autoresizingMask = [.width, .maxYMargin]
        divider.wantsLayer = true
        background.addSubview(divider)
        // Cover full-size SwiftUI content that otherwise bleeds different
        // column colors into the transparent titlebar. Native titlebar views
        // remain above this sibling and keep their AppKit-managed geometry.
        titlebarContainer.addSubview(background, positioned: .above, relativeTo: contentView)
        titlebarBackgroundView = background
        titlebarDividerView = divider
    }

    private func applyChromeFromDefaultsIfNeeded() {
        guard let window else { return }
        let settings = AppSettings.shared
        let signature = [
            settings.language.rawValue,
            settings.appearance.rawValue,
            String(settings.journalColumnMode),
            settings.journalInspectorVisible ? "1" : "0",
            settings.physicalCalendarEnabled ? "1" : "0",
            String(UserDefaults.standard.double(forKey: "wick.journal.navWidth")),
            String(UserDefaults.standard.double(forKey: "wick.journal.listWidth")),
        ].joined(separator: "|")
        guard signature != lastChromeDefaultsSignature else { return }
        lastChromeDefaultsSignature = signature
        updateTitle(for: window)
        applyWindowTheme(to: window)
        updateMinSize(for: window)
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
        let appearance = window.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let palette = DayArcEngine.palette(
            at: DayArcEngine.currentDate(),
            scheme: isDark ? .dark : .light
        )
        window.backgroundColor = palette.cardTop.nsColor
        titlebarBackgroundView?.layer?.backgroundColor = palette.cardTop.nsColor.cgColor
        titlebarDividerView?.layer?.backgroundColor = palette.divider.nsColor.cgColor
    }

    private func applyWindowThemeIfPresent() {
        guard let window else { return }
        applyWindowTheme(to: window)
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
        detachJournalContent()
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

/// The journal content as a concrete type, so `NSHostingController<JournalRoot>`
/// can be stored, torn down on close, and rebuilt on the next open.
private struct JournalRoot: View {
    var body: some View {
        JournalRootView()
            .environmentObject(AppSettings.shared)
            .environmentObject(JournalStore.shared)
    }
}

/// Observes the effective appearance of the titlebar frame. The app's
/// `.system` appearance leaves `NSApp.appearance` nil, so UserDefaults changes
/// cannot detect the later macOS light/dark transition on their own.
@MainActor
private final class JournalTitlebarBackgroundView: NSView {
    private let onEffectiveAppearanceChange: () -> Void

    init(frame frameRect: NSRect, onEffectiveAppearanceChange: @escaping () -> Void) {
        self.onEffectiveAppearanceChange = onEffectiveAppearanceChange
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onEffectiveAppearanceChange()
    }
}
