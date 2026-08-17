import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WickSync

// MARK: - Item card
struct JournalItemEditorCard: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: JournalStore
    @Environment(\.wickPalette) private var palette

    /// Owning day entry — required so image deletion stays correct in multi-day timelines.
    let entryID: UUID
    /// Owning entry's day key ("yyyy-MM-dd") — matches exchange positions by open date.
    let entryDayKey: String
    let index: Int
    @Binding var item: JournalItem
    let canDelete: Bool
    /// True when the owning entry is older than today — reviews open next day.
    let reviewEligible: Bool
    let onDelete: () -> Void
    let onPasteImage: () -> Bool
    let onPickImage: () -> Void
    let onDrop: ([NSItemProvider]) -> Bool
    let onChange: () -> Void

    @State private var showReviewPopover = false
    /// Pre-verdict note text; merges into the review when one is picked,
    /// discarded when the popover is dismissed without a verdict.
    @State private var reviewNoteDraft = ""

    var body: some View {
        // One flat surface per item: no inner boxes. Tag, body, and images
        // read as one continuous piece; only whitespace and type color set
        // them apart.
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text(
                    String(
                        format: L10n.string(.journalItemNumberFormat, language: settings.language),
                        index + 1
                    )
                )
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(0.4)
                // CJK ink sits low in its line box; nudge up so the label
                // optically centers with the 28pt icon buttons in this row.
                .offset(y: -2)

                Spacer()

                Button(action: onPickImage) {
                    Image(systemName: "photo.badge.plus")
                }
                .buttonStyle(JournalQuietIconButtonStyle())
                .help(L10n.string(.journalAddImage, language: settings.language))
                .accessibilityLabel(Text(L10n.string(.journalAddImage, language: settings.language)))

                if canDelete {
                    Button(action: onDelete) {
                        // minus.circle ink rides ~1pt low versus the photo
                        // glyph beside it — lift it into optical alignment.
                        Image(systemName: "minus.circle")
                            .offset(y: -1)
                    }
                    .buttonStyle(JournalQuietIconButtonStyle(role: .destructive))
                    .help(L10n.string(.journalDeleteItem, language: settings.language))
                    .accessibilityLabel(Text(L10n.string(.journalDeleteItem, language: settings.language)))
                }
            }

            IMESafeTextField(
                text: Binding(
                    get: { item.tag },
                    set: { item.tag = $0 }
                ),
                placeholder: L10n.string(.journalItemTagPlaceholder, language: settings.language),
                font: .systemFont(ofSize: 13, weight: .medium),
                textColor: palette.accentText.nsColor,
                style: .plain,
                onChange: onChange,
                onPasteImage: onPasteImage
            )
            .frame(height: 22)

            IMESafeTextEditor(
                text: Binding(
                    get: { item.body },
                    set: { item.body = $0 }
                ),
                font: .systemFont(ofSize: 14),
                // ~2–3 lines empty; grows with content so short notes stay compact.
                minHeight: 48,
                maxHeight: nil,
                onChange: onChange,
                onPasteImage: onPasteImage
            )
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: .topLeading) {
                // Aligned with the text view's first line: 0 (no editor
                // padding) + 5 (NSTextView line fragment padding).
                if item.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(L10n.string(.journalBodyPlaceholder, language: settings.language))
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .allowsHitTesting(false)
                }
            }

            imagesSection

            JournalExchangePositions(entryDayKey: entryDayKey, tag: item.tag)

            if !noteText.isEmpty || item.review != nil || reviewEligible {
                HStack(alignment: .bottom, spacing: 8) {
                    if !noteText.isEmpty {
                        // The seal says the verdict, this marked line carries
                        // the annotation. (Italic is a no-op for CJK, so the
                        // marker + secondary color do the distinguishing.)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "pencil.line")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(palette.textTertiary.color)
                            Text(noteText)
                                .font(.system(size: 13))
                                .foregroundStyle(palette.textSecondary.color)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer(minLength: 0)

                    reviewSlot
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.cardTop.scaledAlpha(0.65).color)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(palette.cardStroke.scaledAlpha(0.5).color, lineWidth: 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            // The journal window object is reused across open/close — reset
            // the popover state so it cannot re-present on the next open.
            showReviewPopover = false
        }
        // The whole card is the image drop zone (the images section itself
        // collapses to zero height when the item has no images).
        .onDrop(of: [.image, .fileURL], isTargeted: nil, perform: onDrop)
    }

    // MARK: Review

    private var noteText: String {
        item.review?.note.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Bottom-right "stamp corner": the 复盘 button while unreviewed, the
    /// enlarged decorative seal once a verdict exists. Both open the same
    /// review popover.
    @ViewBuilder
    private var reviewSlot: some View {
        if let review = item.review {
            Button {
                showReviewPopover = true
            } label: {
                JournalReviewBadge(verdict: review.verdict, style: .seal, size: 56)
            }
            .buttonStyle(.plain)
            .help(L10n.string(.journalReviewHelp, language: settings.language))
            .accessibilityLabel(Text(verdictName(review.verdict)))
            .popover(isPresented: $showReviewPopover, arrowEdge: .top) {
                reviewPopoverContent
            }
        } else if reviewEligible {
            Button {
                showReviewPopover = true
            } label: {
                Text(L10n.string(.journalReview, language: settings.language))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.accentText.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .strokeBorder(palette.controlBorder.color, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help(L10n.string(.journalReviewHelp, language: settings.language))
            .accessibilityLabel(Text(L10n.string(.journalReviewHelp, language: settings.language)))
            .popover(isPresented: $showReviewPopover, arrowEdge: .top) {
                reviewPopoverContent
            }
        }
    }

    /// Verdict picker inside a popover: clicking anywhere outside dismisses
    /// it (sidebar, other cards, closing the window), so an abandoned picker
    /// can never linger. Picking a verdict also dismisses it. The note field
    /// is always present; before a verdict exists the note is a local draft
    /// that merges into the review the moment one is picked (and is
    /// discarded if the popover is abandoned).
    private var reviewPopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                ForEach([JournalReviewVerdict.correct, .wrong], id: \.self) { verdict in
                    verdictButton(verdict)
                }

                if item.review != nil {
                    Spacer(minLength: 4)
                    Button(action: clearReview) {
                        Text(L10n.string(.journalReviewClear, language: settings.language))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.textTertiary.color)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(L10n.string(.journalReviewClear, language: settings.language)))
                }
            }

            IMESafeTextField(
                text: Binding(
                    get: { item.review?.note ?? reviewNoteDraft },
                    set: { newValue in
                        if item.review != nil {
                            item.review?.note = newValue
                            item.review?.updatedAt = Date()
                        } else {
                            reviewNoteDraft = newValue
                        }
                    }
                ),
                placeholder: L10n.string(.journalReviewNotePlaceholder, language: settings.language),
                font: .systemFont(ofSize: 13),
                textColor: palette.textSecondary.nsColor,
                style: .plain,
                onChange: {
                    // Draft notes persist only when a verdict is picked.
                    if item.review != nil { onChange() }
                },
                onPasteImage: onPasteImage
            )
            .frame(width: 220, height: 22)
        }
        .padding(10)
        .onChange(of: showReviewPopover) { presented in
            if !presented { reviewNoteDraft = "" }
        }
    }

    /// The seal itself is the option: full strength when selectable, dimmed
    /// when another verdict already holds the review.
    private func verdictButton(_ verdict: JournalReviewVerdict) -> some View {
        let isActive = item.review?.verdict == verdict
        return Button {
            setVerdict(verdict)
        } label: {
            JournalReviewBadge(verdict: verdict, style: .seal)
                .opacity(item.review == nil || isActive ? 1 : 0.3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verdictName(verdict)))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func setVerdict(_ verdict: JournalReviewVerdict) {
        if var review = item.review {
            review.verdict = verdict
            review.updatedAt = Date()
            item.review = review
        } else {
            item.review = JournalReview(verdict: verdict, note: reviewNoteDraft)
        }
        reviewNoteDraft = ""
        onChange()
        showReviewPopover = false
    }

    private func clearReview() {
        item.review = nil
        onChange()
        showReviewPopover = false
    }

    private func verdictName(_ verdict: JournalReviewVerdict) -> String {
        let key: L10n.Key
        switch verdict {
        case .correct: key = .journalReviewCorrect
        case .wrong: key = .journalReviewWrong
        }
        return L10n.string(key, language: settings.language)
    }

    private var imagesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !item.imageFilenames.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 140), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(item.imageFilenames, id: \.self) { filename in
                        JournalImageThumb(
                            filename: filename,
                            onDelete: {
                                store.removeImage(filename: filename, from: entryID, itemID: item.id)
                                item.imageFilenames.removeAll { $0 == filename }
                            }
                        )
                    }
                }
            }
        }
    }
}

