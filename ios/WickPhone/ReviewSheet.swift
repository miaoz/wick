import SwiftUI
import UIKit
import WickSync

/// Sheet for reviewing a journal item: choose verdict (对 / 错), write notes, and stamp.
struct ReviewSheet: View {
    let item: JournalItem
    let onCommit: (JournalReview) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var verdict: JournalReviewVerdict = .correct
    @State private var noteDraft: String = ""

    init(item: JournalItem, onCommit: @escaping (JournalReview) -> Void) {
        self.item = item
        self.onCommit = onCommit
        if let existing = item.review {
            _verdict = State(initialValue: existing.verdict)
            _noteDraft = State(initialValue: existing.note)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Drag handle
                Capsule()
                    .fill(PhoneTheme.inkTertiary.opacity(0.4))
                    .frame(width: 38, height: 4)
                    .padding(.top, 8)

                Text("盖印复盘")
                    .font(.system(.title3, design: .serif).weight(.bold))
                    .foregroundColor(PhoneTheme.inkPrimary)

                // Choice cards
                HStack(spacing: 14) {
                    VerdictCard(
                        verdict: .correct,
                        title: "对 · 遵循系统",
                        desc: "符合策略，盈亏皆是概率",
                        isSelected: verdict == .correct
                    ) {
                        verdict = .correct
                        triggerHapticFeedback()
                    }

                    VerdictCard(
                        verdict: .wrong,
                        title: "错 · 违纪冲动",
                        desc: "情绪交易、扛单或未按计划",
                        isSelected: verdict == .wrong
                    ) {
                        verdict = .wrong
                        triggerHapticFeedback()
                    }
                }
                .padding(.horizontal)

                // Optional note area
                VStack(alignment: .leading, spacing: 6) {
                    Text("复盘反思批注（可选）")
                        .font(.caption)
                        .foregroundColor(PhoneTheme.inkSecondary)

                    TextEditor(text: $noteDraft)
                        .font(.system(.body, design: .serif))
                        .frame(height: 80)
                        .padding(8)
                        .background(PhoneTheme.paper)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(PhoneTheme.rule, lineWidth: 1)
                        )
                }
                .padding(.horizontal)

                Spacer()

                // Stamp button
                Button {
                    let review = JournalReview(
                        verdict: verdict,
                        note: noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    triggerHapticFeedback()
                    onCommit(review)
                    dismiss()
                } label: {
                    HStack {
                        JournalReviewBadge(verdict: verdict, style: .mini, size: 22)
                        Text("盖下朱砂方章")
                            .font(.headline)
                    }
                    .foregroundColor(Color(red: 0.98, green: 0.95, blue: 0.90))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(PhoneTheme.cinnabar)
                            .shadow(color: PhoneTheme.cinnabar.opacity(0.35), radius: 6, y: 2)
                    )
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            .background(PhoneTheme.paperHi.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundColor(PhoneTheme.inkSecondary)
                }
            }
        }
        .presentationDetents([.fraction(0.55), .medium])
        .presentationDragIndicator(.hidden)
    }

    private func triggerHapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}

private struct VerdictCard: View {
    let verdict: JournalReviewVerdict
    let title: String
    let desc: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                JournalReviewBadge(verdict: verdict, style: .mini, size: 36)

                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(PhoneTheme.inkPrimary)

                Text(desc)
                    .font(.caption2)
                    .foregroundColor(PhoneTheme.inkTertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? PhoneTheme.cinnabarSoft : PhoneTheme.paper)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? PhoneTheme.cinnabar : PhoneTheme.rule, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
