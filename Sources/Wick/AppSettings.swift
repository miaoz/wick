import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .chinese:
            return Locale(identifier: "zh_CN")
        case .english:
            return Locale(identifier: "en_US")
        }
    }

    var displayName: String {
        switch self {
        case .chinese:
            return "中文"
        case .english:
            return "English"
        }
    }
}

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
    }

    /// Suppresses reminder rescheduling while loading defaults in `init`.
    private var isLoading = true

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
            // Assign once when possible to avoid double reschedule.
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
            // Default evening reminder time.
            journalReminderHour = 21
        } else {
            journalReminderHour = UserDefaults.standard.integer(forKey: Keys.journalReminderHour)
        }

        if UserDefaults.standard.object(forKey: Keys.journalReminderMinute) == nil {
            journalReminderMinute = 0
        } else {
            journalReminderMinute = UserDefaults.standard.integer(forKey: Keys.journalReminderMinute)
        }

        isLoading = false
    }

    private func notifyReminderSettingsChanged() {
        guard !isLoading else { return }
        JournalReminderScheduler.shared.rescheduleFromSettings()
    }
}
