import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Root

struct JournalRootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: JournalStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var exportStatus: String?

    /// 栏宽(拖分隔条调整,松手才落 UserDefaults;§05 状态记忆)。
    @State private var navWidth: CGFloat
    @State private var listWidth: CGFloat
    /// Active drags freeze their origin and ceiling so layout changes cannot
    /// feed back into gesture coordinates on macOS 13.
    @State private var navDragSession: ColumnDragSession?
    @State private var listDragSession: ColumnDragSession?
    /// DEBUG `-wick-journal-detail-only` 专注态启动(不动持久化档位)。
    private let launchModeOverride: Int?

    private static let navWidthKey = "wick.journal.navWidth"
    private static let listWidthKey = "wick.journal.listWidth"

    // Multi-journal library actions (triggered from the navigation sidebar:
    // "+" in the section header, rename/delete via row context menu).
    // The dialog KIND is stored separately from the show flag so dismissing
    // never swaps content mid-animation, and one modifier per dialog type
    // avoids the macOS 13 multiple-alert bug class.
    private enum JournalNameAlert {
        case new
        case rename
    }

    private enum JournalConfirmDialog {
        case startFresh
        case deleteJournal
    }

    @State private var journalNameAlert: JournalNameAlert = .new
    @State private var showJournalNameAlert = false
    @State private var journalConfirmDialog: JournalConfirmDialog = .startFresh
    @State private var showJournalConfirmDialog = false
    @State private var journalNameDraft = ""
    /// rename/delete 的目标日记本(右键菜单行),nil 回退到当前活跃本。
    @State private var journalActionTargetID: UUID?

    init() {
        #if DEBUG
        launchModeOverride = CommandLine.arguments.contains("-wick-journal-detail-only") ? 2 : nil
        #else
        launchModeOverride = nil
        #endif
        _navWidth = State(initialValue: Self.storedWidth(Self.navWidthKey, fallback: 224, minimum: 160))
        _listWidth = State(initialValue: Self.storedWidth(Self.listWidthKey, fallback: 260, minimum: 200))
    }

    private static func storedWidth(_ key: String, fallback: CGFloat, minimum: CGFloat) -> CGFloat {
        let value = UserDefaults.standard.double(forKey: key)
        return value >= Double(minimum) ? CGFloat(value) : fallback
    }

    /// 当前导航深度:0 = 全导航, 1 = 仅列表, 2 = 专注(§05)。
    private var columnMode: Int {
        launchModeOverride ?? settings.journalColumnMode
    }

    var body: some View {
        // Low-frequency day-arc palette refresh (5 min granularity is plenty).
        // This only re-resolves colors — it never writes bindings, so IME
        // composition in the editor is unaffected.
        TimelineView(.periodic(from: .now, by: 300)) { _ in
            let palette = DayArcEngine.palette(at: DayArcEngine.currentDate(), scheme: colorScheme)
            chromeContent(palette: palette)
        }
    }

    @ViewBuilder
    private func chromeContent(palette: WickPalette) -> some View {
        let base = Group {
            VStack(spacing: 0) {
                if store.isReadOnlyDueToLoadFailure {
                    loadFailureBanner
                } else if store.didRestoreFromBackup {
                    restoreBanner(palette: palette)
                }
                splitLayout(palette: palette)
            }
        }
        .environment(\.wickPalette, palette)
        .environment(\.pnlColorConvention, settings.pnlColorConvention)
        .tint(palette.accent.color)
        .frame(minWidth: Self.editorMinWidth, minHeight: 480)
        .preferredColorScheme(settings.preferredColorScheme)
        .background(palette.backgroundBottom.color)
        .alert(
            L10n.string(.journalRecoveryFailedTitle, language: settings.language),
            isPresented: Binding(
                get: { store.recoveryErrorMessage != nil },
                set: { if !$0 { store.dismissRecoveryError() } }
            )
        ) {
            Button(L10n.string(.ok, language: settings.language), role: .cancel) {
                store.dismissRecoveryError()
            }
        } message: {
            Text(store.recoveryErrorMessage ?? "")
        }
        .confirmationDialog(
            journalConfirmDialog == .deleteJournal
                ? L10n.string(.journalLibraryDeleteConfirm, language: settings.language)
                : L10n.string(.journalStartFresh, language: settings.language),
            isPresented: $showJournalConfirmDialog,
            titleVisibility: .visible
        ) {
            switch journalConfirmDialog {
            case .deleteJournal:
                Button(L10n.string(.journalLibraryDelete, language: settings.language), role: .destructive) {
                    if let id = journalActionTargetID ?? store.activeJournalID {
                        _ = store.deleteJournal(id: id)
                    }
                }
                Button(L10n.string(.cancel, language: settings.language), role: .cancel) {}
            case .startFresh:
                Button(L10n.string(.journalStartFresh, language: settings.language), role: .destructive) {
                    try? store.abandonCorruptDatabaseAndStartFresh()
                }
                Button(L10n.string(.cancel, language: settings.language), role: .cancel) {}
            }
        }
        .alert(
            journalNameAlert == .rename
                ? L10n.string(.journalLibraryRenameTitle, language: settings.language)
                : L10n.string(.journalLibraryNewTitle, language: settings.language),
            isPresented: $showJournalNameAlert
        ) {
            TextField(
                L10n.string(.journalLibraryNamePlaceholder, language: settings.language),
                text: $journalNameDraft
            )
            Button(
                journalNameAlert == .rename
                    ? L10n.string(.journalLibrarySaveName, language: settings.language)
                    : L10n.string(.journalLibraryCreate, language: settings.language)
            ) {
                switch journalNameAlert {
                case .rename:
                    if let id = journalActionTargetID ?? store.activeJournalID {
                        store.renameJournal(id: id, to: journalNameDraft)
                    }
                case .new:
                    store.createJournal(name: journalNameDraft)
                }
            }
            Button(L10n.string(.cancel, language: settings.language), role: .cancel) {}
        }
        .background {
            // Hidden focusable buttons for shortcuts that aren't in the toolbar.
            Button("") {
                focusSearchField()
            }
            .keyboardShortcut("f", modifiers: [.command])
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)

            // The native titlebar accessory controls have no keyboardShortcut
            // modifiers, so these stay as hidden in-view buttons.
            Button("") {
                _ = store.openOrCreateToday()
            }
            .keyboardShortcut("n", modifiers: [.command])
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)

            Button("") {
                // 三态循环:全导航 → 仅列表 → 专注(§05)。
                cycleColumns()
            }
            .keyboardShortcut("s", modifiers: [.control, .command])
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)

            // ⌥⌘0 检查器(仅彩蛋关闭时)
            Button("") {
                if !settings.physicalCalendarEnabled {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        settings.journalInspectorVisible.toggle()
                    }
                }
            }
            .keyboardShortcut("0", modifiers: [.option, .command])
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }

        // The window uses an empty native unified toolbar only to establish
        // the system titlebar geometry. Wick controls live in the native top
        // titlebar accessory installed by JournalWindowController.
        if #available(macOS 15.0, *) {
            // Keep SwiftUI from synthesizing a title item into the otherwise
            // empty AppKit toolbar (macOS 26 ignores titleVisibility = .hidden).
            base.toolbar(removing: .title)
        } else {
            base
        }
    }

    private func beginNewJournal() {
        journalActionTargetID = nil
        journalNameAlert = .new
        journalNameDraft = store.defaultJournalName(for: settings.language)
        showJournalNameAlert = true
    }

    private func beginRenameJournal(_ journal: JournalInfo) {
        journalActionTargetID = journal.id
        journalNameAlert = .rename
        journalNameDraft = journal.name
        showJournalNameAlert = true
    }

    private func beginDeleteJournal(_ journal: JournalInfo) {
        journalActionTargetID = journal.id
        journalConfirmDialog = .deleteJournal
        showJournalConfirmDialog = true
    }

    private var loadFailureBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string(.journalLoadFailureTitle, language: settings.language))
                .font(AppFont.preset(.headline))
            Text(L10n.string(.journalLoadFailureBody, language: settings.language))
                .font(AppFont.preset(.callout))
            HStack {
                Button(L10n.string(.journalImport, language: settings.language)) {
                    importJournal()
                }
                Button(L10n.string(.journalStartFresh, language: settings.language), role: .destructive) {
                    journalConfirmDialog = .startFresh
                    showJournalConfirmDialog = true
                }
                Spacer()
                if let exportStatus {
                    Text(exportStatus).font(AppFont.preset(.caption)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.18))
    }

    private func restoreBanner(palette: WickPalette) -> some View {
        Text(L10n.string(.journalRestoredFromBackup, language: settings.language))
            .font(AppFont.preset(.callout))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.accentSoft.color)
    }

    private func focusSearchField() {
        // UI-03: ⌘F must actually focus the top-bar search field. The search
        // lives in the titlebar accessory (a separate hierarchy), so the
        // journal window posts a notification the accessory listens for.
        NotificationCenter.default.post(name: .wickJournalFocusSearch, object: nil)
    }

    private func cycleColumns() {
        withAnimation(.easeInOut(duration: 0.18)) {
            settings.journalColumnMode = (settings.journalColumnMode + 1) % 3
        }
    }

    private func importJournal() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip, .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // UI-06: the unzip + validation run off the main thread.
        Task {
            do {
                try await store.importArchive(from: url)
                exportStatus = L10n.string(.journalImportSuccess, language: settings.language)
            } catch {
                exportStatus = L10n.string(.journalImportFailed, language: settings.language)
            }
        }
    }

    // MARK: - 栏位布局

    /// 手动三栏:栏与窗框平铺齐平、栏间只有发丝印刷界线。
    /// 不用 NavigationSplitView——macOS 26 会把侧栏画成浮起的圆角卡片,
    /// 与「同一叠纸」的栏面语言冲突(设计 §05 的拖拽/双击逃生口在此自实现)。
    private func splitLayout(palette: WickPalette) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if columnMode == 0 {
                JournalNavigationSidebar(
                    onNewJournal: beginNewJournal,
                    onRenameJournal: { beginRenameJournal($0) },
                    onDeleteJournal: { beginDeleteJournal($0) }
                )
                .frame(width: navWidth)

                JournalColumnDivider(
                    fill: palette.divider.color,
                    leadingFill: palette.sidebarBackground.color,
                    trailingFill: palette.columnPaper.color,
                    onDrag: { dragNav(by: $0) },
                    onDragEnd: { endNavDrag() },
                    onDoubleClick: { setColumnMode(1) }
                )
            }

            if columnMode <= 1 {
                JournalDayListColumn()
                    .frame(width: listWidth)

                JournalColumnDivider(
                    fill: palette.divider.color,
                    leadingFill: palette.columnPaper.color,
                    trailingFill: palette.editorCanvas.color,
                    onDrag: { dragList(by: $0) },
                    onDragEnd: { endListDrag() },
                    onDoubleClick: { setColumnMode(2) }
                )
            }

            HStack(alignment: .top, spacing: 0) {
                // The 440pt floor sits on the editor PAGE itself — putting it
                // on the editor+inspector group lets the fixed-width inspector
                // eat the floor and deform the page header first.
                JournalEditorPane()
                    .frame(minWidth: Self.editorMinWidth, maxWidth: .infinity, maxHeight: .infinity)
                // 栏四 · 检查器(今日事件 + 盈亏月历):仅彩蛋关闭时存在;
                // ⌥⌘0 / 顶栏右钮开关。彩蛋开启时主窗退为纯三栏。
                if !settings.physicalCalendarEnabled && settings.journalInspectorVisible {
                    Rectangle()
                        .fill(palette.divider.color)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                    JournalInspectorView()
                        .frame(width: 288)
                        .transition(.move(edge: .trailing))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The dividers move as their leading columns resize. Measuring the
        // gesture in this stationary ancestor avoids Ventura recomputing a
        // local translation against the divider's new position.
        .coordinateSpace(name: JournalColumnDragCoordinateSpace.name)
    }

    static let navWidthRange: ClosedRange<CGFloat> = 190...280
    static let listWidthRange: ClosedRange<CGFloat> = 220...340
    /// 编辑栏宽度地板:再窄页眉(大日期+小注+盈亏+删除)就溢出变形。
    /// JournalWindowController 用它算窗口 minSize。
    static let editorMinWidth: CGFloat = 440
    /// 编辑栏舒适宽度:页眉单行全件(大日期+小注+盈亏+保存注+删除)正好排开。
    /// 只用于首启默认尺寸,不作为地板——窄窗时页眉走 ViewThatFits 两行版。
    static let editorComfortWidth: CGFloat = 640

    /// Current persisted column widths (defaults until first drag). The window
    /// controller reads these to floor minSize at the REAL column widths —
    /// flooring at the range minimums let the actual (wider) columns squeeze
    /// the editor page below its own floor.
    static var currentNavWidth: CGFloat {
        storedWidth(navWidthKey, fallback: 224, minimum: 160)
    }

    static var currentListWidth: CGFloat {
        storedWidth(listWidthKey, fallback: 260, minimum: 200)
    }

    private func setColumnMode(_ mode: Int) {
        settings.journalColumnMode = mode
    }

    private func dragNav(by translation: CGFloat) {
        var session = navDragSession ?? ColumnDragSession(
            initialWidth: navWidth,
            maximumWidth: navWidthCeiling()
        )
        let target = session.initialWidth + translation
        // 拖过最小宽度再压 24pt = 拖到边缘收起(§05 逃生口)。
        let shouldCollapse = target < Self.navWidthRange.lowerBound - 24
        if session.shouldCollapse != shouldCollapse {
            session.shouldCollapse = shouldCollapse
        }
        if navDragSession == nil || navDragSession?.shouldCollapse != shouldCollapse {
            navDragSession = session
        }
        setWidth(
            min(session.maximumWidth, max(Self.navWidthRange.lowerBound, target)),
            current: navWidth,
            assign: { navWidth = $0 }
        )
    }

    private func endNavDrag() {
        let shouldCollapse = navDragSession?.shouldCollapse == true
        navDragSession = nil
        if shouldCollapse {
            setColumnMode(1)
            return
        }
        UserDefaults.standard.set(Double(navWidth), forKey: Self.navWidthKey)
    }

    private func dragList(by translation: CGFloat) {
        var session = listDragSession ?? ColumnDragSession(
            initialWidth: listWidth,
            maximumWidth: listWidthCeiling()
        )
        let target = session.initialWidth + translation
        let shouldCollapse = target < Self.listWidthRange.lowerBound - 24
        if session.shouldCollapse != shouldCollapse {
            session.shouldCollapse = shouldCollapse
        }
        if listDragSession == nil || listDragSession?.shouldCollapse != shouldCollapse {
            listDragSession = session
        }
        setWidth(
            min(session.maximumWidth, max(Self.listWidthRange.lowerBound, target)),
            current: listWidth,
            assign: { listWidth = $0 }
        )
    }

    private func endListDrag() {
        let shouldCollapse = listDragSession?.shouldCollapse == true
        listDragSession = nil
        if shouldCollapse {
            setColumnMode(2)
            return
        }
        UserDefaults.standard.set(Double(listWidth), forKey: Self.listWidthKey)
    }

    private func setWidth(
        _ newWidth: CGFloat,
        current: CGFloat,
        assign: (CGFloat) -> Void
    ) {
        guard abs(newWidth - current) >= 0.5 else { return }
        assign(newWidth)
    }

    /// Width the inspector currently occupies (1pt rule + 288), factored into
    /// drag ceilings and the window floor.
    private var inspectorReserve: CGFloat {
        !settings.physicalCalendarEnabled && settings.journalInspectorVisible ? 289 : 0
    }

    /// Live drag ceilings: the rest of the window must keep the editor page's
    /// floor, so a column drag can never squeeze the page (the window minSize
    /// only catches up with the persisted widths on drag end).
    private func navWidthCeiling() -> CGFloat {
        let contentWidth = JournalWindowController.shared.contentWidth
        guard contentWidth > 0 else { return Self.navWidthRange.upperBound }
        let reserved = listWidth + 14 + Self.editorMinWidth + inspectorReserve
        return max(
            Self.navWidthRange.lowerBound,
            min(Self.navWidthRange.upperBound, contentWidth - reserved)
        )
    }

    private func listWidthCeiling() -> CGFloat {
        let contentWidth = JournalWindowController.shared.contentWidth
        guard contentWidth > 0 else { return Self.listWidthRange.upperBound }
        let leading = columnMode == 0 ? navWidth + 14 : 7
        let reserved = leading + Self.editorMinWidth + inspectorReserve
        return max(
            Self.listWidthRange.lowerBound,
            min(Self.listWidthRange.upperBound, contentWidth - reserved)
        )
    }

}

