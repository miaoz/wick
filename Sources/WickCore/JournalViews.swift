import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Root

struct JournalRootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: JournalStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var exportStatus: String?
    @State private var showStartFreshConfirm = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        // Low-frequency day-arc palette refresh (5 min granularity is plenty).
        // This only re-resolves colors — it never writes bindings, so IME
        // composition in the editor is unaffected.
        TimelineView(.periodic(from: .now, by: 300)) { _ in
            let palette = DayArcEngine.palette(at: DayArcEngine.currentDate(), scheme: colorScheme)
            chromeContent(palette: palette)
        }
    }

    @ViewBuilder
    private func chromeContent(palette: WickPalette) -> some View {
        let base = Group {
            splitLayout
        }
        .environment(\.wickPalette, palette)
        .tint(palette.accent.color)
        .frame(minWidth: 720, minHeight: 480)
        .preferredColorScheme(settings.preferredColorScheme)
        .background(palette.backgroundBottom.color)
        .safeAreaInset(edge: .top, spacing: 0) {
            if store.isReadOnlyDueToLoadFailure {
                loadFailureBanner
            } else if store.didRestoreFromBackup {
                restoreBanner(palette: palette)
            }
        }
        .confirmationDialog(
            L10n.string(.journalStartFresh, language: settings.language),
            isPresented: $showStartFreshConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.string(.journalStartFresh, language: settings.language), role: .destructive) {
                try? store.abandonCorruptDatabaseAndStartFresh()
            }
            Button(L10n.string(.cancel, language: settings.language), role: .cancel) {}
        }
        .background {
            // Hidden focusable buttons for shortcuts that aren't in the toolbar.
            Button("") {
                focusSearchField()
            }
            .keyboardShortcut("f", modifiers: [.command])
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }

        // macOS 14+ installs a real window toolbar (the split view's own
        // sidebar toggle plus this new-entry item). On macOS 13 nothing
        // materializes in this manually created window, so the panes render
        // their own in-view top strips instead (see `journalNeedsInViewTopBar`).
        if journalNeedsInViewTopBar {
            base
        } else {
            base.toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        _ = store.openOrCreateToday()
                    } label: {
                        Label(
                            L10n.string(.journalNewEntry, language: settings.language),
                            systemImage: "square.and.pencil"
                        )
                    }
                    .help(L10n.string(.journalNewEntry, language: settings.language))
                    .keyboardShortcut("n", modifiers: [.command])
                }
            }
        }
    }

    private var loadFailureBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string(.journalLoadFailureTitle, language: settings.language))
                .font(.headline)
            Text(L10n.string(.journalLoadFailureBody, language: settings.language))
                .font(.callout)
            HStack {
                Button(L10n.string(.journalImport, language: settings.language)) {
                    importJournal()
                }
                Button(L10n.string(.journalStartFresh, language: settings.language), role: .destructive) {
                    showStartFreshConfirm = true
                }
                Spacer()
                if let exportStatus {
                    Text(exportStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.18))
    }

    private func restoreBanner(palette: WickPalette) -> some View {
        Text(L10n.string(.journalRestoredFromBackup, language: settings.language))
            .font(.callout)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.accentSoft.color)
    }

    private func focusSearchField() {
        // Best-effort: post a notification; the sidebar search field becomes first responder via window.
        if let window = NSApp.keyWindow {
            window.makeFirstResponder(window.contentView)
        }
    }

    private func importJournal() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip, .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.importArchive(from: url)
            exportStatus = L10n.string(.journalImportSuccess, language: settings.language)
        } catch {
            exportStatus = L10n.string(.journalImportFailed, language: settings.language)
        }
    }

    private var splitLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            JournalTimelineSidebar(columnVisibility: $columnVisibility)
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
        } detail: {
            JournalEditorPane(columnVisibility: $columnVisibility)
        }
    }
}

