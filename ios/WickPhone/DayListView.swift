import SwiftUI
import WickCalendarKit
import WickSync
import WickTrading

/// Tab 2: "日记" (Journal day list + PnL Heatmap).
/// Includes journal switcher, compact monthly heatmap with realized PnL, tag filter chips, and month-sectioned day cards.
struct DayListView: View {
    @EnvironmentObject private var store: PhoneJournalStore
    @EnvironmentObject private var sync: PhoneSyncCoordinator
    @StateObject private var exchangeCoordinator = PhoneExchangeCoordinator.shared
    @Environment(\.appLanguage) private var language: AppLanguage

    @State private var selectedTag: String? = nil
    @State private var heatmapMonth = Date()
    @State private var navigationPath = NavigationPath()

    private enum NameAlert {
        case new
        case rename
    }

    @State private var nameAlertMode: NameAlert = .new
    @State private var showNameAlert = false
    @State private var nameDraft = ""
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                // Top Custom Header (dl-topbar)
                HStack {
                    journalMenu
                    Spacer()
                    Button {
                        let entry = store.openOrCreateToday()
                        navigationPath.append(entry.dayKey)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                            Text(L10n.string(.journalToday, language: language))
                                .font(.system(size: 11.5, weight: .bold, design: .serif))
                        }
                        .foregroundColor(PhoneTheme.cinnabar)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(PhoneTheme.cinnabarSoft)
                        .cornerRadius(4)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .padding(.bottom, 6)

                ScrollView {
                    VStack(spacing: 14) {
                        // 1. Compact PnL Heatmap Card
                        PnlHeatmapCard(
                            currentMonth: $heatmapMonth,
                            entries: store.entries,
                            exchangeCoordinator: exchangeCoordinator,
                            language: language,
                            onSelectDay: { dayKey in
                                if let entry = store.entries.first(where: { $0.dayKey == dayKey }) {
                                    navigationPath.append(entry.dayKey)
                                } else {
                                    let newEntry = store.openOrCreateToday()
                                    navigationPath.append(newEntry.dayKey)
                                }
                            }
                        )
                        .padding(.horizontal, 14)
                        .padding(.top, 6)

                        // 2. Tag Filter Flow
                        let allTags = extractTags(from: store.entries)
                        if !allTags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    TagChipButton(
                                        title: L10n.string(.journalAllTags, language: language),
                                        isActive: selectedTag == nil
                                    ) {
                                        selectedTag = nil
                                    }

                                    ForEach(allTags, id: \.self) { tag in
                                        TagChipButton(
                                            title: tag,
                                            isActive: selectedTag == tag
                                        ) {
                                            selectedTag = (selectedTag == tag) ? nil : tag
                                        }
                                    }
                                }
                                .padding(.horizontal, 14)
                            }
                        }

                        // 3. Month-Sectioned Day Cards
                        let filteredEntries = store.entries.filter { entry in
                            guard let tag = selectedTag else { return true }
                            return entry.items.contains { $0.tag == tag }
                        }

