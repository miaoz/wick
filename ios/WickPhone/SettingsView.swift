import SwiftUI
import UniformTypeIdentifiers
import WickCalendarKit
import WickSync
import WickTrading

/// Tab 4: "设置" (Settings & Preferences).
/// Sync settings, per-journal exchange position binding & cloud snapshot sync, library management, and calendar Easter Egg.
struct SettingsView: View {
    @EnvironmentObject private var sync: PhoneSyncCoordinator
    @EnvironmentObject private var store: PhoneJournalStore
    @StateObject private var exchangeCoordinator = PhoneExchangeCoordinator.shared
    @AppStorage("wick.calendar.physicalEasterEgg") private var physicalEasterEgg = false

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

    var body: some View {
        NavigationStack {
            Form {
                // Section 1: Appearance & Typography
                Section("外观与主题") {
                    HStack {
                        Text("主题风格")
                        Spacer()
                        Text("秉烛 · 一日弧光")
                            .foregroundColor(PhoneTheme.inkSecondary)
                    }
                    HStack {
                        Text("正文字体")
                        Spacer()
                        Text("宋体纸面印刷")
                            .foregroundColor(PhoneTheme.inkSecondary)
                    }
                }

                // Section 2: Trading Calendar & Easter Egg
                Section("交易日历") {
                    HStack {
                        Text("数据源")
                        Spacer()
                        Text("华尔街见闻 REST 缓存")
                            .foregroundColor(PhoneTheme.inkSecondary)
                    }

                    // Easter Egg Card with Cinnabar Dotted Box
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: $physicalEasterEgg) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("拟物物理黄历 (彩蛋)")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundColor(PhoneTheme.cinnabar)
                                Text("默认关闭。开启后黄历 Tab 切换为朱漆装订条与撕页物理，合成纸声与触觉震动完整保留。")
                                    .font(.caption2)
                                    .foregroundColor(PhoneTheme.inkSecondary)
                            }
                        }
                        .tint(PhoneTheme.ember)
                    }
                    .padding(.vertical, 4)
                }

                // Section 3: Per-Journal Exchange Binding & Cloud Snapshot Sync
                Section("交易所与实盘仓位") {
                    // Journal Target Picker
                    Picker("绑定日记本", selection: Binding(
                        get: { targetJournal?.id },
                        set: { targetJournalID = $0 }
                    )) {
                        ForEach(store.journals) { journal in
                            HStack {
                                Text(journal.name)
                                if journal.id == store.activeJournalID {
                                    Text("(当前打开)")
                                }
                            }
                            .tag(Optional(journal.id))
                        }
                    }
                    .pickerStyle(.menu)

                    if let journal = targetJournal {
                        if let binding = journal.exchangeBinding {
                            LabeledContent("当前绑定", value: venueName(binding.venue))
                            LabeledContent("账户标识", value: binding.accountLabel)

                            if exchangeCoordinator.isSyncing(for: journal.id) {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("正在拉取成交…")
                                        .font(.footnote)
                                        .foregroundColor(PhoneTheme.inkSecondary)
                                }
                            } else if let error = exchangeCoordinator.error(for: journal.id) {
                                Text("同步失败: \(error)")
                                    .font(.caption2)
                                    .foregroundColor(PhoneTheme.cinnabar)
                            } else if let snap = exchangeCoordinator.snapshot(for: journal.id) {
                                LabeledContent("已聚合仓位", value: "\(snap.positions.count) 笔")
                                LabeledContent("最新对账", value: snap.fetchedAt.formatted(date: .omitted, time: .shortened))
                            }

                            Button("立即刷新「\(journal.name)」仓位") {
                                exchangeCoordinator.syncNow(journalID: journal.id)
                            }
                            .foregroundColor(PhoneTheme.cinnabar)
                            .disabled(exchangeCoordinator.isSyncing(for: journal.id))

                            Button("解除「\(journal.name)」交易所绑定", role: .destructive) {
                                showUnbindConfirm = true
                            }
                        } else {
                            Text("「\(journal.name)」尚未绑定交易所。一本日记绑定一个交易所只读账户。Hyperliquid 仅需填写 0x 钱包地址，无需私钥。")
                                .font(.footnote)
                                .foregroundColor(PhoneTheme.inkSecondary)

                            Button("为「\(journal.name)」绑定交易所…") {
                                bindingSheetTargetJournalID = journal.id
                                accountLabelDraft = ""
                                apiKeyDraft = ""
                                secretDraft = ""
                                passphraseDraft = ""
                                showExchangeSheet = true
                            }
                            .foregroundColor(PhoneTheme.cinnabar)
                        }
                    }

                    Toggle("云端快照同步 (只读多端)", isOn: $exchangeCoordinator.cloudSyncEnabled)
                        .tint(PhoneTheme.ember)
                    Text("开启后通过 Dropbox 同步已聚合的仓位快照，在其他设备上以只读小票与盈亏月历展示。CEX 凭据永不上传。")
                        .font(.caption2)
                        .foregroundColor(PhoneTheme.inkTertiary)
                }

                // Section 4: Dropbox Sync
                Section("数据同步") {
                    if sync.syncEnabled && sync.backend.isAuthorized {
                        LabeledContent("Dropbox", value: sync.accountEmail.isEmpty ? "—" : sync.accountEmail)
                        statusRow
                        Button("立即同步") {
                            sync.engine.syncNow()
                        }
                        .foregroundColor(PhoneTheme.cinnabar)

                        Button("断开 Dropbox", role: .destructive) {
                            showDisconnectConfirm = true
                        }
                    } else {
                        Text("通过 Dropbox 在多台设备间同步日记。本地始终是唯一主副本。")
                            .font(.footnote)
                            .foregroundColor(PhoneTheme.inkSecondary)

                        Button(isConnecting ? "正在连接…" : "连接 Dropbox") {
                            connect()
                        }
                        .foregroundColor(PhoneTheme.cinnabar)
                        .disabled(isConnecting)

                        if sync.syncEnabled, !sync.backend.isAuthorized {
                            Text("需要重新连接 Dropbox")
                                .font(.footnote)
                                .foregroundColor(PhoneTheme.cinnabar)
                        }
                        if let error = sync.lastAuthError {
                            Text(error)
                                .font(.caption2)
                                .foregroundColor(PhoneTheme.inkTertiary)
                        }
                    }
                }

                // Section 5: Conflicts
                if !sync.engine.pendingConflicts.isEmpty {
                    Section("冲突") {
                        ForEach(sync.engine.pendingConflicts) { conflict in
                            HStack {
                                Text("\(conflict.dayKey)：双方内容均已保留")
                                    .font(.footnote)
                                Spacer()
                                Button("知道了") {
                                    sync.engine.dismissConflict(id: conflict.id)
                                }
                                .font(.footnote)
                            }
                        }
                    }
                }

                // Section 6: Journal Storage & Recovery
                Section("存储保护与备份") {
                    if store.isReadOnlyDueToLoadFailure {
                        Text("日记文件无法读取，已阻止覆盖（只读保护中）")
                            .font(.footnote)
                            .foregroundColor(.red)
                    }

                    if store.isCatalogReadOnly {
                        Text("日记库无法读取，已进入只读保护。请先尝试恢复备份或导入日记。")
                            .font(.footnote)
                            .foregroundColor(.red)

                        Button("从 catalog 备份恢复") {
                            do {
                                try store.restoreCatalogFromBackup()
                            } catch {
                                recoveryErrorMessage = error.localizedDescription
                            }
                        }
                    }

                    Button("导入 journal.json…") {
                        showJournalImporter = true
                    }
                }

                // Section 7: About
                Section {
                    HStack {
                        Text("Wick for iOS")
                        Spacer()
                        Text("1.0 (By Candlelight)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(PhoneTheme.inkTertiary)
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
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
                .font(.footnote)
                .foregroundColor(PhoneTheme.inkSecondary)
        case .offline:
            Text("当前离线，将自动重试")
                .font(.footnote)
                .foregroundColor(PhoneTheme.inkSecondary)
        case .needsAuth:
            Text("需要重新连接 Dropbox")
                .font(.footnote)
                .foregroundColor(PhoneTheme.cinnabar)
        case .error(let message):
            Text(message.contains("remote format") ? "远端数据由更新版本的 Wick 写入，请升级 App" : message)
                .font(.footnote)
                .foregroundColor(PhoneTheme.inkSecondary)
        case .idle:
            if let lastSyncAt = sync.engine.lastSyncAt {
                LabeledContent("最后同步", value: lastSyncAt.formatted(date: .omitted, time: .shortened))
            } else {
                Text("尚未同步")
                    .font(.footnote)
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
            Form {
                Section("选择日记本与交易所") {
                    Picker("绑定日记本", selection: $selectedJournalID) {
                        ForEach(journals) { journal in
                            Text(journal.name).tag(journal.id)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("交易所", selection: $selectedVenue) {
                        Text("Hyperliquid (0x 钱包)").tag(ExchangeVenue.hyperliquid)
                        Text("Binance USDⓈ-M").tag(ExchangeVenue.binance)
                        Text("OKX SWAP").tag(ExchangeVenue.okx)
                    }
                    .pickerStyle(.menu)
                }

                Section("账户信息") {
                    if selectedVenue == .hyperliquid {
                        TextField("0x 钱包地址 (如 0x1234...abcd)", text: $accountLabelDraft)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } else {
                        TextField("账户备注名称 (如 主账号)", text: $accountLabelDraft)
                        TextField("API Key", text: $apiKeyDraft)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        SecureField("API Secret", text: $secretDraft)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        if selectedVenue == .okx {
                            SecureField("Passphrase", text: $passphraseDraft)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                    }
                }
            }
            .navigationTitle("绑定交易所")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { onSave() }
                        .disabled(accountLabelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
