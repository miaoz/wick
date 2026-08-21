import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WickSync
import WickTrading

// MARK: - 栏一 · 导航侧栏(秉烛 v1.0)
//
// 盈亏月历(彩蛋开启时)· 日记本 · 标签签条。搜索移到了顶栏;
// 月历在默认(彩蛋关)时住在右栏检查器下半栏(见 final.html §00 修订)。

struct JournalNavigationSidebar: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: JournalStore
    @Environment(\.wickPalette) private var palette

    let onNewJournal: () -> Void
    let onRenameJournal: (JournalInfo) -> Void
    let onDeleteJournal: (JournalInfo) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if settings.physicalCalendarEnabled {
                // 彩蛋开启:主窗退为纯三栏,月历回导航栏顶部(现状位置)。
                JournalPnlCalendarView()
                    .padding(.horizontal, 4)
            }

            sideSection(
                L10n.string(.inspectorJournalsSection, language: settings.language),
                onAdd: onNewJournal,
                addHelp: L10n.string(.journalLibraryNew, language: settings.language)
            ) {
                ForEach(store.journals) { journal in
                    Button {
                        store.switchToJournal(id: journal.id)
                    } label: {
                        HStack(spacing: 8) {
                            Text(journal.name)
                                .font(.system(size: 13, weight: journal.id == store.activeJournalID ? .semibold : .regular, design: .rounded))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if journal.id == store.activeJournalID {
                                Text(L10n.string(.sidebarTodayMark, language: settings.language))
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color(red: 1, green: 0.95, blue: 0.88).opacity(0.85))
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .foregroundStyle(journal.id == store.activeJournalID ? Color(red: 1, green: 0.95, blue: 0.88) : palette.textPrimary.color)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(journal.id == store.activeJournalID ? palette.accent.color : .clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 4)
                    .contextMenu {
                        Button { onRenameJournal(journal) } label: {
                            Text(L10n.string(.journalLibraryRename, language: settings.language))
                        }
                        if store.journals.count > 1 {
                            Button(role: .destructive) { onDeleteJournal(journal) } label: {
                                Text(L10n.string(.journalLibraryDelete, language: settings.language))
                            }
                        }
                    }
                }
            }

            if !store.allTags.isEmpty {
                sideSection(L10n.string(.inspectorTagsSection, language: settings.language)) {
                    sidebarTagFlow
                }
            }

            Spacer(minLength: 0)
        }
        // 文字左缘落 x=10,与首颗红绿灯左缘(x≈9)对齐(v4 同此关系:灯 18 / 文 20);
        // 行 pill 自带 4pt 外边距,不与窗缘相切。
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.sidebarBackground.color)
    }

    private func sideSection<Content: View>(
        _ title: String,
        onAdd: (() -> Void)? = nil,
        addHelp: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(palette.textTertiary.color)
                Spacer(minLength: 4)
                if let onAdd {
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.textTertiary.color)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(addHelp ?? "")
                }
            }
            .padding(.horizontal, 10)
            content()
        }
    }

    // MARK: 标签签条(宋体 + 朱砂,方角)

    private var sidebarTagFlow: some View {
        let tags = store.allTags
        return SidebarChipFlow(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                sidebarTagChip(tag)
            }
        }
        .padding(.horizontal, 10)
    }

    private func sidebarTagChip(_ tag: String) -> some View {
        let isSelected = store.selectedTagFilter?.lowercased() == tag.lowercased()
        return Button {
            store.setTagFilter(isSelected ? nil : tag)
        } label: {
            Text(tag)
                .font(.custom("Songti SC", size: 11).weight(isSelected ? .bold : .medium))
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color(red: 0.98, green: 0.92, blue: 0.85) : palette.pnlUp.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isSelected ? palette.pnlUp.color : .clear)
                .overlay {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(palette.pnlUp.color.opacity(isSelected ? 1 : 0.8), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// 签条贪心换行布局(macOS 13+ Layout):逐条量宽、放不下就换行,
/// 超长签条按栏宽截断(…)。LazyVGrid adaptive 的等宽列会让长签条
/// 溢出列框、拖栏时与邻签重叠,故不用。
private struct SidebarChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var height: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            size.width = min(size.width, maxWidth)
            if x > 0, x + size.width > maxWidth {
                x = 0
                height += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }
        return CGSize(width: min(usedWidth, maxWidth), height: height + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            size.width = min(size.width, bounds.width)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - 栏二 · 日期列表

struct JournalDayListColumn: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: JournalStore
    @Environment(\.wickPalette) private var palette
    @ObservedObject private var positionCoordinator = ExchangePositionCoordinator.shared

    var body: some View {
        VStack(spacing: 0) {
            if store.isItemScoped {
                listHeader
                Divider().overlay(palette.divider.color)
            }
            if store.isItemScoped {
                itemScopedList
            } else {
                dayScopedList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.columnPaper.color)
        .onChange(of: store.searchText) { _ in
            store.handleFilterChange()
        }
    }

    private var listHeader: some View {
        HStack {
            Text(store.selectedTagFilter ?? L10n.string(.inspectorEntriesSection, language: settings.language))
                .font(.custom("Songti SC", size: 12).weight(.bold))
                .foregroundStyle(palette.textPrimary.color)
            Spacer()
            Text("\(store.filteredEntries.count)")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.textTertiary.color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var dayScopedList: some View {
        Group {
            if store.filteredEntries.isEmpty {
                emptyState
            } else {
                List(selection: Binding(
                    get: {
                        if case .day(let id) = store.selection { return id }
                        return nil
                    },
                    set: { store.selectDay($0) }
                )) {
                    ForEach(daySections) { section in
                        Section {
                            ForEach(section.entries) { entry in
                                JournalDayTimelineRow(
                                    entry: entry,
                                    dayPnL: pnlByDay[Calendar.current.startOfDay(for: entry.date)],
                                    closedPositions: closedPositionsByDayKey[entry.dayKey],
                                    showsPositionStats: positionCoordinator.snapshot != nil
                                )
                                .tag(entry.id)
                                .listRowBackground(selectionRowBackground(isSelected: isDaySelected(entry.id)))
                                .contextMenu {
                                    Button(role: .destructive) {
                                        store.deleteEntry(id: entry.id)
                                    } label: {
                                        Text(L10n.string(.journalDelete, language: settings.language))
                                    }
                                }
                            }
                        } header: {
                            monthSectionHeader(section)
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(TableViewSelectionSuppressor())
            }
        }
    }

    private var itemScopedList: some View {
        Group {
            if store.filteredTimelineItems.isEmpty {
                emptyFilterState
            } else {
                List(selection: Binding(
                    get: {
                        if case .item(let ref) = store.selection { return ref.id }
                        return nil
                    },
                    set: { newID in
                        guard let newID,
                              let row = store.filteredTimelineItems.first(where: { $0.id == newID })
                        else {
                            store.selectItem(nil)
                            return
                        }
                        store.selectItem(row.ref)
                    }
                )) {
                    ForEach(itemSections, id: \.title) { section in
                        Section(section.title) {
                            ForEach(section.items) { row in
                                JournalItemTimelineRow(row: row)
                                    .tag(row.id)
                                    .listRowBackground(selectionRowBackground(isSelected: isItemSelected(row.id)))
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            store.deleteItem(itemID: row.ref.itemID, from: row.ref.entryID)
                                        } label: {
                                            Text(L10n.string(.journalDeleteItem, language: settings.language))
                                        }
                                        Button {
                                            store.selectedTagFilter = nil
                                            store.searchText = ""
                                            store.selectDay(row.ref.entryID)
                                        } label: {
                                            Text(L10n.string(.journalOpenFullDay, language: settings.language))
                                        }
                                    }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(TableViewSelectionSuppressor())
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "book.closed")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text(L10n.string(.journalEmptyTitle, language: settings.language))
                .font(.headline)
            Text(L10n.string(.journalEmptySubtitle, language: settings.language))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button {
                _ = store.openOrCreateToday()
            } label: {
                Text(L10n.string(.journalNewEntry, language: settings.language))
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyFilterState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text(L10n.string(.journalFilterEmptyTitle, language: settings.language))
                .font(.headline)
            Text(L10n.string(.journalFilterEmptySubtitle, language: settings.language))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private struct DaySection: Identifiable {
        /// Month start, stable identity.
        var id: Date { monthStart }
        let monthStart: Date
        /// 月份名(「八月」/ "August")。
        let month: String
        /// 年(等宽小字)。
        let year: String
        let entries: [JournalEntry]
    }

    private struct ItemSection {
        let title: String
        let items: [JournalTimelineItem]
    }

    private var daySections: [DaySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: store.filteredEntries) {
            calendar.date(from: calendar.dateComponents([.year, .month], from: $0.date))
                ?? calendar.startOfDay(for: $0.date)
        }
        return grouped.keys.sorted(by: >).map { month in
            DaySection(
                monthStart: month,
                month: monthName(month),
                year: String(calendar.component(.year, from: month)),
                entries: (grouped[month] ?? []).sorted { $0.date > $1.date }
            )
        }
    }

    /// 按月分组,节头即「八月 2026」(秉烛 v4 列表节头)。
    private func monthSectionHeader(_ section: DaySection) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(section.month)
                .font(.custom("Songti SC", size: 12).weight(.bold))
                .foregroundStyle(palette.textPrimary.color)
            Text(section.year)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(palette.textTertiary.color)
        }
        .padding(.top, 8)
    }

    private func monthName(_ month: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = settings.language.locale
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        return formatter.string(from: month)
    }

    /// 各日已实现盈亏(与盈亏月历同一来源)。
    private var pnlByDay: [Date: Double] {
        DailyRealizedPnl.sumsByDay(
            fills: positionCoordinator.snapshot?.fills ?? [],
            calendar: .current
        )
    }

    /// 开仓日 → 已平仓笔数(对冲双 lane 各自计一笔)。
    private var closedPositionsByDayKey: [String: Int] {
        var counts: [String: Int] = [:]
        for position in positionCoordinator.snapshot?.positions ?? [] where position.isClosed {
            counts[JournalDayKey.make(from: position.openTime), default: 0] += 1
        }
        return counts
    }

    private var itemSections: [ItemSection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: store.filteredTimelineItems) {
            calendar.startOfDay(for: $0.date)
        }
        return grouped.keys.sorted(by: >).map { day in
            ItemSection(title: dayTitle(day), items: grouped[day] ?? [])
        }
    }

    private func isDaySelected(_ id: UUID) -> Bool {
        guard case .day(let selectedID) = store.selection else { return false }
        return selectedID == id
    }

    private func isItemSelected(_ id: String) -> Bool {
        guard case .item(let ref) = store.selection else { return false }
        return ref.id == id
    }

    /// 选中态:页纸高亮 + 左缘 3pt 朱砂印刷界线(秉烛 v4 列表行)。
    /// 不圆角、不胶囊——系统高亮在 macOS 26 是亮蓝、13 是灰,一律压住。
    @ViewBuilder
    private func selectionRowBackground(isSelected: Bool) -> some View {
        if isSelected {
            ZStack(alignment: .leading) {
                palette.pageSurface.color
                Rectangle()
                    .fill(palette.pnlUp.color)
                    .frame(width: 3)
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        let language = settings.language
        if calendar.isDateInToday(day) {
            return L10n.string(.journalToday, language: language)
        }
        if calendar.isDateInYesterday(day) {
            return L10n.string(.journalYesterday, language: language)
        }
        return day.formatted(
            .dateTime
            .year()
            .month()
            .day()
            .weekday(.wide)
            .locale(settings.locale)
        )
    }
}

// MARK: - 列表行

/// 日期行(秉烛 v4 day-row):「8月20日 周四 / 4 条 · 2 笔已平仓」,
/// 右缘等宽盈亏(红盈黛亏,无成交「—」)+ 复盘小章。
struct JournalDayTimelineRow: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.wickPalette) private var palette
    let entry: JournalEntry
    /// 当日已实现盈亏;nil = 无成交。
    let dayPnL: Double?
    /// 当日开仓且已平仓的笔数;nil = 未启用交易所数据。
    let closedPositions: Int?
    /// 交易所快照在场时才显示「· 无持仓 / N 笔已平仓」段。
    let showsPositionStats: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(dayText)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.textPrimary.color)
                    Text(entry.date.formatted(.dateTime.weekday(.abbreviated).locale(settings.locale)))
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textTertiary.color)
                }
                Text(statsLine)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(palette.textTertiary.color)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                if let dayPnL {
                    Text(Self.format(pnl: dayPnL))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(dayPnL >= 0 ? palette.pnlUp.color : palette.pnlDown.color)
                } else {
                    Text("—")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.textTertiary.color)
                }
                if let verdict = entry.items.compactMap(\.review).last?.verdict {
                    JournalReviewBadge(verdict: verdict, style: .mini, size: 20)
                }
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            // 行下发丝分隔线(印刷栏线)。
            Rectangle()
                .fill(palette.divider.color.opacity(0.6))
                .frame(height: 1)
        }
    }

    /// 「8月20日」/ "Aug 20"。
    private var dayText: String {
        let formatter = DateFormatter()
        formatter.locale = settings.language.locale
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: entry.date)
    }

    private var statsLine: String {
        let count = entry.items.count
        if showsPositionStats {
            let closed = closedPositions ?? 0
            if closed > 0 {
                return String(
                    format: L10n.string(.journalDayStatsFormat, language: settings.language),
                    count, closed
                )
            }
            return String(
                format: L10n.string(.journalDayStatsFlatFormat, language: settings.language),
                count
            )
        }
        return String(
            format: L10n.string(.journalItemCountFormat, language: settings.language),
            count
        )
    }

    private static let pnlFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static func format(pnl: Double) -> String {
        let sign = pnl >= 0 ? "+" : "−"
        let digits = pnlFormatter.string(from: NSNumber(value: pnl.magnitude)) ?? "0.00"
        return sign + digits
    }
}

struct JournalItemTimelineRow: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.wickPalette) private var palette
    let row: JournalTimelineItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(tagTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.accentText.color)
                    .lineLimit(1)
                if let review = row.item.review {
                    JournalReviewBadge(verdict: review.verdict, style: .mini, size: 20)
                }
                Spacer(minLength: 8)
                if !row.item.imageFilenames.isEmpty {
                    Label("\(row.item.imageFilenames.count)", systemImage: "photo")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }

            if !row.item.previewText.isEmpty {
                Text(row.item.previewText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if !row.entryTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(row.entryTitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var tagTitle: String {
        let tag = row.item.tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if tag.isEmpty {
            return L10n.string(.journalUntitledItem, language: settings.language)
        }
        return tag
    }
}