/// True on macOS 13: no toolbar (neither SwiftUI `.toolbar` items nor the
/// split view's sidebar toggle) materializes in the manually created journal
/// window there, so the top controls are rendered in-view inside each pane's
/// top safe-area strip, aligned with the traffic lights.
/// `WICK_INVIEW_TOPBAR=1` forces the in-view chrome on any version (debug).
private var journalNeedsInViewTopBar: Bool {
    if ProcessInfo.processInfo.environment["WICK_INVIEW_TOPBAR"] != nil {
        return true
    }
    return ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 14
}

/// Shared chip button for the panes' in-view top strips (macOS 13 chrome).
private struct JournalTopChip: View {
    @Environment(\.wickPalette) private var palette

    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textSecondary.color)
                .frame(width: 30, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(palette.controlBackground.color)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(palette.controlBorder.color, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Timeline

private struct JournalTimelineSidebar: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: JournalStore
    @Environment(\.wickPalette) private var palette

    let columnVisibility: Binding<NavigationSplitViewVisibility>

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
        .safeAreaInset(edge: .top, spacing: 0) {
            if journalNeedsInViewTopBar {
                topStrip
            }
        }
        .onChange(of: store.searchText) { _ in
            store.handleFilterChange()
        }
    }

    /// In-view titlebar strip (macOS 13): sidebar toggle right-aligned within
    /// the sidebar column, level with the traffic lights.
    private var topStrip: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)

                JournalTopChip(
                    systemName: "sidebar.left",
                    help: L10n.string(.journalToggleSidebar, language: settings.language)
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        columnVisibility.wrappedValue = .detailOnly
                    }
                }
                .keyboardShortcut("s", modifiers: [.control, .command])
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)

            Rectangle()
                .fill(palette.cardStroke.color)
                .frame(height: 1)
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

            if store.isItemScoped {
                Text(L10n.string(.journalItemScopeHint, language: settings.language))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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

private struct JournalDayTimelineRow: View {
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

private struct JournalItemTimelineRow: View {
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

// MARK: - Editor

private struct JournalEditorPane: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: JournalStore
    @Environment(\.wickPalette) private var palette

    let columnVisibility: Binding<NavigationSplitViewVisibility>

    @State private var draft = JournalEntry()
    @State private var saveTask: Task<Void, Never>?
    @State private var showDeleteDayConfirm = false
    @State private var showDeleteItemConfirm = false
    @State private var showDatePicker = false
    @State private var imageImportItemID: UUID?

    /// When selection is `.item`, only this item is edited/shown.
    private var isItemScopedEditor: Bool {
        if case .item = store.selection { return true }
        return false
    }

    private var visibleItemIDs: [UUID] {
        if case .item(let ref) = store.selection {
            return [ref.itemID]
        }
        return draft.items.map(\.id)
    }

    var body: some View {
        Group {
            if store.selection == nil || store.selectedEntry == nil {
                noSelection
            } else {
                editor
            }
        }
        .background(palette.backgroundBottom.color)
        .safeAreaInset(edge: .top, spacing: 0) {
            if journalNeedsInViewTopBar {
                topStrip
            }
        }
        .onChange(of: store.selection) { _ in
            loadDraft()
        }
        .onAppear {
            loadDraft()
        }
        .onReceive(NotificationCenter.default.publisher(for: .wickWillFlushJournalDrafts)) { _ in
            flushDraftImmediately()
        }
        .onDisappear {
            flushDraftImmediately()
        }
        .disabled(store.isReadOnlyDueToLoadFailure)
        .fileImporter(
            isPresented: Binding(
                get: { imageImportItemID != nil },
                set: { if !$0 { imageImportItemID = nil } }
            ),
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result,
                  let entryID = store.selectedEntryID,
                  let itemID = imageImportItemID
            else {
                imageImportItemID = nil
                return
            }
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer {
                    if scoped {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                _ = store.addImage(from: url, to: entryID, itemID: itemID)
            }
            reloadDraftFromStore()
            imageImportItemID = nil
        }
        .confirmationDialog(
            L10n.string(.journalDeleteConfirm, language: settings.language),
            isPresented: $showDeleteDayConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.string(.journalDelete, language: settings.language), role: .destructive) {
                if let id = store.selectedEntryID {
                    store.deleteEntry(id: id)
                }
            }
            Button(L10n.string(.cancel, language: settings.language), role: .cancel) {}
        }
        .confirmationDialog(
            L10n.string(.journalDeleteItemConfirm, language: settings.language),
            isPresented: $showDeleteItemConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.string(.journalDeleteItem, language: settings.language), role: .destructive) {
                if case .item(let ref) = store.selection {
                    saveTask?.cancel()
                    store.updateEntry(draft)
                    store.deleteItem(itemID: ref.itemID, from: ref.entryID)
                }
            }
            Button(L10n.string(.cancel, language: settings.language), role: .cancel) {}
        }
    }

    private var noSelection: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 42, weight: .ultraLight))
                .foregroundStyle(.secondary)
            Text(L10n.string(.journalSelectPrompt, language: settings.language))
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Button {
                _ = store.openOrCreateToday()
            } label: {
                Text(L10n.string(.journalNewEntry, language: settings.language))
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// In-view titlebar strip (macOS 13): new-entry chip right-aligned within
    /// the editor column, level with the traffic lights. When the sidebar is
    /// collapsed its toggle moves here (leading, clear of the traffic lights).
    private var topStrip: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if columnVisibility.wrappedValue == .detailOnly {
                    JournalTopChip(
                        systemName: "sidebar.left",
                        help: L10n.string(.journalToggleSidebar, language: settings.language)
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            columnVisibility.wrappedValue = .all
                        }
                    }
                    .keyboardShortcut("s", modifiers: [.control, .command])
                    .padding(.leading, 70)
                }

                Spacer(minLength: 0)

                JournalTopChip(
                    systemName: "square.and.pencil",
                    help: L10n.string(.journalNewEntry, language: settings.language)
                ) {
                    _ = store.openOrCreateToday()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)

            Rectangle()
                .fill(palette.cardStroke.color)
                .frame(height: 1)
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            DayArcStrip(date: draft.date, language: settings.language)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                        JournalItemEditorCard(
                            index: displayIndex(for: item.id, fallback: index),
                            item: binding(for: item.id),
                            canDelete: isItemScopedEditor || draft.items.count > 1,
                            onDelete: {
                                if isItemScopedEditor {
                                    showDeleteItemConfirm = true
                                } else {
                                    deleteItem(id: item.id)
                                }
                            },
                            onPasteImage: {
                                pasteImage(to: item.id)
                            },
                            onPickImage: {
                                imageImportItemID = item.id
                            },
                            onDrop: { providers in
                                handleDrop(providers, itemID: item.id)
                            },
                            onChange: scheduleSave
                        )
                    }

                    if !isItemScopedEditor {
                        Button {
                            addItem()
                        } label: {
                            Label(
                                L10n.string(.journalAddItem, language: settings.language),
                                systemImage: "plus.circle"
                            )
                        }
                        .buttonStyle(.bordered)

                        footerDayActions
                    } else {
                        footerItemActions
                    }
                }
                .padding(28)
                .frame(maxWidth: 880, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var visibleItems: [JournalItem] {
        let ids = Set(visibleItemIDs)
        return draft.items.filter { ids.contains($0.id) }
    }

    private func displayIndex(for itemID: UUID, fallback: Int) -> Int {
        if let index = draft.items.firstIndex(where: { $0.id == itemID }) {
            return index
        }
        return fallback
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                // Locale-correct, zero-padded date label; the field-style
                // DatePicker followed the system locale and space-padded
                // single digits ("2026/ 7/28"), so it is now display-only
                // with a graphical calendar in a popover.
                Button {
                    showDatePicker = true
                } label: {
                    HStack(spacing: 6) {
                        Text(formattedDate)
                            .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                        Image(systemName: "calendar")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.textTertiary.color)
                    }
                    .foregroundStyle(palette.textPrimary.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(palette.controlBackground.color)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(palette.controlBorder.color, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isItemScopedEditor)
                .accessibilityLabel(Text(L10n.string(.journalChangeDate, language: settings.language)))
                .popover(isPresented: $showDatePicker, arrowEdge: .top) {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { draft.date },
                            set: { newValue in
                                draft.date = Calendar.current.startOfDay(for: newValue)
                                scheduleSave()
                            }
                        ),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .datePickerStyle(.graphical)
                    .environment(\.locale, settings.language.locale)
                    .padding(10)
                }

                Spacer()

                if isItemScopedEditor {
                    Text(L10n.string(.journalItemScopeBadge, language: settings.language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.accentText.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(palette.accentSoft.color, in: Capsule())
                } else {
                    Text(
                        String(
                            format: L10n.string(.journalItemCountFormat, language: settings.language),
                            draft.items.count
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if store.isReadOnlyDueToLoadFailure {
                    Text(L10n.string(.journalReadOnly, language: settings.language))
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text(L10n.string(.journalAutosaved, language: settings.language))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            if isItemScopedEditor {
                if !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(draft.title)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Text(L10n.string(.journalItemScopeEditorHint, language: settings.language))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                IMESafeTextField(
                    text: Binding(
                        get: { draft.title },
                        set: { draft.title = $0 }
                    ),
                    placeholder: L10n.string(.journalTitlePlaceholder, language: settings.language),
                    font: Self.titleFont,
                    style: .plain,
                    onChange: scheduleSave
                )
                .frame(height: 34)

                Text(L10n.string(.journalItemsHint, language: settings.language))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var footerDayActions: some View {
        HStack {
            Button(role: .destructive) {
                showDeleteDayConfirm = true
            } label: {
                Label(
                    L10n.string(.journalDelete, language: settings.language),
                    systemImage: "trash"
                )
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    private var footerItemActions: some View {
        HStack {
            Button {
                store.openSelectedDayFully()
            } label: {
                Label(
                    L10n.string(.journalOpenFullDay, language: settings.language),
                    systemImage: "calendar"
                )
            }
            .buttonStyle(.bordered)

            Spacer()

            Button(role: .destructive) {
                showDeleteItemConfirm = true
            } label: {
                Label(
                    L10n.string(.journalDeleteItem, language: settings.language),
                    systemImage: "trash"
                )
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Draft helpers

    /// Locale-correct, zero-padded numeric date ("2026年07月28日" / "07/28/2026").
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = settings.language.locale
        formatter.setLocalizedDateFormatFromTemplate("yMMdd")
        return formatter.string(from: draft.date)
    }

    private static var titleFont: NSFont {
        let base = NSFont.systemFont(ofSize: 26, weight: .semibold)
        if let rounded = base.fontDescriptor.withDesign(.rounded) {
            return NSFont(descriptor: rounded, size: 26) ?? base
        }
        return base
    }

    private func binding(for itemID: UUID) -> Binding<JournalItem> {
        Binding(
            get: {
                draft.items.first(where: { $0.id == itemID }) ?? JournalItem(id: itemID)
            },
            set: { newValue in
                guard let index = draft.items.firstIndex(where: { $0.id == itemID }) else {
                    return
                }
                draft.items[index] = newValue
            }
        )
    }

    private func loadDraft() {
        saveTask?.cancel()
        guard let entryID = store.selectedEntryID,
              let entry = store.entries.first(where: { $0.id == entryID })
        else {
            draft = JournalEntry()
            return
        }
        draft = entry
    }

    private func reloadDraftFromStore() {
        guard let entryID = store.selectedEntryID,
              let entry = store.entries.first(where: { $0.id == entryID })
        else {
            return
        }
        var merged = entry
        for index in merged.items.indices {
            let itemID = merged.items[index].id
            if let local = draft.items.first(where: { $0.id == itemID }) {
                merged.items[index].tag = local.tag
                merged.items[index].body = local.body
            }
        }
        merged.title = draft.title
        merged.date = draft.date
        draft = merged
    }

    private func scheduleSave() {
        guard !store.isReadOnlyDueToLoadFailure else { return }
        saveTask?.cancel()
        // Debounce disk writes, and never commit while an IME is composing —
        // intermediate marked text + @Published store refresh is what swallows CJK input.
        saveTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                if TextInputComposition.isActive {
                    continue
                }
                store.updateEntry(draft)
                return
            }
        }
    }

    private func flushDraftImmediately() {
        saveTask?.cancel()
        guard store.selectedEntryID != nil, !store.isReadOnlyDueToLoadFailure else { return }
        // Even if IME is active, quitting must not lose committed characters already in the binding.
        store.updateEntry(draft)
    }

    private func addItem() {
        saveTask?.cancel()
        store.updateEntry(draft)
        guard let entryID = store.selectedEntryID,
              let item = store.addItem(to: entryID)
        else {
            return
        }
        draft.items.append(item)
        draft.updatedAt = Date()
    }

    private func deleteItem(id: UUID) {
        saveTask?.cancel()
        store.updateEntry(draft)
        guard let entryID = store.selectedEntryID else { return }
        store.deleteItem(itemID: id, from: entryID)
        loadDraft()
    }

    private func pasteImage(to itemID: UUID) {
        guard let entryID = store.selectedEntryID else { return }
        saveTask?.cancel()
        store.updateEntry(draft)
        if store.pasteImageFromClipboard(to: entryID, itemID: itemID) {
            reloadDraftFromStore()
        }
    }

    private func handleDrop(_ providers: [NSItemProvider], itemID: UUID) -> Bool {
        guard let entryID = store.selectedEntryID else { return false }
        var accepted = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                accepted = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in
                        saveTask?.cancel()
                        store.updateEntry(draft)
                        _ = store.addImage(from: data, to: entryID, itemID: itemID, preferredExtension: "png")
                        reloadDraftFromStore()
                    }
                }
                continue
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else if let value = item as? URL {
                        url = value
                    } else {
                        url = nil
                    }
                    guard let url else { return }
                    Task { @MainActor in
                        saveTask?.cancel()
                        store.updateEntry(draft)
                        _ = store.addImage(from: url, to: entryID, itemID: itemID)
                        reloadDraftFromStore()
                    }
                }
            }
        }

        return accepted
    }
}

// MARK: - Item card

private struct JournalItemEditorCard: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: JournalStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.wickPalette) private var palette

    let index: Int
    @Binding var item: JournalItem
    let canDelete: Bool
    let onDelete: () -> Void
    let onPasteImage: () -> Void
    let onPickImage: () -> Void
    let onDrop: ([NSItemProvider]) -> Bool
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Text(
                    String(
                        format: L10n.string(.journalItemNumberFormat, language: settings.language),
                        index + 1
                    )
                )
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)

                Spacer()

                if canDelete {
                    Button(role: .destructive, action: onDelete) {
                        Label(
                            L10n.string(.journalDeleteItem, language: settings.language),
                            systemImage: "minus.circle"
                        )
                    }
                    .buttonStyle(.borderless)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string(.journalItemTag, language: settings.language))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                IMESafeTextField(
                    text: Binding(
                        get: { item.tag },
                        set: { item.tag = $0 }
                    ),
                    placeholder: L10n.string(.journalItemTagPlaceholder, language: settings.language),
                    font: .systemFont(ofSize: NSFont.systemFontSize),
                    style: .rounded,
                    onChange: onChange
                )
                .frame(height: 28)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string(.journalBody, language: settings.language))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                IMESafeTextEditor(
                    text: Binding(
                        get: { item.body },
                        set: { item.body = $0 }
                    ),
                    font: .systemFont(ofSize: 14),
                    onChange: onChange
                )
                .frame(minHeight: 120)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.03))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .overlay(alignment: .topLeading) {
                    if item.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(L10n.string(.journalBodyPlaceholder, language: settings.language))
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
            }

            imagesSection
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.cardTop.color)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(palette.cardStroke.color, lineWidth: 1)
        }
    }

    private var imagesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.string(.journalImages, language: settings.language))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                Button(action: onPasteImage) {
                    Label(
                        L10n.string(.journalPasteImage, language: settings.language),
                        systemImage: "doc.on.clipboard"
                    )
                }
                .help(L10n.string(.journalPasteImageHelp, language: settings.language))

                Button(action: onPickImage) {
                    Label(
                        L10n.string(.journalAddImage, language: settings.language),
                        systemImage: "photo.badge.plus"
                    )
                }
            }

            if item.imageFilenames.isEmpty {
                Text(L10n.string(.journalImagesHint, language: settings.language))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                            .foregroundStyle(Color.primary.opacity(0.15))
                    )
                    .onDrop(of: [.image, .fileURL], isTargeted: nil, perform: onDrop)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 140), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(item.imageFilenames, id: \.self) { filename in
                        JournalImageThumb(
                            filename: filename,
                            onDelete: {
                                guard let entryID = store.selectedEntryID else { return }
                                store.removeImage(filename: filename, from: entryID, itemID: item.id)
                                item.imageFilenames.removeAll { $0 == filename }
                            }
                        )
                    }
                }
                .onDrop(of: [.image, .fileURL], isTargeted: nil, perform: onDrop)
            }
        }
    }
}

