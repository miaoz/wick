import SwiftUI
import UIKit
import WickCalendarKit
import WickSync
import WickTrading

/// Single day journal editor: "一天一页纸" (One day, one sheet).
/// Edits a local draft and saves debounced. Commits on flush/disappear/background.
struct EditorView: View {
    @EnvironmentObject private var store: PhoneJournalStore
    @EnvironmentObject private var exchangeCoordinator: PhoneExchangeCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language: AppLanguage

    @State private var draft: JournalEntry
    @State private var originalEntry: JournalEntry
    @State private var saveTask: Task<Void, Never>?
    @State private var isDirty = false
    @State private var reviewingItemIndex: Int?
    @State private var imagePreviewState: PhoneImagePreviewState?
    @State private var showDeleteDayConfirm = false
    @State private var showDeleteItemConfirm = false
    @State private var pendingDeleteItemIndex: Int?

    init(entry: JournalEntry) {
        _draft = State(initialValue: entry)
        _originalEntry = State(initialValue: entry)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 16) {
                    // Top Navigation Bar (Back + Delete Day)
                    HStack {
                        Button {
                            saveNow()
                            dismiss()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(PhoneFont.ui(13, weight: .semibold))
                                Text(L10n.string(.back, language: language))
                                    .font(PhoneFont.paper(12.5, weight: .medium))
                            }
                            .foregroundColor(PhoneTheme.inkSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(PhoneTheme.paperHi)
                            .cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
                        }

                        Spacer()

                        Button {
                            showDeleteDayConfirm = true
                        } label: {
                            Image(systemName: "trash")
                                .font(PhoneFont.ui(13, weight: .medium))
                                .foregroundColor(PhoneTheme.char.opacity(0.75))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(PhoneTheme.paperHi)
                                .cornerRadius(4)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
                        }
                        .accessibilityLabel(Text(L10n.string(.journalDelete, language: language)))
                    }
                    .padding(.horizontal, 2)
                    .padding(.top, 2)

                    // Main Paper Sheet Card
                    VStack(alignment: .leading, spacing: 14) {
                        // Header
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Self.dateDisplay(for: draft.date, language: language))
                                    .font(PhoneFont.paper(28, weight: .black))
                                    .foregroundColor(PhoneTheme.inkPrimary)

                                if let lunar = LunarLine.string(for: draft.date) {
                                    Text(lunar)
                                        .font(PhoneFont.paper(11))
                                        .foregroundColor(PhoneTheme.inkSecondary)
                                }
                            }

                            Spacer()

