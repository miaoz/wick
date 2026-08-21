import AppKit
import SwiftUI

/// Ventura-only host for `MenuBarExtra` `.window` content.
///
/// On macOS 13 the system `NSHostingView` lays SwiftUI out against a placeholder
/// panel frame *before* the NSPanel snaps to the content's fitting size. `Text`
/// origins from that first pass stick. We never put `Text` into that system
/// host: this representable is a plain `NSView` whose size we publish to
/// SwiftUI, and the real tree lives in our own `NSHostingView` installed only
/// after the panel window has a live width.
///
/// Height changes (progress → settings) cannot rely on
/// `invalidateIntrinsicContentSize()` — MenuBarExtra does not re-query a nested
/// AppKit view, and `.fixedSize()` on an `NSViewRepresentable` freezes the first
/// measurement. The hosted tree reports its ideal size via a preference; we
/// write that into an explicit SwiftUI `.frame` so the panel can grow.
struct MenuBarExtraContentHost<Content: View>: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var journalStore: JournalStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var panelSize = CGSize(
        width: PanelHostMetrics.width,
        height: PanelHostMetrics.placeholderHeight
    )

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Representable(
            root: MenuBarExtraHostedRoot(
                content: content,
                settings: settings,
                journalStore: journalStore,
                colorScheme: colorScheme,
                preferredScheme: settings.preferredColorScheme,
                onIdealSize: applyIdealSize
            )
        )
        .frame(width: panelSize.width, height: panelSize.height)
    }

    private func applyIdealSize(_ size: CGSize) {
        let next = CGSize(
            width: max(1, size.width),
            height: max(1, min(size.height, PanelHostMetrics.maxHeight))
        )
        guard abs(next.width - panelSize.width) > 0.5
            || abs(next.height - panelSize.height) > 0.5
        else { return }
        panelSize = next
    }
}

private enum PanelHostMetrics {
    static let width: CGFloat = 360
    static let placeholderHeight: CGFloat = 340
    static let maxHeight: CGFloat = 720
}

private struct PanelSizePreference: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

/// Stable root type for the inner `NSHostingView` so `@State` inside `Content`
/// survives `updateNSView` (an `AnyView` root would not).
private struct MenuBarExtraHostedRoot<Content: View>: View {
    let content: Content
    let settings: AppSettings
    let journalStore: JournalStore
    let colorScheme: ColorScheme
    let preferredScheme: ColorScheme?
    let onIdealSize: (CGSize) -> Void

    var body: some View {
        content
            .environmentObject(settings)
            .environmentObject(journalStore)
            .environment(\.colorScheme, colorScheme)
            .preferredColorScheme(preferredScheme)
            // Ideal height even when the inner hosting view is still the
            // progress-sized frame, so opening settings can report a taller
            // size instead of the clipped bounds.
            .fixedSize(horizontal: false, vertical: true)
            .overlay {
                GeometryReader { proxy in
                    Color.clear.preference(key: PanelSizePreference.self, value: proxy.size)
                }
                .allowsHitTesting(false)
            }
            .onPreferenceChange(PanelSizePreference.self) { size in
                guard size.width > 1, size.height > 1 else { return }
                // Preference changes arrive during the inner graph's update;
                // hop so we don't mutate the outer host's `@State` in-place.
                DispatchQueue.main.async {
                    onIdealSize(size)
                }
            }
    }
}

private struct Representable<Root: View>: NSViewRepresentable {
    var root: Root

    func makeNSView(context: Context) -> MenuBarExtraHostView<Root> {
        MenuBarExtraHostView(rootView: root)
    }

    func updateNSView(_ nsView: MenuBarExtraHostView<Root>, context: Context) {
        nsView.rootView = root
    }
}

/// Container that stays empty until it sits in a real panel window, then
/// installs the inner SwiftUI tree so `Text` first-layouts against live bounds.
private final class MenuBarExtraHostView<Root: View>: NSView {
    var rootView: Root {
        didSet {
            hostingView?.rootView = rootView
        }
    }

    private var hostingView: NSHostingView<Root>?
    private let measured: NSSize

    init(rootView: Root) {
        self.rootView = rootView
        self.measured = Self.measure(rootView)
        super.init(frame: NSRect(origin: .zero, size: measured))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize { measured }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installHostingIfNeeded()
    }

    override func layout() {
        super.layout()
        installHostingIfNeeded()
        hostingView?.frame = bounds
    }

    private func installHostingIfNeeded() {
        guard hostingView == nil else { return }
        guard window != nil else { return }
        // Same guard as `MenuBarExtraPanel`: never treat the status-item
        // button window (or a zero placeholder) as the live panel.
        guard bounds.width > 60, bounds.height > 30 else { return }
        let windowFrame = window?.frame ?? .zero
        guard windowFrame.width > 60, windowFrame.height > 30 else { return }
        // Width is the distinctive signal: the live panel is ~360pt, the
        // placeholder is 0 or a default/screen size. Installing into a wrong
        // *width* would recreate the original first-layout bug.
        guard abs(bounds.width - measured.width) <= 8
            || abs(bounds.width - PanelHostMetrics.width) <= 8
        else { return }

        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = [.intrinsicContentSize]
        if #available(macOS 13.3, *) {
            hosting.safeAreaRegions = []
        }
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
        hostingView = hosting
    }

    private static func measure(_ rootView: Root) -> NSSize {
        let probe = NSHostingView(rootView: rootView)
        probe.sizingOptions = [.intrinsicContentSize]
        var size = probe.fittingSize
        if size.width < 1 {
            size.width = PanelHostMetrics.width
        }
        if size.height < 1 {
            size.height = PanelHostMetrics.placeholderHeight
        }
        size.height = min(size.height, PanelHostMetrics.maxHeight)
        return size
    }
}
