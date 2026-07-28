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
            if store.selectedEntry != nil {
                JournalEditorPane()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                store.selectEntry(id: nil)
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
            listContent
        }
        .background(JournalChrome.sidebarBackground(for: colorScheme))
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
                        store.searchText = ""
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
        }
        .padding(12)
    }

    private var listContent: some View {
        Group {
            if store.filteredEntries.isEmpty {
                emptyState
            } else {
                List(selection: Binding(
                    get: { store.selectedEntryID },
                    set: { store.selectEntry(id: $0) }
                )) {
                    ForEach(groupedSections, id: \.title) { section in
                        Section(section.title) {
                            ForEach(section.entries) { entry in
                                JournalTimelineRow(entry: entry)
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

    private struct DaySection: Identifiable {
        var id: String { title }
        let title: String
        let entries: [JournalEntry]
    }

    private var groupedSections: [DaySection] {
        let calendar = Calendar.current
        let locale = settings.locale
        let language = settings.language

        let grouped = Dictionary(grouping: store.filteredEntries) { entry in
            calendar.startOfDay(for: entry.date)
        }

        return grouped.keys.sorted(by: >).map { day in
            let title: String
            if calendar.isDateInToday(day) {
                title = L10n.string(.journalToday, language: language)
            } else if calendar.isDateInYesterday(day) {
                title = L10n.string(.journalYesterday, language: language)
            } else {
                title = day.formatted(
                    .dateTime
                    .year()
                    .month()
                    .day()
                    .weekday(.wide)
                    .locale(locale)
                )
            }
            let entries = (grouped[day] ?? []).sorted { $0.updatedAt > $1.updatedAt }
            return DaySection(title: title, entries: entries)
        }
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

private struct JournalTimelineRow: View {
    @EnvironmentObject private var settings: AppSettings
    let entry: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(rowTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if !entry.imageFilenames.isEmpty {
                    Label("\(entry.imageFilenames.count)", systemImage: "photo")
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

            if !previewBody.isEmpty {
                Text(previewBody)
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

    private var previewBody: String {
        let body = entry.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, !body.isEmpty {
            return body
        }
        if title.isEmpty {
            // previewText already used body; avoid repeating when no tags either
            return entry.tags.isEmpty ? "" : body
        }
        return body
    }
}

// MARK: - Editor

private struct JournalEditorPane: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: JournalStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var draft = JournalEntry()
    @State private var tagInput = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var isImportingImages = false
    @State private var showDeleteConfirm = false

    var body: some View {
        Group {
            if store.selectedEntry == nil {
                noSelection
            } else {
                editor
            }
        }
        .background(JournalChrome.background(for: colorScheme))
        .onChange(of: store.selectedEntryID) { newID in
            loadDraft(for: newID)
        }
        .onAppear {
            loadDraft(for: store.selectedEntryID)
        }
        .fileImporter(
            isPresented: $isImportingImages,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result, let id = store.selectedEntryID else {
                return
            }
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer {
                    if scoped {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                _ = store.addImage(from: url, to: id)
            }
            reloadDraftImages()
        }
        .confirmationDialog(
            L10n.string(.journalDeleteConfirm, language: settings.language),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.string(.journalDelete, language: settings.language), role: .destructive) {
                if let id = store.selectedEntryID {
                    store.deleteEntry(id: id)
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
                tagsSection
                bodySection
                imagesSection
                footerActions
            }
            .padding(28)
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
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

                Spacer()

                Text(L10n.string(.journalAutosaved, language: settings.language))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            TextField(
                L10n.string(.journalTitlePlaceholder, language: settings.language),
                text: Binding(
                    get: { draft.title },
                    set: { draft.title = $0; scheduleSave() }
                )
            )
            .font(.system(size: 26, weight: .semibold, design: .rounded))
            .textFieldStyle(.plain)
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string(.journalTags, language: settings.language))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack(spacing: 8) {
                TextField(
                    L10n.string(.journalTagPlaceholder, language: settings.language),
                    text: $tagInput
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit(addTagFromInput)

                Button(L10n.string(.journalAddTag, language: settings.language)) {
                    addTagFromInput()
                }
                .disabled(tagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !draft.tags.isEmpty {
                FlowTagLayout(spacing: 6) {
                    ForEach(draft.tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                            Button {
                                draft.tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
                                scheduleSave()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(Color.accentColor.opacity(0.28), lineWidth: 1)
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                }
            }

            Text(L10n.string(.journalTagHint, language: settings.language))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(JournalChrome.cardFill(for: colorScheme))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(JournalChrome.cardStroke(for: colorScheme), lineWidth: 1)
        }
    }

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string(.journalBody, language: settings.language))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            TextEditor(
                text: Binding(
                    get: { draft.body },
                    set: { draft.body = $0; scheduleSave() }
                )
            )
            .font(.system(size: 14, weight: .regular, design: .default))
            .frame(minHeight: 220)
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
                if draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(L10n.string(.journalBodyPlaceholder, language: settings.language))
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var imagesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.string(.journalImages, language: settings.language))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                Button {
                    pasteImage()
                } label: {
                    Label(
                        L10n.string(.journalPasteImage, language: settings.language),
                        systemImage: "doc.on.clipboard"
                    )
                }
                .help(L10n.string(.journalPasteImageHelp, language: settings.language))

                Button {
                    isImportingImages = true
                } label: {
                    Label(
                        L10n.string(.journalAddImage, language: settings.language),
                        systemImage: "photo.badge.plus"
                    )
                }
            }

            if draft.imageFilenames.isEmpty {
                Text(L10n.string(.journalImagesHint, language: settings.language))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                            .foregroundStyle(Color.primary.opacity(0.15))
                    )
                    .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
                        handleDrop(providers)
                    }
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(draft.imageFilenames, id: \.self) { filename in
                        JournalImageThumb(
                            filename: filename,
                            onDelete: {
                                guard let id = store.selectedEntryID else { return }
                                store.removeImage(filename: filename, from: id)
                                reloadDraftImages()
                            }
                        )
                    }
                }
                .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
                    handleDrop(providers)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(JournalChrome.cardFill(for: colorScheme))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(JournalChrome.cardStroke(for: colorScheme), lineWidth: 1)
        }
    }

    private var footerActions: some View {
        HStack {
            Button(role: .destructive) {
                showDeleteConfirm = true
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

    // MARK: - Draft helpers

    private func loadDraft(for id: UUID?) {
        saveTask?.cancel()
        guard let id, let entry = store.entries.first(where: { $0.id == id }) else {
            draft = JournalEntry()
            tagInput = ""
            return
        }
        draft = entry
        tagInput = ""
    }

    private func reloadDraftImages() {
        guard let id = store.selectedEntryID,
              let entry = store.entries.first(where: { $0.id == id })
        else {
            return
        }
        draft.imageFilenames = entry.imageFilenames
        draft.updatedAt = entry.updatedAt
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

    private func addTagFromInput() {
        let raw = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }

        let pieces = raw
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "，" || $0 == ";" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for piece in pieces {
            if !draft.tags.contains(where: { $0.caseInsensitiveCompare(piece) == .orderedSame }) {
                draft.tags.append(piece)
            }
        }
        tagInput = ""
        scheduleSave()
    }

    private func pasteImage() {
        guard let id = store.selectedEntryID else { return }
        if store.pasteImageFromClipboard(to: id) {
            reloadDraftImages()
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let id = store.selectedEntryID else { return false }
        var accepted = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                accepted = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in
                        _ = store.addImage(from: data, to: id, preferredExtension: "png")
                        reloadDraftImages()
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
                        _ = store.addImage(from: url, to: id)
                        reloadDraftImages()
                    }
                }
            }
        }

        return accepted
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
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 120, maxHeight: 160)
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

// MARK: - Simple flow layout for tags

private struct FlowTagLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widthUsed: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            widthUsed = max(widthUsed, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth.isFinite ? maxWidth : widthUsed, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
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


