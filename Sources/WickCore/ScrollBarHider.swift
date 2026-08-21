import AppKit
import SwiftUI

/// Hides the AppKit scrollers of the scroll view backing a SwiftUI `List` /
/// `ScrollView`. `.scrollIndicators(.hidden)` only reaches AppKit-backed
/// scroll views on newer macOS; on macOS 13 the underlying `NSScrollView`
/// still shows its scrollers, so disable them directly. Scrolling itself is
/// unaffected — an `NSScrollView` scrolls fine with no scroller views.
struct ScrollBarHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ProbeView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ProbeView)?.reapply()
    }

    final class ProbeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reapply()
        }

        override func layout() {
            super.layout()
            // SwiftUI may re-enable the scrollers or rebuild the scroll view
            // on any pass; hiding is idempotent and cheap.
            reapply()
        }

        func reapply() {
            // Defer: the scroll view is not necessarily in place yet.
            DispatchQueue.main.async { [weak self] in
                guard let scrollView = self?.nearbyScrollView() else { return }
                if scrollView.hasVerticalScroller { scrollView.hasVerticalScroller = false }
                if scrollView.hasHorizontalScroller { scrollView.hasHorizontalScroller = false }
            }
        }

        /// The scroll view rendered by the same `List` / `ScrollView` this
        /// probe is attached to. The representable sits in a sibling subtree,
        /// so walk up and take the first scroll view found in each ancestor's
        /// subtree (depth-first hits outer scroll views before nested ones).
        private func nearbyScrollView() -> NSScrollView? {
            var node: NSView? = self
            while let current = node {
                if let scrollView = current as? NSScrollView { return scrollView }
                if let found = current.firstDescendant(where: { $0 is NSScrollView }) as? NSScrollView {
                    return found
                }
                node = current.superview
            }
            return nil
        }
    }
}

private extension NSView {
    func firstDescendant(where matches: (NSView) -> Bool) -> NSView? {
        for sub in subviews {
            if matches(sub) { return sub }
            if let found = sub.firstDescendant(where: matches) { return found }
        }
        return nil
    }
}
