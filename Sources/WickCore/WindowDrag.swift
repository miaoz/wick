import AppKit
import SwiftUI

extension View {
    /// Makes this view a handle that moves the containing window (ported from himekuri).
    /// We always use the overlaid AppKit view — `WindowDragGesture` is macOS 15+.
    func windowDragHandle() -> some View {
        modifier(WindowDragHandleModifier())
    }
}

private struct WindowDragHandleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(LegacyWindowDragHandle())
    }
}

private struct LegacyWindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }

        /// The pad lives in an accessory-policy app that is often inactive;
        /// without this the first click would only bring it forward.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}
