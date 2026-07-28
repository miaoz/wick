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
    }

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Keys.language)
        }
    }

    @Published var appearance: AppAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Keys.appearance)
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
    }
}
