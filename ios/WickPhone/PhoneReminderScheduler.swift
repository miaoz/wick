import Foundation
import UserNotifications
import WickSync

/// Schedules a daily local notification for journaling and review on iOS.
@MainActor
final class PhoneReminderScheduler: ObservableObject {
    static let shared = PhoneReminderScheduler()

    private static let identifier = "wick.journal.daily-reminder"

    @Published private(set) var isAuthorized = false

    private init() {
        Task { await checkAuthorization() }
    }

    func checkAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
    }

    func schedule(enabled: Bool, time: Date) {
        let center = UNUserNotificationCenter.current()
        guard enabled else {
            center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
            return
        }

        Task {
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
                guard granted else { return }
            } else if settings.authorizationStatus == .denied {
                return
            }

            let cal = Calendar.current
            let comps = cal.dateComponents([.hour, .minute], from: time)

            let content = UNMutableNotificationContent()
            content.title = "秉烛 · 每日复盘"
            content.body = "今日的交易与思绪，此刻记录下来吧。"
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let request = UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger)

            center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
            try? await center.add(request)
            await checkAuthorization()
        }
    }
}
