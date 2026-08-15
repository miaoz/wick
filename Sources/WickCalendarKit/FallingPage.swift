import SwiftUI
import WickSync

/// Everything the freed piece needs to fall on its own.
public struct FallingPage: Identifiable {
    public let id = UUID()
    public let date: Date
    public let events: [MacroCalendarEvent]
    public let language: AppLanguage
    /// The events page the sheet was flipped to when it came off.
    public let eventsPage: Int
    public let seed: UInt64
    public let start: CGSize
    public let grabX: CGFloat
    /// Torn by an upward flick: the piece is flung over the staples first.
    public let upward: Bool
    /// Hand speed at the moment the fibers gave - the throw it inherits.
    public let throwVelocity: CGSize
    /// The pad the sheet came off - it renders and falls in this page size.
    public let layout: PaperLayout

    public init(
        date: Date,
        events: [MacroCalendarEvent],
        language: AppLanguage,
        eventsPage: Int,
        seed: UInt64,
        start: CGSize,
        grabX: CGFloat,
        upward: Bool,
        throwVelocity: CGSize,
        layout: PaperLayout = .desktop
    ) {
        self.date = date
        self.events = events
        self.language = language
        self.eventsPage = eventsPage
        self.seed = seed
        self.start = start
        self.grabX = grabX
        self.upward = upward
        self.throwVelocity = throwVelocity
        self.layout = layout
    }
}

/// The freed sheet in flight. Paper at terminal speed only accelerates — it sways
/// and banks, but never bobs, and never flips. Waypoints are interpolated by hand
/// off the timeline so it works on macOS 13 without `KeyframeAnimator`.
///
/// The *presentation* is platform-specific: macOS spawns a transparent click-through
/// overlay window (see `WickCore.FallingPageOverlay`); iOS hosts it in a full-screen
/// overlay. This view is the shared, platform-agnostic sheet.
public struct FallingPageView: View {
    public let page: FallingPage
    public let fallDistance: CGFloat
    public let headroom: CGFloat

    @State private var start = Date()

    /// Which way the sheet leans when the hand gave it no sideways speed.
    private let dir: Double
    private let plan: FallPlan

    public init(page: FallingPage, fallDistance: CGFloat, headroom: CGFloat = 0) {
        self.page = page
        self.fallDistance = fallDistance
        self.headroom = headroom
        let dir: Double = page.grabX < page.layout.pageW / 2 ? -1 : 1
        let rise = Double(max(min(headroom - 40, 210), 0))
        self.dir = dir
        self.plan = FallPlan.make(page: page, fallDistance: fallDistance, dir: dir, rise: rise)
    }

    public var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            sheet(plan.state(at: t))
        }
        .padding(.top, headroom + page.layout.blockTopPad + page.layout.pageTopInset - 14)
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
            eventsPage: page.eventsPage,
            layout: page.layout
        )
        .clipShape(TornPieceShape(seed: page.seed, base: page.layout.tearY))
        // The padding gives the drop shadow room; a full-bleed piece starts
        // exactly on the pad instead, and its shadow only matters mid-flight.
        .padding(page.layout.isFullBleed ? 0 : 14)
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
