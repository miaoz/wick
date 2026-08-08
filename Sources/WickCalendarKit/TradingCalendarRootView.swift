import SpriteKit
import SwiftUI
import WickSync

/// Renders a SwiftUI page to a bitmap the paper solver can warp.
@MainActor
enum CalendarSnapshot {
    static func cgImage<V: View>(of view: V, scale: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.cgImage
    }
}

/// The trading calendar — a himekuri-style「黄历」tear-off pad whose pages show that
/// day's global macro events. The pad stack, next page, binding, tear seam and the
/// torn piece are SwiftUI; only the top page is a SpriteKit-warped texture, and a torn
/// sheet is handed to the host via `onPageTorn` to fall away (macOS: an overlay window,
/// iOS: a full-screen overlay).
///
/// Platform-agnostic: the host supplies the language, a close action, and a closure
/// that presents the torn page.
public struct TradingCalendarRootView: View {
    let language: AppLanguage
    let onClose: () -> Void
    let onPageTorn: (FallingPage) -> Void

    @ObservedObject private var store = MacroCalendarStore.shared

    @State private var currentDate = Date()
    @State private var sim = PaperSim()
    @State private var paperScene = CalendarPaperScene(size: CGSize(
        width: TradingCalendarGeometry.pageW + 2 * TradingCalendarGeometry.overhangX,
        height: TradingCalendarGeometry.pageH + TradingCalendarGeometry.overhangBottom
    ))

    @State private var damage: CGFloat = 0
    @State private var drag: CGSize = .zero
    @State private var hold: CGFloat = 0
    @State private var dragging = false
    @State private var grabX: CGFloat = 0
    @State private var grabY: CGFloat = 0
    @State private var tearCenterX: CGFloat = TradingCalendarGeometry.pageW * 0.7
    @State private var tornMidDrag = false
    @State private var lastVelocity: CGSize = .zero
    @State private var lastTickLevel = 0
    @State private var tornCount = 0
    @State private var eventsPage = 0

    public init(
        language: AppLanguage,
        onClose: @escaping () -> Void,
        onPageTorn: @escaping (FallingPage) -> Void
    ) {
        self.language = language
        self.onClose = onClose
        self.onPageTorn = onPageTorn
    }

    private var sceneW: CGFloat {
        TradingCalendarGeometry.pageW + 2 * TradingCalendarGeometry.overhangX
    }
    private var sceneH: CGFloat {
        TradingCalendarGeometry.pageH + TradingCalendarGeometry.overhangBottom
    }

    // MARK: - Body

    public var body: some View {
        ZStack(alignment: .top) {
            padBlock
                .padding(.top, TradingCalendarGeometry.blockTopPad)
        }
        .frame(width: TradingCalendarGeometry.windowW, height: TradingCalendarGeometry.windowH, alignment: .top)
        .onAppear {
            paperScene.sim = sim
            store.loadIfNeeded(for: currentDate)
            store.loadIfNeeded(for: nextDate)
            refreshPageTexture()
        }
        .onChange(of: currentDate) { _ in
            store.loadIfNeeded(for: nextDate)
            refreshPageTexture()
        }
        .onChange(of: currentEvents) { _ in
            refreshPageTexture()
        }
        .onChange(of: eventsPage) { _ in
            refreshPageTexture()
        }
        .onReceive(NotificationCenter.default.publisher(for: .wickCalendarFlipEventsPage)) { note in
            guard let direction = note.userInfo?["direction"] as? Int else { return }
            flipEventsPage(by: direction)
        }
        #if os(macOS)
        .onExitCommand {
            onClose()
        }
        #endif
    }

    private var currentEvents: [MacroCalendarEvent] { store.events(for: currentDate) }

    private var currentEventPageCount: Int {
        MacroEventPaging.pageCount(for: currentEvents.count)
    }

    /// Advances the events page with wrap-around; a no-op on quiet days.
    /// Shared by taps on the pane and the window's arrow-key / scroll input.
    private func flipEventsPage(by delta: Int) {
        let count = currentEventPageCount
        guard count > 1 else { return }
        eventsPage = (eventsPage + delta + count) % count
        Haptics.tick()
    }

