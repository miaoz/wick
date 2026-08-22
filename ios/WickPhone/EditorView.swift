import SwiftUI
import UIKit
import WickSync

/// Day editor: title + item cards (tag, body, images). Edits a local draft and
/// saves debounced; the draft commits on flush (remote apply / journal switch),
/// on disappear, and on scenePhase transition so the app-level Store flush
/// never sees uncommitted view state.
struct EditorView: View {
    @EnvironmentObject private var store: PhoneJournalStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var draft: JournalEntry
    @State private var saveTask: Task<Void, Never>?
    /// True while the draft differs from the store — a dirty draft is never
    /// rebased by a remote apply (it commits/merges on its own later).
    @State private var isDirty = false

    init(entry: JournalEntry) {
        _draft = State(initialValue: entry)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("标题（可选）", text: $draft.title)
                    .font(.headline)
                    .onChange(of: draft.title) { _ in scheduleSave() }

                ForEach($draft.items) { $item in
                    ItemCard(
                        item: $item,
                        imageURL: { store.imageURL(for: $0) },
                        onChange: scheduleSave
                    )
                }

                Button {
                    draft.items.append(JournalItem())
                    scheduleSave()
                } label: {
                    Label("添加条目", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle(Self.headerText(for: draft.date))
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onReceive(NotificationCenter.default.publisher(for: .wickWillFlushJournalDrafts)) { _ in
            saveNow()
        }
        .onReceive(store.remoteEntryDidApply) { apply in
            rebaseIfClean(apply)
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .inactive, .background:
                saveNow()
                store.flushPendingWrites()
            default:
                break
            }
        }
        .onDisappear(perform: saveNow)
    }

    private func scheduleSave() {
        isDirty = true
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        guard !store.isReadOnlyDueToLoadFailure else { return }
        store.updateEntry(draft)
        isDirty = false
    }

    /// A remote apply replaced this day: only rebase a CLEAN draft so the
    /// user's typing is never overwritten by the fresh store value.
    private func rebaseIfClean(_ apply: JournalRemoteApply) {
        guard apply.dayKey == draft.dayKey, !isDirty else { return }
        if let fresh = store.entries.first(where: { $0.dayKey == apply.dayKey }) {
            draft = fresh
        }
    }

    private static func headerText(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
    }
}

private struct ItemCard: View {
    @Binding var item: JournalItem
    let imageURL: (String) -> URL?
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("标签", text: $item.tag)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.orange)
                .onChange(of: item.tag) { _ in onChange() }

            TextEditor(text: $item.body)
                .frame(minHeight: 72)
                .scrollContentBackground(.hidden)
                .onChange(of: item.body) { _ in onChange() }

            if !item.imageFilenames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(item.imageFilenames, id: \.self) { filename in
                            if let url = imageURL(filename),
                               let image = UIImage(contentsOfFile: url.path) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 88, height: 88)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}
