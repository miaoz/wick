import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Editor
struct JournalEditorPane: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: JournalStore
    @Environment(\.wickPalette) private var palette

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

    private func pasteImage(to itemID: UUID) -> Bool {
        guard let entryID = store.selectedEntryID else { return false }
        saveTask?.cancel()
        store.updateEntry(draft)
        if store.pasteImageFromClipboard(to: entryID, itemID: itemID) {
            reloadDraftFromStore()
            return true
        }
        return false
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