    private var nextDate: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
    }

    private var nextEvents: [MacroCalendarEvent] { store.events(for: nextDate) }

    private var remainingFraction: Double {
        let cal = Calendar.current
        guard let daysInYear = cal.range(of: .day, in: .year, for: currentDate)?.count else { return 1 }
        let dayOfYear = cal.ordinality(of: .day, in: .year, for: currentDate) ?? 1
        return Double(daysInYear - dayOfYear + 1) / Double(daysInYear)
    }

    // MARK: - The pad

    private var padBlock: some View {
        ZStack(alignment: .top) {
            // Soft shadow the whole pad casts on the wall.
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.black.opacity(0.25))
                .frame(width: TradingCalendarGeometry.pageW, height: TradingCalendarGeometry.pageH)
                .offset(x: 6, y: TradingCalendarGeometry.pageTopInset + 14)
                .blur(radius: 16)

            CalendarPadStack(remainingFraction: remainingFraction)

            // Next page recessed in the stack, shaded by the sheet above.
            MacroDayPageView(
                date: nextDate,
                events: nextEvents,
                isLoading: store.isLoading(for: nextDate),
                errorText: store.errorText(for: nextDate),
                language: language,
                eventsPage: 0
            )
            .overlay(nextPageShading)
            .padding(.top, TradingCalendarGeometry.pageTopInset)

            // Shadow the bowing sheet casts onto the page beneath.
            if abs(drag.height) > 2 {
                let p = min(abs(drag.height) / 110, 1)
                let up = drag.height < 0
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.24 * p))
                    .frame(width: TradingCalendarGeometry.pageW - 20, height: 110 + 60 * p)
                    .offset(
                        x: drag.width * 0.25,
                        y: TradingCalendarGeometry.pageTopInset + TradingCalendarGeometry.pageH - 130 + (up ? -60 * p : 10 * p)
                    )
                    .blur(radius: 14 + 10 * p)
                    .allowsHitTesting(false)
            }

            // Top page: a printed texture warped by the paper solver.
            SpriteView(scene: paperScene, options: [.allowsTransparency])
                .frame(width: sceneW, height: sceneH)
                .padding(.top, TradingCalendarGeometry.pageTopInset)
                .allowsHitTesting(false)

            // A half-torn seam: parted fibers catch the light where the last pull left off.
            if damage > 0.03 {
                TearEdgeLine(seed: tearSeed(for: tornCount))
                    .stroke(Color.white.opacity(0.55), lineWidth: 0.7)
                    .frame(width: TradingCalendarGeometry.pageW, height: 36)
                    .mask {
                        Rectangle()
                            .frame(width: max(tornFront * 2 - 36, 0), height: 36)
                            .blur(radius: 16)
                            .position(x: tearCenterX, y: 18)
                    }
                    .padding(.top, TradingCalendarGeometry.pageTopInset)
                    .allowsHitTesting(false)
            }

            // A torn remnant left under the staples.
            if tornCount > 0 {
                StubShape(seed: tearSeed(for: tornCount - 1))
                    .fill(TradingCalendarTheme.paperEdge)
                    .frame(width: TradingCalendarGeometry.pageW, height: 44)
                    .padding(.top, TradingCalendarGeometry.pageTopInset)
                    .allowsHitTesting(false)
            }

            // The stapled binding across the top; drag it to move the pad (macOS).
            CalendarPadBinding(onClose: onClose)

            tearHitLayer
        }
        .frame(width: sceneW, height: TradingCalendarGeometry.pageH + 60, alignment: .top)
    }

    private var nextPageShading: some View {
        LinearGradient(stops: [
            .init(color: .black.opacity(0.11), location: 0),
            .init(color: .black.opacity(0.05), location: 0.45),
            .init(color: .black.opacity(0.08), location: 1)
        ], startPoint: .top, endPoint: .bottom)
        .allowsHitTesting(false)
    }

    // MARK: - Crack model

    private var upSpan: CGFloat {
        max(0.95 * (grabY - TradingCalendarGeometry.tearY), 110)
    }

    private var liveTearProgress: CGFloat {
        let pulled = max(
            max(drag.height / TradingCalendarGeometry.tearThreshold, -drag.height / upSpan),
            0
        )
        return pulled * (1 + 0.8 * damage)
    }

    private var tornFront: CGFloat {
        min((damage + liveTearProgress) / 0.95, 1) * seamSpan
    }

    private var seamSpan: CGFloat {
        max(tearCenterX, TradingCalendarGeometry.pageW - tearCenterX) + 90
    }

    // MARK: - Tear gesture

    private var tearHitLayer: some View {
        Color.clear
            .frame(width: TradingCalendarGeometry.pageW, height: TradingCalendarGeometry.pageH * TradingCalendarGeometry.tearZone)
            .contentShape(Rectangle())
            .gesture(tearGesture)
            .calendarCursorOnHover()
            .padding(.top, TradingCalendarGeometry.pageTopInset + TradingCalendarGeometry.pageH * (1 - TradingCalendarGeometry.tearZone))
    }

    private var tearGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if tornMidDrag { return }
                if !dragging { beginGrab(at: value.startLocation) }

                let dy = value.translation.height
                // Pulling down bows the sheet out (it resists, travel saturates);
                // lifting up is the flip that follows the hand until the fibers give.
                let y: CGFloat
                if dy >= 0 {
                    let capDown: CGFloat = 190
                    y = capDown * tanh(dy / capDown)
                } else {
                    y = dy
                }
                let x = 70 * tanh(value.translation.width / 70)
                drag = CGSize(width: x, height: y)
                lastVelocity = value.velocity

                sim.moveGrab(
                    to: CGPoint(x: grabX + value.translation.width,
                                y: grabY + value.translation.height),
                    lift: hold
                )
                sim.setSeam(centerX: tearCenterX, front: tornFront)

                let pulled = max(y / TradingCalendarGeometry.tearThreshold, -y / upSpan)
                let progress = damage + max(pulled, 0) * (1 + 0.8 * damage)

                // Crackles tick as fibers give way, picking up from the damage.
                let level = Int(min(progress / 0.95, 1) * 4)
                if level > lastTickLevel, level > 0 {
                    lastTickLevel = level
                    Haptics.tick()
                    TearSound.shared.playCrackle(intensity: Float(min(progress, 1)))
                }

                // Past this point the crack runs away and the page comes off.
                if progress >= 0.95 {
                    tornMidDrag = true
                    performTear()
                    return
                }
            }
            .onEnded { value in
                dragging = false
                lastTickLevel = 0
                CalendarCursor.openHand()
                sim.release()
                if tornMidDrag {
                    tornMidDrag = false
                    return
                }
                // A tap on the events pane flips through event pages instead of
                // tearing; it falls through to the settle path (pulled ≈ 0,
                // so the sheet just springs back) after cycling the page.
                if abs(value.translation.width) < 8, abs(value.translation.height) < 8,
                   value.startLocation.y + TradingCalendarGeometry.pageH * (1 - TradingCalendarGeometry.tearZone)
                       >= TradingCalendarGeometry.eventsPaneTopY {
                    flipEventsPage(by: 1)
                }
                let flickDown = drag.height > 60 && value.predictedEndTranslation.height > 240
                let flickUp = drag.height < -50 && value.predictedEndTranslation.height < -260
                let pulled = max(drag.height / TradingCalendarGeometry.tearThreshold,
                                 -drag.height / upSpan)
                let amplified = max(pulled, 0) * (1 + 0.8 * damage)
                if damage + amplified >= 0.95 || flickDown || flickUp {
                    performTear()
                } else {
                    settleWithoutTearing(pulled: pulled, amplified: amplified)
                }
            }
    }

    private func beginGrab(at start: CGPoint) {
        dragging = true
        grabX = min(max(start.x, 0), TradingCalendarGeometry.pageW)
        grabY = TradingCalendarGeometry.pageH * (1 - TradingCalendarGeometry.tearZone) + start.y
        // An untouched seam starts parting wherever you grab; a damaged one keeps tearing.
        if damage < 0.02 { tearCenterX = grabX }
        lastTickLevel = Int(damage * 4)
        sim.setGrab(at: CGPoint(x: grabX, y: grabY))
        CalendarCursor.closedHand()
        withAnimation(.spring(response: 0.22, dampingFraction: 0.62)) {
            hold = 1
        }
        TearSound.shared.playRustle()
    }

    private func settleWithoutTearing(pulled: CGFloat, amplified: CGFloat) {
        if pulled > 0.15 {
            // Fibers that parted stay parted: the pull leaves lasting damage.
            damage = min(damage + amplified * 0.7, 0.8)
            TearSound.shared.playCrackle(intensity: Float(pulled) * 0.5)
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
            drag = .zero
            hold = 0
        }
        sim.setSeam(centerX: tearCenterX, front: min(damage / 0.95, 1) * seamSpan)
    }

    // MARK: - Tearing

    private func refreshPageTexture() {
        let page = MacroDayPageView(
            date: currentDate,
            events: currentEvents,
            isLoading: store.isLoading(for: currentDate),
            errorText: store.errorText(for: currentDate),
            language: language,
            eventsPage: eventsPage
        )
        if let cg = CalendarSnapshot.cgImage(of: page, scale: 2) {
            paperScene.setPageTexture(SKTexture(cgImage: cg))
        }
    }

    /// Irreversible. The page comes off and is handed to the host to fall away
    /// (past the bottom of the screen); the next day is revealed underneath.
    private func performTear() {
        let upward = drag.height < 0 || lastVelocity.height < -200
        let piece = FallingPage(
            date: currentDate,
            events: store.events(for: currentDate),
            language: language,
            eventsPage: eventsPage,
            seed: tearSeed(for: tornCount),
            start: CGSize(
                width: drag.width * 0.3,
                height: upward ? max(drag.height * 0.55, -140) : min(drag.height * 0.15, 16)
            ),
            grabX: grabX,
            upward: upward,
            throwVelocity: lastVelocity
        )
        TearSound.shared.playRip()
        Haptics.rip()
        onPageTorn(piece)

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            currentDate = nextDate
            drag = .zero
            hold = 0
            damage = 0
            tornCount += 1
            eventsPage = 0
        }
        sim.reset()
    }
}

