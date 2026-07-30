import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Item card
struct JournalItemEditorCard: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: JournalStore
    @Environment(\.wickPalette) private var palette

    /// Owning day entry — required so image deletion stays correct in multi-day timelines.
    let entryID: UUID
    let index: Int
    @Binding var item: JournalItem
    let canDelete: Bool
    let onDelete: () -> Void
    let onPasteImage: () -> Bool
    let onPickImage: () -> Void
    let onDrop: ([NSItemProvider]) -> Bool
    let onChange: () -> Void

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

                Spacer()

                if canDelete {
                    Button(role: .destructive, action: onDelete) {
                        Label(
                            L10n.string(.journalDeleteItem, language: settings.language),
                            systemImage: "minus.circle"
                        )
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.tertiary)
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
                onChange: onChange,
                onPasteImage: onPasteImage
            )
            .frame(minHeight: 120)
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
    }

    private var imagesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                if item.imageFilenames.isEmpty {
                    Text(L10n.string(.journalImagesHint, language: settings.language))
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 8)

                Button(action: onPickImage) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .help(L10n.string(.journalAddImage, language: settings.language))
                .accessibilityLabel(Text(L10n.string(.journalAddImage, language: settings.language)))
            }

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
        .onDrop(of: [.image, .fileURL], isTargeted: nil, perform: onDrop)
    }
}

struct JournalImageThumb: View {
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

