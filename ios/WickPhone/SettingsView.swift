import SwiftUI
import UniformTypeIdentifiers
import WickCalendarKit
import WickSync
import WickTrading

/// Tab 4: "设置" (Settings & Preferences).
/// Appearance (Light/Dark/System), PnL color convention, daily reminder, trading calendar Easter Egg,
/// per-journal exchange binding, Dropbox sync, and data backup.
/// Styled in Wick's "秉烛" (By Candlelight) mineral & paper visual language.
struct SettingsView: View {
    @EnvironmentObject private var sync: PhoneSyncCoordinator
    @EnvironmentObject private var store: PhoneJournalStore
    @EnvironmentObject private var exchangeCoordinator: PhoneExchangeCoordinator
    private let reminderScheduler = PhoneReminderScheduler.shared

    // Language Setting
    @AppStorage("wick.language") private var languageRaw = AppLanguage.chinese.rawValue

    // Appearance & Convention Settings
    @AppStorage("wick.appearance") private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage("wick.pnlColorConvention") private var pnlConventionRaw = PnlColorConvention.redUp.rawValue
    @AppStorage("wick.calendar.physicalEasterEgg") private var physicalEasterEgg = false
    @AppStorage("wick.calendar.weekStartsOnMonday") private var weekStartsOnMonday = false

    // Reminder Settings
    @AppStorage("wick.journal.reminder.enabled") private var reminderEnabled = false
    @AppStorage("wick.journal.reminder.hour") private var reminderHour = 21
    @AppStorage("wick.journal.reminder.minute") private var reminderMinute = 0

    // Dropbox / Recovery States
    @State private var isConnecting = false
    @State private var showDisconnectConfirm = false
    @State private var showJournalImporter = false
    @State private var recoveryErrorMessage: String?

    // Exchange Bind State
    @State private var targetJournalID: UUID?
    @State private var showExchangeSheet = false
    @State private var bindingSheetTargetJournalID: UUID?
    @State private var selectedVenue: ExchangeVenue = .hyperliquid
    @State private var accountLabelDraft = ""
    @State private var apiKeyDraft = ""
    @State private var secretDraft = ""
    @State private var passphraseDraft = ""
    @State private var showUnbindConfirm = false

