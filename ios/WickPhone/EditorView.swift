import SwiftUI
import UIKit
import WickCalendarKit
import WickSync
import WickTrading

/// Single day journal editor: "一天一页纸" (One day, one sheet).
/// Edits a local draft and saves debounced. Commits on flush/disappear/background.
struct EditorView: View {
    @EnvironmentObject private var store: PhoneJournalStore
    @StateObject private var exchangeCoordinator = PhoneExchangeCoordinator.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var draft: JournalEntry
    @State private var saveTask: Task<Void, Never>?
    @State private var isDirty = false
    @State private var reviewingItemIndex: Int?

    init(entry: JournalEntry) {
        _draft = State(initialValue: entry)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 16) {
                    // Main Paper Sheet Card
                    VStack(alignment: .leading, spacing: 14) {
                        // Header
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Self.dateDisplay(for: draft.date))
                                    .font(.system(size: 28, weight: .black, design: .serif))
                                    .foregroundColor(PhoneTheme.inkPrimary)

                                if let lunar = LunarLine.string(for: draft.date) {
                                    Text(lunar)
                                        .font(.system(size: 11, design: .serif))
                                        .foregroundColor(PhoneTheme.inkSecondary)
                                }
                            }

                            Spacer()

                            // Today PnL summary badge
                            VStack(alignment: .trailing, spacing: 2) {
                                if let pnl = exchangeCoordinator.pnl(for: draft.date) {
                                    let isGain = pnl >= 0
                                    Text("已实现盈亏")
                                        .font(.caption2)
                                        .foregroundColor(PhoneTheme.inkTertiary)
                                    Text("\(isGain ? "+" : "")\(String(format: "%.2f", pnl)) USDT")
                                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                                        .foregroundColor(PhoneTheme.pnlColor(isGain: isGain))
                                } else {
                                    Text("今日记录")
                                        .font(.caption2)
                                        .foregroundColor(PhoneTheme.inkTertiary)
                                    Text("\(draft.items.count) 条目")
                                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
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
                                Text("本日尚无记录")
                                    .font(.system(.subheadline, design: .serif))
                                    .foregroundColor(PhoneTheme.inkTertiary)
                                Text("点击右下角按钮写下第一笔交易想法…")
                                    .font(.caption)
                                    .foregroundColor(PhoneTheme.inkTertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                        } else {
                            ForEach(Array(draft.items.enumerated()), id: \.element.id) { idx, item in
                                let matchedPositions = exchangeCoordinator.positions(entryDate: draft.date, tag: item.tag)

                                ItemRowView(
                                    item: $draft.items[idx],
                                    matchedPositions: matchedPositions,
                                    imageURL: { store.imageURL(for: $0) },
                                    onReviewTap: {
                                        reviewingItemIndex = idx
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
                let newItem = JournalItem(
                    id: UUID(),
                    tag: "计划",
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
        .navigationTitle(Self.headerTitle(for: draft.date))
        .navigationBarTitleDisplayMode(.inline)
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

    private func rebaseIfClean(_ apply: JournalRemoteApply) {
        guard apply.dayKey == draft.dayKey, !isDirty else { return }
        if let fresh = store.entries.first(where: { $0.dayKey == apply.dayKey }) {
            draft = fresh
        }
    }

    private static func dateDisplay(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    private static func headerTitle(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天 · 8月24日" }
        if cal.isDateInYesterday(date) { return "昨天" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
    }
}

private struct ItemReviewTarget: Identifiable {
    var id: UUID { item.id }
    let index: Int
    let item: JournalItem
}

private struct ItemRowView: View {
    @Binding var item: JournalItem
    let matchedPositions: [TradingPosition]
    let imageURL: (String) -> URL?
    let onReviewTap: () -> Void
    let onChange: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Main content
            VStack(alignment: .leading, spacing: 8) {
                // Tag chip + quick edit
                HStack {
                    TextField("标签", text: $item.tag)
                        .font(.system(size: 11, weight: .bold, design: .serif))
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
                }

                // Body editor
                TextEditor(text: $item.body)
                    .font(.system(size: 13.5, design: .serif))
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

                // Images horizontal scroll
                if !item.imageFilenames.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(item.imageFilenames, id: \.self) { filename in
                                if let url = imageURL(filename),
                                   let image = UIImage(contentsOfFile: url.path) {
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
                            }
                        }
                    }
                }

                // Review note quote box if present
                if let review = item.review, !review.note.isEmpty {
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(review.verdict == .correct ? PhoneTheme.cinnabar : PhoneTheme.dai)
                            .frame(width: 2)
                        Text(review.note)
                            .font(.system(size: 11, design: .serif))
                            .foregroundColor(PhoneTheme.inkSecondary)
                            .padding(.vertical, 2)
                    }
                    .padding(.horizontal, 6)
                    .background(PhoneTheme.paper)
                    .cornerRadius(3)
                }
            }

            // Review stamp slot on trailing edge
            Button(action: onReviewTap) {
                if let review = item.review {
                    JournalReviewBadge(verdict: review.verdict, style: .mini, size: 36)
                } else {
                    VStack(spacing: 2) {
                        Text("复盘")
                            .font(.system(size: 10, weight: .bold, design: .serif))
                            .foregroundColor(PhoneTheme.cinnabar)
                    }
                    .frame(width: 36, height: 36)
                    .background(PhoneTheme.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(PhoneTheme.cinnabar.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3]))
                    )
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}
