import AppKit
import SwiftUI

/// Turns off the AppKit-drawn selection pill of the list view backing a
/// SwiftUI `List` (a `SwiftUIOutlineListView` / `NSTableView`). The journal
/// sidebar paints its own selection background via `listRowBackground`;
/// without this the system's bright blue pill shows for the whole mouse-down
/// until SwiftUI's re-render covers it.
struct TableViewSelectionSuppressor: NSViewRepresentable {
    func makeNSView(context: Context) -> ProbeView {
        ProbeView()
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.applyIfNeeded()
    }

    final class ProbeView: NSView {
        private weak var tableView: NSTableView?
        private var didScheduleRetry = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                tableView = nil
                didScheduleRetry = false
            } else {
                applyIfNeeded()
            }
        }

        func applyIfNeeded() {
            if let tableView, tableView.window != nil {
                tableView.selectionHighlightStyle = .none
                return
            }
            if let found = containingListView as? NSTableView {
                tableView = found
                found.selectionHighlightStyle = .none
                return
            }
            guard !didScheduleRetry else { return }
            didScheduleRetry = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.didScheduleRetry = false
                if let found = self.containingListView as? NSTableView {
                    self.tableView = found
                    found.selectionHighlightStyle = .none
                }
            }
        }
    }
}

private extension NSView {
    /// The list view rendered by the same `List` this view is attached to.
    /// The representable sits in a sibling subtree of the list, so walk up
    /// and search each ancestor's subtree depth-first.
    var containingListView: NSView? {
        var node: NSView? = self
        while let current = node {
            if current is NSTableView || current is NSOutlineView { return current }
            if let found = current.firstDescendant(where: { $0 is NSTableView || $0 is NSOutlineView }) {
                return found
            }
            node = current.superview
        }
        return nil
    }

    func firstDescendant(where matches: (NSView) -> Bool) -> NSView? {
        for sub in subviews {
            if matches(sub) { return sub }
            if let found = sub.firstDescendant(where: matches) { return found }
        }
        return nil
    }
}
