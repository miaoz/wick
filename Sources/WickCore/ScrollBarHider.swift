import AppKit
import SwiftUI

/// Hides the AppKit scrollers of the scroll view backing a SwiftUI `List` /
/// `ScrollView`.
///
/// `.scrollIndicators(.never)` is the SwiftUI-side request: `.hidden` still
/// shows bars on macOS when a mouse is connected or System Settings →
/// "Show scroll bars" is Always. On macOS 13 that modifier does not reach
/// AppKit-backed lists at all, and even on later versions SwiftUI flips
/// `hasVerticalScroller` back on during layout / hover. This probe finds
/// the nearest `NSScrollView` and keeps its scrollers off via KVO.
/// Scrolling itself is unaffected.
struct ScrollBarHider: NSViewRepresentable {
    func makeNSView(context: Context) -> ProbeView {
        ProbeView()
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.reapply()
    }

    final class ProbeView: NSView {
        private weak var watched: NSScrollView?
        private var hiding = false
        private var observingStyle = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                unwatch()
            } else {
                reapply()
            }
        }

        override func layout() {
            super.layout()
            // SwiftUI rebuilds or re-enables the scroll view on any pass;
            // hiding is idempotent and cheap.
            reapply()
        }

        func reapply() {
            attachAndHide()
            // The scroll view is often not in the tree yet on the first
            // updateNSView / viewDidMoveToWindow. Retry once; KVO takes
            // over after we latch onto a live NSScrollView.
            if watched == nil {
                DispatchQueue.main.async { [weak self] in
                    self?.attachAndHide()
                }
            }
        }

        override func observeValue(
            forKeyPath keyPath: String?,
            of object: Any?,
            change: [NSKeyValueChangeKey: Any]?,
            context: UnsafeMutableRawPointer?
        ) {
            if (keyPath == "hasVerticalScroller" || keyPath == "hasHorizontalScroller"),
               let scrollView = object as? NSScrollView {
                // KVO from an on-screen NSScrollView fires on the main thread.
                MainActor.assumeIsolated {
                    hideScrollers(of: scrollView)
                }
                return
            }
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }

        @objc private func scrollerStyleDidChange(_ notification: Notification) {
            guard let scrollView = watched else { return }
            hideScrollers(of: scrollView)
        }

        private func attachAndHide() {
            guard let scrollView = nearbyScrollView() else { return }
            watch(scrollView)
            hideScrollers(of: scrollView)
        }

        private func watch(_ scrollView: NSScrollView) {
            if watched === scrollView { return }
            unwatch()
            scrollView.addObserver(self, forKeyPath: "hasVerticalScroller", options: [.new], context: nil)
            scrollView.addObserver(self, forKeyPath: "hasHorizontalScroller", options: [.new], context: nil)
            watched = scrollView
            if !observingStyle {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(scrollerStyleDidChange(_:)),
                    name: NSScroller.preferredScrollerStyleDidChangeNotification,
                    object: nil
                )
                observingStyle = true
            }
            // SwiftUI re-enables scrollers a few frames after first layout
            // without going through a KVO-compliant setter on macOS 13.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.hideScrollers(of: scrollView)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.hideScrollers(of: scrollView)
            }
        }

        private func unwatch() {
            if let watched {
                watched.removeObserver(self, forKeyPath: "hasVerticalScroller")
                watched.removeObserver(self, forKeyPath: "hasHorizontalScroller")
            }
            watched = nil
            if observingStyle {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSScroller.preferredScrollerStyleDidChangeNotification,
                    object: nil
                )
                observingStyle = false
            }
        }

        private func hideScrollers(of scrollView: NSScrollView) {
            guard !hiding else { return }
            hiding = true
            defer { hiding = false }

            if scrollView.hasVerticalScroller { scrollView.hasVerticalScroller = false }
            if scrollView.hasHorizontalScroller { scrollView.hasHorizontalScroller = false }
            if !scrollView.autohidesScrollers { scrollView.autohidesScrollers = true }
            conceal(scrollView.verticalScroller)
            conceal(scrollView.horizontalScroller)
        }

        private func conceal(_ scroller: NSScroller?) {
            guard let scroller else { return }
            if !scroller.isHidden { scroller.isHidden = true }
            if scroller.alphaValue != 0 { scroller.alphaValue = 0 }
        }

        /// The `List` / `ScrollView` this probe is attached to. The representable
        /// sits in a sibling subtree, so walk up until an ancestor's subtree
        /// contains an `NSScrollView`. Prefer the candidate whose frame
        /// contains the probe (so a walk that reaches the window does not
        /// steal a neighbouring column). Nested IME editors are ignored —
        /// they live inside the scroll view's document view, which we do not
        /// recurse into.
        private func nearbyScrollView() -> NSScrollView? {
            let point = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: nil)
            var node: NSView? = self
            var hops = 0
            while let current = node, hops < 16 {
                let candidates = Self.outerScrollViews(in: current)
                if !candidates.isEmpty {
                    let containing = candidates.filter {
                        $0.convert($0.bounds, to: nil).contains(point)
                    }
                    return containing.max(by: Self.area)
                        ?? candidates.max(by: Self.area)
                }
                node = current.superview
                hops += 1
            }
            return nil
        }

        /// Scroll views in `root`'s tree, not descending into a scroll view's
        /// own document (nested text-editor scrollers stay untouched).
        private static func outerScrollViews(in root: NSView) -> [NSScrollView] {
            var result: [NSScrollView] = []
            if let scrollView = root as? NSScrollView {
                result.append(scrollView)
                return result
            }
            func walk(_ view: NSView) {
                for sub in view.subviews {
                    if let scrollView = sub as? NSScrollView {
                        result.append(scrollView)
                    } else {
                        walk(sub)
                    }
                }
            }
            walk(root)
            return result
        }

        private static func area(_ a: NSScrollView, _ b: NSScrollView) -> Bool {
            (a.bounds.width * a.bounds.height) < (b.bounds.width * b.bounds.height)
        }
    }
}

extension View {
    /// Fills the parent so the probe's frame matches the List / ScrollView
    /// it is hiding; a zero-size background can sit outside the scroller
    /// and pick the wrong column.
    func hidesAppKitScrollers() -> some View {
        background {
            ScrollBarHider()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        }
    }
}
