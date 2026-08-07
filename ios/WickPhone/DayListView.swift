import SwiftUI
import WickSync

/// Day list: newest first, tap to edit. v0 UI is Chinese-only (the macOS app
/// stays bilingual via L10n; phone localization lands with the feature set).
/// Lives inside HomeView's NavigationStack. The leading menu manages journals
/// (switch / create / rename / delete), mirroring the macOS library menu.
struct DayListView: View {
    @EnvironmentObject private var store: PhoneJournalStore
    @EnvironmentObject private var sync: PhoneSyncCoordinator

    @Binding var path: NavigationPath

    private enum NameAlert {
        case new
        case rename
    }

    @State private var nameAlertMode: NameAlert = .new
    @State private var showNameAlert = false
    @State private var nameDraft = ""
    @State private var showDeleteConfirm = false

    var body: some View {
        List {
            ForEach(store.entries) { entry in
                NavigationLink(value: entry.dayKey) {
                    DayRow(entry: entry)
                }
            }
            .onDelete(perform: deleteDays)
        }
        .navigationTitle(store.activeJournal?.name ?? "日记")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                journalMenu
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let entry = store.openOrCreateToday()
                    path.append(entry.dayKey)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .alert(
            nameAlertMode == .rename ? "重命名日记本" : "新建日记本",
            isPresented: $showNameAlert
        ) {
            TextField("名称", text: $nameDraft)
            Button(nameAlertMode == .rename ? "保存" : "创建") {
                switch nameAlertMode {
                case .rename:
                    if let id = store.activeJournalID {
                        store.renameJournal(id: id, to: nameDraft)
                    }
                case .new:
                    store.createJournal(name: nameDraft)
                }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog(
            "删除当前日记本？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let id = store.activeJournalID {
                    _ = store.deleteJournal(id: id)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除「\(store.activeJournal?.name ?? "")」在本机的全部内容，且不可撤销。")
        }
    }

    private var journalMenu: some View {
        Menu {
            ForEach(store.journals) { journal in
                Button {
                    store.switchToJournal(id: journal.id)
                } label: {
                    if journal.id == store.activeJournalID {
                        Label(journal.name, systemImage: "checkmark")
                    } else {
                        Text(journal.name)
                    }
                }
            }

            Divider()

            Button("新建日记本…") {
                nameAlertMode = .new
                nameDraft = ""
                showNameAlert = true
            }
            Button("重命名…") {
                nameAlertMode = .rename
                nameDraft = store.activeJournal?.name ?? ""
                showNameAlert = true
            }
            Button("删除日记本…", role: .destructive) {
                showDeleteConfirm = true
            }
            .disabled(store.journals.count <= 1)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "book.closed")
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
        }
    }

    private func deleteDays(at offsets: IndexSet) {
        for index in offsets {
            store.deleteEntry(dayKey: store.entries[index].dayKey)
        }
    }
}

private struct DayRow: View {
    let entry: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(Self.dateText(for: entry.date))
                    .font(.headline)
                Spacer()
                Text("\(entry.items.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            let preview = entry.previewText
            if !preview.isEmpty {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private static func dateText(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        return formatter.string(from: date)
    }
}