                            // Today PnL summary badge
                            VStack(alignment: .trailing, spacing: 2) {
                                if let pnl = exchangeCoordinator.pnl(for: draft.date) {
                                    let isGain = pnl >= 0
                                    Text(L10n.string(.exchangePositionRealizedPnl, language: language))
                                        .font(PhoneFont.preset(.caption2))
                                        .foregroundColor(PhoneTheme.inkTertiary)
                                    Text("\(isGain ? "+" : "")\(String(format: "%.2f", pnl)) USDT")
                                        .font(PhoneFont.ui(13, weight: .bold, monospacedDigit: true))
                                        .foregroundColor(PhoneTheme.pnlColor(isGain: isGain))
                                } else {
                                    Text(L10n.string(.todayRecordsTitle, language: language))
                                        .font(PhoneFont.preset(.caption2))
                                        .foregroundColor(PhoneTheme.inkTertiary)
                                    Text(String(format: L10n.string(.recordsCountFormat, language: language), draft.items.count))
                                        .font(PhoneFont.ui(13, weight: .bold, monospacedDigit: true))
                                        .foregroundColor(PhoneTheme.cinnabar)
                                }
                            }
                        }

                        // Day Burn Strip
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let fraction = TimeProgressCalculator.dayFractionRemaining(at: context.date)
                            BurnStripView(
                                elapsed: 1.0 - fraction,
                                ticks: 24,
                                showsFlame: Calendar.current.isDateInToday(draft.date)
                            )
                            .frame(height: 10)
                        }

                        Divider()
                            .background(PhoneTheme.rule)

                        // Journal Items List
                        if draft.items.isEmpty {
                            VStack(spacing: 8) {
                                Text(L10n.string(.journalEmptyTitle, language: language))
                                    .font(PhoneFont.paper(15))
                                    .foregroundColor(PhoneTheme.inkTertiary)
                                Text(language == .chinese ? "点击右下角按钮写下第一笔交易想法…" : "Tap the plus button to add an entry…")
                                    .font(PhoneFont.preset(.caption))
                                    .foregroundColor(PhoneTheme.inkTertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                        } else {
                            ForEach(Array(draft.items.enumerated()), id: \.element.id) { idx, item in
                                let matchedPositions = exchangeCoordinator.positions(entryDate: draft.date, tag: item.tag)

                                ItemRowView(
                                    index: idx,
                                    item: $draft.items[idx],
                                    canDelete: draft.items.count > 1,
                                    matchedPositions: matchedPositions,
                                    language: language,
                                    imageURL: { store.imageURL(for: $0) },
                                    onReviewTap: {
                                        reviewingItemIndex = idx
                                    },
                                    onDelete: {
                                        requestDeleteItem(at: idx)
                                    },
                                    onImageTap: { filenames, imgIdx in
                                        imagePreviewState = PhoneImagePreviewState(filenames: filenames, currentIndex: imgIdx)
                                    },
                                    onChange: scheduleSave
                                )

                                if idx < draft.items.count - 1 {
                                    Divider()
                                        .background(PhoneTheme.rule)
                                }
                            }
                        }
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(PhoneTheme.paperHi)
                            .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(PhoneTheme.rule, lineWidth: 1)
                    )
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 90)
            }

            // Floating Action Button (FAB)
            Button {
                let defaultTag = language == .chinese ? "计划" : "Plan"
                let newItem = JournalItem(
                    id: UUID(),
                    tag: defaultTag,
                    body: ""
                )
                draft.items.append(newItem)
                scheduleSave()
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.bold))
                    .foregroundColor(Color(red: 0.98, green: 0.95, blue: 0.90))
                    .frame(width: 52, height: 52)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [PhoneTheme.emberHi, PhoneTheme.ember],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: PhoneTheme.ember.opacity(0.4), radius: 8, x: 0, y: 4)
                    )
            }
            .padding(.trailing, 20)
            .padding(.bottom, 24)
        }
        .background(PhoneTheme.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .scrollDismissesKeyboard(.interactively)
        .sheet(item: Binding(
            get: {
                reviewingItemIndex.flatMap { idx in
                    idx < draft.items.count ? ItemReviewTarget(index: idx, item: draft.items[idx]) : nil
                }
            },
            set: { _ in reviewingItemIndex = nil }
        )) { target in
            ReviewSheet(item: target.item) { review in
                draft.items[target.index].review = review
                scheduleSave()
            }
        }
        .alert(
            L10n.string(.journalDeleteConfirm, language: language),
            isPresented: $showDeleteDayConfirm
        ) {
            Button(L10n.string(.journalDelete, language: language), role: .destructive) {
                store.deleteEntry(entryID: draft.id)
                dismiss()
            }
            Button(L10n.string(.cancel, language: language), role: .cancel) {}
        } message: {
            Text(language == .chinese ? "删除后将无法恢复此日的全部条目。" : "This will permanently delete all entries for this day.")
        }
        .alert(
            L10n.string(.journalDeleteItemConfirm, language: language),
            isPresented: $showDeleteItemConfirm
        ) {
            Button(L10n.string(.journalDeleteItem, language: language), role: .destructive) {
                if let idx = pendingDeleteItemIndex {
                    performDeleteItem(at: idx)
                    pendingDeleteItemIndex = nil
                }
            }
            Button(L10n.string(.cancel, language: language), role: .cancel) {
                pendingDeleteItemIndex = nil
            }
        }
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
        .overlay {
            if imagePreviewState != nil {
                PhoneImagePreviewOverlay(
                    state: $imagePreviewState,
                    imageURL: { store.imageURL(for: $0) },
                    language: language
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(100)
            }
        }
        .animation(.easeOut(duration: 0.2), value: imagePreviewState != nil)
    }

    private func requestDeleteItem(at index: Int) {
        guard index < draft.items.count else { return }
        let item = draft.items[index]
        let hasContent = !item.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                         !item.imageFilenames.isEmpty ||
                         item.review != nil
        if hasContent {
            pendingDeleteItemIndex = index
            showDeleteItemConfirm = true
        } else {
            performDeleteItem(at: index)
        }
    }

    private func performDeleteItem(at index: Int) {
        guard index < draft.items.count else { return }
        draft.items.remove(at: index)
        if draft.items.isEmpty {
            let defaultTag = language == .chinese ? "计划" : "Plan"
            draft.items = [JournalItem(id: UUID(), tag: defaultTag, body: "")]
        }
        scheduleSave()
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
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
        guard isDirty, !store.isReadOnlyDueToLoadFailure else { return }
        store.updateEntry(draft)
        isDirty = false
    }

    private func rebaseIfClean(_ apply: JournalRemoteApply) {
        guard apply.entryID == draft.id, !isDirty else { return }
        if let fresh = store.entries.first(where: { $0.id == apply.entryID }) {
            draft = fresh
        }
    }

    private static func dateDisplay(for date: Date, language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateFormat = language == .chinese ? "M月d日" : "MMM d"
        return formatter.string(from: date)
    }
}

