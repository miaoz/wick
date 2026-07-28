import AppKit
import Foundation
import SwiftUI
import UserNotifications

/// Schedules a daily local notification that opens the journal when tapped.
///
/// UserNotifications requires a real app bundle (`*.app` + bundle id). When launched via
/// `swift run` / raw binary under `.build/`, the framework aborts — so all UN calls are gated.
@MainActor
final class JournalReminderScheduler: NSObject, UNUserNotificationCenterDelegate, ObservableObject {
    static let shared = JournalReminderScheduler()

    enum IDs {
        static let notification = "wick.journal.daily-reminder"
        static let category = "wick.journal.reminder"
        static let openAction = "wick.journal.open"
    }

    enum AuthorizationState: Equatable {
        case unavailable
        case notDetermined
        case authorized
        case denied
        case provisional
    }

    @Published private(set) var authorizationState: AuthorizationState = .unavailable
    @Published private(set) var lastScheduleError: String?

    /// `true` only when running inside a packaged `.app` that UserNotifications can bind to.
    static var notificationsAvailable: Bool {
        guard let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty else {
            return false
        }
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            return true
        }
        return bundleURL.path.contains(".app/")
    }

    private var center: UNUserNotificationCenter?
    private var didConfigure = false

    private override init() {
        super.init()
    }

    func configure() {
        guard Self.notificationsAvailable else {
            authorizationState = .unavailable
            NSLog("Wick: journal reminders disabled (not running as an app bundle)")
            return
        }

        let notificationCenter = UNUserNotificationCenter.current()
        center = notificationCenter
        notificationCenter.delegate = self
        didConfigure = true
        registerCategories()
        Task {
            await refreshAuthorizationState()
            rescheduleFromSettings()
        }
    }

    func rescheduleFromSettings() {
        let settings = AppSettings.shared
        Task {
            await reschedule(
                enabled: settings.journalReminderEnabled,
                hour: settings.journalReminderHour,
                minute: settings.journalReminderMinute
            )
        }
    }

    func refreshAuthorizationState() async {
        guard let center else {
            authorizationState = Self.notificationsAvailable ? .notDetermined : .unavailable
            return
        }
        let settings = await center.notificationSettings()
        authorizationState = mapAuthorization(settings.authorizationStatus)
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        guard let center else {
            return false
        }

        let settings = await center.notificationSettings()
        authorizationState = mapAuthorization(settings.authorizationStatus)

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                await refreshAuthorizationState()
                return granted
            } catch {
                lastScheduleError = error.localizedDescription
                return false
            }
        @unknown default:
            return false
        }
    }

    func openSystemNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
            return
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    func reschedule(enabled: Bool, hour: Int, minute: Int) async {
        guard let center else {
            if Self.notificationsAvailable, !didConfigure {
                return
            }
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: [IDs.notification])
        lastScheduleError = nil

        guard enabled else {
            await refreshAuthorizationState()
            return
        }

        let authorized = await requestAuthorizationIfNeeded()
        guard authorized else {
            await refreshAuthorizationState()
            return
        }

        let content = UNMutableNotificationContent()
        let language = AppSettings.shared.language
        content.title = L10n.string(.journalReminderTitle, language: language)
        content.body = L10n.string(.journalReminderBody, language: language)
        content.sound = .default
        content.categoryIdentifier = IDs.category
        content.userInfo = ["action": "openJournal"]

        var dateComponents = DateComponents()
        dateComponents.hour = max(0, min(23, hour))
        dateComponents.minute = max(0, min(59, minute))

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: IDs.notification,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            lastScheduleError = nil
        } catch {
            lastScheduleError = error.localizedDescription
            NSLog("Wick journal reminder schedule failed: \(error.localizedDescription)")
        }
        await refreshAuthorizationState()
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        let shouldOpen =
            action == UNNotificationDefaultActionIdentifier
            || action == IDs.openAction

        if shouldOpen {
            Task { @MainActor in
                JournalWindowController.shared.openJournal(createTodayIfNeeded: true)
            }
        }
        completionHandler()
    }

    private func registerCategories() {
        guard let center else { return }

        let open = UNNotificationAction(
            identifier: IDs.openAction,
            title: L10n.string(.journalOpenAction, language: AppSettings.shared.language),
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: IDs.category,
            actions: [open],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    private func mapAuthorization(_ status: UNAuthorizationStatus) -> AuthorizationState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        case .provisional, .ephemeral:
            return .provisional
        @unknown default:
            return .notDetermined
        }
    }
}

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
    }
}

/// Item source for the macOS 13 journal toolbar: classic layout — sidebar
/// toggle leftmost (responder-chain `toggleSidebar:`, same as the system
/// item), new-entry at the trailing edge. The toggle uses the responder chain
/// so it drives the SwiftUI split view exactly like the system toggle does.
private final class LegacyJournalToolbarDelegate: NSObject, NSToolbarDelegate {
    private enum ItemID {
        static let toggle = NSToolbarItem.Identifier("wick.toggleSidebar")
        static let newEntry = NSToolbarItem.Identifier("wick.newEntry")
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case ItemID.toggle:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(toggleSidebar)
            return item
        case ItemID.newEntry:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(newEntry)
            return item
        default:
            return nil
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ItemID.toggle, .flexibleSpace, ItemID.newEntry]
    }

    @objc private func toggleSidebar() {
        NSApplication.shared.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
    }

    @objc private func newEntry() {
        MainActor.assumeIsolated {
            _ = JournalStore.shared.openOrCreateToday()
        }
    }
}
