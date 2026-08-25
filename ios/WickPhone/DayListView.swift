import SwiftUI
import WickCalendarKit
import WickSync
import WickTrading

/// Tab 2: "日记" (Journal day list + PnL Heatmap).
/// Includes journal switcher, compact monthly heatmap with realized PnL, tag filter chips, and month-sectioned day cards.
struct DayListView: View {
    @EnvironmentObject private var store: PhoneJournalStore
    @EnvironmentObject private var sync: PhoneSyncCoordinator
    @EnvironmentObject private var exchangeCoordinator: PhoneExchangeCoordinator
    @Environment(\.appLanguage) private var language: AppLanguage

    @State private var selectedTag: String? = nil
    @State private var heatmapMonth = Date()
    @State private var navigationPath = NavigationPath()
    @State private var showJournalManager = false

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
                    Button {
                        showJournalManager = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(store.activeJournal?.name ?? L10n.string(.journalLibraryDefaultName, language: language))
                                .font(PhoneFont.paper(15, weight: .bold))
                                .foregroundColor(PhoneTheme.inkPrimary)
                            Image(systemName: "chevron.down")
                                .font(PhoneFont.ui(10, weight: .bold))
                                .foregroundColor(PhoneTheme.cinnabar)
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(PhoneTheme.paperHi)
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Spacer()
                    Button {
                        let entry = store.openOrCreateToday()
                        navigationPath.append(entry.id)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(PhoneFont.ui(12, weight: .bold))
                            Text(L10n.string(.journalToday, language: language))
                                .font(PhoneFont.paper(11.5, weight: .bold))
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

                List {
                    // 1. Compact PnL Heatmap Card & Tag Filter
                    Section {
                        PnlHeatmapCard(
                            currentMonth: $heatmapMonth,
                            entries: store.entries,
                            exchangeCoordinator: exchangeCoordinator,
                            language: language,
                            onSelectDay: { dayKey in
                                if let entry = store.entries.first(where: {
                                    JournalDayKey.make(from: $0.date) == dayKey
                                }) {
                                    navigationPath.append(entry.id)
                                } else {
                                    let newEntry = store.openOrCreateToday()
                                    navigationPath.append(newEntry.id)
                                }
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

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
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 6, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }

                    // 2. Month-Sectioned Day Cards with Swipe-to-Delete
                    Section {
                        let filteredEntries = store.entries.filter { entry in
                            guard let tag = selectedTag else { return true }
                            return entry.items.contains { $0.tag == tag }
                        }

                        if filteredEntries.isEmpty {
                            VStack(spacing: 8) {
                                Text(L10n.string(.journalFilterEmptyTitle, language: language))
                                    .font(PhoneFont.preset(.subheadline))
                                    .foregroundColor(PhoneTheme.inkTertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        } else {
                            ForEach(filteredEntries) { entry in
                                ZStack {
                                    DayCardView(
                                        entry: entry,
                                        pnl: exchangeCoordinator.pnl(for: entry.date),
                                        closedCount: exchangeCoordinator.closedCount(
                                            for: JournalDayKey.make(from: entry.date)
                                        ),
                                        language: language
                                    )

                                    NavigationLink(value: entry.id) {
                                        EmptyView()
                                    }
                                    .opacity(0)
                                }
                                .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        withAnimation {
                                            store.deleteEntry(entryID: entry.id)
                                        }
                                    } label: {
                                        Label(L10n.string(.journalDelete, language: language), systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .background(PhoneTheme.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { entryID in
                if let entry = store.entries.first(where: { $0.id == entryID }) {
                    EditorView(entry: entry)
                }
            }
            .sheet(isPresented: $showJournalManager) {
                JournalManagerSheet(store: store, language: language)
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
                .font(PhoneFont.paper(11.5, weight: isActive ? .bold : .medium))
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
    let id: String
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
            // Header: Left Chevron + Centered Month Title + Right Chevron
            HStack {
                Button {
                    shiftMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(PhoneFont.ui(11.5, weight: .bold))
                        .foregroundColor(PhoneTheme.inkSecondary)
                        .frame(width: 36, height: 28, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)

                Spacer(minLength: 8)

                Text(Self.monthDisplay(for: currentMonth, language: language))
                    .font(PhoneFont.paper(13, weight: .bold))
                    .foregroundColor(PhoneTheme.inkPrimary)

                Spacer(minLength: 8)

                Button {
                    shiftMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(PhoneFont.ui(11.5, weight: .bold))
                        .foregroundColor(PhoneTheme.inkSecondary)
                        .frame(width: 36, height: 28, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(!canGoForward)
                .opacity(canGoForward ? 1 : 0.25)
            }

            // Month Total Row (已实现合计)
            monthTotalRow

            // Mon-Sun Week Header
            HStack {
                ForEach(weekHeaders, id: \.self) { day in
                    Text(day)
                        .font(PhoneFont.ui(8.5, weight: .semibold))
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
            let hasEntry = entries.contains { JournalDayKey.make(from: $0.date) == dayKey }
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
                        .font(PhoneFont.ui(9.5, weight: (hasEntry || pnl != nil) ? .bold : .regular, monospacedDigit: true))
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
        let cal = Calendar.current
        let start = Self.monthStart(of: currentMonth, calendar: cal)
        if let newMonth = cal.date(byAdding: .month, value: delta, to: start) {
            currentMonth = newMonth
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
    }

    private func generateDaysInMonth(for month: Date) -> [MonthGridCell] {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday start

        let firstDay = Self.monthStart(of: month, calendar: cal)
        let monthKey = Self.monthKey(for: firstDay)
        let firstWeekday = cal.component(.weekday, from: firstDay) // Sunday = 1, Monday = 2
        let offset = (firstWeekday + 5) % 7 // Days before 1st of month in Monday-first layout

        let numberOfDays = cal.range(of: .day, in: .month, for: firstDay)?.count ?? 30
        var cells: [MonthGridCell] = []

        for i in 0..<offset {
            cells.append(MonthGridCell(id: "\(monthKey)-pad-\(i)", date: nil))
        }

        for day in 1...numberOfDays {
            let date = cal.date(byAdding: .day, value: day - 1, to: firstDay)
            cells.append(MonthGridCell(id: "\(monthKey)-day-\(day)", date: date))
        }
        return cells
    }

    /// 「已实现合计 +1,204.6」(单据等宽数字,红盈黛亏;全零不占版)。
    @ViewBuilder
    private var monthTotalRow: some View {
        if let total = monthTotal {
            HStack {
                Text(L10n.string(.inspectorMonthTotal, language: language))
                    .font(PhoneFont.ui(10, weight: .medium, monospacedDigit: true))
                    .foregroundColor(PhoneTheme.inkTertiary)
                Spacer()
                Text(Self.format(pnl: total))
                    .font(PhoneFont.ui(12.5, weight: .bold, monospacedDigit: true))
                    .foregroundColor(PhoneTheme.pnlColor(isGain: total >= 0))
            }
            .padding(.top, -2)
        }
    }

    private var monthTotal: Double? {
        let calendar = Calendar.current
        let days = exchangeCoordinator.pnlByDay
        let values = days.filter { calendar.isDate($0.key, equalTo: currentMonth, toGranularity: .month) }
            .map(\.value)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    private var canGoForward: Bool {
        let calendar = Calendar.current
        let currentMonthStart = Self.monthStart(of: currentMonth, calendar: calendar)
        let thisMonthStart = Self.monthStart(of: Date(), calendar: calendar)
        return currentMonthStart < thisMonthStart
    }

    private static func monthStart(of date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private static func monthKey(for date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        return fmt.string(from: date)
    }

    private static let pnlFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static func format(pnl: Double) -> String {
        let sign = pnl >= 0 ? "+" : "−"
        let digits = pnlFormatter.string(from: NSNumber(value: pnl.magnitude)) ?? "0"
        return sign + digits
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
                    .font(PhoneFont.paper(20, weight: .black))
                    .foregroundColor(PhoneTheme.inkPrimary)
                Text(Self.relativeDay(for: entry.date, language: language))
                    .font(PhoneFont.ui(9.5))
                    .foregroundColor(PhoneTheme.inkTertiary)
            }
            .frame(width: 44, alignment: .leading)

            // Content preview & tags
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.previewText.isEmpty ? (language == .chinese ? "（无正文）" : "(Empty)") : entry.previewText)
                    .font(PhoneFont.paper(12.5))
                    .foregroundColor(PhoneTheme.inkPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let pnl {
                        let isGain = pnl >= 0
                        Text("\(isGain ? "+" : "")\(String(format: "%.1f", pnl))")
                            .font(PhoneFont.ui(9.5, weight: .bold, monospacedDigit: true))
                            .foregroundColor(PhoneTheme.pnlColor(isGain: isGain))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(PhoneTheme.pnlColorSoft(isGain: isGain))
                            .cornerRadius(2)
                    }

                    ForEach(Array(entry.items.prefix(2))) { item in
                        if !item.tag.isEmpty {
                            Text(item.tag)
                                .font(PhoneFont.paper(9.5, weight: .bold))
                                .foregroundColor(PhoneTheme.cinnabar)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(PhoneTheme.cinnabarSoft)
                                .cornerRadius(2)
                        }
                    }
                    Text(String(format: L10n.string(.recordsCountFormat, language: language), entry.items.count))
                        .font(PhoneFont.ui(9.5))
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

private struct JournalManagerSheet: View {
    @ObservedObject var store: PhoneJournalStore
    let language: AppLanguage
    @Environment(\.dismiss) private var dismiss

    @State private var showNewJournalAlert = false
    @State private var newJournalName = ""
    @State private var renamingJournal: JournalInfo?
    @State private var renameJournalDraft = ""
    @State private var deletingJournal: JournalInfo?
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.journals) { journal in
                        let isActive = journal.id == store.activeJournalID
                        HStack(spacing: 12) {
                            // Active status icon
                            if isActive {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(PhoneFont.ui(14, weight: .bold))
                                    .foregroundColor(PhoneTheme.cinnabar)
                            } else {
                                Image(systemName: "circle")
                                    .font(PhoneFont.ui(14))
                                    .foregroundColor(PhoneTheme.inkTertiary.opacity(0.4))
                            }

                            // Journal Name in user's custom selected font!
                            Text(journal.name)
                                .font(PhoneFont.paper(16, weight: isActive ? .bold : .medium))
                                .foregroundColor(isActive ? PhoneTheme.inkPrimary : PhoneTheme.inkSecondary)

                            Spacer()

                            if isActive {
                                Text(language == .chinese ? "当前使用" : "Active")
                                    .font(PhoneFont.ui(10.5, weight: .medium))
                                    .foregroundColor(PhoneTheme.cinnabar)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(PhoneTheme.cinnabarSoft)
                                    .cornerRadius(3)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if store.activeJournalID != journal.id {
                                store.switchToJournal(id: journal.id)
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                            }
                            dismiss()
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if store.journals.count > 1 {
                                Button(role: .destructive) {
                                    deletingJournal = journal
                                    showDeleteConfirm = true
                                } label: {
                                    Label(L10n.string(.journalLibraryDelete, language: language), systemImage: "trash")
                                }
                            }

                            Button {
                                renamingJournal = journal
                                renameJournalDraft = journal.name
                            } label: {
                                Label(L10n.string(.journalLibraryRenameTitle, language: language), systemImage: "pencil")
                            }
                            .tint(PhoneTheme.char)
                        }
                        .contextMenu {
                            Button {
                                renamingJournal = journal
                                renameJournalDraft = journal.name
                            } label: {
                                Label(L10n.string(.journalLibraryRenameTitle, language: language), systemImage: "pencil")
                            }

                            if store.journals.count > 1 {
                                Button(role: .destructive) {
                                    deletingJournal = journal
                                    showDeleteConfirm = true
                                } label: {
                                    Label(L10n.string(.journalLibraryDelete, language: language), systemImage: "trash")
                                }
                            }
                        }
                    }
                    .onMove { indices, newOffset in
                        store.moveJournal(from: indices, to: newOffset)
                    }
                } footer: {
                    Text(language == .chinese ? "长按并拖拽可调整日记本排序；左滑可重命名或删除。" : "Long press and drag to reorder journals; swipe left to rename or delete.")
                        .font(PhoneFont.paper(11))
                        .foregroundColor(PhoneTheme.inkTertiary)
                        .padding(.top, 6)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(PhoneTheme.paper.ignoresSafeArea())
            .navigationTitle(Text(language == .chinese ? "日记本" : "Journals"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        newJournalName = ""
                        showNewJournalAlert = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(PhoneFont.ui(11, weight: .bold))
                            Text(L10n.string(.journalLibraryNewTitle, language: language))
                                .font(PhoneFont.paper(13, weight: .bold))
                        }
                        .foregroundColor(PhoneTheme.cinnabar)
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string(.ok, language: language)) {
                        dismiss()
                    }
                    .font(PhoneFont.paper(13, weight: .bold))
                    .foregroundColor(PhoneTheme.inkPrimary)
                }
            }
            .alert(
                L10n.string(.journalLibraryNewTitle, language: language),
                isPresented: $showNewJournalAlert
            ) {
                TextField(L10n.string(.journalLibraryNamePlaceholder, language: language), text: $newJournalName)
                Button(L10n.string(.journalLibraryCreate, language: language)) {
                    let trimmed = newJournalName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        _ = store.createJournal(name: trimmed)
                    }
                }
                Button(L10n.string(.cancel, language: language), role: .cancel) {}
            }
            .alert(
                L10n.string(.journalLibraryRenameTitle, language: language),
                isPresented: Binding(
                    get: { renamingJournal != nil },
                    set: { if !$0 { renamingJournal = nil } }
                )
            ) {
                TextField(L10n.string(.journalLibraryNamePlaceholder, language: language), text: $renameJournalDraft)
                Button(L10n.string(.journalLibrarySaveName, language: language)) {
                    if let target = renamingJournal {
                        let trimmed = renameJournalDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            store.renameJournal(id: target.id, to: trimmed)
                        }
                        renamingJournal = nil
                    }
                }
                Button(L10n.string(.cancel, language: language), role: .cancel) {
                    renamingJournal = nil
                }
            }
            .confirmationDialog(
                L10n.string(.journalLibraryDeleteConfirm, language: language),
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button(L10n.string(.journalLibraryDelete, language: language), role: .destructive) {
                    if let target = deletingJournal {
                        _ = store.deleteJournal(id: target.id)
                        deletingJournal = nil
                    }
                }
                Button(L10n.string(.cancel, language: language), role: .cancel) {
                    deletingJournal = nil
                }
            } message: {
                Text(language == .chinese ? "将删除「\(deletingJournal?.name ?? "")」在本机的全部内容，且不可撤销。" : "This will permanently delete \"\(deletingJournal?.name ?? "")\" on this device.")
            }
        }
    }
}
