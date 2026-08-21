import SwiftUI
#if os(macOS)
import AppKit
#endif

extension View {
    /// Makes this view a handle that moves the containing window (ported from himekuri).
    /// On macOS we always use the overlaid AppKit view — `WindowDragGesture` is 15+.
    /// On iOS there is no movable window, so it's a no-op.
    public func windowDragHandle() -> some View {
        #if os(macOS)
        modifier(WindowDragHandleModifier())
        #else
        self
        #endif
    }

    /// Same drag handle, but layered BELOW the content: SwiftUI controls on
    /// top keep their clicks, only the empty gaps fall through to dragging.
    public func windowDragBackground() -> some View {
        #if os(macOS)
        background(LegacyWindowDragHandle())
        #else
        self
        #endif
    }
}

#if os(macOS)
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
#endif
