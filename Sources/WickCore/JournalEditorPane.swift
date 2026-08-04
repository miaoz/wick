import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Editor

/// Right-hand journal editor: a continuous date timeline (newest first).
/// - Day mode: every journal day is a scrollable section (full day chrome).
/// - Item-scoped mode (tag / search filter): matching items only, grouped by day,
///   still a continuous scrollable timeline — not a single selected day/item.
struct JournalEditorPane: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: JournalStore
    @Environment(\.wickPalette) private var palette

    /// Per-entry drafts so multi-day editing survives LazyVStack recycling.
    @State private var drafts: [UUID: JournalEntry] = [:]
    @State private var saveTasks: [UUID: Task<Void, Never>] = [:]
    @State private var showDeleteDayConfirm = false
    @State private var showDeleteItemConfirm = false
    @State private var pendingDeleteDayID: UUID?
    @State private var pendingDeleteItem: JournalItemRef?
    @State private var datePickerEntryID: UUID?
    @State private var imageImportTarget: JournalItemRef?
    @State private var showImageImporter = false
    @State private var pendingScrollID: String?

    private var isItemScoped: Bool { store.isItemScoped }

    var body: some View {
        Group {
            if isItemScoped {
                if store.filteredTimelineItems.isEmpty {
                    emptyFilter
                } else {
                    timelineChrome
                }
            } else if store.filteredEntries.isEmpty {
                noSelection
            } else {
                timelineChrome
            }
        }
        .background(palette.backgroundBottom.color)
        .onAppear {
            seedDraftsForVisibleTimeline()
            queueScrollToSelection()
        }
        .onChange(of: store.selection) { _ in
            seedDraftsForVisibleTimeline()
            queueScrollToSelection()
        }
        .onChange(of: store.selectedTagFilter) { _ in
            seedDraftsForVisibleTimeline()
            queueScrollToSelection()
        }
        .onChange(of: store.searchText) { _ in
            seedDraftsForVisibleTimeline()
            queueScrollToSelection()
        }
        .onChange(of: store.entries) { _ in
            pruneDrafts()
            seedDraftsForVisibleTimeline()
        }
        .onReceive(NotificationCenter.default.publisher(for: .wickWillFlushJournalDrafts)) { _ in
            flushAllDraftsImmediately()
        }
        .onDisappear {
            flushAllDraftsImmediately()
        }
        .disabled(store.isReadOnlyDueToLoadFailure)
        .fileImporter(
            isPresented: $showImageImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            // Read the target before clearing: isPresented resets *before*
            // this completion runs, so a payload-driven binding would
            // already be nil here (that bug made picks no-op).
            defer { imageImportTarget = nil }
            guard case .success(let urls) = result,
                  let target = imageImportTarget
            else {
                return
            }
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer {
                    if scoped {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                _ = store.addImage(from: url, to: target.entryID, itemID: target.itemID)
            }
            mergeImagesFromStore(entryID: target.entryID)
        }
        .confirmationDialog(
            L10n.string(.journalDeleteConfirm, language: settings.language),
            isPresented: $showDeleteDayConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.string(.journalDelete, language: settings.language), role: .destructive) {
                if let id = pendingDeleteDayID {
                    cancelSave(for: id)
                    drafts[id] = nil
                    store.deleteEntry(id: id)
                }
                pendingDeleteDayID = nil
            }
            Button(L10n.string(.cancel, language: settings.language), role: .cancel) {
                pendingDeleteDayID = nil
            }
        }
        .confirmationDialog(
            L10n.string(.journalDeleteItemConfirm, language: settings.language),
            isPresented: $showDeleteItemConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.string(.journalDeleteItem, language: settings.language), role: .destructive) {
                if let ref = pendingDeleteItem {
                    cancelSave(for: ref.entryID)
                    if let draft = drafts[ref.entryID] {
                        store.updateEntry(draft)
                    }
                    store.deleteItem(itemID: ref.itemID, from: ref.entryID)
                    if let entry = store.entries.first(where: { $0.id == ref.entryID }) {
                        drafts[ref.entryID] = entry
                    } else {
                        drafts[ref.entryID] = nil
                    }
                }
                pendingDeleteItem = nil
            }
            Button(L10n.string(.cancel, language: settings.language), role: .cancel) {
                pendingDeleteItem = nil
            }
        }
    }

    // MARK: - Empty states

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

    private var emptyFilter: some View {
        VStack(spacing: 14) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 42, weight: .ultraLight))
                .foregroundStyle(.secondary)
            Text(L10n.string(.journalFilterEmptyTitle, language: settings.language))
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text(L10n.string(.journalFilterEmptySubtitle, language: settings.language))
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Timeline

    /// Date for the single top chrome strip (panel chrome, not per-day content).
    private var chromeStripDate: Date {
        if let id = store.selectedEntryID,
           let entry = store.entries.first(where: { $0.id == id })
        {
            return entry.date
        }
        if let first = store.filteredEntries.first {
            return first.date
        }
        return Date()
    }

    private var timelineChrome: some View {
        VStack(spacing: 0) {
            // One arc strip for the whole editor panel — not repeated per day/item.
            DayArcStrip(date: chromeStripDate, language: settings.language)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        if isItemScoped {
                            itemScopedSections
                        } else {
                            dayScopedSections
                        }
                    }
                    .padding(.vertical, 20)
                    .padding(.horizontal, 28)
                    .frame(maxWidth: 880, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: pendingScrollID) { target in
                    guard let target else { return }
                    // Double-pass: first layout pass may not have built LazyVStack rows yet.
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(target, anchor: .top)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            proxy.scrollTo(target, anchor: .top)
                            if pendingScrollID == target {
                                pendingScrollID = nil
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var dayScopedSections: some View {
        ForEach(store.filteredEntries) { entry in
            daySection(
                entryID: entry.id,
                isFocused: store.selectedEntryID == entry.id
            )
            .id(Self.dayScrollID(entry.id))
            .onAppear {
                ensureDraft(for: entry.id)
            }
        }
    }

    @ViewBuilder
    private var itemScopedSections: some View {
        ForEach(itemDayGroups) { group in
            VStack(alignment: .leading, spacing: 14) {
                itemScopedDayHeader(group)

                ForEach(group.items) { row in
                    itemCard(
                        entryID: row.ref.entryID,
                        itemID: row.ref.itemID,
                        isFocused: store.selectedItemID == row.ref.itemID
                            && store.selectedEntryID == row.ref.entryID
                    )
                    .id(Self.itemScrollID(row.ref))
                    .onAppear {
                        ensureDraft(for: row.ref.entryID)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(palette.cardTop.scaledAlpha(0.35).color)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(palette.cardStroke.scaledAlpha(0.4).color, lineWidth: 1)
            }
        }
    }

    private func itemScopedDayHeader(_ group: ItemDayGroup) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(formattedDate(group.day))
                .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(palette.textPrimary.color)

            Spacer(minLength: 8)

            Button {
                // Leave filter mode and open this calendar day fully.
                store.selectedTagFilter = nil
                store.searchText = ""
                store.selectDay(group.representativeEntryID)
            } label: {
                Image(systemName: "calendar")
            }
            .buttonStyle(JournalQuietIconButtonStyle())
            .help(L10n.string(.journalOpenFullDay, language: settings.language))
            .accessibilityLabel(Text(L10n.string(.journalOpenFullDay, language: settings.language)))
        }
    }

    // MARK: - Day section (full day)

    @ViewBuilder
    private func daySection(
        entryID: UUID,
        isFocused: Bool
    ) -> some View {
        let draft = drafts[entryID] ?? store.entries.first(where: { $0.id == entryID }) ?? JournalEntry()

        VStack(alignment: .leading, spacing: 16) {
            dayHeader(entryID: entryID, draft: draft, itemCount: draft.items.count, isFocused: isFocused)

            ForEach(Array(draft.items.enumerated()), id: \.element.id) { index, item in
                itemCard(
                    entryID: entryID,
                    itemID: item.id,
                    itemIndex: index,
                    isFocused: false
                )
            }

            HStack {
                Spacer(minLength: 0)
                Button {
                    addItem(to: entryID)
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(JournalQuietIconButtonStyle())
                .help(L10n.string(.journalAddItem, language: settings.language))
                .accessibilityLabel(Text(L10n.string(.journalAddItem, language: settings.language)))
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.cardTop.scaledAlpha(isFocused ? 0.55 : 0.35).color)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isFocused
                        ? palette.accent.color.opacity(0.4)
                        : palette.cardStroke.scaledAlpha(0.4).color,
                    lineWidth: isFocused ? 1.5 : 1
                )
        }
    }

    private func dayHeader(
        entryID: UUID,
        draft: JournalEntry,
        itemCount: Int,
        isFocused: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                datePickerEntryID = entryID
            } label: {
                HStack(spacing: 6) {
                    Text(formattedDate(draft.date))
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
            .accessibilityLabel(Text(L10n.string(.journalChangeDate, language: settings.language)))
            .popover(isPresented: Binding(
                get: { datePickerEntryID == entryID },
                set: { if !$0 { datePickerEntryID = nil } }
            ), arrowEdge: .top) {
                DatePicker(
                    "",
                    selection: Binding(
                        get: { drafts[entryID]?.date ?? draft.date },
                        set: { newValue in
                            mutateDraft(entryID) { entry in
                                entry.date = Calendar.current.startOfDay(for: newValue)
                            }
                            scheduleSave(for: entryID)
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

            Text(
                String(
                    format: L10n.string(.journalItemCountFormat, language: settings.language),
                    itemCount
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if store.isReadOnlyDueToLoadFailure {
                Text(L10n.string(.journalReadOnly, language: settings.language))
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if isFocused {
                Text(L10n.string(.journalAutosaved, language: settings.language))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Button {
                pendingDeleteDayID = entryID
                showDeleteDayConfirm = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(JournalQuietIconButtonStyle(role: .destructive))
            .help(L10n.string(.journalDelete, language: settings.language))
            .accessibilityLabel(Text(L10n.string(.journalDelete, language: settings.language)))
        }
    }

    // MARK: - Item card

    private func itemCard(
        entryID: UUID,
        itemID: UUID,
        itemIndex: Int? = nil,
        isFocused: Bool
    ) -> some View {
        let draft = drafts[entryID] ?? store.entries.first(where: { $0.id == entryID }) ?? JournalEntry()
        let index = itemIndex ?? displayIndex(for: itemID, in: draft, fallback: 0)
        let canDelete = isItemScoped || draft.items.count > 1
        let reviewEligible = Calendar.current.startOfDay(for: draft.date)
            < Calendar.current.startOfDay(for: Date())

        return JournalItemEditorCard(
            entryID: entryID,
            index: index,
            item: binding(entryID: entryID, itemID: itemID),
            canDelete: canDelete,
            reviewEligible: reviewEligible,
            onDelete: {
                if isItemScoped {
                    pendingDeleteItem = JournalItemRef(entryID: entryID, itemID: itemID)
                    showDeleteItemConfirm = true
                } else {
                    deleteItem(itemID: itemID, from: entryID)
                }
            },
            onPasteImage: {
                pasteImage(to: itemID, in: entryID)
            },
            onPickImage: {
                imageImportTarget = JournalItemRef(entryID: entryID, itemID: itemID)
                showImageImporter = true
            },
            onDrop: { providers in
                handleDrop(providers, itemID: itemID, entryID: entryID)
            },
            onChange: { scheduleSave(for: entryID) }
        )
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(palette.accent.color.opacity(0.45), lineWidth: 1.5)
            }
        }
    }

    // MARK: - Item-scoped grouping

    private struct ItemDayGroup: Identifiable {
        /// Start-of-day key.
        var id: Date { day }
        let day: Date
        let items: [JournalTimelineItem]

        var representativeEntryID: UUID {
            items.first?.ref.entryID ?? UUID()
        }
    }

    private var itemDayGroups: [ItemDayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: store.filteredTimelineItems) {
            calendar.startOfDay(for: $0.date)
        }
        return grouped.keys.sorted(by: >).map { day in
            ItemDayGroup(day: day, items: grouped[day] ?? [])
        }
    }

    // MARK: - Draft helpers

    private static func dayScrollID(_ entryID: UUID) -> String {
        "day-\(entryID.uuidString)"
    }

    private static func itemScrollID(_ ref: JournalItemRef) -> String {
        "item-\(ref.id)"
    }

    private func scrollID(for selection: JournalSelection?) -> String? {
        switch selection {
        case .day(let id):
            return Self.dayScrollID(id)
        case .item(let ref):
            return Self.itemScrollID(ref)
        case nil:
            return nil
        }
    }

    private func queueScrollToSelection() {
        guard let id = scrollID(for: store.selection) else { return }
        pendingScrollID = id
    }

    private func seedDraftsForVisibleTimeline() {
        if isItemScoped {
            let entryIDs = Set(store.filteredTimelineItems.map(\.ref.entryID))
            for id in entryIDs {
                ensureDraft(for: id)
            }
        } else {
            for entry in store.filteredEntries {
                ensureDraft(for: entry.id)
            }
        }
    }

    private func ensureDraft(for entryID: UUID) {
        guard drafts[entryID] == nil,
              let entry = store.entries.first(where: { $0.id == entryID })
        else {
            return
        }
        drafts[entryID] = entry
    }

    private func pruneDrafts() {
        let live = Set(store.entries.map(\.id))
        for key in drafts.keys where !live.contains(key) {
            cancelSave(for: key)
            drafts[key] = nil
        }
    }

    private func mutateDraft(_ entryID: UUID, _ body: (inout JournalEntry) -> Void) {
        ensureDraft(for: entryID)
        guard var draft = drafts[entryID] else { return }
        body(&draft)
        drafts[entryID] = draft
    }

    private func binding(entryID: UUID, itemID: UUID) -> Binding<JournalItem> {
        Binding(
            get: {
                if let item = drafts[entryID]?.items.first(where: { $0.id == itemID }) {
                    return item
                }
                if let item = store.entries
                    .first(where: { $0.id == entryID })?
                    .items.first(where: { $0.id == itemID })
                {
                    return item
                }
                return JournalItem(id: itemID)
            },
            set: { newValue in
                mutateDraft(entryID) { entry in
                    if let index = entry.items.firstIndex(where: { $0.id == itemID }) {
                        entry.items[index] = newValue
                    }
                }
            }
        )
    }

    private func displayIndex(for itemID: UUID, in draft: JournalEntry, fallback: Int) -> Int {
        if let index = draft.items.firstIndex(where: { $0.id == itemID }) {
            return index
        }
        return fallback
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = settings.language.locale
        formatter.setLocalizedDateFormatFromTemplate("yMMdd")
        return formatter.string(from: date)
    }

    // MARK: - Persistence

    private func scheduleSave(for entryID: UUID) {
        guard !store.isReadOnlyDueToLoadFailure else { return }
        cancelSave(for: entryID)
        saveTasks[entryID] = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                if TextInputComposition.isActive {
                    continue
                }
                if let draft = drafts[entryID] {
                    store.updateEntry(draft)
                }
                saveTasks[entryID] = nil
                return
            }
        }
    }

    private func cancelSave(for entryID: UUID) {
        saveTasks[entryID]?.cancel()
        saveTasks[entryID] = nil
    }

    private func flushAllDraftsImmediately() {
        for (entryID, task) in saveTasks {
            task.cancel()
            saveTasks[entryID] = nil
        }
        guard !store.isReadOnlyDueToLoadFailure else { return }
        for (entryID, draft) in drafts {
            if store.entries.contains(where: { $0.id == entryID }) {
                store.updateEntry(draft)
            }
        }
    }

    private func mergeImagesFromStore(entryID: UUID) {
        guard let entry = store.entries.first(where: { $0.id == entryID }) else { return }
        mutateDraft(entryID) { draft in
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
    }

    private func addItem(to entryID: UUID) {
        cancelSave(for: entryID)
        if let draft = drafts[entryID] {
            store.updateEntry(draft)
        }
        guard let item = store.addItem(to: entryID) else { return }
        mutateDraft(entryID) { draft in
            draft.items.append(item)
            draft.updatedAt = Date()
        }
    }

    private func deleteItem(itemID: UUID, from entryID: UUID) {
        cancelSave(for: entryID)
        if let draft = drafts[entryID] {
            store.updateEntry(draft)
        }
        store.deleteItem(itemID: itemID, from: entryID)
        if let entry = store.entries.first(where: { $0.id == entryID }) {
            drafts[entryID] = entry
        } else {
            drafts[entryID] = nil
        }
    }

    private func pasteImage(to itemID: UUID, in entryID: UUID) -> Bool {
        cancelSave(for: entryID)
        if let draft = drafts[entryID] {
            store.updateEntry(draft)
        }
        if store.pasteImageFromClipboard(to: entryID, itemID: itemID) {
            mergeImagesFromStore(entryID: entryID)
            return true
        }
        return false
    }

    private func handleDrop(_ providers: [NSItemProvider], itemID: UUID, entryID: UUID) -> Bool {
        var accepted = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                accepted = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in
                        cancelSave(for: entryID)
                        if let draft = drafts[entryID] {
                            store.updateEntry(draft)
                        }
                        _ = store.addImage(
                            from: data,
                            to: entryID,
                            itemID: itemID,
                            preferredExtension: "png"
                        )
                        mergeImagesFromStore(entryID: entryID)
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
                        cancelSave(for: entryID)
                        if let draft = drafts[entryID] {
                            store.updateEntry(draft)
                        }
                        _ = store.addImage(from: url, to: entryID, itemID: itemID)
                        mergeImagesFromStore(entryID: entryID)
                    }
                }
            }
        }

        return accepted
    }
}
