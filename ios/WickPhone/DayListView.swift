import SwiftUI
import WickSync

/// Day list: newest first, tap to edit. v0 UI is Chinese-only (the macOS app
/// stays bilingual via L10n; phone localization lands with the feature set).
/// Lives inside HomeView's NavigationStack.
struct DayListView: View {
    @EnvironmentObject private var store: PhoneJournalStore
    @EnvironmentObject private var sync: PhoneSyncCoordinator

    @Binding var path: NavigationPath
    @State private var showSettings = false

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
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
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
        .sheet(isPresented: $showSettings) {
            SettingsView()
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
