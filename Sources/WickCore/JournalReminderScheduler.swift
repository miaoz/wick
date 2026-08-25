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
        let userInfo = response.notification.request.content.userInfo
        let downloadURLString = userInfo["downloadURL"] as? String

        if (userInfo["action"] as? String) == "downloadUpdate" || action == UpdateCheckerPresenter.IDs.downloadActionID {
            nonisolated(unsafe) let finish = completionHandler
            Task { @MainActor in
                let targetURL = downloadURLString.flatMap(URL.init(string:)) ?? UpdateChecker.r2LatestDownloadURL
                NSWorkspace.shared.open(targetURL)
                finish()
            }
            return
        }

        let shouldOpen =
            action == UNNotificationDefaultActionIdentifier
            || action == IDs.openAction

        if shouldOpen {
            // UN completion handlers are not Sendable under Swift 6; open on
            // the main actor and complete after. `nonisolated(unsafe)` is the
            // practical bridge for this system callback.
            nonisolated(unsafe) let finish = completionHandler
            Task { @MainActor in
                JournalWindowController.shared.openJournal(createTodayIfNeeded: true)
                finish()
            }
        } else {
            completionHandler()
        }
    }

    private func registerCategories() {
        guard let center else { return }

        let language = AppSettings.shared.language

        let openJournal = UNNotificationAction(
            identifier: IDs.openAction,
            title: L10n.string(.journalOpenAction, language: language),
            options: [.foreground]
        )
        let reminderCategory = UNNotificationCategory(
            identifier: IDs.category,
            actions: [openJournal],
            intentIdentifiers: [],
            options: []
        )

        let downloadUpdate = UNNotificationAction(
            identifier: UpdateCheckerPresenter.IDs.downloadActionID,
            title: L10n.string(.downloadUpdateAction, language: language),
            options: [.foreground]
        )
        let updateCategory = UNNotificationCategory(
            identifier: UpdateCheckerPresenter.IDs.categoryID,
            actions: [downloadUpdate],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([reminderCategory, updateCategory])
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

