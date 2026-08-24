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
    @StateObject private var exchangeCoordinator = PhoneExchangeCoordinator.shared
    @StateObject private var reminderScheduler = PhoneReminderScheduler.shared

    // Appearance & Convention Settings
    @AppStorage("wick.appearance") private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage("wick.pnlColorConvention") private var pnlConventionRaw = PnlColorConvention.redUp.rawValue
    @AppStorage("wick.calendar.physicalEasterEgg") private var physicalEasterEgg = false

    // Reminder Settings
    @AppStorage("wick.journal.reminder.enabled") private var reminderEnabled = false
    @State private var reminderTime = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date()) ?? Date()

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
            set: { pnlConventionRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // 1. Appearance & Theme
                    SettingsCard(title: "外观与主题") {
                        SettingsRow(title: "外观模式", subtitle: "跟随系统 / 亮色 / 暗色") {
                            SettingsSegmentedPicker(
                                options: AppAppearance.allCases,
                                selection: appearanceBinding
                            ) { option in
                                option.displayName(language: .chinese)
                            }
                        }

                        SettingsRow(title: "涨跌配色", subtitle: "红涨绿跌 / 绿涨红跌", isLast: true) {
                            SettingsSegmentedPicker(
                                options: PnlColorConvention.allCases,
                                selection: pnlConventionBinding
                            ) { option in
                                option.displayName(language: .chinese)
                            }
                        }
                    }

                    // 2. Daily Notification Reminder
                    SettingsCard(title: "日记提醒") {
                        SettingsRow(
                            title: "每日复盘提醒",
                            subtitle: "每晚定时推送复盘提醒通知",
                            isLast: !reminderEnabled
                        ) {
                            Toggle("", isOn: $reminderEnabled)
                                .labelsHidden()
                                .tint(PhoneTheme.ember)
                                .onChange(of: reminderEnabled) { enabled in
                                    reminderScheduler.schedule(enabled: enabled, time: reminderTime)
                                }
                        }

                        if reminderEnabled {
                            SettingsRow(title: "提醒时间", isLast: true) {
                                DatePicker(
                                    "",
                                    selection: $reminderTime,
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()
                                .colorMultiply(PhoneTheme.inkPrimary)
                                .onChange(of: reminderTime) { time in
                                    reminderScheduler.schedule(enabled: reminderEnabled, time: time)
                                }
                            }
                        }
                    }

                    // 3. Trading Calendar & Easter Egg
                    SettingsCard(title: "交易日历") {
                        SettingsRow(title: "数据源", subtitle: "华尔街见闻 REST 直连缓存", isLast: true) {
                            Text("实时在线")
                                .font(.system(size: 11, weight: .medium, design: .serif))
                                .foregroundColor(PhoneTheme.inkTertiary)
                        }

                        // Easter Egg Box
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("拟物物理黄历 (彩蛋)")
                                        .font(.system(size: 13, weight: .bold, design: .serif))
                                        .foregroundColor(PhoneTheme.cinnabar)
                                    Text("默认关闭。开启后黄历 Tab 将切换为朱漆装订条与撕页物理，合成纸声与触觉震动完整保留。")
                                        .font(.system(size: 10.5, design: .serif))
                                        .foregroundColor(PhoneTheme.inkSecondary)
                                }
                                Spacer(minLength: 8)
                                Toggle("", isOn: $physicalEasterEgg)
                                    .labelsHidden()
                                    .tint(PhoneTheme.ember)
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
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                    }

                    // 4. Per-Journal Exchange Binding
                    SettingsCard(title: "交易所与实盘仓位") {
                        SettingsRow(title: "绑定日记本", subtitle: "选择要配置凭据的日记本") {
                            Menu {
                                ForEach(store.journals) { journal in
                                    Button {
                                        targetJournalID = journal.id
                                    } label: {
                                        HStack {
                                            Text(journal.name)
                                            if journal.id == store.activeJournalID {
                                                Text("(当前)")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(targetJournal?.name ?? "未选择")
                                        .font(.system(size: 12, weight: .semibold, design: .serif))
                                        .foregroundColor(PhoneTheme.inkPrimary)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 9))
                                        .foregroundColor(PhoneTheme.cinnabar)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(PhoneTheme.paper)
                                .cornerRadius(4)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
                            }
                        }

                        if let journal = targetJournal {
                            if let binding = journal.exchangeBinding {
                                SettingsRow(title: "当前绑定") {
                                    Text(venueName(binding.venue))
                                        .font(.system(size: 12, weight: .semibold, design: .serif))
                                        .foregroundColor(PhoneTheme.inkPrimary)
                                }

                                SettingsRow(title: "账户标识") {
                                    Text(binding.accountLabel)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(PhoneTheme.inkSecondary)
                                }

                                if exchangeCoordinator.isSyncing(for: journal.id) {
                                    SettingsRow(title: "同步状态") {
                                        HStack(spacing: 6) {
                                            ProgressView()
                                                .scaleEffect(0.7)
                                            Text("正在拉取成交…")
                                                .font(.system(size: 11, design: .serif))
                                                .foregroundColor(PhoneTheme.inkSecondary)
                                        }
                                    }
                                } else if let error = exchangeCoordinator.error(for: journal.id) {
                                    SettingsRow(title: "同步失败") {
                                        Text(error)
                                            .font(.system(size: 10.5, design: .serif))
                                            .foregroundColor(PhoneTheme.cinnabar)
                                    }
                                } else if let snap = exchangeCoordinator.snapshot(for: journal.id) {
                                    SettingsRow(title: "已聚合仓位") {
                                        Text("\(snap.positions.count) 笔")
                                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                            .foregroundColor(PhoneTheme.cinnabar)
                                    }
                                    SettingsRow(title: "最新对账") {
                                        Text(snap.fetchedAt.formatted(date: .omitted, time: .shortened))
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(PhoneTheme.inkSecondary)
                                    }
                                }

                                SettingsRow(title: "仓位刷新") {
                                    Button {
                                        exchangeCoordinator.syncNow(journalID: journal.id)
                                    } label: {
                                        Text("立即刷新「\(journal.name)」")
                                            .font(.system(size: 12, weight: .bold, design: .serif))
                                            .foregroundColor(PhoneTheme.cinnabar)
                                    }
                                    .disabled(exchangeCoordinator.isSyncing(for: journal.id))
                                }

                                SettingsRow(title: "解除绑定") {
                                    Button(role: .destructive) {
                                        showUnbindConfirm = true
                                    } label: {
                                        Text("解除绑定…")
                                            .font(.system(size: 12, weight: .medium, design: .serif))
                                            .foregroundColor(PhoneTheme.cinnabar)
                                    }
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("「\(journal.name)」尚未绑定交易所。一本日记绑定一个交易所只读账户。Hyperliquid 仅需填写 0x 钱包地址，无需私钥。")
                                        .font(.system(size: 11, design: .serif))
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
                                                .font(.system(size: 11))
                                            Text("为「\(journal.name)」绑定交易所…")
                                                .font(.system(size: 12, weight: .bold, design: .serif))
                                        }
                                        .foregroundColor(Color(red: 0.98, green: 0.95, blue: 0.90))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(PhoneTheme.cinnabar)
                                        .cornerRadius(4)
                                        .shadow(color: PhoneTheme.cinnabar.opacity(0.3), radius: 3, y: 1)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                            }
                        }

                        SettingsRow(
                            title: "云端快照同步",
                            subtitle: "开启后通过 Dropbox 同步已聚合的仓位快照，在其他设备上以只读小票与盈亏月历展示。CEX 凭据永不上传。",
                            isLast: true
                        ) {
                            Toggle("", isOn: $exchangeCoordinator.cloudSyncEnabled)
                                .labelsHidden()
                                .tint(PhoneTheme.ember)
                        }
                    }

                    // 5. Dropbox Sync
                    SettingsCard(title: "数据同步") {
                        if sync.syncEnabled && sync.backend.isAuthorized {
                            SettingsRow(title: "Dropbox 账号") {
                                Text(sync.accountEmail.isEmpty ? "已授权" : sync.accountEmail)
                                    .font(.system(size: 11.5, design: .serif))
                                    .foregroundColor(PhoneTheme.inkSecondary)
                            }

                            SettingsRow(title: "同步状态") {
                                statusRow
                            }

                            SettingsRow(title: "立即同步") {
                                Button {
                                    sync.engine.syncNow()
                                } label: {
                                    Text("对账同步")
                                        .font(.system(size: 12, weight: .bold, design: .serif))
                                        .foregroundColor(PhoneTheme.cinnabar)
                                }
                            }

                            SettingsRow(title: "断开连接", isLast: true) {
                                Button(role: .destructive) {
                                    showDisconnectConfirm = true
                                } label: {
                                    Text("断开 Dropbox…")
                                        .font(.system(size: 12, weight: .medium, design: .serif))
                                        .foregroundColor(PhoneTheme.cinnabar)
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("通过 Dropbox 在多台设备间双向同步日记。本地始终是唯一主副本。")
                                    .font(.system(size: 11, design: .serif))
                                    .foregroundColor(PhoneTheme.inkSecondary)

                                Button {
                                    connect()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                            .font(.system(size: 11))
                                        Text(isConnecting ? "正在连接…" : "连接 Dropbox")
                                            .font(.system(size: 12, weight: .bold, design: .serif))
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
                                    Text("需要重新连接 Dropbox")
                                        .font(.system(size: 10.5, design: .serif))
                                        .foregroundColor(PhoneTheme.cinnabar)
                                }
                                if let error = sync.lastAuthError {
                                    Text(error)
                                        .font(.system(size: 10, design: .serif))
                                        .foregroundColor(PhoneTheme.inkTertiary)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                    }

                    // 6. Conflicts
                    if !sync.engine.pendingConflicts.isEmpty {
                        SettingsCard(title: "对账冲突") {
                            ForEach(sync.engine.pendingConflicts) { conflict in
                                SettingsRow(title: conflict.dayKey, subtitle: "双方内容均已合并保留") {
                                    Button("知道了") {
                                        sync.engine.dismissConflict(id: conflict.id)
                                    }
                                    .font(.system(size: 11, weight: .bold, design: .serif))
                                    .foregroundColor(PhoneTheme.cinnabar)
                                }
                            }
                        }
                    }

                    // 7. Storage & Backup
                    SettingsCard(title: "存储与备份") {
                        if store.isReadOnlyDueToLoadFailure {
                            SettingsRow(title: "只读保护") {
                                Text("日记文件无法读取，已阻止覆盖")
                                    .font(.system(size: 10.5, design: .serif))
                                    .foregroundColor(PhoneTheme.cinnabar)
                            }
                        }

                        if store.isCatalogReadOnly {
                            SettingsRow(title: "库只读保护") {
                                Button("从 catalog 备份恢复") {
                                    do {
                                        try store.restoreCatalogFromBackup()
                                    } catch {
                                        recoveryErrorMessage = error.localizedDescription
                                    }
                                }
                                .font(.system(size: 11.5, weight: .bold, design: .serif))
                                .foregroundColor(PhoneTheme.cinnabar)
                            }
                        }

                        if let exportData = store.exportJournalData() {
                            SettingsRow(title: "导出日记") {
                                ShareLink(
                                    item: exportData,
                                    preview: SharePreview("journal.json", image: Image(systemName: "book.closed"))
                                ) {
                                    HStack(spacing: 4) {
                                        Text("导出 journal.json")
                                            .font(.system(size: 11.5, weight: .bold, design: .serif))
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.system(size: 10))
                                    }
                                    .foregroundColor(PhoneTheme.inkPrimary)
                                }
                            }
                        }

                        SettingsRow(title: "导入备份", isLast: true) {
                            Button("导入 journal.json…") {
                                showJournalImporter = true
                            }
                            .font(.system(size: 11.5, weight: .bold, design: .serif))
                            .foregroundColor(PhoneTheme.cinnabar)
                        }
                    }

                    // 8. About
                    VStack(spacing: 4) {
                        Text("Wick for iOS · 秉烛")
                            .font(.system(size: 12, weight: .bold, design: .serif))
                            .foregroundColor(PhoneTheme.inkSecondary)
                        Text("1.0 · 本地优先 · 纯粹时间与交易记录")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(PhoneTheme.inkTertiary)
                    }
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
                "解除交易所绑定？",
                isPresented: $showUnbindConfirm,
                titleVisibility: .visible
            ) {
                Button("解除绑定", role: .destructive) {
                    if let journalID = targetJournal?.id {
                        exchangeCoordinator.removeBinding(for: journalID)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将移除「\(targetJournal?.name ?? "")」本地与云端的仓位快照，凭据将被安全清除。")
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
            .alert("恢复失败", isPresented: Binding(
                get: { recoveryErrorMessage != nil },
                set: { if !$0 { recoveryErrorMessage = nil } }
            )) {
                Button("好", role: .cancel) { recoveryErrorMessage = nil }
            } message: {
                Text(recoveryErrorMessage ?? "")
            }
            .confirmationDialog(
                "断开 Dropbox？",
                isPresented: $showDisconnectConfirm,
                titleVisibility: .visible
            ) {
                Button("断开 Dropbox", role: .destructive) {
                    sync.disconnectDropbox()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将停止同步。本机与 Dropbox 中已有的数据都会保留。")
            }
        }
    }

    private func venueName(_ venue: ExchangeVenue) -> String {
        switch venue {
        case .hyperliquid: return "Hyperliquid 永续"
        case .binance: return "Binance USDⓈ-M"
        case .okx: return "OKX SWAP 永续"
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch sync.engine.status {
        case .syncing:
            Text("正在同步…")
                .font(.system(size: 11, design: .serif))
                .foregroundColor(PhoneTheme.inkSecondary)
        case .offline:
            Text("当前离线，将自动重试")
                .font(.system(size: 11, design: .serif))
                .foregroundColor(PhoneTheme.inkSecondary)
        case .needsAuth:
            Text("需要重新连接 Dropbox")
                .font(.system(size: 11, design: .serif))
                .foregroundColor(PhoneTheme.cinnabar)
        case .error(let message):
            Text(message.contains("remote format") ? "远端数据由更新版本的 Wick 写入，请升级 App" : message)
                .font(.system(size: 10.5, design: .serif))
                .foregroundColor(PhoneTheme.inkSecondary)
        case .idle:
            if let lastSyncAt = sync.engine.lastSyncAt {
                Text(lastSyncAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(PhoneTheme.inkSecondary)
            } else {
                Text("尚未同步")
                    .font(.system(size: 11, design: .serif))
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
                .font(.system(size: 11, weight: .bold, design: .serif))
                .foregroundColor(PhoneTheme.inkTertiary)
                .tracking(1.2)
                .textCase(.uppercase)
                .padding(.horizontal, 2)

            VStack(spacing: 0) {
                content
            }
            .background(PhoneTheme.paperHi)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(PhoneTheme.rule, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 2, y: 1)
        }
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
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .foregroundColor(PhoneTheme.inkPrimary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 10.5, design: .serif))
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
                        .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .serif))
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
                        Text("绑定交易所")
                            .font(.system(size: 16, weight: .bold, design: .serif))
                            .foregroundColor(PhoneTheme.inkPrimary)
                        Spacer()
                        Button("取消") { dismiss() }
                            .font(.system(size: 13, design: .serif))
                            .foregroundColor(PhoneTheme.inkSecondary)
                    }
                    .padding(.horizontal, 2)
                    .padding(.top, 4)

                    // 1. Select Journal & Venue
                    SettingsCard(title: "日记本与交易所") {
                        SettingsRow(title: "目标日记本") {
                            Menu {
                                ForEach(journals) { journal in
                                    Button(journal.name) {
                                        selectedJournalID = journal.id
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(journals.first(where: { $0.id == selectedJournalID })?.name ?? "选择")
                                        .font(.system(size: 12, weight: .semibold, design: .serif))
                                        .foregroundColor(PhoneTheme.inkPrimary)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 9))
                                        .foregroundColor(PhoneTheme.cinnabar)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(PhoneTheme.paper)
                                .cornerRadius(4)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
                            }
                        }

                        SettingsRow(title: "交易所类型", isLast: true) {
                            Menu {
                                Button("Hyperliquid (0x 钱包)") { selectedVenue = .hyperliquid }
                                Button("Binance USDⓈ-M") { selectedVenue = .binance }
                                Button("OKX SWAP") { selectedVenue = .okx }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(venueTitle(selectedVenue))
                                        .font(.system(size: 12, weight: .semibold, design: .serif))
                                        .foregroundColor(PhoneTheme.inkPrimary)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 9))
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

                    // 2. Account Credentials Inputs
                    SettingsCard(title: "账户凭据") {
                        if selectedVenue == .hyperliquid {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("0x 钱包地址 (不填私钥)")
                                    .font(.system(size: 11, design: .serif))
                                    .foregroundColor(PhoneTheme.inkSecondary)
                                TextField("0x1234...abcd", text: $accountLabelDraft)
                                    .font(.system(size: 12, design: .monospaced))
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
                                    Text("账户备注")
                                        .font(.system(size: 11, design: .serif))
                                        .foregroundColor(PhoneTheme.inkSecondary)
                                    TextField("如 主账号", text: $accountLabelDraft)
                                        .font(.system(size: 12, design: .serif))
                                        .padding(8)
                                        .background(PhoneTheme.paper)
                                        .cornerRadius(4)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("API Key (只读)")
                                        .font(.system(size: 11, design: .serif))
                                        .foregroundColor(PhoneTheme.inkSecondary)
                                    TextField("API Key", text: $apiKeyDraft)
                                        .font(.system(size: 12, design: .monospaced))
                                        .padding(8)
                                        .background(PhoneTheme.paper)
                                        .cornerRadius(4)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
                                        .autocorrectionDisabled()
                                        .textInputAutocapitalization(.never)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("API Secret")
                                        .font(.system(size: 11, design: .serif))
                                        .foregroundColor(PhoneTheme.inkSecondary)
                                    SecureField("Secret", text: $secretDraft)
                                        .font(.system(size: 12, design: .monospaced))
                                        .padding(8)
                                        .background(PhoneTheme.paper)
                                        .cornerRadius(4)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
                                        .autocorrectionDisabled()
                                        .textInputAutocapitalization(.never)
                                }

                                if selectedVenue == .okx {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Passphrase")
                                            .font(.system(size: 11, design: .serif))
                                            .foregroundColor(PhoneTheme.inkSecondary)
                                        SecureField("Passphrase", text: $passphraseDraft)
                                            .font(.system(size: 12, design: .monospaced))
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
                        Text("保存并绑定")
                            .font(.system(size: 13, weight: .bold, design: .serif))
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

    private func venueTitle(_ venue: ExchangeVenue) -> String {
        switch venue {
        case .hyperliquid: return "Hyperliquid (0x)"
        case .binance: return "Binance USDⓈ-M"
        case .okx: return "OKX SWAP"
        }
    }
}
