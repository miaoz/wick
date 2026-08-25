import SwiftUI
import WickCalendarKit




/// The app's font is chosen from the user's installed fonts (a PostScript name)
/// or left empty for the shipped Songti/system look. See `AppFont`.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Keys {
        static let language = "wick.language"
        static let appearance = "wick.appearance"
        static let pnlColorConvention = "wick.pnlColorConvention"
        static let journalFontName = "wick.journal.fontName"
        /// Pre-2026-08-22 two-choice enum (default/classicalMing); migrated once.
        static let legacyJournalFontStyle = "wick.journal.fontStyle"
        static let journalReminderEnabled = "wick.journal.reminderEnabled"
        static let journalReminderHour = "wick.journal.reminderHour"
        static let journalReminderMinute = "wick.journal.reminderMinute"
        static let showMenuBarPercentage = "wick.menubar.showPercentage"
        static let launchAtLogin = "wick.launchAtLogin"
        static let checkForUpdatesAutomatically = "wick.updates.checkAutomatically"
        static let legacyCheckForUpdatesOnLaunch = "wick.updates.checkOnLaunch"
        static let lastKnownRemoteVersion = "wick.updates.lastKnownRemoteVersion"
        static let lastKnownRemoteURL = "wick.updates.lastKnownRemoteURL"
        static let lastNotifiedUpdateVersion = "wick.updates.lastNotifiedVersion"
        static let weekStartsOnMonday = "wick.calendar.weekStartsOnMonday"
        static let physicalCalendar = "wick.calendar.physicalEasterEgg"
        static let journalInspectorVisible = "wick.journal.inspectorVisible"
        static let journalColumnMode = "wick.journal.columnMode"
        static let deviceID = "wick.deviceID"
        static let syncEnabled = "wick.sync.enabled"
        static let syncAccountEmail = "wick.sync.accountEmail"
        static let syncTradingSnapshots = "wick.sync.tradingSnapshots"
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

    /// 涨跌配色: which of the two palette colors marks a gain.
    @Published var pnlColorConvention: PnlColorConvention {
        didSet {
            UserDefaults.standard.set(pnlColorConvention.rawValue, forKey: Keys.pnlColorConvention)
            TradingCalendarTheme.pnlConvention = pnlColorConvention
            NotificationCenter.default.post(name: .wickCalendarPnlConventionChanged, object: nil)
        }
    }

    /// 字体: 所选设备字体的 PostScript 名;空字符串 = 默认(系统宋体/UI)。
    @Published var journalFontName: String {
        didSet {
            UserDefaults.standard.set(journalFontName, forKey: Keys.journalFontName)
            WickPrintFont.invalidateCache()
            applyJournalFontStyle()
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

    @Published var checkForUpdatesAutomatically: Bool {
        didSet {
            UserDefaults.standard.set(checkForUpdatesAutomatically, forKey: Keys.checkForUpdatesAutomatically)
            if checkForUpdatesAutomatically {
                UpdateCheckerPresenter.shared.startPeriodicChecks()
            }
        }
    }

    /// Backwards compatibility alias for older references.
    var checkForUpdatesOnLaunch: Bool {
        get { checkForUpdatesAutomatically }
        set { checkForUpdatesAutomatically = newValue }
    }

    @Published var lastNotifiedUpdateVersion: String {
        didSet {
            UserDefaults.standard.set(lastNotifiedUpdateVersion, forKey: Keys.lastNotifiedUpdateVersion)
        }
    }

    /// Dropbox journal sync master switch (driven by `SyncCoordinator`).
    @Published var syncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(syncEnabled, forKey: Keys.syncEnabled)
        }
    }

    /// Opt-in transport for derived trading history. Credentials never use it.
    @Published var syncTradingSnapshots: Bool {
        didSet {
            UserDefaults.standard.set(syncTradingSnapshots, forKey: Keys.syncTradingSnapshots)
        }
    }

    /// 彩蛋:贴桌物理黄历(无边框暗室窗 + 撕页物理)。默认关 —— 黄历默认
    /// 以印刷语言住在主窗右栏检查器;开启后黄历独立贴桌,主窗退为纯三栏,
    /// 盈亏月历移至导航栏顶部(见 final.html §00「月历归属跟着黄历走」)。
    @Published var physicalCalendarEnabled: Bool {
        didSet {
            UserDefaults.standard.set(physicalCalendarEnabled, forKey: Keys.physicalCalendar)
        }
    }

    /// 主窗右栏检查器开关(⌥⌘0)。仅彩蛋关闭时有意义。
    @Published var journalInspectorVisible: Bool {
        didSet {
            UserDefaults.standard.set(journalInspectorVisible, forKey: Keys.journalInspectorVisible)
        }
    }

    /// 主窗导航深度:0 = 全导航(三栏), 1 = 仅列表, 2 = 专注(仅编辑)。
    @Published var journalColumnMode: Int {
        didSet {
            UserDefaults.standard.set(journalColumnMode, forKey: Keys.journalColumnMode)
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

        let conventionRaw = UserDefaults.standard.string(forKey: Keys.pnlColorConvention) ?? PnlColorConvention.greenUp.rawValue
        let convention = PnlColorConvention(rawValue: conventionRaw) ?? .greenUp
        pnlColorConvention = convention
        TradingCalendarTheme.pnlConvention = convention

        // Font name, with a one-time migration from the old two-choice enum.
        var fontName = UserDefaults.standard.string(forKey: Keys.journalFontName) ?? ""
        if fontName.isEmpty, let legacyRaw = UserDefaults.standard.string(forKey: Keys.legacyJournalFontStyle) {
            fontName = (legacyRaw == "classicalMing") ? AppFont.classicalMingName : ""
            UserDefaults.standard.set(fontName, forKey: Keys.journalFontName)
            UserDefaults.standard.removeObject(forKey: Keys.legacyJournalFontStyle)
        }
        journalFontName = fontName

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

        if let explicit = UserDefaults.standard.object(forKey: Keys.checkForUpdatesAutomatically) as? Bool {
            checkForUpdatesAutomatically = explicit
        } else if let legacy = UserDefaults.standard.object(forKey: Keys.legacyCheckForUpdatesOnLaunch) as? Bool {
            checkForUpdatesAutomatically = legacy
        } else {
            checkForUpdatesAutomatically = true
        }

        lastNotifiedUpdateVersion = UserDefaults.standard.string(forKey: Keys.lastNotifiedUpdateVersion) ?? ""

        syncEnabled = UserDefaults.standard.bool(forKey: Keys.syncEnabled)
        syncAccountEmail = UserDefaults.standard.string(forKey: Keys.syncAccountEmail) ?? ""
        syncTradingSnapshots = UserDefaults.standard.bool(forKey: Keys.syncTradingSnapshots)

        physicalCalendarEnabled = UserDefaults.standard.bool(forKey: Keys.physicalCalendar)

        if UserDefaults.standard.object(forKey: Keys.journalInspectorVisible) == nil {
            journalInspectorVisible = true
        } else {
            journalInspectorVisible = UserDefaults.standard.bool(forKey: Keys.journalInspectorVisible)
        }

        if UserDefaults.standard.object(forKey: Keys.journalColumnMode) == nil {
            journalColumnMode = 0
        } else {
            journalColumnMode = UserDefaults.standard.integer(forKey: Keys.journalColumnMode)
        }

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
        applyJournalFontStyle()
    }

    /// Mirrors the font preference into the trading calendar theme (the calendar
    /// resolves its faces at render time from `TradingCalendarTheme.fontStyle`).
    /// A pad that is already open re-snapshots on `.wickCalendarFontStyleChanged`.
    private func applyJournalFontStyle() {
        guard !isLoading else { return }
        if journalFontName.isEmpty {
            TradingCalendarTheme.fontStyle = .default
        } else {
            TradingCalendarTheme.fontStyle = .custom(postScriptName: journalFontName)
        }
        NotificationCenter.default.post(name: .wickCalendarFontStyleChanged, object: nil)
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
