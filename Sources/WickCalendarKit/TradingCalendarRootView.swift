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

/// The trading calendar - a himekuri-style「黄历」tear-off pad whose pages show that
/// day's global macro events. The pad stack, next page, binding, tear seam and the
/// torn piece are SwiftUI; only the top page is a SpriteKit-warped texture, and a torn
/// sheet is handed to the host via `onPageTorn` to fall away (macOS: an overlay window,
/// iOS: a full-screen overlay).
///
/// The pad is sticky like a real himekuri: the day on top is pinned via
/// `TearOffState` and survives relaunch and midnight. Nothing here advances or
/// restores it on its own — only tearing (one page at a time) or the
/// easter-egg re-enable reset (`.wickCalendarResetToToday`) moves it.
///
/// Platform-agnostic: the host supplies the language, a close action, a closure
/// that presents the torn page, and the pad's `PaperLayout` (desktop widget by
/// default; the iPhone app passes a full-screen layout whose page is the display).
public struct TradingCalendarRootView: View {
    let language: AppLanguage
    let onClose: () -> Void
    let onPageTorn: (FallingPage) -> Void
    let layout: PaperLayout

    @Environment(\.pnlColorConvention) private var envPnlConvention
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var store = MacroCalendarStore.shared

    @GestureState private var isGestureActive = false

    @State private var currentDate: Date
    @State private var sim: PaperSim
    @State private var paperScene: CalendarPaperScene

    @State private var damage: CGFloat = 0
    @State private var drag: CGSize = .zero
    @State private var hold: CGFloat = 0
    @State private var dragging = false
    @State private var grabX: CGFloat = 0
    @State private var grabY: CGFloat = 0
    @State private var tearCenterX: CGFloat
    @State private var tornMidDrag = false
    @State private var lastVelocity: CGSize = .zero
    @State private var lastTickLevel = 0
    @State private var tornCount = 0
    /// A tear whose falling sheet hasn't reached the screen yet; the day
    /// advance commits on presentation (`commitTear`), never before.
    @State private var pendingTearID: UUID?
    @State private var eventsPage = 0
    @State private var activeTab: MacroCalendarTab = .macro
    @State private var sortOrder: MacroEventSortOrder = .time

    public init(
        language: AppLanguage,
        onClose: @escaping () -> Void,
        onPageTorn: @escaping (FallingPage) -> Void,
        layout: PaperLayout = .desktop
    ) {
        self.language = language
        self.onClose = onClose
        self.onPageTorn = onPageTorn
        self.layout = layout
        _currentDate = State(initialValue: TearOffState.displayedDate())
        _sim = State(initialValue: PaperSim(layout: layout))
        _paperScene = State(initialValue: CalendarPaperScene(layout: layout))
        _tearCenterX = State(initialValue: layout.pageW * 0.7)
    }

    private var sceneW: CGFloat { layout.sceneW }
    private var sceneH: CGFloat { layout.sceneH }

    // MARK: - Body

