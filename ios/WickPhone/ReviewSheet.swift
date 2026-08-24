import SwiftUI
import UIKit
import WickCalendarKit
import WickSync

/// Sheet for reviewing a journal item: choose verdict (对 / 错), write notes, and stamp.
/// Pure seal stamp aesthetics matching macOS — no redundant slogans or text clutter.
struct ReviewSheet: View {
    let item: JournalItem
    let onCommit: (JournalReview?) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language

    @State private var verdict: JournalReviewVerdict = .correct
    @State private var noteDraft: String = ""
    private let hadExistingReview: Bool

    init(item: JournalItem, onCommit: @escaping (JournalReview?) -> Void) {
        self.item = item
        self.onCommit = onCommit
        self.hadExistingReview = item.review != nil
        if let existing = item.review {
            _verdict = State(initialValue: existing.verdict)
            _noteDraft = State(initialValue: existing.note)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Drag handle
                Capsule()
                    .fill(PhoneTheme.inkTertiary.opacity(0.4))
                    .frame(width: 38, height: 4)
                    .padding(.top, 8)

                // Header
                Text(L10n.string(.journalReview, language: language))
                    .font(PhoneFont.paper(16, weight: .bold))
                    .foregroundColor(PhoneTheme.inkPrimary)

                // Pure Seal Stamp Choice
                HStack(spacing: 28) {
                    SealChoiceButton(
                        verdict: .correct,
                        isSelected: verdict == .correct,
                        language: language
                    ) {
                        verdict = .correct
                        triggerHapticFeedback()
                    }

                    SealChoiceButton(
                        verdict: .wrong,
                        isSelected: verdict == .wrong,
                        language: language
                    ) {
                        verdict = .wrong
                        triggerHapticFeedback()
                    }
                }
                .padding(.vertical, 8)

                // Optional note area
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string(.reviewNoteLabel, language: language))
                        .font(PhoneFont.paper(11, weight: .medium))
                        .foregroundColor(PhoneTheme.inkTertiary)

                    ZStack(alignment: .topLeading) {
                        if noteDraft.isEmpty {
                            Text(L10n.string(.journalReviewNotePlaceholder, language: language))
                                .font(PhoneFont.paper(13))
                                .foregroundColor(PhoneTheme.inkTertiary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $noteDraft)
                            .font(PhoneFont.paper(13))
                            .foregroundColor(PhoneTheme.inkPrimary)
                            .frame(height: 72)
                            .padding(8)
                            .scrollContentBackground(.hidden)
                            .background(PhoneTheme.paper)
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(PhoneTheme.rule, lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 0)

                // Action Buttons
                VStack(spacing: 10) {
                    Button {
                        let review = JournalReview(
                            verdict: verdict,
                            note: noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        triggerHapticFeedback()
                        onCommit(review)
                        dismiss()
                    } label: {
                        Text(L10n.string(.stampReview, language: language))
                            .font(PhoneFont.paper(14, weight: .bold))
                            .foregroundColor(Color(red: 0.98, green: 0.95, blue: 0.90))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(PhoneTheme.cinnabar)
                            .cornerRadius(6)
                            .shadow(color: PhoneTheme.cinnabar.opacity(0.35), radius: 4, y: 2)
                    }

                    if hadExistingReview {
                        Button {
                            triggerHapticFeedback()
                            onCommit(nil)
                            dismiss()
                        } label: {
                            Text(L10n.string(.journalReviewClear, language: language))
                                .font(PhoneFont.paper(12, weight: .medium))
                                .foregroundColor(PhoneTheme.inkTertiary)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .background(PhoneTheme.paperHi.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.string(.cancel, language: language)) { dismiss() }
                        .font(PhoneFont.paper(13))
                        .foregroundColor(PhoneTheme.inkSecondary)
                }
            }
        }
        .presentationDetents([.fraction(0.48), .medium])
        .presentationDragIndicator(.hidden)
    }

    private func triggerHapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}

private struct SealChoiceButton: View {
    let verdict: JournalReviewVerdict
    let isSelected: Bool
    let language: AppLanguage
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                JournalReviewBadge(verdict: verdict, style: .seal, size: 52, language: language)
                    .opacity(isSelected ? 1.0 : 0.35)
                    .scaleEffect(isSelected ? 1.05 : 0.95)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)

                // Selection Indicator Bar
                Rectangle()
                    .fill(isSelected ? PhoneTheme.cinnabar : Color.clear)
                    .frame(width: 24, height: 2)
                    .cornerRadius(1)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? PhoneTheme.paper : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? PhoneTheme.rule : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