private struct ItemReviewTarget: Identifiable {
    var id: UUID { item.id }
    let index: Int
    let item: JournalItem
}

private struct ItemRowView: View {
    let index: Int
    @Binding var item: JournalItem
    let canDelete: Bool
    let matchedPositions: [TradingPosition]
    let language: AppLanguage
    let imageURL: (String) -> URL?
    let onReviewTap: () -> Void
    let onDelete: () -> Void
    let onImageTap: ([String], Int) -> Void
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top bar: Item Index + Tag Chip + Spacer + Delete Item Button (minus.circle)
            HStack(alignment: .center, spacing: 8) {
                Text(String(format: L10n.string(.journalItemNumberFormat, language: language), index + 1))
                    .font(PhoneFont.ui(10, weight: .medium, monospacedDigit: true))
                    .foregroundColor(PhoneTheme.inkTertiary)

                TextField(language == .chinese ? "标签" : "Tag", text: $item.tag)
                    .font(PhoneFont.paper(11, weight: .bold))
                    .foregroundColor(PhoneTheme.cinnabar)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(PhoneTheme.cinnabarSoft)
                    )
                    .frame(maxWidth: 120)
                    .onChange(of: item.tag) { _ in onChange() }

                Spacer()

                if canDelete {
                    Button(action: onDelete) {
                        Image(systemName: "minus.circle")
                            .font(PhoneFont.ui(13, weight: .medium))
                            .foregroundColor(PhoneTheme.char.opacity(0.6))
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(L10n.string(.journalDeleteItem, language: language)))
                }
            }

            // Body editor
            TextEditor(text: $item.body)
                .font(PhoneFont.paper(13.5))
                .lineSpacing(PhoneFont.paperLineSpacing(13.5))
                .foregroundColor(PhoneTheme.inkPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 56)
                .onChange(of: item.body) { _ in onChange() }

            // Exchange trade receipts if matched
            if !matchedPositions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(matchedPositions) { position in
                        PhoneReceiptCard(position: position)
                    }
                }
                .padding(.top, 2)
            }

            // Images horizontal scroll with tap-to-preview
            if !item.imageFilenames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(item.imageFilenames.enumerated()), id: \.offset) { imgIdx, filename in
                            if let url = imageURL(filename),
                               let image = UIImage(contentsOfFile: url.path) {
                                Button {
                                    onImageTap(item.imageFilenames, imgIdx)
                                } label: {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(PhoneTheme.rule, lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            // Bottom bar: Review note quote on left + Review seal/button on bottom-right
            HStack(alignment: .bottom, spacing: 8) {
                if let review = item.review, !review.note.isEmpty {
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(review.verdict == .correct ? PhoneTheme.cinnabar : PhoneTheme.dai)
                            .frame(width: 2)
                        Text(review.note)
                            .font(PhoneFont.paper(11))
                            .lineSpacing(PhoneFont.paperLineSpacing(11))
                            .foregroundColor(PhoneTheme.inkSecondary)
                            .padding(.vertical, 2)
                    }
                    .padding(.horizontal, 6)
                    .background(PhoneTheme.paper)
                    .cornerRadius(3)
                }

                Spacer(minLength: 0)

                Button(action: onReviewTap) {
                    if let review = item.review {
                        JournalReviewBadge(verdict: review.verdict, style: .mini, size: 36, language: language)
                    } else {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.seal")
                                .font(PhoneFont.ui(9.5, weight: .bold))
                            Text(L10n.string(.journalReview, language: language))
                                .font(PhoneFont.paper(11, weight: .bold))
                        }
                        .foregroundColor(PhoneTheme.cinnabar.opacity(0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(PhoneTheme.cinnabarSoft)
                        .cornerRadius(3)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}