    public var body: some View {
        ZStack(alignment: .top) {
            padBlock
                .padding(.top, layout.blockTopPad)
        }
        .frame(width: layout.windowW, height: layout.windowH, alignment: .top)
        .onAppear {
            paperScene.sim = sim
            // Pin the day on top: a pad that is never torn keeps showing this
            // same page tomorrow instead of flipping itself at midnight.
            TearOffState.saveDisplayedDate(currentDate)
            store.loadIfNeeded(for: currentDate)
            store.loadIfNeeded(for: nextDate)
            TradingCalendarTheme.pnlConvention = envPnlConvention
            refreshPageTexture()
            resetDragState()
        }
        .onDisappear {
            resetDragState()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase != .active {
                cancelOrSettleDrag()
            }
        }
        .onChange(of: isGestureActive) { active in
            if !active && dragging {
                cancelOrSettleDrag()
            }
        }
        .onChange(of: currentDate) { _ in
            store.loadIfNeeded(for: nextDate)
            refreshPageTexture()
        }
        .onChange(of: currentEvents) { _ in
            refreshPageTexture()
        }
        .onChange(of: currentEarnings) { _ in
            refreshPageTexture()
        }
        .onChange(of: eventsPage) { _ in
            refreshPageTexture()
        }
        .onChange(of: activeTab) { _ in
            refreshPageTexture()
        }
        .onChange(of: sortOrder) { _ in
            refreshPageTexture()
        }
        .onChange(of: store.isLoading(for: currentDate)) { _ in
            // A fetch completing with an EMPTY result (quiet day) or an error
            // leaves events/earnings unchanged, so without this the top page
            // texture would stay stuck on the isLoading=true frame forever.
            refreshPageTexture()
        }
        .onChange(of: store.errorText(for: currentDate)) { _ in
            refreshPageTexture()
        }
        .onChange(of: store.earningsErrorText(for: currentDate)) { _ in
            refreshPageTexture()
        }
        .onChange(of: envPnlConvention) { newConvention in
            TradingCalendarTheme.pnlConvention = newConvention
            refreshPageTexture()
        }
        .onReceive(NotificationCenter.default.publisher(for: .wickCalendarFlipEventsPage)) { note in
            // `direction` flips a page within the active tab; `tabSwitch`
            // toggles between the macro and earnings compartments.
            if let direction = note.userInfo?["direction"] as? Int {
                flipEventsPage(by: direction)
            }
            if note.userInfo?["tabSwitch"] != nil {
                switchTab()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wickCalendarToggleSortOrder)) { _ in
            toggleSortOrder()
        }
        .onReceive(NotificationCenter.default.publisher(for: .wickCalendarFontStyleChanged)) { _ in
            refreshPageTexture()
        }
        .onReceive(NotificationCenter.default.publisher(for: .wickCalendarPnlConventionChanged)) { _ in
            refreshPageTexture()
        }
        .onReceive(NotificationCenter.default.publisher(for: .wickCalendarResetToToday)) { _ in
            currentDate = Date()
            TearOffState.saveDisplayedDate(currentDate)
            tornCount = 0
            eventsPage = 0
            store.loadIfNeeded(for: currentDate)
            store.loadIfNeeded(for: nextDate)
            refreshPageTexture()
        }
        #if os(macOS)
        .onExitCommand {
            onClose()
        }
        #endif
    }

    private var currentEvents: [MacroCalendarEvent] { store.events(for: currentDate) }

    private var currentEarnings: [EarningsReport] { store.earnings(for: currentDate) }

    /// The active tab's row count drives paging and the overflow line.
    private var activeCount: Int {
        activeTab == .macro ? currentEvents.count : currentEarnings.count
    }

    private var currentEventPageCount: Int {
        MacroEventPaging.pageCount(for: activeCount, layout: layout)
    }

    /// Advances the events page with wrap-around; a no-op on quiet days.
    /// Shared by taps on the pane and the window's arrow-key / scroll input.
    private func flipEventsPage(by delta: Int) {
        let count = currentEventPageCount
        guard count > 1 else { return }
        eventsPage = (eventsPage + delta + count) % count
        Haptics.tick()
    }

    /// Switches the pane between macro events and the earnings calendar;
    /// paging resets since the lists don't share a page geometry.
    private func switchTab() {
        activeTab = activeTab == .macro ? .earnings : .macro
        eventsPage = 0
        Haptics.tick()
    }

    /// Selects a specific compartment tab; resets page if switched or if on an overflow page.
    private func selectTab(_ tab: MacroCalendarTab) {
        if activeTab != tab {
            activeTab = tab
            eventsPage = 0
            Haptics.tick()
        } else if eventsPage != 0 {
            eventsPage = 0
            Haptics.tick()
        }
    }

    /// Toggles the event sort order between time and importance in the macro pane.
    private func toggleSortOrder() {
        sortOrder = (sortOrder == .time) ? .importance : .time
        eventsPage = 0
        Haptics.tick()
    }

    /// The active tab's error text for a day (the two feeds fail independently).
    private func errorText(for date: Date) -> String? {
        activeTab == .macro ? store.errorText(for: date) : store.earningsErrorText(for: date)
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
            // Soft shadow the whole pad casts on the wall (desktop only - a
            // full-bleed page *is* the wall's replacement).
            if layout.hasWall {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.black.opacity(0.25))
                    .frame(width: layout.pageW, height: layout.pageH)
                    .offset(x: 6, y: layout.pageTopInset + 14)
                    .blur(radius: 16)
            }

            CalendarPadStack(remainingFraction: remainingFraction, layout: layout)

            // Next page recessed in the stack, shaded by the sheet above.
            MacroDayPageView(
                date: nextDate,
                events: nextEvents,
                earnings: store.earnings(for: nextDate),
                isLoading: store.isLoading(for: nextDate),
                errorText: errorText(for: nextDate),
                language: language,
                eventsPage: 0,
                tab: activeTab,
                sortOrder: sortOrder,
                layout: layout,
                convention: envPnlConvention
            )
            .overlay(nextPageShading)
            .padding(.top, layout.pageTopInset)

