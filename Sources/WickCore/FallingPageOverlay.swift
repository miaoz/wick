import AppKit
import SwiftUI

/// A torn page falls in its own transparent, click-through window that spans from the
/// pad down to the bottom edge of the screen, so it drifts past everything and slips
/// off the display instead of being clipped or faded (ported from himekuri).
///
/// macOS-only presentation of the shared `WickCalendarKit.FallingPageView`; the iOS app
/// hosts the same view in a full-screen overlay instead.
@MainActor
enum FallingPageOverlay {
    /// Horizontal breathing room for the flutter swings plus a thrown carry.
    private static let margin: CGFloat = 300

    static func spawn(_ piece: FallingPage, from main: NSWindow) {
        guard let screen = main.screen ?? NSScreen.main else { return }

        let top = main.frame.maxY
        let bottom = screen.frame.minY
        // A piece flung upward needs air above the pad before it falls.
        let headroom: CGFloat = piece.upward ? min(300, max(screen.visibleFrame.maxY - top, 0)) : 0
        let height = top + headroom - bottom
        guard height > 100 else { return }

        let frame = NSRect(
            x: main.frame.minX - margin,
            y: bottom,
            width: TradingCalendarGeometry.windowW + 2 * margin,
            height: height
        )

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = main.level
        window.collectionBehavior = main.collectionBehavior

        // Distance from the page's resting spot to fully past the screen bottom.
        let distance = (top - bottom)
            - TradingCalendarGeometry.blockTopPad
            - TradingCalendarGeometry.pageTopInset
            + 60
        let host = NSHostingView(
            rootView: FallingPageView(page: piece, fallDistance: distance, headroom: headroom)
                .environment(\.pnlColorConvention, piece.convention)
                .environment(\.appLanguage, piece.language)
        )
        host.frame = NSRect(origin: .zero, size: frame.size)
        window.contentView = host

        main.addChildWindow(window, ordered: .above)
        window.orderFront(nil)

        Task {
            try? await Task.sleep(nanoseconds: 3_400_000_000)
            main.removeChildWindow(window)
            window.contentView = nil
            window.orderOut(nil)
            // Borderless windows can ignore `close()` once they are not key,
            // so this may be a no-op — but when it lands it drops the window
            // from NSApp.windows; without it every tear leaked one window.
            window.close()
        }
    }
}
