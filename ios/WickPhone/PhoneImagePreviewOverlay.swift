import SwiftUI
import UIKit
import WickSync

// MARK: - Image Preview State

public struct PhoneImagePreviewState: Identifiable, Equatable {
    public let id = UUID()
    public var filenames: [String]
    public var currentIndex: Int

    public init(filenames: [String], currentIndex: Int = 0) {
        self.filenames = filenames
        self.currentIndex = max(0, min(filenames.count - 1, currentIndex))
    }

    public var currentFilename: String? {
        guard filenames.indices.contains(currentIndex) else { return nil }
        return filenames[currentIndex]
    }
}

// MARK: - Lightbox Image Preview Overlay

public struct PhoneImagePreviewOverlay: View {
    @Binding var state: PhoneImagePreviewState?
    let imageURL: (String) -> URL?
    let language: AppLanguage

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var dragDismissOffset: CGFloat = 0
    @State private var didCopyFeedback = false
    @State private var isSharing = false

    private var currentFilename: String? {
        state?.currentFilename
    }

    private var hasMultipleImages: Bool {
        (state?.filenames.count ?? 0) > 1
    }

    public init(
        state: Binding<PhoneImagePreviewState?>,
        imageURL: @escaping (String) -> URL?,
        language: AppLanguage = .chinese
    ) {
        self._state = state
        self.imageURL = imageURL
        self.language = language
    }

    public var body: some View {
        ZStack {
            // Dark scrim background with interactive drag-to-dismiss dimming
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            // Image canvas
            if let state {
                TabView(selection: Binding(
                    get: { state.currentIndex },
                    set: { newIndex in
                        resetZoom()
                        self.state?.currentIndex = newIndex
                    }
                )) {
                    ForEach(Array(state.filenames.enumerated()), id: \.offset) { index, filename in
                        zoomableImageView(for: filename)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
            }

            // Top control bar
            VStack {
                topBar
                    .padding(.top, 8)
                    .padding(.horizontal, 16)

                Spacer()

                // Bottom index indicator
                if hasMultipleImages, let state {
                    bottomIndicator(current: state.currentIndex + 1, total: state.filenames.count)
                        .padding(.bottom, 24)
                }
            }
        }
        .sheet(isPresented: $isSharing) {
            if let filename = currentFilename,
               let url = imageURL(filename),
               let image = UIImage(contentsOfFile: url.path) {
                ShareActivityView(items: [image])
            }
        }
    }

    private var backgroundOpacity: Double {
        let progress = min(1.0, max(0.0, Double(abs(dragDismissOffset)) / 300.0))
        return 0.94 * (1.0 - progress * 0.7)
    }

    // MARK: - Zoomable Image View

    @ViewBuilder
    private func zoomableImageView(for filename: String) -> some View {
        GeometryReader { proxy in
            let url = imageURL(filename)
            let uiImage = url.flatMap { UIImage(contentsOfFile: $0.path) }

            ZStack {
                if let uiImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(x: offset.width, y: offset.height + dragDismissOffset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let newScale = lastScale * value
                                    scale = max(0.8, min(6.0, newScale))
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    if scale < 1.0 {
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                            resetZoom()
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
                                    } else {
                                        // Vertical pull-to-dismiss gesture
                                        dragDismissOffset = value.translation.height
                                    }
                                }
                                .onEnded { value in
                                    if scale > 1.05 {
                                        lastOffset = offset
                                    } else {
                                        if abs(value.translation.height) > 120 || abs(value.velocity.height) > 700 {
                                            dismiss()
                                        } else {
                                            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                                dragDismissOffset = 0
                                            }
                                        }
                                    }
                                }
                        )
                        .onTapGesture(count: 2) {
                            toggleDoubleTapZoom()
                        }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo")
                            .font(.system(size: 44, weight: .light))
                            .foregroundColor(.white.opacity(0.4))
                        Text(filename)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 10) {
            // Filename
            if let filename = currentFilename {
                Text(filename)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 180, alignment: .leading)
            }

            Spacer()

            // Copy button
            Button {
                copyCurrentImage()
            } label: {
                Image(systemName: didCopyFeedback ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(didCopyFeedback ? Color.green : Color.white)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
            }

            // Share / Save button
            Button {
                isSharing = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
            }

            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.18))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.55))
                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
        )
    }

    // MARK: - Bottom Indicator

    private func bottomIndicator(current: Int, total: Int) -> some View {
        HStack(spacing: 6) {
            Text("\(current) / \(total)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.55))
                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
        )
    }

    // MARK: - Actions & Helpers

    private func toggleDoubleTapZoom() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            if scale > 1.05 {
                resetZoom()
            } else {
                scale = 2.5
                lastScale = 2.5
            }
        }
    }

    private func resetZoom() {
        scale = 1.0
        lastScale = 1.0
        offset = .zero
        lastOffset = .zero
        dragDismissOffset = 0
    }

    private func copyCurrentImage() {
        guard let filename = currentFilename,
              let url = imageURL(filename),
              let image = UIImage(contentsOfFile: url.path) else { return }

        UIPasteboard.general.image = image
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        withAnimation(.easeInOut(duration: 0.15)) {
            didCopyFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeInOut(duration: 0.2)) {
                didCopyFeedback = false
            }
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) {
            state = nil
        }
    }
}

// MARK: - UIActivityViewController Wrapper for Sharing

private struct ShareActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