            // Shadow the bowing sheet casts onto the page beneath.
            if abs(drag.height) > 2 {
                let s = layout.contentScale
                let p = min(abs(drag.height) / 110, 1)
                let up = drag.height < 0
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.24 * p))
                    .frame(width: layout.pageW - 20 * s, height: 110 * s + 60 * s * p)
                    .offset(
                        x: drag.width * 0.25,
                        y: layout.pageTopInset + layout.pageH - 130 * s + (up ? -60 * s * p : 10 * s * p)
                    )
                    .blur(radius: 14 + 10 * p)
                    .allowsHitTesting(false)
            }

            // Top page: a printed texture warped by the paper solver.
            SpriteView(scene: paperScene, options: [.allowsTransparency])
                .frame(width: sceneW, height: sceneH)
                .padding(.top, layout.pageTopInset)
                .allowsHitTesting(false)

            // A half-torn seam: parted fibers catch the light where the last pull left off.
            if damage > 0.03 {
                TearEdgeLine(seed: tearSeed(for: tornCount), base: layout.tearY)
                    .stroke(Color.white.opacity(0.55), lineWidth: 0.7)
                    .frame(width: layout.pageW, height: layout.tearY + 16)
                    .mask {
                        Rectangle()
                            .frame(width: max(tornFront * 2 - 36, 0), height: layout.tearY + 16)
                            .blur(radius: 16)
                            .position(x: tearCenterX, y: (layout.tearY + 16) / 2)
                    }
                    .padding(.top, layout.pageTopInset)
                    .allowsHitTesting(false)
            }

            // A torn remnant left under the staples.
            if tornCount > 0 {
                StubShape(seed: tearSeed(for: tornCount - 1), base: layout.tearY)
                    .fill(TradingCalendarTheme.paperEdge)
                    .frame(width: layout.pageW, height: layout.tearY + 24)
                    .padding(.top, layout.pageTopInset)
                    .allowsHitTesting(false)
            }

            // The stapled binding across the top; drag it to move the pad (macOS).
            CalendarPadBinding(onClose: onClose, layout: layout, convention: envPnlConvention)

            tearHitLayer
        }
        .frame(width: sceneW, height: layout.pageH + 60, alignment: .top)
        // Right-click (macOS) / long-press (iOS) share of the page image. On iOS
        // the tear drag (minimumDistance: 0) wins in the tear zone, so the menu
        // effectively comes from the page's upper half there.
        .contextMenu {
            Button(L10n.string(.calendarShareThisPage, language: language)) {
                cancelOrSettleDrag()
                if let image = renderCurrentPage() {
                    ImageShare.presentShareSheet(for: image, scale: 2)
                }
            }
            Button(L10n.string(.journalCopyImage, language: language)) {
                cancelOrSettleDrag()
                if let image = renderCurrentPage() {
                    ImageShare.copy(image, scale: 2)
                }
            }
        } preview: {
            currentPageView
        }
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
        max(0.95 * (grabY - layout.tearY), 110)
    }

    /// Pull needed to tear. A physical finger distance on the mouse-driven
    /// desktop pad; scaled with the page on a full-bleed pad so a phone swipe
    /// must be a deliberate drag, not a scroll-length flick.
    private var tearThreshold: CGFloat {
        TradingCalendarGeometry.tearThreshold * max(1, layout.contentScale)
    }

    private var liveTearProgress: CGFloat {
        let pulled = max(
            max(drag.height / tearThreshold, -drag.height / upSpan),
            0
        )
        return pulled * (1 + 0.8 * damage)
    }

    private var tornFront: CGFloat {
        min((damage + liveTearProgress) / 0.95, 1) * seamSpan
    }

    private var seamSpan: CGFloat {
        max(tearCenterX, layout.pageW - tearCenterX) + 90 * layout.contentScale
    }

    // MARK: - Tear gesture

    private var tearHitLayer: some View {
        Color.clear
            .frame(width: layout.pageW, height: layout.pageH * layout.tearZone)
            .contentShape(Rectangle())
            .gesture(tearGesture)
            .calendarCursorOnHover()
            .padding(.top, layout.pageTopInset + layout.pageH * (1 - layout.tearZone))
    }

    private var tearGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isGestureActive) { _, state, _ in
                state = true
            }
            .onChanged { value in
                if tornMidDrag { return }
                if !dragging { beginGrab(at: value.startLocation) }

                let dy = value.translation.height
                // Pulling down bows the sheet out (it resists, travel saturates);
                // lifting up is the flip that follows the hand until the fibers give.
                let y: CGFloat
                if dy >= 0 {
                    let capDown: CGFloat = 190 * max(1, layout.contentScale)
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

                let pulled = max(y / tearThreshold, -y / upSpan)
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
                guard dragging else { return }
                dragging = false
                lastTickLevel = 0
                CalendarCursor.openHand()
                sim.release()
                if tornMidDrag {
                    tornMidDrag = false
                    return
                }
                // A tap inside the events pane never tears: taps on the tab
                // strip (the pane's header row) switch or select tabs, taps on the rows
                // below flip pages. Either way the gesture falls through to
                // the settle path (pulled ≈ 0), so the sheet just springs back.
                if abs(value.translation.width) < 8, abs(value.translation.height) < 8 {
                    let pageY = value.startLocation.y + layout.pageH * (1 - layout.tearZone)
                    handleEventsPaneTap(at: value.startLocation, pageY: pageY)
                }
                // Velocity flicks feel right with a mouse but would let a
                // careless phone swipe skip a day with no tearing at all -
                // desktop pad only.
                let flickDown = !layout.isFullBleed
                    && drag.height > 60 && value.predictedEndTranslation.height > 240
                let flickUp = !layout.isFullBleed
                    && drag.height < -50 && value.predictedEndTranslation.height < -260
                let pulled = max(drag.height / tearThreshold,
                                 -drag.height / upSpan)
                let amplified = max(pulled, 0) * (1 + 0.8 * damage)
                if damage + amplified >= 0.95 || flickDown || flickUp {
                    performTear()
                } else {
                    settleWithoutTearing(pulled: pulled, amplified: amplified)
                }
            }
    }

    private func handleEventsPaneTap(at point: CGPoint, pageY: CGFloat) {
        let s = layout.contentScale
        // Generous vertical hit target for the tab header strip (from divider line through chips)
        let tabHeaderH = 38 * s
        if pageY >= layout.eventsPaneTopY - 4 * s, pageY < layout.eventsPaneTopY + tabHeaderH {
            let leftPad = layout.isFullBleed ? layout.frameSideInset + 11 * s : 18 * s
            let macroBoundary = leftPad + 50 * s
            let earningsBoundary = leftPad + 130 * s
            let sortBoundary = layout.pageW - (layout.isFullBleed ? layout.frameSideInset + 65 * s : 65 * s)
            if activeTab == .macro && point.x >= sortBoundary {
                toggleSortOrder()
            } else if point.x < macroBoundary {
                selectTab(.macro)
            } else if point.x < earningsBoundary {
                selectTab(.earnings)
            } else {
                switchTab()
            }
        } else if pageY >= layout.eventsPaneTopY + tabHeaderH {
            flipEventsPage(by: 1)
        }
    }

    private func beginGrab(at start: CGPoint) {
        dragging = true
        grabX = min(max(start.x, 0), layout.pageW)
        grabY = layout.pageH * (1 - layout.tearZone) + start.y
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

    private func cancelOrSettleDrag(pulled: CGFloat = 0, amplified: CGFloat = 0) {
        guard dragging || hold > 0 || drag != .zero else { return }
        dragging = false
        tornMidDrag = false
        lastTickLevel = 0
        CalendarCursor.openHand()
        sim.release()
        settleWithoutTearing(pulled: pulled, amplified: amplified)
    }

    private func resetDragState() {
        dragging = false
        tornMidDrag = false
        lastTickLevel = 0
        CalendarCursor.openHand()
        sim.release()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            drag = .zero
            hold = 0
        }
        sim.setSeam(centerX: tearCenterX, front: min(damage / 0.95, 1) * seamSpan)
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

    /// The page as currently displayed — single source for the tear texture
    /// and for share / copy rendering, so a shared image matches the screen.
    private var currentPageView: MacroDayPageView {
        MacroDayPageView(
            date: currentDate,
            events: currentEvents,
            earnings: currentEarnings,
            isLoading: store.isLoading(for: currentDate),
            errorText: errorText(for: currentDate),
            language: language,
            eventsPage: eventsPage,
            tab: activeTab,
            sortOrder: sortOrder,
            layout: layout,
            convention: envPnlConvention
        )
    }

    private func renderCurrentPage(scale: CGFloat = 2) -> CGImage? {
        CalendarSnapshot.cgImage(of: currentPageView, scale: scale)
    }

    private func refreshPageTexture() {
        if let cg = renderCurrentPage() {
            paperScene.setPageTexture(SKTexture(cgImage: cg))
        }
    }

    /// The pull crossed the point of no return: the fibers give and the sheet
    /// comes off in the hand, handed to the host to fall away. The pad commits
    /// the advance ONLY once the falling sheet's first frame is on screen
    /// (`onPresented`): the paper leaving IS the date change. A pull whose
    /// sheet never falls is just a shake — the day stays put.
    private func performTear() {
        let tornToDate = nextDate
        let upward = drag.height < 0 || lastVelocity.height < -200
        let piece = FallingPage(
            date: currentDate,
            events: currentEvents,
            earnings: currentEarnings,
            language: language,
            eventsPage: eventsPage,
            tab: activeTab,
            sortOrder: sortOrder,
            seed: tearSeed(for: tornCount),
            start: CGSize(
                width: drag.width * 0.3,
                height: upward ? max(drag.height * 0.55, -140) : min(drag.height * 0.15, 16)
            ),
            grabX: grabX,
            upward: upward,
            throwVelocity: lastVelocity,
            layout: layout,
            convention: envPnlConvention,
            onPresented: { [self] in commitTear(to: tornToDate) }
        )
        let pieceID = piece.id
        pendingTearID = pieceID
        TearSound.shared.playRip()
        Haptics.rip()
        onPageTorn(piece)

        // If the sheet never reaches the screen (the host couldn't present
        // it), settle the pull back as a shake: no paper fell, so the day
        // must not move either.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            guard pendingTearID == pieceID else { return }
            pendingTearID = nil
            settleWithoutTearing(pulled: 0, amplified: 0)
        }
    }

    /// The falling sheet's first frame covers the pad — now the next day
    /// (already painted underneath) can be revealed without a visible
    /// in-place flip.
    private func commitTear(to tornToDate: Date) {
        guard pendingTearID != nil else { return }
        pendingTearID = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            currentDate = tornToDate
            drag = .zero
            hold = 0
            damage = 0
            tornCount += 1
            eventsPage = 0
        }
        TearOffState.saveDisplayedDate(tornToDate)
        sim.reset()
    }
}

