import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Root

struct JournalRootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: JournalStore
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("wick.journal.useSplitLayout") private var useSplitLayout = true

    var body: some View {
        Group {
            if useSplitLayout {
                splitLayout
            } else {
                singleColumnLayout
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .preferredColorScheme(settings.preferredColorScheme)
        .background(JournalChrome.background(for: colorScheme))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    useSplitLayout.toggle()
                } label: {
                    Label(
                        useSplitLayout
                            ? L10n.string(.journalLayoutSingle, language: settings.language)
                            : L10n.string(.journalLayoutSplit, language: settings.language),
                        systemImage: useSplitLayout ? "rectangle" : "sidebar.left"
                    )
                }
                .help(
                    useSplitLayout
                        ? L10n.string(.journalLayoutSingle, language: settings.language)
                        : L10n.string(.journalLayoutSplit, language: settings.language)
                )

                Button {
                    _ = store.createEntry()
                } label: {
                    Label(
                        L10n.string(.journalNewEntry, language: settings.language),
                        systemImage: "square.and.pencil"
                    )
                }
                .help(L10n.string(.journalNewEntry, language: settings.language))
            }
        }
        .navigationTitle(L10n.string(.journalTitle, language: settings.language))
    }

    private var splitLayout: some View {
        NavigationSplitView {
            JournalTimelineSidebar()
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
        } detail: {
            JournalEditorPane()
        }
    }

    private var singleColumnLayout: some View {
        NavigationStack {
            if store.selection != nil {
                JournalEditorPane()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                store.selection = nil
                            } label: {
                                Label(
                                    L10n.string(.back, language: settings.language),
                                    systemImage: "chevron.left"
                                )
                            }
                        }
                    }
            } else {
                JournalTimelineSidebar()
            }
        }
    }
}

// MARK: - Timeline

private struct JournalTimelineSidebar: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: JournalStore
    @Environment(\.colorScheme) private var colorScheme

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
        .background(JournalChrome.sidebarBackground(for: colorScheme))
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        tagChip(
                            title: L10n.string(.journalAllTags, language: settings.language),
                            isSelected: store.selectedTagFilter == nil
                        ) {
                            store.setTagFilter(nil)
                        }

                        ForEach(store.allTags, id: \.self) { tag in
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
                        }
                    }
                }
            }

            if store.isItemScoped {
                Text(L10n.string(.journalItemScopeHint, language: settings.language))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
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
                _ = store.createEntry()
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
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                )
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.08),
                            lineWidth: 1
                        )
                }
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.8))
        }
        .buttonStyle(.plain)
    }
}

private struct JournalDayTimelineRow: View {
    @EnvironmentObject private var settings: AppSettings
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
                    .foregroundStyle(Color.accentColor.opacity(0.9))
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
    let row: JournalTimelineItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(tagTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
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
    @Environment(\.colorScheme) private var colorScheme

    @State private var draft = JournalEntry()
    @State private var saveTask: Task<Void, Never>?
    @State private var showDeleteDayConfirm = false
    @State private var showDeleteItemConfirm = false
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
        .background(JournalChrome.background(for: colorScheme))
        .onChange(of: store.selection) { _ in
            loadDraft()
        }
        .onAppear {
            loadDraft()
        }
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
                _ = store.createEntry()
            } label: {
                Text(L10n.string(.journalNewEntry, language: settings.language))
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editor: some View {
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
                .datePickerStyle(.field)
                .disabled(isItemScopedEditor)

                Spacer()

                if isItemScopedEditor {
                    Text(L10n.string(.journalItemScopeBadge, language: settings.language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
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

                Text(L10n.string(.journalAutosaved, language: settings.language))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
                TextField(
                    L10n.string(.journalTitlePlaceholder, language: settings.language),
                    text: Binding(
                        get: { draft.title },
                        set: { draft.title = $0; scheduleSave() }
                    )
                )
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .textFieldStyle(.plain)

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
        saveTask?.cancel()
        let snapshot = draft
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            store.updateEntry(snapshot)
        }
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

                TextField(
                    L10n.string(.journalItemTagPlaceholder, language: settings.language),
                    text: Binding(
                        get: { item.tag },
                        set: { item.tag = $0; onChange() }
                    )
                )
                .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string(.journalBody, language: settings.language))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                TextEditor(
                    text: Binding(
                        get: { item.body },
                        set: { item.body = $0; onChange() }
                    )
                )
                .font(.system(size: 14))
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
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
                .fill(JournalChrome.cardFill(for: colorScheme))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(JournalChrome.cardStroke(for: colorScheme), lineWidth: 1)
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
                if let image = store.loadNSImage(filename: filename) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
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

// MARK: - Chrome

private enum JournalChrome {
    static func background(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(nsColor: .windowBackgroundColor)
            : Color(nsColor: .controlBackgroundColor)
    }

    static func sidebarBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(nsColor: .underPageBackgroundColor)
            : Color(nsColor: .windowBackgroundColor)
    }

    static func cardFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.04)
            : Color.white.opacity(0.72)
    }

    static func cardStroke(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.06)
    }
}
