import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WickSync

/// Which field the user clicked to enter edit mode on an item card (P1).
enum ItemEditorFocus: Equatable {
    case tag
    case body
}

// MARK: - Item card
struct JournalItemEditorCard: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: JournalStore
    @Environment(\.wickPalette) private var palette

    /// Owning day entry — required so image deletion stays correct in multi-day timelines.
    let entryID: UUID
    /// The displayed calendar date used to match exchange position open dates.
    let entryDate: Date
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
    /// False until the user clicks the tag or body: display uses SwiftUI `Text`
    /// so off-screen days stay lazy on macOS 13 (P1).
    let isEditing: Bool
    /// Which field should take first responder when `isEditing` becomes true.
    let initialFocus: ItemEditorFocus
    let onBeginEditing: (ItemEditorFocus) -> Void

    @State private var showReviewPopover = false
    /// Pre-verdict note text; merges into the review when one is picked,
    /// discarded when the popover is dismissed without a verdict.
    @State private var reviewNoteDraft = ""

    var body: some View {
        // 条目 = 纸面上的一段墨迹:无卡片壳,条目之间靠发丝线与留白分隔;
        // 只有复盘章有权浮在内容上(bottomTrailing)。
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Text(
                    String(
                        format: L10n.string(.journalItemNumberFormat, language: settings.language),
                        index + 1
                    )
                )
                .font(AppFont.ui(10, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.textTertiary.color)

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

            tagField

            bodyField

            imagesSection

            JournalExchangePositions(
                entryID: entryID,
                entryDate: entryDate,
                itemID: item.id,
                tag: item.tag
            )

            // The unreviewed call-to-action (and the note) keep a row of
            // their own - only the picked seal gets to float over content.
            if !noteText.isEmpty || (reviewEligible && item.review == nil) {
                HStack(alignment: .bottom, spacing: 8) {
                    if !noteText.isEmpty {
                        noteRow
                    }

                    Spacer(minLength: 0)

                    if item.review == nil {
                        reviewButton
                    }
                }
            }
        }
        .padding(.vertical, 12)
        // Once a verdict is picked, its seal floats over the entry's bottom-
        // trailing corner - covering the button's former spot and whatever
        // sits beneath it (positions, photos, body text) at reduced ink
        // opacity so the content underneath stays readable.
        .overlay(alignment: .bottomTrailing) {
            if let review = item.review {
                floatingReviewSeal(review)
                    .padding(.trailing, 2)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            // The journal window object is reused across open/close - reset
            // the popover state so it cannot re-present on the next open.
            showReviewPopover = false
        }
        // The whole card is the image drop zone (the images section itself
        // collapses to zero height when the item has no images).
        .onDrop(of: [.image, .fileURL], isTargeted: nil, perform: onDrop)
    }

    // MARK: Display / edit fields (P1)

    @ViewBuilder
    private var tagField: some View {
        if isEditing {
            IMESafeTextField(
                text: Binding(
                    get: { item.tag },
                    set: { item.tag = $0 }
                ),
                placeholder: L10n.string(.journalItemTagPlaceholder, language: settings.language),
                font: WickPrintFont.songti(12.5, bold: true),
                textColor: palette.pnlUp.nsColor,
                style: .plain,
                onChange: onChange,
                onPasteImage: onPasteImage,
                becomeFirstResponder: initialFocus == .tag
            )
            .frame(height: 22)
        } else {
            let trimmed = item.tag.trimmingCharacters(in: .whitespacesAndNewlines)
            Text(trimmed.isEmpty ? " " : item.tag)
                .font(AppFont.paper(12.5, weight: .bold))
                .foregroundStyle(trimmed.isEmpty ? Color.clear : palette.pnlUp.color)
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                .overlay(alignment: .leading) {
                    if trimmed.isEmpty {
                        Text(L10n.string(.journalItemTagPlaceholder, language: settings.language))
                            .font(AppFont.paper(12.5, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { onBeginEditing(.tag) }
        }
    }

    @ViewBuilder
    private var bodyField: some View {
        if isEditing {
            IMESafeTextEditor(
                text: Binding(
                    get: { item.body },
                    set: { item.body = $0 }
                ),
                font: WickPrintFont.songti(13.5),
                minHeight: 48,
                maxHeight: nil,
                onChange: onChange,
                onPasteImage: onPasteImage,
                becomeFirstResponder: initialFocus == .body
            )
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: .topLeading) {
                if item.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(L10n.string(.journalBodyPlaceholder, language: settings.language))
                        .font(AppFont.paper(13.5))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .allowsHitTesting(false)
                }
            }
        } else {
            let trimmed = item.body.trimmingCharacters(in: .whitespacesAndNewlines)
            Text(trimmed.isEmpty ? " " : item.body)
                .font(AppFont.paper(13.5))
                .foregroundStyle(palette.textPrimary.color)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
                .padding(.horizontal, 5)
                .overlay(alignment: .topLeading) {
                    if trimmed.isEmpty {
                        Text(L10n.string(.journalBodyPlaceholder, language: settings.language))
                            .font(AppFont.paper(13.5))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { onBeginEditing(.body) }
        }
    }

    // MARK: Review

    private var noteText: String {
        item.review?.note.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Ink opacity for the floating verdict seal: enough to read the content
    /// (figures, text) underneath it.
    private static let sealOpacity = 0.82

    /// 复盘批注:朱砂左边线引文(e-note),章本身只表对/错。
    private var noteRow: some View {
        HStack(alignment: .top, spacing: 9) {
            Rectangle()
                .fill(palette.reviewCorrect.color)
                .frame(width: 2)
            Text(noteText)
                .font(AppFont.paper(11.5))
                .foregroundStyle(palette.textSecondary.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// In-row "复盘" call-to-action while unreviewed. It owns a normal row and
    /// never overlaps content - floating over records/photos is a privilege of
    /// the picked seal, not the button.
    private var reviewButton: some View {
        Button {
            showReviewPopover = true
        } label: {
            Text(L10n.string(.journalReview, language: settings.language))
                .font(AppFont.paper(12, weight: .bold))
                .foregroundStyle(palette.reviewCorrect.color.opacity(0.8))
                .frame(width: 44, height: 44)
                .rotationEffect(.degrees(-3))
        }
        .buttonStyle(.plain)
        .help(L10n.string(.journalReviewHelp, language: settings.language))
        .accessibilityLabel(Text(L10n.string(.journalReviewHelp, language: settings.language)))
        .popover(isPresented: $showReviewPopover, arrowEdge: .top) {
            reviewPopoverContent
        }
    }

    /// The picked verdict, stamped over the card's bottom-trailing corner:
    /// big enough to cover the button's former spot plus the content beneath
    /// (positions, photos, body), semi-transparent so it reads as ink on
    /// paper. Tapping reopens the review popover.
    private func floatingReviewSeal(_ review: JournalReview) -> some View {
        Button {
            showReviewPopover = true
        } label: {
            JournalReviewBadge(verdict: review.verdict, style: .seal, size: 56)
                .opacity(Self.sealOpacity)
        }
        .buttonStyle(.plain)
        .help(L10n.string(.journalReviewHelp, language: settings.language))
        .accessibilityLabel(Text(verdictName(review.verdict)))
        .popover(isPresented: $showReviewPopover, arrowEdge: .top) {
            reviewPopoverContent
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
                            .font(AppFont.ui(12, weight: .medium))
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
                font: AppFont.paperNSFont(13),
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
            JournalReviewBadge(verdict: verdict, style: .seal, size: 40)
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
            .font(AppFont.ui(fontSize, weight: .medium))
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
