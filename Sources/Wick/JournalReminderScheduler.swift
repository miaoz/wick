import AppKit
import Foundation
import SwiftUI
import UserNotifications

/// Schedules a daily local notification that opens the journal when tapped.
///
/// UserNotifications requires a real app bundle (`*.app` + bundle id). When launched via
/// `swift run` / raw binary under `.build/`, the framework aborts — so all UN calls are gated.
@MainActor
final class JournalReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = JournalReminderScheduler()

    enum IDs {
        static let notification = "wick.journal.daily-reminder"
        static let category = "wick.journal.reminder"
        static let openAction = "wick.journal.open"
    }

    /// `true` only when running inside a packaged `.app` that UserNotifications can bind to.
    static var notificationsAvailable: Bool {
        guard let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty else {
            return false
        }
        // `swift run` uses something like `…/.build/debug/` as the main bundle URL.
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            return true
        }
        // Some launchers may point at Contents/MacOS; accept a parent .app.
        return bundleURL.path.contains(".app/")
    }

    private var center: UNUserNotificationCenter?
    private var didConfigure = false

    private override init() {
        super.init()
    }

    func configure() {
        guard Self.notificationsAvailable else {
            NSLog("Wick: journal reminders disabled (not running as an app bundle)")
            return
        }

        let notificationCenter = UNUserNotificationCenter.current()
        center = notificationCenter
        notificationCenter.delegate = self
        didConfigure = true
        registerCategories()
        rescheduleFromSettings()
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

    func requestAuthorizationIfNeeded() async -> Bool {
        guard let center else {
            return false
        }

        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    func reschedule(enabled: Bool, hour: Int, minute: Int) async {
        guard let center else {
            // Not configured yet (or not an app bundle). Configure may still be pending.
            if Self.notificationsAvailable, !didConfigure {
                // Wait for applicationDidFinishLaunching → configure().
                return
            }
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: [IDs.notification])

        guard enabled else {
            return
        }

        let authorized = await requestAuthorizationIfNeeded()
        guard authorized else {
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
        } catch {
            NSLog("Wick journal reminder schedule failed: \(error.localizedDescription)")
        }
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
}

/// Owns the journal `NSWindow` so it can be opened from the menu bar, settings, or notifications
/// without depending on SwiftUI `openWindow` (which is only available while a scene view is mounted).
@MainActor
final class JournalWindowController: NSObject, NSWindowDelegate {
    static let shared = JournalWindowController()

    private var window: NSWindow?
    private var languageObserver: NSObjectProtocol?

    private override init() {
        super.init()
    }

    func openJournal(createTodayIfNeeded: Bool = false) {
        if createTodayIfNeeded {
            _ = JournalStore.shared.openOrCreateToday()
        }

        let journalWindow = ensureWindow()
        updateTitle(for: journalWindow)
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
        window.titlebarAppearsTransparent = false
        window.backgroundColor = NSColor.windowBackgroundColor

        self.window = window

        // Keep title in sync when the user switches language in settings.
        languageObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
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
        window.title = L10n.string(.journalTitle, language: AppSettings.shared.language)
    }

    func windowWillClose(_ notification: Notification) {
        // Keep the window instance for fast re-open; content stays loaded.
    }
}
