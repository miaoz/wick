import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case light
    case dark
    case system

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .light:
            return .light
        case .dark:
            return .dark
        case .system:
            return nil
        }
    }

    func displayName(language: AppLanguage) -> String {
        switch (self, language) {
        case (.light, .chinese):
            return "亮色"
        case (.light, .english):
            return "Light"
        case (.dark, .chinese):
            return "暗色"
        case (.dark, .english):
            return "Dark"
        case (.system, .chinese):
            return "跟随系统"
        case (.system, .english):
            return "System"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Keys {
        static let language = "wick.language"
        static let appearance = "wick.appearance"
        static let journalReminderEnabled = "wick.journal.reminderEnabled"
        static let journalReminderHour = "wick.journal.reminderHour"
        static let journalReminderMinute = "wick.journal.reminderMinute"
        static let showMenuBarPercentage = "wick.menubar.showPercentage"
        static let launchAtLogin = "wick.launchAtLogin"
        static let checkForUpdatesOnLaunch = "wick.updates.checkOnLaunch"
        static let lastKnownRemoteVersion = "wick.updates.lastKnownRemoteVersion"
        static let lastKnownRemoteURL = "wick.updates.lastKnownRemoteURL"
        static let weekStartsOnMonday = "wick.calendar.weekStartsOnMonday"
        static let deviceID = "wick.deviceID"
        static let syncEnabled = "wick.sync.enabled"
        static let syncAccountEmail = "wick.sync.accountEmail"
    }

    /// Suppresses reminder rescheduling while loading defaults in `init`.
    private var isLoading = true

    /// Stable per-install identifier (the sync layer marks tombstones/manifests with it).
    let deviceID: String

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Keys.language)
            notifyReminderSettingsChanged()
        }
    }

    @Published var appearance: AppAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Keys.appearance)
        }
    }

    /// Daily local notification that opens the journal.
    @Published var journalReminderEnabled: Bool {
        didSet {
            UserDefaults.standard.set(journalReminderEnabled, forKey: Keys.journalReminderEnabled)
            notifyReminderSettingsChanged()
        }
    }

    @Published var journalReminderHour: Int {
        didSet {
            UserDefaults.standard.set(journalReminderHour, forKey: Keys.journalReminderHour)
            notifyReminderSettingsChanged()
        }
    }

    @Published var journalReminderMinute: Int {
        didSet {
            UserDefaults.standard.set(journalReminderMinute, forKey: Keys.journalReminderMinute)
            notifyReminderSettingsChanged()
        }
    }

    /// Show remaining day percentage next to the menu bar icon.
    @Published var showMenuBarPercentage: Bool {
        didSet {
            UserDefaults.standard.set(showMenuBarPercentage, forKey: Keys.showMenuBarPercentage)
        }
    }

    /// Prefer Monday as the first day of the week for weekly progress.
    @Published var weekStartsOnMonday: Bool {
        didSet {
            UserDefaults.standard.set(weekStartsOnMonday, forKey: Keys.weekStartsOnMonday)
        }
    }

    /// Desired open-at-login preference (actual system status is in `LaunchAtLogin`).
    @Published var launchAtLoginDesired: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLoginDesired, forKey: Keys.launchAtLogin)
            if !isLoading {
                applyLaunchAtLoginPreference()
            }
        }
    }

    @Published var checkForUpdatesOnLaunch: Bool {
        didSet {
            UserDefaults.standard.set(checkForUpdatesOnLaunch, forKey: Keys.checkForUpdatesOnLaunch)
        }
    }

    /// Dropbox journal sync master switch (driven by `SyncCoordinator`).
    @Published var syncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(syncEnabled, forKey: Keys.syncEnabled)
        }
    }

    /// Cached sign-in identity for the settings UI (token itself is in Keychain).
    @Published var syncAccountEmail: String {
        didSet {
            UserDefaults.standard.set(syncAccountEmail, forKey: Keys.syncAccountEmail)
        }
    }

    @Published var lastKnownRemoteVersion: String {
        didSet {
            UserDefaults.standard.set(lastKnownRemoteVersion, forKey: Keys.lastKnownRemoteVersion)
        }
    }

    @Published var lastKnownRemoteURL: String {
        didSet {
            UserDefaults.standard.set(lastKnownRemoteURL, forKey: Keys.lastKnownRemoteURL)
        }
    }

    /// Combined reminder time for DatePicker bindings.
    var journalReminderTime: Date {
        get {
            var components = DateComponents()
            components.hour = journalReminderHour
            components.minute = journalReminderMinute
            return Calendar.current.date(from: components) ?? Date()
        }
        set {
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            let hour = components.hour ?? 21
            let minute = components.minute ?? 0
            if hour != journalReminderHour {
                journalReminderHour = hour
            }
            if minute != journalReminderMinute {
                journalReminderMinute = minute
            }
        }
    }

    var locale: Locale {
        language.locale
    }

    var preferredColorScheme: ColorScheme? {
        appearance.colorScheme
    }

    /// Calendar configured for week-start preference.
    var progressCalendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = locale
        if weekStartsOnMonday {
            calendar.firstWeekday = 2 // Monday
        }
        return calendar
    }

    private init() {
        let languageRaw = UserDefaults.standard.string(forKey: Keys.language) ?? AppLanguage.chinese.rawValue
        language = AppLanguage(rawValue: languageRaw) ?? .chinese

        let appearanceRaw = UserDefaults.standard.string(forKey: Keys.appearance) ?? AppAppearance.system.rawValue
        appearance = AppAppearance(rawValue: appearanceRaw) ?? .system

        if UserDefaults.standard.object(forKey: Keys.journalReminderEnabled) == nil {
            journalReminderEnabled = true
        } else {
            journalReminderEnabled = UserDefaults.standard.bool(forKey: Keys.journalReminderEnabled)
        }

        if UserDefaults.standard.object(forKey: Keys.journalReminderHour) == nil {
            journalReminderHour = 21
        } else {
            journalReminderHour = UserDefaults.standard.integer(forKey: Keys.journalReminderHour)
        }

        if UserDefaults.standard.object(forKey: Keys.journalReminderMinute) == nil {
            journalReminderMinute = 0
        } else {
            journalReminderMinute = UserDefaults.standard.integer(forKey: Keys.journalReminderMinute)
        }

        if UserDefaults.standard.object(forKey: Keys.showMenuBarPercentage) == nil {
            showMenuBarPercentage = true
        } else {
            showMenuBarPercentage = UserDefaults.standard.bool(forKey: Keys.showMenuBarPercentage)
        }

        if UserDefaults.standard.object(forKey: Keys.weekStartsOnMonday) == nil {
            // Default: follow region (China → Monday-ish via locale); store false to mean system.
            weekStartsOnMonday = false
        } else {
            weekStartsOnMonday = UserDefaults.standard.bool(forKey: Keys.weekStartsOnMonday)
        }

        if UserDefaults.standard.object(forKey: Keys.launchAtLogin) == nil {
            launchAtLoginDesired = false
        } else {
            launchAtLoginDesired = UserDefaults.standard.bool(forKey: Keys.launchAtLogin)
        }

        if UserDefaults.standard.object(forKey: Keys.checkForUpdatesOnLaunch) == nil {
            checkForUpdatesOnLaunch = true
        } else {
            checkForUpdatesOnLaunch = UserDefaults.standard.bool(forKey: Keys.checkForUpdatesOnLaunch)
        }

        syncEnabled = UserDefaults.standard.bool(forKey: Keys.syncEnabled)
        syncAccountEmail = UserDefaults.standard.string(forKey: Keys.syncAccountEmail) ?? ""

        lastKnownRemoteVersion = UserDefaults.standard.string(forKey: Keys.lastKnownRemoteVersion) ?? ""
        lastKnownRemoteURL = UserDefaults.standard.string(forKey: Keys.lastKnownRemoteURL) ?? ""

        if let existing = UserDefaults.standard.string(forKey: Keys.deviceID) {
            deviceID = existing
        } else {
            let fresh = UUID().uuidString
            UserDefaults.standard.set(fresh, forKey: Keys.deviceID)
            deviceID = fresh
        }

        isLoading = false
    }

    private func notifyReminderSettingsChanged() {
        guard !isLoading else { return }
        JournalReminderScheduler.shared.rescheduleFromSettings()
    }

    func applyLaunchAtLoginPreference() {
        do {
            try LaunchAtLogin.setEnabled(launchAtLoginDesired)
        } catch {
            NSLog("Wick launch-at-login failed: \(error.localizedDescription)")
        }
        objectWillChange.send()
    }

    var isLaunchAtLoginEnabledInSystem: Bool {
        LaunchAtLogin.isEnabled
    }

    var launchAtLoginNeedsApproval: Bool {
        LaunchAtLogin.status == .requiresApproval
    }
}
