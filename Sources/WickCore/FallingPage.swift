import AppKit
import SwiftUI

/// Everything the freed piece needs to fall on its own.
struct FallingPage: Identifiable {
    let id = UUID()
    let date: Date
    let events: [MacroCalendarEvent]
    let language: AppLanguage
    /// The events page the sheet was flipped to when it came off.
    let eventsPage: Int
    let seed: UInt64
    let start: CGSize
    let grabX: CGFloat
    /// Torn by an upward flick: the piece is flung over the staples first.
    let upward: Bool
    /// Hand speed at the moment the fibers gave — the throw it inherits.
    let throwVelocity: CGSize
}

/// A torn page falls in its own transparent, click-through window that spans from the
/// pad down to the bottom edge of the screen, so it drifts past everything and slips
/// off the display instead of being clipped or faded (ported from himekuri).
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
        )
        host.frame = NSRect(origin: .zero, size: frame.size)
        window.contentView = host

        main.addChildWindow(window, ordered: .above)
        window.orderFront(nil)

        Task {
            try? await Task.sleep(nanoseconds: 3_400_000_000)
            main.removeChildWindow(window)
            window.orderOut(nil)
            window.contentView = nil
        }
    }
}

/// The freed sheet in flight. Paper at terminal speed only accelerates — it sways
/// and banks, but never bobs, and never flips. Waypoints are interpolated by hand
/// off the timeline so it works on macOS 13 without `KeyframeAnimator`.
struct FallingPageView: View {
    let page: FallingPage
    let fallDistance: CGFloat
    let headroom: CGFloat

    @State private var start = Date()

    /// Which way the sheet leans when the hand gave it no sideways speed.
    private let dir: Double
    private let plan: FallPlan

    init(page: FallingPage, fallDistance: CGFloat, headroom: CGFloat = 0) {
        self.page = page
        self.fallDistance = fallDistance
        self.headroom = headroom
        let dir: Double = page.grabX < TradingCalendarGeometry.pageW / 2 ? -1 : 1
        let rise = Double(max(min(headroom - 40, 210), 0))
        self.dir = dir
        self.plan = FallPlan.make(page: page, fallDistance: fallDistance, dir: dir, rise: rise)
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            sheet(plan.state(at: t))
        }
        .padding(.top, headroom + TradingCalendarGeometry.blockTopPad + TradingCalendarGeometry.pageTopInset - 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { start = Date() }
        .allowsHitTesting(false)
    }

    /// The sheet itself at one instant of the flight.
    private func sheet(_ v: FallState) -> some View {
        // Farther from the wall: softer, fainter, lower shadow.
        let depth = min(max(v.y / Double(fallDistance), 0), 1)
        return MacroDayPageView(
            date: page.date,
            events: page.events,
            isLoading: false,
            errorText: nil,
            language: page.language,
            eventsPage: page.eventsPage
        )
        .clipShape(TornPieceShape(seed: page.seed))
        .padding(14)
        .compositingGroup()
        .shadow(
            color: .black.opacity(0.30 - 0.18 * depth),
            radius: 9 + 16 * depth,
            y: 7 + 20 * depth
        )
        .rotation3DEffect(
            .degrees(v.tilt),
            axis: (x: 1, y: 0.15 * dir, z: 0),
            anchor: .center,
            perspective: 0.45
        )
        .rotationEffect(.degrees(v.rot), anchor: .center)
        .offset(x: v.x, y: v.y)
    }
}