    @AppStorage("wick.journal.fontName") private var journalFontName = ""
    @State private var showFontPicker = false
    @State private var showTimePickerSheet = false

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .chinese
    }

    private var currentFontDisplayName: String {
        if journalFontName.isEmpty {
            return L10n.string(.fontDefault, language: language)
        }
        return UIFont(name: journalFontName, size: 12)?.familyName ?? journalFontName
    }

    private var fontDisplaySubtitle: String {
        language == .chinese ? "设备字体与文件导入" : "Device fonts & import"
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { language },
            set: { languageRaw = $0.rawValue }
        )
    }

    private var targetJournal: JournalInfo? {
        if let targetJournalID,
           let match = store.journals.first(where: { $0.id == targetJournalID }) {
            return match
        }
        return store.activeJournal ?? store.journals.first
    }

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance(rawValue: appearanceRaw) ?? .system },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    private var pnlConventionBinding: Binding<PnlColorConvention> {
        Binding(
            get: { PnlColorConvention(rawValue: pnlConventionRaw) ?? .redUp },
            set: {
                pnlConventionRaw = $0.rawValue
                TradingCalendarTheme.pnlConvention = $0
                NotificationCenter.default.post(name: .wickCalendarPnlConventionChanged, object: nil)
            }
        )
    }

    private var reminderDate: Date {
        Calendar.current.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: Date()) ?? Date()
    }

    private var reminderDateBinding: Binding<Date> {
        Binding(
            get: { reminderDate },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                reminderHour = comps.hour ?? 21
                reminderMinute = comps.minute ?? 0
                reminderScheduler.schedule(enabled: reminderEnabled, time: newDate)
            }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // 1. Appearance & Language
                    SettingsCard(title: L10n.string(.appearanceAndLanguageSection, language: language)) {
                        SettingsRow(
                            title: L10n.string(.language, language: language),
                            subtitle: language == .chinese ? "中文 / English" : "English / 中文"
                        ) {
                            SettingsSegmentedPicker(
                                options: AppLanguage.allCases,
                                selection: languageBinding
                            ) { option in
                                option.displayName
                            }
                        }

                        SettingsRow(
                            title: L10n.string(.appearance, language: language),
                            subtitle: language == .chinese ? "自动 / 亮色 / 暗色" : "Auto / Light / Dark"
                        ) {
                            SettingsSegmentedPicker(
                                options: AppAppearance.allCases,
                                selection: appearanceBinding
                            ) { option in
                                option.displayName(language: language)
                            }
                        }

                        SettingsRow(
                            title: L10n.string(.pnlColorConvention, language: language),
                            subtitle: language == .chinese ? "红涨绿跌 / 绿涨红跌" : "Red up / Green up",
                            isLast: false
                        ) {
                            SettingsSegmentedPicker(
                                options: PnlColorConvention.allCases,
                                selection: pnlConventionBinding
                            ) { option in
                                option.displayName(language: language)
                            }
                        }

                        SettingsRow(
                            title: L10n.string(.journalFontStyle, language: language),
                            subtitle: fontDisplaySubtitle,
                            isLast: true
                        ) {
                            Button {
                                showFontPicker = true
                            } label: {
                                HStack(spacing: 4) {
                                    Text(currentFontDisplayName)
                                        .font(PhoneFont.paper(11.5, weight: .medium))
                                        .foregroundColor(PhoneTheme.cinnabar)
                                        .lineLimit(1)
                                    Image(systemName: "chevron.right")
                                        .font(PhoneFont.ui(9, weight: .semibold))
                                        .foregroundColor(PhoneTheme.inkTertiary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(PhoneTheme.cinnabarSoft)
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // 2. General
                    SettingsCard(title: L10n.string(.generalSection, language: language)) {
                        SettingsRow(
                            title: L10n.string(.weekStartsOnMonday, language: language),
                            subtitle: language == .chinese ? "周一作为每周第一天" : "Monday as the first day of the week",
                            isLast: true
                        ) {
                            Toggle("", isOn: $weekStartsOnMonday)
                                .labelsHidden()
                                .tint(PhoneTheme.ember)
                        }
                    }

                    // 3. Journal & Reminders
                    SettingsCard(title: L10n.string(.journalAndReminderSection, language: language)) {
                        SettingsRow(
                            title: L10n.string(.journalReminderEnabled, language: language),
                            subtitle: L10n.string(.dailyReviewReminderSubtitle, language: language),
                            isLast: !reminderEnabled
                        ) {
                            Toggle("", isOn: $reminderEnabled)
                                .labelsHidden()
                                .tint(PhoneTheme.ember)
                                .onChange(of: reminderEnabled) { enabled in
                                    reminderScheduler.schedule(enabled: enabled, time: reminderDate)
                                }
                        }

                        if reminderEnabled {
                            SettingsRow(title: L10n.string(.journalReminderTime, language: language), isLast: true) {
                                Button {
                                    showTimePickerSheet = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(formattedReminderTime(reminderDate))
                                            .font(PhoneFont.paper(12.5, weight: .bold))
                                            .foregroundColor(PhoneTheme.inkPrimary)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(PhoneFont.ui(8.5, weight: .semibold))
                                            .foregroundColor(PhoneTheme.inkTertiary)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4.5)
                                    .background(PhoneTheme.paper)
                                    .cornerRadius(4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(PhoneTheme.rule, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // 4. Trading Calendar & Easter Egg
                    SettingsCard(title: L10n.string(.tradingCalendar, language: language)) {
                        SettingsRow(
                            title: language == .chinese ? "数据源" : "Data Feed",
                            subtitle: language == .chinese ? "华尔街见闻 REST 直连缓存" : "WallStreetCN REST cache",
                            isLast: false
                        ) {
                            Text(language == .chinese ? "实时在线" : "Online")
                                .font(PhoneFont.paper(11, weight: .medium))
                                .foregroundColor(PhoneTheme.inkTertiary)
                        }

                        // Easter Egg Box
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(language == .chinese ? "拟物物理黄历 (彩蛋)" : "Physical Desk Calendar (Easter Egg)")
                                        .font(PhoneFont.paper(13, weight: .bold))
                                        .foregroundColor(PhoneTheme.cinnabar)
                                    Text(L10n.string(.calendarEasterEggNote, language: language))
                                        .font(PhoneFont.paper(10.5))
                                        .foregroundColor(PhoneTheme.inkSecondary)
                                }
                                Spacer(minLength: 8)
                                Toggle("", isOn: $physicalEasterEgg)
                                    .labelsHidden()
                                    .tint(PhoneTheme.ember)
                                    .onChange(of: physicalEasterEgg) { enabled in
                                        // The pad's torn-to page is sticky; switching
                                        // the easter egg back on is the only reset.
                                        guard enabled else { return }
                                        TearOffState.resetToToday()
                                        NotificationCenter.default.post(name: .wickCalendarResetToToday, object: nil)
                                    }
                            }
                            .padding(12)
                            .background(PhoneTheme.cinnabarSoft)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                    .foregroundColor(PhoneTheme.cinnabar)
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                    }

                    // 5. Dropbox Sync
                    SettingsCard(title: L10n.string(.syncSection, language: language)) {
                        if sync.syncEnabled && sync.backend.isAuthorized {
                            SettingsRow(title: language == .chinese ? "Dropbox 账号" : "Dropbox Account") {
                                Text(sync.accountEmail.isEmpty ? (language == .chinese ? "已授权" : "Authorized") : sync.accountEmail)
                                    .font(PhoneFont.paper(11.5))
                                    .foregroundColor(PhoneTheme.inkSecondary)
                            }

                            SettingsRow(title: language == .chinese ? "同步状态" : "Sync Status") {
                                statusRow
                            }

                            SettingsRow(title: L10n.string(.syncNow, language: language)) {
                                Button {
                                    sync.engine.syncNow()
                                } label: {
                                    Text(L10n.string(.syncNow, language: language))
                                        .font(PhoneFont.paper(12, weight: .bold))
                                        .foregroundColor(PhoneTheme.cinnabar)
                                }
                            }

                            SettingsRow(
                                title: L10n.string(.syncDisconnect, language: language),
                                isLast: sync.engine.pendingConflicts.isEmpty
                            ) {
                                Button(role: .destructive) {
                                    showDisconnectConfirm = true
                                } label: {
                                    Text(L10n.string(.syncDisconnect, language: language))
                                        .font(PhoneFont.paper(12, weight: .medium))
                                        .foregroundColor(PhoneTheme.cinnabar)
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L10n.string(.syncExplanation, language: language))
                                    .font(PhoneFont.paper(11))
                                    .foregroundColor(PhoneTheme.inkSecondary)

                                Button {
                                    connect()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                            .font(PhoneFont.ui(11))
                                        Text(isConnecting ? L10n.string(.syncConnecting, language: language) : L10n.string(.syncConnect, language: language))
                                            .font(PhoneFont.paper(12, weight: .bold))
                                    }
                                    .foregroundColor(Color(red: 0.98, green: 0.95, blue: 0.90))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(PhoneTheme.cinnabar)
                                    .cornerRadius(4)
                                    .shadow(color: PhoneTheme.cinnabar.opacity(0.3), radius: 3, y: 1)
                                }
                                .disabled(isConnecting)

                                if sync.syncEnabled, !sync.backend.isAuthorized {
                                    Text(L10n.string(.syncStatusNeedsAuth, language: language))
                                        .font(PhoneFont.paper(10.5))
                                        .foregroundColor(PhoneTheme.cinnabar)
                                }
                                if let error = sync.lastAuthError {
                                    Text(error)
                                        .font(PhoneFont.paper(10))
                                        .foregroundColor(PhoneTheme.inkTertiary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }

                        if !sync.engine.pendingConflicts.isEmpty {
                            ForEach(Array(sync.engine.pendingConflicts.enumerated()), id: \.element.id) { index, conflict in
                                SettingsRow(
                                    title: conflict.displayDay,
                                    subtitle: language == .chinese ? "双方内容均已合并保留" : "Merged and preserved both versions",
                                    isLast: index == sync.engine.pendingConflicts.count - 1
                                ) {
                                    Button(L10n.string(.syncConflictDismiss, language: language)) {
                                        sync.engine.dismissConflict(id: conflict.id)
                                    }
                                    .font(PhoneFont.paper(11, weight: .bold))
                                    .foregroundColor(PhoneTheme.cinnabar)
                                }
                            }
                        }
                    }

                    // 6. Per-Journal Exchange Binding
                    SettingsCard(title: L10n.string(.exchangeSection, language: language)) {
                        SettingsRow(
                            title: language == .chinese ? "绑定日记本" : "Bound Journal",
                            subtitle: language == .chinese ? "选择要配置凭据的日记本" : "Select journal to configure credentials"
                        ) {
                            SettingsJournalPickerMenu(
                                journals: store.journals,
                                activeJournalID: store.activeJournalID,
                                targetJournalID: $targetJournalID,
                                language: language
                            )
                        }

                        if let journal = targetJournal {
                            if let binding = journal.exchangeBinding {
                                SettingsRow(title: language == .chinese ? "当前绑定" : "Current Binding") {
                                    Text(venueName(binding.venue))
                                        .font(PhoneFont.paper(12, weight: .semibold))
                                        .foregroundColor(PhoneTheme.inkPrimary)
                                }

                                SettingsRow(title: language == .chinese ? "账户标识" : "Account Label") {
                                    Text(binding.accountLabel)
                                        .font(PhoneFont.ui(11, monospacedDigit: true))
                                        .foregroundColor(PhoneTheme.inkSecondary)
                                }

                                if exchangeCoordinator.isSyncing(for: journal.id) {
                                    SettingsRow(title: language == .chinese ? "同步状态" : "Sync Status") {
                                        HStack(spacing: 6) {
                                            ProgressView()
                                                .scaleEffect(0.7)
                                            Text(L10n.string(.exchangeSyncing, language: language))
                                                .font(PhoneFont.paper(11))
                                                .foregroundColor(PhoneTheme.inkSecondary)
                                        }
                                    }
                                } else if let error = exchangeCoordinator.error(for: journal.id) {
                                    SettingsRow(title: language == .chinese ? "同步失败" : "Sync Failed") {
                                        Text(error)
                                            .font(PhoneFont.paper(10.5))
                                            .foregroundColor(PhoneTheme.cinnabar)
                                    }
                                } else if let snap = exchangeCoordinator.snapshot(for: journal.id) {
                                    SettingsRow(title: language == .chinese ? "已聚合仓位" : "Aggregated Positions") {
                                        Text(String(format: language == .chinese ? "%d 笔" : "%d positions", snap.positions.count))
                                            .font(PhoneFont.ui(11.5, weight: .bold, monospacedDigit: true))
                                            .foregroundColor(PhoneTheme.cinnabar)
                                    }
                                    SettingsRow(title: language == .chinese ? "最新对账" : "Last Reconciled") {
                                        Text(snap.fetchedAt.formatted(date: .omitted, time: .shortened))
                                            .font(PhoneFont.ui(11, monospacedDigit: true))
                                            .foregroundColor(PhoneTheme.inkSecondary)
                                    }
                                }

                                SettingsRow(title: language == .chinese ? "仓位刷新" : "Positions Refresh") {
                                    Button {
                                        exchangeCoordinator.syncNow(journalID: journal.id)
                                    } label: {
                                        Text(language == .chinese ? "立即刷新「\(journal.name)」" : "Refresh \"\(journal.name)\"")
                                            .font(PhoneFont.paper(12, weight: .bold))
                                            .foregroundColor(PhoneTheme.cinnabar)
                                    }
                                    .disabled(exchangeCoordinator.isSyncing(for: journal.id))
                                }

                                SettingsRow(title: L10n.string(.exchangeUnbind, language: language)) {
                                    Button(role: .destructive) {
                                        showUnbindConfirm = true
                                    } label: {
                                        Text(L10n.string(.exchangeDisconnect, language: language))
                                            .font(PhoneFont.paper(12, weight: .medium))
                                            .foregroundColor(PhoneTheme.cinnabar)
                                    }
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(language == .chinese ? "「\(journal.name)」尚未绑定交易所。一本日记绑定一个交易所只读账户。Hyperliquid 仅需填写 0x 钱包地址，无需私钥。" : "\"\(journal.name)\" has no exchange linked. One journal binds one read-only account. Hyperliquid only requires a 0x address without private keys.")
                                        .font(PhoneFont.paper(11))
                                        .foregroundColor(PhoneTheme.inkSecondary)

                                    Button {
                                        bindingSheetTargetJournalID = journal.id
                                        accountLabelDraft = ""
                                        apiKeyDraft = ""
                                        secretDraft = ""
                                        passphraseDraft = ""
                                        showExchangeSheet = true
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "link")
                                                .font(PhoneFont.ui(11))
                                            Text(language == .chinese ? "为「\(journal.name)」绑定交易所…" : "Bind Exchange for \"\(journal.name)\"…")
                                                .font(PhoneFont.paper(12, weight: .bold))
                                        }
                                        .foregroundColor(Color(red: 0.98, green: 0.95, blue: 0.90))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(PhoneTheme.cinnabar)
                                        .cornerRadius(4)
                                        .shadow(color: PhoneTheme.cinnabar.opacity(0.3), radius: 3, y: 1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                            }
                        }

                        SettingsRow(
                            title: L10n.string(.syncTradingSnapshots, language: language),
                            subtitle: L10n.string(.syncTradingSnapshotsHint, language: language),
                            isLast: true
                        ) {
                            Toggle("", isOn: $exchangeCoordinator.cloudSyncEnabled)
                                .labelsHidden()
                                .tint(PhoneTheme.ember)
                        }
                    }

                    // 7. Storage & Backup
                    SettingsCard(title: L10n.string(.dataSection, language: language)) {
                        if store.isReadOnlyDueToLoadFailure {
                            SettingsRow(title: L10n.string(.journalReadOnly, language: language)) {
                                Text(L10n.string(.journalLoadFailureTitle, language: language))
                                    .font(PhoneFont.paper(10.5))
                                    .foregroundColor(PhoneTheme.cinnabar)
                            }
                        }

                        if store.isCatalogReadOnly {
                            SettingsRow(title: language == .chinese ? "库只读保护" : "Catalog Protected") {
                                Button(language == .chinese ? "从 catalog 备份恢复" : "Restore from catalog backup") {
                                    do {
                                        try store.restoreCatalogFromBackup()
                                    } catch {
                                        recoveryErrorMessage = error.localizedDescription
                                    }
                                }
                                .font(PhoneFont.paper(11.5, weight: .bold))
                                .foregroundColor(PhoneTheme.cinnabar)
                            }
                        }

                        if let exportData = store.exportJournalData() {
                            SettingsRow(title: L10n.string(.journalExport, language: language)) {
                                ShareLink(
                                    item: exportData,
                                    preview: SharePreview("journal.json", image: Image(systemName: "book.closed"))
                                ) {
                                    HStack(spacing: 4) {
                                        Text(language == .chinese ? "导出 journal.json" : "Export journal.json")
                                            .font(PhoneFont.paper(11.5, weight: .bold))
                                        Image(systemName: "square.and.arrow.up")
                                            .font(PhoneFont.ui(10))
                                    }
                                    .foregroundColor(PhoneTheme.inkPrimary)
                                }
                            }
                        }

                        SettingsRow(title: L10n.string(.journalImport, language: language), isLast: true) {
                            Button(language == .chinese ? "导入 journal.json…" : "Import journal.json…") {
                                showJournalImporter = true
                            }
                            .font(PhoneFont.paper(11.5, weight: .bold))
                            .foregroundColor(PhoneTheme.cinnabar)
                        }
                    }

                    // Version & Branding Footer
                    VStack(spacing: 4) {
                        Text(language == .chinese ? "Wick for iOS · 秉烛日记" : "Wick for iOS")
                            .font(PhoneFont.paper(12, weight: .bold))
                            .foregroundColor(PhoneTheme.inkSecondary)

                        Text("v\(PhoneAppInfo.versionDisplay)")
                            .font(PhoneFont.paper(10.5, weight: .medium))
                            .foregroundColor(PhoneTheme.inkTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
            }
            .background(PhoneTheme.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if targetJournalID == nil {
                    targetJournalID = store.activeJournalID ?? store.journals.first?.id
                }
            }
            .onChange(of: store.journals.map(\.id)) { ids in
                if let targetJournalID, !ids.contains(targetJournalID) {
                    self.targetJournalID = store.activeJournalID ?? ids.first
                }
            }
            .sheet(isPresented: $showExchangeSheet) {
                ExchangeBindingSheet(
                    journals: store.journals,
                    language: language,
                    selectedJournalID: Binding(
                        get: { bindingSheetTargetJournalID ?? targetJournal?.id ?? store.activeJournalID ?? store.journals.first?.id ?? UUID() },
                        set: { bindingSheetTargetJournalID = $0 }
                    ),
                    selectedVenue: $selectedVenue,
                    accountLabelDraft: $accountLabelDraft,
                    apiKeyDraft: $apiKeyDraft,
                    secretDraft: $secretDraft,
                    passphraseDraft: $passphraseDraft,
                    onSave: {
                        guard let journalID = bindingSheetTargetJournalID ?? targetJournal?.id ?? store.activeJournalID else { return }
                        let binding = JournalExchangeBinding(
                            venue: selectedVenue,
                            accountLabel: accountLabelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        var secrets: ExchangeSecretBlob? = nil
                        if selectedVenue != .hyperliquid {
                            secrets = ExchangeSecretBlob(
                                venue: selectedVenue,
                                apiKey: apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines),
                                secret: secretDraft.trimmingCharacters(in: .whitespacesAndNewlines),
                                passphrase: passphraseDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                        }
                        exchangeCoordinator.setBinding(binding, secrets: secrets, for: journalID)
                        showExchangeSheet = false
                    }
                )
            }
            .confirmationDialog(
                L10n.string(.exchangeDisconnectConfirmTitle, language: language),
                isPresented: $showUnbindConfirm,
                titleVisibility: .visible
            ) {
                Button(L10n.string(.exchangeDisconnect, language: language), role: .destructive) {
                    if let journalID = targetJournal?.id {
                        exchangeCoordinator.removeBinding(for: journalID)
                    }
                }
                Button(L10n.string(.cancel, language: language), role: .cancel) {}
            } message: {
                Text(L10n.string(.exchangeDisconnectConfirmBody, language: language))
            }
            .fileImporter(
                isPresented: $showJournalImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    do {
                        try store.importJournalJSON(from: url)
                    } catch {
                        recoveryErrorMessage = error.localizedDescription
                    }
                case .failure(let error):
                    recoveryErrorMessage = error.localizedDescription
                }
            }
            .alert(L10n.string(.journalRecoveryFailedTitle, language: language), isPresented: Binding(
                get: { recoveryErrorMessage != nil },
                set: { if !$0 { recoveryErrorMessage = nil } }
            )) {
                Button(L10n.string(.ok, language: language), role: .cancel) { recoveryErrorMessage = nil }
            } message: {
                Text(recoveryErrorMessage ?? "")
            }
            .confirmationDialog(
                L10n.string(.syncDisconnectConfirmTitle, language: language),
                isPresented: $showDisconnectConfirm,
                titleVisibility: .visible
            ) {
                Button(L10n.string(.syncDisconnect, language: language), role: .destructive) {
                    sync.disconnectDropbox()
                }
                Button(L10n.string(.cancel, language: language), role: .cancel) {}
            } message: {
                Text(L10n.string(.syncDisconnectConfirmBody, language: language))
            }
            .sheet(isPresented: $showFontPicker) {
                PhoneFontPickerView()
            }
            .sheet(isPresented: $showTimePickerSheet) {
                NavigationStack {
                    VStack(spacing: 0) {
                        DatePicker(
                            "",
                            selection: reminderDateBinding,
                            displayedComponents: .hourAndMinute
                        )
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .padding(.top, 12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PhoneTheme.paper.ignoresSafeArea())
                    .navigationTitle(L10n.string(.journalReminderTime, language: language))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(language == .chinese ? "完成" : "Done") {
                                showTimePickerSheet = false
                            }
                            .font(PhoneFont.paper(13, weight: .bold))
                            .foregroundColor(PhoneTheme.cinnabar)
                        }
                    }
                }
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private func venueName(_ venue: ExchangeVenue) -> String {
        switch venue {
        case .hyperliquid: return "Hyperliquid"
        case .binance: return "Binance USDⓈ-M"
        case .okx: return "OKX SWAP"
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch sync.engine.status {
        case .syncing:
            Text(L10n.string(.syncStatusSyncing, language: language))
                .font(PhoneFont.paper(11))
                .foregroundColor(PhoneTheme.inkSecondary)
        case .offline:
            Text(L10n.string(.syncStatusOffline, language: language))
                .font(PhoneFont.paper(11))
                .foregroundColor(PhoneTheme.inkSecondary)
        case .needsAuth:
            Text(L10n.string(.syncStatusNeedsAuth, language: language))
                .font(PhoneFont.paper(11))
                .foregroundColor(PhoneTheme.cinnabar)
        case .error(let kind, let message):
            // SY-04: localize via the typed kind, never a raw English substring.
            Text(kind == .remoteFormatTooNew ? L10n.string(.syncRemoteTooNew, language: language) : message)
                .font(PhoneFont.paper(10.5))
                .foregroundColor(PhoneTheme.inkSecondary)
        case .idle:
            if let lastSyncAt = sync.engine.lastSyncAt {
                Text(lastSyncAt.formatted(date: .omitted, time: .shortened))
                    .font(PhoneFont.ui(11, monospacedDigit: true))
                    .foregroundColor(PhoneTheme.inkSecondary)
            } else {
                Text(L10n.string(.syncNeverSynced, language: language))
                    .font(PhoneFont.paper(11))
                    .foregroundColor(PhoneTheme.inkTertiary)
            }
        }
    }

    private func connect() {
        guard !isConnecting else { return }
        isConnecting = true
        Task {
            await sync.connectDropbox()
            isConnecting = false
        }
    }

    private func formattedReminderTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Reusable Wick "秉烛" Settings Components

private struct SettingsCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(PhoneFont.paper(11, weight: .bold))
                .foregroundColor(PhoneTheme.inkTertiary)
                .tracking(1.2)
                .textCase(.uppercase)
                .padding(.horizontal, 2)

            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PhoneTheme.paperHi)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(PhoneTheme.rule, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 2, y: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    let subtitle: String?
    let isLast: Bool
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        isLast: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isLast = isLast
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(PhoneFont.paper(13, weight: .medium))
                        .foregroundColor(PhoneTheme.inkPrimary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(PhoneFont.paper(10.5))
                            .foregroundColor(PhoneTheme.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                content
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if !isLast {
                Rectangle()
                    .fill(PhoneTheme.rule)
                    .frame(height: 1)
                    .padding(.leading, 14)
            }
        }
    }
}

private struct SettingsSegmentedPicker<T: Hashable & Identifiable>: View {
    let options: [T]
    @Binding var selection: T
    let titleForOption: (T) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                let isSelected = selection == option
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        selection = option
                    }
                } label: {
                    Text(titleForOption(option))
                        .font(PhoneFont.paper(11, weight: isSelected ? .bold : .medium))
                        .foregroundColor(isSelected ? Color(red: 0.98, green: 0.95, blue: 0.90) : PhoneTheme.inkSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4.5)
                        .background(
                            isSelected ?
                            AnyView(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(PhoneTheme.cinnabar)
                                    .shadow(color: PhoneTheme.cinnabar.opacity(0.35), radius: 3, y: 1)
                            ) :
                            AnyView(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(PhoneTheme.paper)
                                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(PhoneTheme.rule, lineWidth: 1))
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Exchange Binding Sheet

private struct ExchangeBindingSheet: View {
    let journals: [JournalInfo]
    let language: AppLanguage
    @Binding var selectedJournalID: UUID
    @Binding var selectedVenue: ExchangeVenue
    @Binding var accountLabelDraft: String
    @Binding var apiKeyDraft: String
    @Binding var secretDraft: String
    @Binding var passphraseDraft: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header Bar
                    HStack {
                        Text(L10n.string(.exchangeBind, language: language))
                            .font(PhoneFont.paper(16, weight: .bold))
                            .foregroundColor(PhoneTheme.inkPrimary)
                        Spacer()
                        Button(L10n.string(.cancel, language: language)) { dismiss() }
                            .font(PhoneFont.paper(13))
                            .foregroundColor(PhoneTheme.inkSecondary)
                    }
                    .padding(.horizontal, 2)
                    .padding(.top, 4)

                    // 1. Select Journal & Venue
                    SettingsCard(title: language == .chinese ? "日记本与交易所" : "Journal & Exchange") {
                        SettingsRow(title: language == .chinese ? "目标日记本" : "Target Journal") {
                            SheetJournalPickerMenu(
                                journals: journals,
                                selectedJournalID: $selectedJournalID,
                                language: language
                            )
                        }

                        SettingsRow(title: L10n.string(.exchangeVenue, language: language), isLast: true) {
                            SheetVenuePickerMenu(
                                selectedVenue: $selectedVenue,
                                language: language
                            )
                        }
                    }

                    // 2. Account Credentials Inputs
                    SettingsCard(title: language == .chinese ? "账户凭据" : "Credentials") {
                        if selectedVenue == .hyperliquid {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(L10n.string(.exchangeHyperliquidHint, language: language))
                                    .font(PhoneFont.paper(11))
                                    .foregroundColor(PhoneTheme.inkSecondary)
                                TextField("0x1234...abcd", text: $accountLabelDraft)
                                    .font(PhoneFont.ui(12, monospacedDigit: true))
                                    .padding(8)
                                    .background(PhoneTheme.paper)
                                    .cornerRadius(4)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            }
                            .padding(12)
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L10n.string(.exchangeAccountLabel, language: language))
                                        .font(PhoneFont.paper(11))
                                        .foregroundColor(PhoneTheme.inkSecondary)
                                    TextField(language == .chinese ? "如 主账号" : "e.g. Main", text: $accountLabelDraft)
                                        .font(PhoneFont.paper(12))
                                        .padding(8)
                                        .background(PhoneTheme.paper)
                                        .cornerRadius(4)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(L10n.string(.exchangeApiKey, language: language)) (\(language == .chinese ? "只读" : "Read-only"))")
                                        .font(PhoneFont.paper(11))
                                        .foregroundColor(PhoneTheme.inkSecondary)
                                    TextField("API Key", text: $apiKeyDraft)
                                        .font(PhoneFont.ui(12, monospacedDigit: true))
                                        .padding(8)
                                        .background(PhoneTheme.paper)
                                        .cornerRadius(4)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
                                        .autocorrectionDisabled()
                                        .textInputAutocapitalization(.never)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L10n.string(.exchangeSecretKey, language: language))
                                        .font(PhoneFont.paper(11))
                                        .foregroundColor(PhoneTheme.inkSecondary)
                                    SecureField("Secret", text: $secretDraft)
                                        .font(PhoneFont.ui(12, monospacedDigit: true))
                                        .padding(8)
                                        .background(PhoneTheme.paper)
                                        .cornerRadius(4)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
                                        .autocorrectionDisabled()
                                        .textInputAutocapitalization(.never)
                                }

                                if selectedVenue == .okx {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(L10n.string(.exchangePassphrase, language: language))
                                            .font(PhoneFont.paper(11))
                                            .foregroundColor(PhoneTheme.inkSecondary)
                                        SecureField("Passphrase", text: $passphraseDraft)
                                            .font(PhoneFont.ui(12, monospacedDigit: true))
                                            .padding(8)
                                            .background(PhoneTheme.paper)
                                            .cornerRadius(4)
                                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
                                            .autocorrectionDisabled()
                                            .textInputAutocapitalization(.never)
                                    }
                                }
                            }
                            .padding(12)
                        }
                    }

                    // Save Button
                    Button {
                        onSave()
                    } label: {
                        Text(L10n.string(.exchangeSaveAndSync, language: language))
                            .font(PhoneFont.paper(13, weight: .bold))
                            .foregroundColor(Color(red: 0.98, green: 0.95, blue: 0.90))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                accountLabelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?
                                PhoneTheme.inkTertiary : PhoneTheme.cinnabar
                            )
                            .cornerRadius(6)
                            .shadow(color: PhoneTheme.cinnabar.opacity(0.3), radius: 4, y: 2)
                    }
                    .disabled(accountLabelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.top, 4)
                }
                .padding(16)
            }
            .background(PhoneTheme.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Isolated Menu Components to prevent UIContextMenuInteraction spurious updates

private struct SettingsJournalPickerMenu: View {
    let journals: [JournalInfo]
    let activeJournalID: UUID?
    @Binding var targetJournalID: UUID?
    let language: AppLanguage

    private var targetJournal: JournalInfo? {
        journals.first(where: { $0.id == (targetJournalID ?? activeJournalID) })
    }

    var body: some View {
        Menu {
            ForEach(journals) { journal in
                Button {
                    targetJournalID = journal.id
                } label: {
                    HStack {
                        Text(journal.name)
                            .font(PhoneFont.paper(13))
                        if journal.id == activeJournalID {
                            Text(language == .chinese ? "(当前)" : "(Active)")
                                .font(PhoneFont.paper(12))
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(targetJournal?.name ?? (language == .chinese ? "未选择" : "None"))
                    .font(PhoneFont.paper(12, weight: .semibold))
                    .foregroundColor(PhoneTheme.inkPrimary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(PhoneFont.ui(9))
                    .foregroundColor(PhoneTheme.cinnabar)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(PhoneTheme.paper)
            .cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
        }
    }
}

private struct SheetJournalPickerMenu: View {
    let journals: [JournalInfo]
    @Binding var selectedJournalID: UUID
    let language: AppLanguage

    var body: some View {
        Menu {
            ForEach(journals) { journal in
                Button {
                    selectedJournalID = journal.id
                } label: {
                    Text(journal.name)
                        .font(PhoneFont.paper(13))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(journals.first(where: { $0.id == selectedJournalID })?.name ?? (language == .chinese ? "选择" : "Select"))
                    .font(PhoneFont.paper(12, weight: .semibold))
                    .foregroundColor(PhoneTheme.inkPrimary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(PhoneFont.ui(9))
                    .foregroundColor(PhoneTheme.cinnabar)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(PhoneTheme.paper)
            .cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
        }
    }
}

private struct SheetVenuePickerMenu: View {
    @Binding var selectedVenue: ExchangeVenue
    let language: AppLanguage

    private func venueTitle(_ venue: ExchangeVenue) -> String {
        switch venue {
        case .hyperliquid: return "Hyperliquid (0x)"
        case .binance: return "Binance USDⓈ-M"
        case .okx: return "OKX SWAP"
        }
    }

    var body: some View {
        Menu {
            Button("Hyperliquid (0x \(language == .chinese ? "钱包" : "Wallet"))") { selectedVenue = .hyperliquid }
            Button("Binance USDⓈ-M") { selectedVenue = .binance }
            Button("OKX SWAP") { selectedVenue = .okx }
        } label: {
            HStack(spacing: 4) {
                Text(venueTitle(selectedVenue))
                    .font(PhoneFont.paper(12, weight: .semibold))
                    .foregroundColor(PhoneTheme.inkPrimary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(PhoneFont.ui(9))
                    .foregroundColor(PhoneTheme.cinnabar)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(PhoneTheme.paper)
            .cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
        }
    }
}

// MARK: - App Info

enum PhoneAppInfo {
    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.0.0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static var versionDisplay: String {
        "\(shortVersion) (\(buildNumber))"
    }
}