                        if filteredEntries.isEmpty {
                            VStack(spacing: 8) {
                                Text(L10n.string(.journalFilterEmptyTitle, language: language))
                                    .font(.system(.subheadline, design: .serif))
                                    .foregroundColor(PhoneTheme.inkTertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(filteredEntries) { entry in
                                    NavigationLink(value: entry.dayKey) {
                                        DayCardView(
                                            entry: entry,
                                            pnl: exchangeCoordinator.pnl(for: entry.date),
                                            closedCount: exchangeCoordinator.closedCount(for: entry.dayKey),
                                            language: language
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 14)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .background(PhoneTheme.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { dayKey in
                if let entry = store.entries.first(where: { $0.dayKey == dayKey }) {
                    EditorView(entry: entry)
                }
            }
            .alert(
                nameAlertMode == .rename ? L10n.string(.journalLibraryRenameTitle, language: language) : L10n.string(.journalLibraryNewTitle, language: language),
                isPresented: $showNameAlert
            ) {
                TextField(L10n.string(.journalLibraryNamePlaceholder, language: language), text: $nameDraft)
                Button(nameAlertMode == .rename ? L10n.string(.journalLibrarySaveName, language: language) : L10n.string(.journalLibraryCreate, language: language)) {
                    switch nameAlertMode {
                    case .rename:
                        if let id = store.activeJournalID {
                            store.renameJournal(id: id, to: nameDraft)
                        }
                    case .new:
                        store.createJournal(name: nameDraft)
                    }
                }
                Button(L10n.string(.cancel, language: language), role: .cancel) {}
            }
            .confirmationDialog(
                L10n.string(.journalLibraryDeleteConfirm, language: language),
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button(L10n.string(.journalLibraryDelete, language: language), role: .destructive) {
                    if let id = store.activeJournalID {
                        _ = store.deleteJournal(id: id)
                    }
                }
                Button(L10n.string(.cancel, language: language), role: .cancel) {}
            } message: {
                Text(language == .chinese ? "将删除「\(store.activeJournal?.name ?? "")」在本机的全部内容，且不可撤销。" : "This will permanently delete \"\(store.activeJournal?.name ?? "")\" on this device.")
            }
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

            Button("\(L10n.string(.journalLibraryNewTitle, language: language))…") {
                nameAlertMode = .new
                nameDraft = ""
                showNameAlert = true
            }
            Button("\(L10n.string(.journalLibraryRenameTitle, language: language))…") {
                nameAlertMode = .rename
                nameDraft = store.activeJournal?.name ?? ""
                showNameAlert = true
            }
            Button("\(L10n.string(.journalLibraryDelete, language: language))…", role: .destructive) {
                showDeleteConfirm = true
            }
            .disabled(store.journals.count <= 1)
        } label: {
            HStack(spacing: 3) {
                Text(store.activeJournal?.name ?? L10n.string(.journalLibraryDefaultName, language: language))
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundColor(PhoneTheme.inkPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(PhoneTheme.cinnabar)
            }
        }
    }

    private func extractTags(from entries: [JournalEntry]) -> [String] {
        var set = Set<String>()
        var list: [String] = []
        for entry in entries {
            for item in entry.items {
                let t = item.tag.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty && set.insert(t).inserted {
                    list.append(t)
                }
            }
        }
        return list
    }
}

// MARK: - Subcomponents

private struct TagChipButton: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: isActive ? .bold : .medium))
                .foregroundColor(isActive ? Color(red: 0.98, green: 0.95, blue: 0.90) : PhoneTheme.inkSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(isActive ? PhoneTheme.cinnabar : PhoneTheme.paperHi)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(isActive ? PhoneTheme.cinnabar : PhoneTheme.rule, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct MonthGridCell: Identifiable {
    let id: Int
    let date: Date?
}

private struct PnlHeatmapCard: View {
    @Binding var currentMonth: Date
    let entries: [JournalEntry]
    @ObservedObject var exchangeCoordinator: PhoneExchangeCoordinator
    let language: AppLanguage
    let onSelectDay: (String) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)
    private var weekHeaders: [String] {
        language == .chinese ? ["一", "二", "三", "四", "五", "六", "日"] : ["M", "T", "W", "T", "F", "S", "S"]
    }

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Text(Self.monthDisplay(for: currentMonth, language: language))
                    .font(.system(size: 13, weight: .bold, design: .serif))
                    .foregroundColor(PhoneTheme.inkPrimary)

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        shiftMonth(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(PhoneTheme.inkSecondary)
                    }

                    Button {
                        shiftMonth(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(PhoneTheme.inkSecondary)
                    }
                }
            }

            // Mon-Sun Week Header
            HStack {
                ForEach(weekHeaders, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(PhoneTheme.inkTertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Month Grid
            let cells = generateDaysInMonth(for: currentMonth)
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(cells) { cell in
                    gridCellView(for: cell)
                }
            }
        }
        .padding(12)
        .background(PhoneTheme.paperHi)
        .cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
    }

    @ViewBuilder
    private func gridCellView(for cell: MonthGridCell) -> some View {
        if let date = cell.date {
            let dayKey = JournalDayKey.make(from: date)
            let hasEntry = entries.contains { $0.dayKey == dayKey }
            let isToday = Calendar.current.isDateInToday(date)
            let dayNum = Calendar.current.component(.day, from: date)
            let pnl = exchangeCoordinator.pnl(for: date)

            Button {
                onSelectDay(dayKey)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(cellBackground(hasEntry: hasEntry, pnl: pnl))
                        .aspectRatio(1, contentMode: .fill)

                    if isToday {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(PhoneTheme.ember, lineWidth: 1.5)
                    }

                    Text("\(dayNum)")
                        .font(.system(size: 9.5, weight: (hasEntry || pnl != nil) ? .bold : .regular, design: .monospaced))
                        .foregroundColor(cellTextColor(hasEntry: hasEntry, pnl: pnl))
                }
            }
            .buttonStyle(.plain)
        } else {
            Color.clear
                .aspectRatio(1, contentMode: .fill)
        }
    }

    private func cellBackground(hasEntry: Bool, pnl: Double?) -> Color {
        if let pnl {
            return PhoneTheme.pnlColorSoft(isGain: pnl >= 0)
        }
        if hasEntry {
            return PhoneTheme.stain
        }
        return Color.black.opacity(0.03)
    }

    private func cellTextColor(hasEntry: Bool, pnl: Double?) -> Color {
        if let pnl {
            return PhoneTheme.pnlColor(isGain: pnl >= 0)
        }
        return hasEntry ? PhoneTheme.inkPrimary : PhoneTheme.inkTertiary
    }

    private func shiftMonth(by delta: Int) {
        if let newMonth = Calendar.current.date(byAdding: .month, value: delta, to: currentMonth) {
            currentMonth = newMonth
        }
    }

    private func generateDaysInMonth(for month: Date) -> [MonthGridCell] {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday start

        guard let monthInterval = cal.dateInterval(of: .month, for: month),
              let firstDay = cal.date(from: cal.dateComponents([.year, .month], from: monthInterval.start))
        else { return [] }

        let firstWeekday = cal.component(.weekday, from: firstDay) // Sunday = 1, Monday = 2
        let offset = (firstWeekday + 5) % 7 // Days before 1st of month in Monday-first layout

        let numberOfDays = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        var cells: [MonthGridCell] = []
        var idCounter = 0

        for _ in 0..<offset {
            cells.append(MonthGridCell(id: idCounter, date: nil))
            idCounter += 1
        }

        for day in 1...numberOfDays {
            let date = cal.date(byAdding: .day, value: day - 1, to: firstDay)
            cells.append(MonthGridCell(id: idCounter, date: date))
            idCounter += 1
        }
        return cells
    }

    private static func monthDisplay(for date: Date, language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateFormat = language == .chinese ? "yyyy年 · M月" : "MMM yyyy"
        return formatter.string(from: date)
    }
}

private struct DayCardView: View {
    let entry: JournalEntry
    let pnl: Double?
    let closedCount: Int
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 12) {
            // Day num & relative text
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.dayNum(for: entry.date))
                    .font(.system(size: 20, weight: .black, design: .serif))
                    .foregroundColor(PhoneTheme.inkPrimary)
                Text(Self.relativeDay(for: entry.date, language: language))
                    .font(.system(size: 9.5))
                    .foregroundColor(PhoneTheme.inkTertiary)
            }
            .frame(width: 44, alignment: .leading)

