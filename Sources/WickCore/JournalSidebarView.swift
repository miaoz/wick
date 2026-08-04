import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Timeline

struct JournalTimelineSidebar: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: JournalStore
    @Environment(\.wickPalette) private var palette

    @State private var tagsExpanded = false
    @State private var tagAreaWidth: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            if store.isItemScoped {
                itemScopedList
            } else {
                dayScopedList
            }
        }
        .background(palette.sidebarBackground.color)
        .onChange(of: store.searchText) { _ in
            store.handleFilterChange()
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    L10n.string(.journalSearchPlaceholder, language: settings.language),
                    text: $store.searchText
                )
                .textFieldStyle(.plain)

                if !store.searchText.isEmpty {
                    Button {
                        store.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            if !store.allTags.isEmpty {
                tagFlowSection
            }
        }
        .padding(12)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { tagAreaWidth = proxy.size.width - 24 }
                    .onChange(of: proxy.size.width) { tagAreaWidth = $0 - 24 }
            }
        )
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
                    ForEach(daySections, id: \.title) { section in
                        Section(section.title) {
                            ForEach(section.entries) { entry in
                                JournalDayTimelineRow(entry: entry)
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
                        }
                    }
                }
                .listStyle(.sidebar)
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

    private struct DaySection {
        let title: String
        let entries: [JournalEntry]
    }

    private struct ItemSection {
        let title: String
        let items: [JournalTimelineItem]
    }

    private var daySections: [DaySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: store.filteredEntries) {
            calendar.startOfDay(for: $0.date)
        }
        return grouped.keys.sorted(by: >).map { day in
            DaySection(
                title: dayTitle(day),
                entries: (grouped[day] ?? []).sorted { $0.updatedAt > $1.updatedAt }
            )
        }
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

    /// Soft, theme-driven selection pill. Replaces the system highlight,
    /// which is bright blue on recent macOS and gray on macOS 13.
    /// The opaque `sidebarBackground` underlay hides the system pill even
    /// if it is still drawn beneath the custom background.
    @ViewBuilder
    private func selectionRowBackground(isSelected: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.sidebarBackground.color)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.accentSoft.color)
                )
                .padding(.horizontal, 4)
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

    private func tagChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? palette.accentSoft.color : Color.primary.opacity(0.06))
                )
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            isSelected ? palette.accent.color.opacity(0.45) : Color.primary.opacity(0.08),
                            lineWidth: 1
                        )
                }
                .foregroundStyle(isSelected ? palette.accentText.color : Color.primary.opacity(0.8))
        }
        .buttonStyle(.plain)
    }

    // MARK: Tag flow

    /// Chips wrap over multiple rows; collapsed to a single row with a
    /// trailing "N more" chip when they exceed the sidebar width.
    private var tagFlowSection: some View {
        let chips = [FlowChip(kind: .all, title: L10n.string(.journalAllTags, language: settings.language))]
            + store.allTags.map { FlowChip(kind: .tag($0), title: $0) }
        let items = chips.map(\.item)
        let lessChip = FlowChip(
            kind: .less,
            title: L10n.string(.journalTagsCollapse, language: settings.language)
        )

        let rows: [[TagChipItem]]
        var lookupChips = chips
        var collapsed: (row: [TagChipItem], hiddenCount: Int)?
        if tagsExpanded {
            rows = TagChipFlow.rows(items: items + [lessChip.item], availableWidth: tagAreaWidth)
            lookupChips.append(lessChip)
        } else if let trimmed = TagChipFlow.collapsedRow(
            items: items,
            availableWidth: tagAreaWidth,
            toggleWidth: { hidden in
                JournalTimelineSidebar.chipWidth(
                    for: String(
                        format: L10n.string(.journalTagsMoreFormat, language: settings.language),
                        hidden
                    )
                )
            }
        ) {
            collapsed = trimmed
            rows = [trimmed.row]
        } else {
            rows = TagChipFlow.rows(items: items, availableWidth: tagAreaWidth)
        }

        return VStack(alignment: .leading, spacing: TagChipFlow.spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: TagChipFlow.spacing) {
                    ForEach(row, id: \.id) { item in
                        flowChipView(for: item.id, chips: lookupChips)
                    }
                    if let collapsed, index == 0 {
                        moreChip(hiddenCount: collapsed.hiddenCount)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func flowChipView(for id: String, chips: [FlowChip]) -> some View {
        switch chips.first(where: { $0.id == id })?.kind {
        case .all:
            tagChip(
                title: L10n.string(.journalAllTags, language: settings.language),
                isSelected: store.selectedTagFilter == nil
            ) {
                store.setTagFilter(nil)
            }
        case .tag(let tag):
            tagChip(
                title: tag,
                isSelected: store.selectedTagFilter?.lowercased() == tag.lowercased()
            ) {
                if store.selectedTagFilter?.lowercased() == tag.lowercased() {
                    store.setTagFilter(nil)
                } else {
                    store.setTagFilter(tag)
                }
            }
        case .less:
            tagChip(
                title: L10n.string(.journalTagsCollapse, language: settings.language),
                isSelected: false
            ) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    tagsExpanded = false
                }
            }
        case nil:
            EmptyView()
        }
    }

    private func moreChip(hiddenCount: Int) -> some View {
        tagChip(
            title: String(
                format: L10n.string(.journalTagsMoreFormat, language: settings.language),
                hiddenCount
            ),
            isSelected: false
        ) {
            withAnimation(.easeInOut(duration: 0.18)) {
                tagsExpanded = true
            }
        }
    }

    private struct FlowChip: Equatable {
        enum Kind: Equatable {
            case all
            case tag(String)
            case less
        }

        let kind: Kind
        let title: String

        var id: String {
            switch kind {
            case .all: return "#all"
            case .tag(let tag): return tag
            case .less: return "#less"
            }
        }

        var item: TagChipItem {
            TagChipItem(id: id, width: JournalTimelineSidebar.chipWidth(for: title))
        }
    }

    private static let chipFont = NSFont.systemFont(ofSize: 11, weight: .semibold)

    /// Matches `tagChip` metrics: 11pt text, 10pt horizontal padding, 1pt stroke.
    private static func chipWidth(for title: String) -> CGFloat {
        ceil((title as NSString).size(withAttributes: [.font: chipFont]).width) + 22
    }
}

struct JournalDayTimelineRow: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.wickPalette) private var palette
    let entry: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(rowTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if entry.items.count > 1 {
                    Text("\(entry.items.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
                if !entry.allImageFilenames.isEmpty {
                    Label("\(entry.allImageFilenames.count)", systemImage: "photo")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }

            if !entry.tags.isEmpty {
                Text(entry.tags.joined(separator: "  "))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.accentText.color)
                    .lineLimit(1)
            }

            if !entry.previewBody.isEmpty {
                Text(entry.previewBody)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var rowTitle: String {
        let preview = entry.previewText
        if preview.isEmpty {
            return L10n.string(.journalUntitled, language: settings.language)
        }
        return preview
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
                    JournalReviewBadge(verdict: review.verdict, style: .mini)
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

