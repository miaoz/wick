import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WickSync

/// Model representing the currently previewed images and selection index.
struct JournalImagePreviewState: Equatable, Identifiable {
    let id = UUID()
    var filenames: [String]
    var currentIndex: Int

    var currentFilename: String? {
        guard filenames.indices.contains(currentIndex) else { return nil }
        return filenames[currentIndex]
    }
}

/// Full-screen / in-window lightbox preview for diary entry images.
///
/// Features:
/// - Smooth zoom and pan with gestures and double-click toggle
/// - Multi-image navigation with keyboard arrows and side buttons
/// - System Preview.app integration and clipboard copy
/// - Keyboard shortcuts: Esc (close), Left/Right (navigate), Cmd+C (copy), Cmd+O (open in Preview)
struct JournalImagePreviewOverlay: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: JournalStore
    @Environment(\.wickPalette) private var palette
    @Binding var state: JournalImagePreviewState?

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var didCopyFeedback = false

    private var currentFilename: String? {
        state?.currentFilename
    }

    private var hasMultipleImages: Bool {
        (state?.filenames.count ?? 0) > 1
    }

    var body: some View {
        ZStack {
            // Dark scrim background
            Color.black.opacity(0.86)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            if let filename = currentFilename {
                imageContent(for: filename)
            }

            // Top control bar
            VStack {
                topBar
                    .padding(.top, 16)
                    .padding(.horizontal, 20)

                Spacer()

                if hasMultipleImages {
                    bottomIndicator
                        .padding(.bottom, 18)
                }
            }

            // Side navigation arrows
            if hasMultipleImages {
                HStack {
                    if let state, state.currentIndex > 0 {
                        sideNavButton(systemName: "chevron.left") {
                            previousImage()
                        }
                        .padding(.leading, 18)
                    } else {
                        Spacer().frame(width: 48)
                    }

                    Spacer()

                    if let state, state.currentIndex < state.filenames.count - 1 {
                        sideNavButton(systemName: "chevron.right") {
                            nextImage()
                        }
                        .padding(.trailing, 18)
                    } else {
                        Spacer().frame(width: 48)
                    }
                }
            }

            // Hidden keyboard shortcut receivers
            shortcutReceivers
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .animation(.easeOut(duration: 0.18), value: state?.currentIndex)
    }

    // MARK: - Image Content

    @ViewBuilder
    private func imageContent(for filename: String) -> some View {
        GeometryReader { proxy in
            let fullImage = store.loadNSImage(filename: filename)
            let thumb = store.loadThumbnail(filename: filename, maxPixel: 800)

            ZStack {
                if let nsImage = fullImage ?? thumb {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let newScale = lastScale * value
                                    scale = max(0.5, min(8.0, newScale))
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    if scale < 1.0 {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                            scale = 1.0
                                            lastScale = 1.0
                                            offset = .zero
                                            lastOffset = .zero
                                        }
                                    }
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    if scale > 1.05 {
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                }
                                .onEnded { _ in
                                    if scale > 1.05 {
                                        lastOffset = offset
                                    } else {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                            offset = .zero
                                            lastOffset = .zero
                                        }
                                    }
                                }
                        )
                        .onTapGesture(count: 2) {
                            toggleZoom()
                        }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo")
                            .font(AppFont.ui(40, weight: .light))
                            .foregroundStyle(.white.opacity(0.4))
                        Text(filename)
                            .font(AppFont.ui(13, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
        }
        .padding(40)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            // Filename / image label
            if let filename = currentFilename {
                Text(filename)
                    .font(AppFont.ui(12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 240, alignment: .leading)
            }

            Spacer()

            // Zoom controls
            HStack(spacing: 2) {
                Button {
                    zoomOut()
                } label: {
                    Image(systemName: "minus")
                        .font(AppFont.ui(11, weight: .bold))
                }
                .buttonStyle(LightboxIconButtonStyle())
                .help(L10n.string(.journalImageZoomOut, language: settings.language))

                Button {
                    toggleZoom()
                } label: {
                    Text("\(Int((scale * 100).rounded()))%")
                        .font(AppFont.ui(11.5, weight: .medium, design: .monospaced))
                        .frame(minWidth: 46)
                }
                .buttonStyle(LightboxIconButtonStyle())
                .help(scale > 1.05 ? L10n.string(.journalImageFit, language: settings.language) : L10n.string(.journalImageActualSize, language: settings.language))

                Button {
                    zoomIn()
                } label: {
                    Image(systemName: "plus")
                        .font(AppFont.ui(11, weight: .bold))
                }
                .buttonStyle(LightboxIconButtonStyle())
                .help(L10n.string(.journalImageZoomIn, language: settings.language))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.12))
            )

            // Open in Preview app
            Button {
                openInPreviewApp()
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(LightboxIconButtonStyle())
            .help(L10n.string(.journalOpenInPreview, language: settings.language))

            // Copy image
            Button {
                copyCurrentImage()
            } label: {
                Image(systemName: didCopyFeedback ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(didCopyFeedback ? Color.green : Color.white)
            }
            .buttonStyle(LightboxIconButtonStyle())
            .help(L10n.string(.journalCopyImage, language: settings.language))

            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(LightboxIconButtonStyle())
            .help(L10n.string(.cancel, language: settings.language))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - Bottom Indicator

    @ViewBuilder
    private var bottomIndicator: some View {
        if let state {
            HStack(spacing: 6) {
                Text("\(state.currentIndex + 1) / \(state.filenames.count)")
                    .font(AppFont.ui(11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.55))
                    .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
            )
        }
    }

    // MARK: - Side Nav Button

    private func sideNavButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(AppFont.ui(18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.55))
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hidden Shortcuts

    private var shortcutReceivers: some View {
        Group {
            Button("") { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])
            Button("") { previousImage() }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { nextImage() }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { copyCurrentImage() }
                .keyboardShortcut("c", modifiers: [.command])
            Button("") { openInPreviewApp() }
                .keyboardShortcut("o", modifiers: [.command])
            Button("") { zoomIn() }
                .keyboardShortcut("+", modifiers: [.command])
            Button("") { zoomIn() }
                .keyboardShortcut("=", modifiers: [.command])
            Button("") { zoomOut() }
                .keyboardShortcut("-", modifiers: [.command])
            Button("") { resetZoom() }
                .keyboardShortcut("0", modifiers: [.command])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    // MARK: - Actions

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.15)) {
            state = nil
        }
    }

    private func previousImage() {
        guard var s = state, s.currentIndex > 0 else { return }
        resetZoom()
        s.currentIndex -= 1
        state = s
    }

    private func nextImage() {
        guard var s = state, s.currentIndex < s.filenames.count - 1 else { return }
        resetZoom()
        s.currentIndex += 1
        state = s
    }

    private func toggleZoom() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            if scale > 1.05 {
                scale = 1.0
                lastScale = 1.0
                offset = .zero
                lastOffset = .zero
            } else {
                scale = 2.0
                lastScale = 2.0
            }
        }
    }

    private func zoomIn() {
        withAnimation(.easeOut(duration: 0.15)) {
            let target = min(scale * 1.35, 8.0)
            scale = target
            lastScale = target
        }
    }

    private func zoomOut() {
        withAnimation(.easeOut(duration: 0.15)) {
            let target = max(scale / 1.35, 0.5)
            scale = target
            lastScale = target
            if scale <= 1.0 {
                offset = .zero
                lastOffset = .zero
            }
        }
    }

    private func resetZoom() {
        scale = 1.0
        lastScale = 1.0
        offset = .zero
        lastOffset = .zero
    }

    private func copyCurrentImage() {
        guard let filename = currentFilename,
              let image = store.loadNSImage(filename: filename)
        else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])

        withAnimation(.easeInOut(duration: 0.15)) {
            didCopyFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.15)) {
                didCopyFeedback = false
            }
        }
    }

    private func openInPreviewApp() {
        guard let filename = currentFilename,
              let url = store.imageURL(for: filename)
        else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Lightbox Button Style

private struct LightboxIconButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.ui(13, weight: .medium))
            .foregroundStyle(Color.white.opacity(isHovered ? 1.0 : 0.85))
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.white.opacity(0.18) : Color.clear)
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.1), value: isHovered)
    }
}