            // Content preview & tags
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.previewText.isEmpty ? (language == .chinese ? "（无正文）" : "(Empty)") : entry.previewText)
                    .font(.system(size: 12.5, design: .serif))
                    .foregroundColor(PhoneTheme.inkPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let pnl {
                        let isGain = pnl >= 0
                        Text("\(isGain ? "+" : "")\(String(format: "%.1f", pnl))")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundColor(PhoneTheme.pnlColor(isGain: isGain))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(PhoneTheme.pnlColorSoft(isGain: isGain))
                            .cornerRadius(2)
                    }

                    ForEach(Array(entry.items.prefix(2))) { item in
                        if !item.tag.isEmpty {
                            Text(item.tag)
                                .font(.system(size: 9.5, weight: .bold, design: .serif))
                                .foregroundColor(PhoneTheme.cinnabar)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(PhoneTheme.cinnabarSoft)
                                .cornerRadius(2)
                        }
                    }
                    Text(String(format: L10n.string(.recordsCountFormat, language: language), entry.items.count))
                        .font(.system(size: 9.5))
                        .foregroundColor(PhoneTheme.inkTertiary)
                }
            }

            Spacer()

            // Review stamp badge if any item reviewed
            if let reviewedItem = entry.items.first(where: { $0.review != nil }),
               let review = reviewedItem.review {
                JournalReviewBadge(verdict: review.verdict, style: .mini, size: 22, language: language)
            }
        }
        .padding(12)
        .background(PhoneTheme.paperHi)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(PhoneTheme.rule, lineWidth: 1)
        )
    }

    private static func dayNum(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private static func relativeDay(for date: Date, language: AppLanguage) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return L10n.string(.journalToday, language: language) }
        if cal.isDateInYesterday(date) { return L10n.string(.journalYesterday, language: language) }
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}
