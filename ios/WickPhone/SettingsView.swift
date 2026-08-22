import SwiftUI
import UniformTypeIdentifiers
import WickSync

/// Sync settings sheet: connect/disconnect Dropbox, status, conflicts.
struct SettingsView: View {
    @EnvironmentObject private var sync: PhoneSyncCoordinator
    @EnvironmentObject private var store: PhoneJournalStore
    @Environment(\.dismiss) private var dismiss

    @State private var isConnecting = false
    @State private var showDisconnectConfirm = false
    @State private var showJournalImporter = false
    @State private var recoveryErrorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("同步") {
                    if sync.syncEnabled && sync.backend.isAuthorized {
                        LabeledContent("Dropbox", value: sync.accountEmail.isEmpty ? "—" : sync.accountEmail)
                        statusRow
                        Button("立即同步") {
                            sync.engine.syncNow()
                        }
                        Button("断开 Dropbox", role: .destructive) {
                            showDisconnectConfirm = true
                        }
                    } else {
                        Text("通过 Dropbox 在多台设备间同步日记。本地始终是主副本。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button(isConnecting ? "正在连接…" : "连接 Dropbox") {
                            connect()
                        }
                        .disabled(isConnecting)
                        if sync.syncEnabled, !sync.backend.isAuthorized {
                            Text("需要重新连接 Dropbox")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if let error = sync.lastAuthError {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

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

                if store.isReadOnlyDueToLoadFailure {
                    Section {
                        Text("日记文件无法读取，已阻止覆盖（只读保护中）")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if store.isCatalogReadOnly {
                    Section {
                        Text("日记库无法读取，已进入只读保护。请先尝试恢复备份或导入日记；清空重建会丢失原目录信息。")
                            .font(.footnote)
                            .foregroundStyle(.red)
                        Button("从 catalog 备份恢复") {
                            do {
                                try store.restoreCatalogFromBackup()
                            } catch {
                                recoveryErrorMessage = error.localizedDescription
                            }
                        }
                        Button("导入 journal.json") {
                            showJournalImporter = true
                        }
                        Button("清空并重新开始", role: .destructive) {
                            do {
                                try store.abandonCatalogAndStartFresh()
                            } catch {
                                recoveryErrorMessage = error.localizedDescription
                            }
                        }
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
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

    @ViewBuilder
    private var statusRow: some View {
        switch sync.engine.status {
        case .syncing:
            Text("正在同步…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .offline:
            Text("当前离线，将自动重试")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .needsAuth:
            Text("需要重新连接 Dropbox")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .error(let message):
            Text(message.contains("remote format") ? "远端数据由更新版本的 Wick 写入，请升级 App" : message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .idle:
            if let lastSyncAt = sync.engine.lastSyncAt {
                LabeledContent("最后同步", value: lastSyncAt.formatted(date: .omitted, time: .shortened))
            } else {
                Text("尚未同步")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