// MARK: - 栏间分隔条(1pt 印刷界线 + 7pt 命中区)

private enum JournalColumnDragCoordinateSpace {
    static let name = "wick.journal.columnDrag"
}

private struct ColumnDragSession {
    let initialWidth: CGFloat
    let maximumWidth: CGFloat
    var shouldCollapse = false
}

/// 栏间发丝界线:视觉上是 1pt rule,两侧各 3pt 用相邻栏面颜色填满,
/// 凑出 7pt 拖拽命中区而版面保持平铺无缝。拖拽调宽、双击收起该栏
/// (§05 逃生口);悬停切换左右 resize 光标。
private struct JournalColumnDivider: View {
    let fill: Color
    /// 界线两侧的栏面色(左/右),用于无缝的命中区填充。
    let leadingFill: Color
    let trailingFill: Color
    let onDrag: (CGFloat) -> Void
    let onDragEnd: () -> Void
    let onDoubleClick: () -> Void
    @State private var isHovering = false

    var body: some View {
        let rule = HStack(spacing: 0) {
            Rectangle().fill(leadingFill).frame(width: 3)
            Rectangle().fill(fill).frame(width: 1)
            Rectangle().fill(trailingFill).frame(width: 3)
        }
        .frame(maxHeight: .infinity)
        // Column backgrounds expand through the window's top safe area, but
        // an ordinary shape starts below it and leaves a short 7pt-wide plug
        // at the titlebar join. Extend the divider too; the AppKit titlebar
        // background sits above it and clips everything above its hairline.
        .ignoresSafeArea(.container, edges: .top)

        if #available(macOS 14.0, *) {
            rule
                .contentShape(Rectangle())
                .onHover { inside in
                    guard inside != isHovering else { return }
                    isHovering = inside
                    if inside {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture(
                        minimumDistance: 1,
                        coordinateSpace: .named(JournalColumnDragCoordinateSpace.name)
                    )
                    .onChanged { onDrag($0.translation.width) }
                    .onEnded { _ in onDragEnd() }
                )
                .onTapGesture(count: 2) { onDoubleClick() }
                .onDisappear {
                    if isHovering {
                        NSCursor.pop()
                        isHovering = false
                    }
                }
        } else {
            rule.overlay {
                VenturaColumnDragHandle(
                    onDrag: onDrag,
                    onDragEnd: onDragEnd,
                    onDoubleClick: onDoubleClick
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// Ventura's SwiftUI drag translation can be recalculated after the divider
/// moves, feeding column width changes back into the gesture. Track in stable
/// window coordinates at the AppKit layer on macOS 13 to break that cycle.
private struct VenturaColumnDragHandle: NSViewRepresentable {
    let onDrag: (CGFloat) -> Void
    let onDragEnd: () -> Void
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> DragHandleView {
        DragHandleView(
            onDrag: onDrag,
            onDragEnd: onDragEnd,
            onDoubleClick: onDoubleClick
        )
    }

    func updateNSView(_ nsView: DragHandleView, context: Context) {
        nsView.onDrag = onDrag
        nsView.onDragEnd = onDragEnd
        nsView.onDoubleClick = onDoubleClick
    }

    final class DragHandleView: NSView {
        var onDrag: (CGFloat) -> Void
        var onDragEnd: () -> Void
        var onDoubleClick: () -> Void
        private var mouseDownX: CGFloat?
        private var didDrag = false

        init(
            onDrag: @escaping (CGFloat) -> Void,
            onDragEnd: @escaping () -> Void,
            onDoubleClick: @escaping () -> Void
        ) {
            self.onDrag = onDrag
            self.onDragEnd = onDragEnd
            self.onDoubleClick = onDoubleClick
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                mouseDownX = nil
                didDrag = false
                onDoubleClick()
                return
            }
            mouseDownX = event.locationInWindow.x
            didDrag = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let mouseDownX else { return }
            didDrag = true
            onDrag(event.locationInWindow.x - mouseDownX)
        }

        override func mouseUp(with event: NSEvent) {
            defer {
                mouseDownX = nil
                didDrag = false
            }
            if didDrag {
                onDragEnd()
            }
        }
    }
}