/// The unturned pages beneath the top sheet, thicker while the year is young.
private struct CalendarPadStack: View {
    let remainingFraction: Double
    let layout: PaperLayout

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
                    .frame(width: layout.pageW, height: layout.pageH)
                    .offset(x: depth * 0.55, y: layout.pageTopInset + depth * 0.85)
            }
        }
        .compositingGroup()
        .opacity(0.88)
        .allowsHitTesting(false)
    }
}

/// The stapled binding across the top of the pad. Dragging it moves the pad (macOS).
/// Desktop has no close control — the journal top bar summons and dismisses the
/// easter-egg window. On a full-bleed pad the strip spans the notch row so the
/// pad reads as stapled to the very top of the screen, and a close button is
/// the only way off the calendar (there is no journal chrome).
private struct CalendarPadBinding: View {
    let onClose: () -> Void
    let layout: PaperLayout
    var convention: PnlColorConvention = .redUp

    var body: some View {
        let s = layout.contentScale
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
                    // The spine tape peeking over the top.
                    Rectangle()
                        .fill(TradingCalendarTheme.accentColor(for: convention).opacity(0.9))
                        .frame(height: 2.5 * s)
                        .padding(.horizontal, 2 * s)
                        .padding(.top, 0.5 * s)
                }
            HStack {
                staple
                Spacer()
                if layout.showsHangingHole {
                    hangingHole
                }
                Spacer()
                staple
            }
            .padding(.horizontal, 46 * s)
            .padding(.top, layout.bindingSafeTop)
        }
        .frame(
            width: layout.isFullBleed ? layout.windowW : layout.pageW + 10,
            height: layout.bindingH
        )
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1.5)
        .windowDragHandle()
    }

    private var staple: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(LinearGradient(
                colors: [Color(white: 0.55), Color(white: 0.75), Color(white: 0.45)],
                startPoint: .top, endPoint: .bottom
            ))
            .frame(width: 16 * layout.contentScale, height: 3.5 * layout.contentScale)
    }

    private var hangingHole: some View {
        Circle()
            .fill(Color.black.opacity(0.32))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1))
            .frame(width: 9, height: 9)
    }
}