struct JournalImageThumb: View {
    @EnvironmentObject private var settings: AppSettings
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
            }
            .buttonStyle(JournalQuietIconButtonStyle(role: .destructive, fontSize: 16, alwaysShowOnDarkChrome: true))
            .help(L10n.string(.journalDeleteItem, language: settings.language))
            .accessibilityLabel(Text(L10n.string(.journalDeleteItem, language: settings.language)))
            .padding(4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

// MARK: - Quiet icon buttons

/// Journal chrome icon control: glyph always uses the day-arc theme color;
/// hover/press only adds a soft mask behind the icon (no gray idle state).
struct JournalQuietIconButtonStyle: ButtonStyle {
    enum Role {
        case regular
        case destructive
    }

    var role: Role = .regular
    var fontSize: CGFloat = 14
    /// Thumbnail “x” sits on photos — white glyph on a dim disc.
    var alwaysShowOnDarkChrome: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        JournalQuietIconButtonBody(
            configuration: configuration,
            role: role,
            fontSize: fontSize,
            alwaysShowOnDarkChrome: alwaysShowOnDarkChrome
        )
    }
}

private struct JournalQuietIconButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let role: JournalQuietIconButtonStyle.Role
    let fontSize: CGFloat
    let alwaysShowOnDarkChrome: Bool

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.wickPalette) private var palette

    var body: some View {
        let active = isHovered || configuration.isPressed
        configuration.label
            .font(.system(size: fontSize, weight: .medium))
            .symbolRenderingMode(.monochrome)
            // Themed glyph stays the same; only the mask below reacts to hover.
            .foregroundStyle(glyphColor)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hoverMask(active: active))
            )
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: active)
    }

    private var glyphColor: Color {
        if alwaysShowOnDarkChrome {
            return .white
        }
        switch role {
        case .regular:
            // Same family as tags / accent controls — follows day-arc phase.
            return palette.accentText.color
        case .destructive:
            // Quiet gray by default (delete should not scream until hover).
            return palette.textTertiary.color
        }
    }

    private func hoverMask(active: Bool) -> Color {
        if alwaysShowOnDarkChrome {
            // Always need a disc over the photo; deepen slightly on hover.
            return Color.black.opacity(active ? 0.55 : 0.32)
        }
        guard active else { return .clear }
        switch role {
        case .regular:
            return palette.accentSoft.color
        case .destructive:
            // Soft neutral mask only — no permanent red glyph.
            return palette.controlBackground.color.opacity(0.9)
        }
    }
}