/// The unturned pages beneath the top sheet, thicker while the year is young.
private struct CalendarPadStack: View {
    let remainingFraction: Double

    var body: some View {
        let layers = max(4, Int(remainingFraction * 22))
        return ZStack(alignment: .top) {
            ForEach(0..<layers, id: \.self) { i in
                let depth = CGFloat(layers - i)
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        TradingCalendarTheme.paper.blended(
                            with: TradingCalendarTheme.paperEdge,
                            by: Double(depth) / Double(layers) * 0.9
                        )
                    )
                    .frame(width: TradingCalendarGeometry.pageW, height: TradingCalendarGeometry.pageH)
                    .offset(x: depth * 0.55, y: TradingCalendarGeometry.pageTopInset + depth * 0.85)
            }
        }
        .compositingGroup()
        .opacity(0.88)
        .allowsHitTesting(false)
    }
}

/// The stapled binding across the top of the pad. Dragging it moves the pad (macOS);
/// the top-right × closes the calendar.
private struct CalendarPadBinding: View {
    let onClose: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(
                    colors: [Color(white: 0.985), Color(white: 0.86)],
                    startPoint: .top, endPoint: .bottom
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
                )
                .overlay(alignment: .top) {
                    // The green spine tape peeking over the top.
                    Rectangle()
                        .fill(TradingCalendarTheme.ink.opacity(0.9))
                        .frame(height: 2.5)
                        .padding(.horizontal, 2)
                        .padding(.top, 0.5)
                }
            HStack {
                staple
                Spacer()
                hangingHole
                Spacer()
                staple
            }
            .padding(.horizontal, 46)
        }
        .frame(width: TradingCalendarGeometry.pageW + 10, height: TradingCalendarGeometry.bindingH)
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1.5)
        .windowDragHandle()
        .overlay(alignment: .topTrailing) {
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(TradingCalendarTheme.ink.opacity(0.6))
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.white.opacity(0.6)))
                    .overlay(Circle().strokeBorder(TradingCalendarTheme.ink.opacity(0.2), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .help("close")
            .offset(x: -6, y: 4)
        }
    }

    private var staple: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(LinearGradient(
                colors: [Color(white: 0.55), Color(white: 0.75), Color(white: 0.45)],
                startPoint: .top, endPoint: .bottom
            ))
            .frame(width: 16, height: 3.5)
    }

    private var hangingHole: some View {
        Circle()
            .fill(Color.black.opacity(0.32))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1))
            .frame(width: 9, height: 9)
    }
}