private struct JournalImageThumb: View {
    @EnvironmentObject private var store: JournalStore
    let filename: String
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = store.loadThumbnail(filename: filename, maxPixel: 360) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .accessibilityLabel(filename)
                } else {
                    Color.secondary.opacity(0.15)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 110, maxHeight: 150)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.55))
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
            .padding(6)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

// MARK: - Day arc strip

/// Signature day-arc element: a full-width 24h gradient of the day's four
/// phase accents. Shows a "now" marker when the edited entry is today.
private struct DayArcStrip: View {
    let date: Date
    let language: AppLanguage

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.wickPalette) private var palette

    var body: some View {
        let isToday = Calendar.current.isDateInToday(date)

        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                LinearGradient(
                    stops: arcStops,
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 4)

                if isToday {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                        .overlay {
                            Circle()
                                .strokeBorder(palette.accentText.color, lineWidth: 1.5)
                        }
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                        .offset(x: nowMarkerX(width: proxy.size.width))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(L10n.string(.dayArcNowLabel, language: language)))
        .accessibilityHidden(!isToday)
    }

    /// Phase accents placed at their anchor hours across the 24h strip.
    private var arcStops: [Gradient.Stop] {
        [
            Gradient.Stop(color: phaseAccent(.night), location: 0),
            Gradient.Stop(color: phaseAccent(.dawn), location: DayPhase.dawn.anchorHour / 24),
            Gradient.Stop(color: phaseAccent(.day), location: DayPhase.day.anchorHour / 24),
            Gradient.Stop(color: phaseAccent(.dusk), location: DayPhase.dusk.anchorHour / 24),
            Gradient.Stop(color: phaseAccent(.night), location: DayPhase.night.anchorHour / 24),
            Gradient.Stop(color: phaseAccent(.night), location: 1),
        ]
    }

    private func phaseAccent(_ phase: DayPhase) -> Color {
        DayArcEngine.anchorPalette(phase, scheme: colorScheme).accent.color
    }

    private func nowMarkerX(width: CGFloat) -> CGFloat {
        let now = DayArcEngine.currentDate()
        let components = Calendar.current.dateComponents([.hour, .minute], from: now)
        let hours = Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
        let fraction = min(max(hours / 24, 0), 1)
        return min(max(fraction * width - 3, 0), max(width - 6, 0))
    }
}
