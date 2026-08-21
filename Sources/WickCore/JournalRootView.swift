import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WickCalendarKit

// MARK: - Root

struct JournalRootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: JournalStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var exportStatus: String?

    /// 栏宽(拖分隔条调整,松手才落 UserDefaults;§05 状态记忆)。
    @State private var navWidth: CGFloat
    @State private var listWidth: CGFloat
    /// 拖拽起始宽度;非 nil 表示对应分隔条正在拖拽。
    @State private var navDragStart: CGFloat?
    @State private var listDragStart: CGFloat?
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
    /// 红绿灯按钮行的垂直中心距内容顶缘的实测距离;0 = 未测量。
    @State private var trafficLightCenterY: CGFloat = 0

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
                topBar(palette: palette)
                splitLayout(palette: palette)
            }
        }
        .environment(\.wickPalette, palette)
        .tint(palette.accent.color)
        .frame(minWidth: 720, minHeight: 480)
        .preferredColorScheme(settings.preferredColorScheme)
        .background(palette.backgroundBottom.color)
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

            // The AppKit toolbar (see JournalWindowController) has no
            // keyboardShortcut support, so these stay as hidden in-view buttons.
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

        // The window runs toolbar-less on every macOS version
        // (JournalWindowController pins window.toolbar to nil): an empty
        // toolbar band wastes the titlebar row, and macOS 26 forces a glass
        // bezel on every toolbar item. The full-width top bar at the top of
        // the window carries the column toggle / journal name / search /
        // new-entry / inspector controls instead (see topBar).
        if #available(macOS 15.0, *) {
            // Belt and braces: if SwiftUI's toolbar ever survives the pinning,
            // don't let it show the window title (macOS 26 ignores
            // titleVisibility = .hidden).
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
                .font(.headline)
            Text(L10n.string(.journalLoadFailureBody, language: settings.language))
                .font(.callout)
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
                    Text(exportStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.18))
    }

    private func restoreBanner(palette: WickPalette) -> some View {
        Text(L10n.string(.journalRestoredFromBackup, language: settings.language))
            .font(.callout)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.accentSoft.color)
    }

    private func focusSearchField() {
        // Best-effort: post a notification; the sidebar search field becomes first responder via window.
        if let window = NSApp.keyWindow {
            window.makeFirstResponder(window.contentView)
        }
    }

    private func importJournal() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip, .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.importArchive(from: url)
            exportStatus = L10n.string(.journalImportSuccess, language: settings.language)
        } catch {
            exportStatus = L10n.string(.journalImportFailed, language: settings.language)
        }
    }

    // MARK: - 栏位布局

    /// 手动三栏:栏与窗框平铺齐平、栏间只有发丝印刷界线。
    /// 不用 NavigationSplitView——macOS 26 会把侧栏画成浮起的圆角卡片,
    /// 与「同一叠纸」的栏面语言冲突(设计 §05 的拖拽/双击逃生口在此自实现)。
    private func splitLayout(palette: WickPalette) -> some View {
        HStack(spacing: 0) {
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

            HStack(spacing: 0) {
                JournalEditorPane()
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
            .frame(minWidth: Self.editorMinWidth, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    static let navWidthRange: ClosedRange<CGFloat> = 190...280
    static let listWidthRange: ClosedRange<CGFloat> = 220...340
    /// 编辑栏宽度地板:再窄页眉(大日期+小注+盈亏+删除)就溢出变形。
    /// JournalWindowController 用它算窗口 minSize。
    static let editorMinWidth: CGFloat = 440

    private func setColumnMode(_ mode: Int) {
        settings.journalColumnMode = mode
    }

    private func dragNav(by translation: CGFloat) {
        let start = navDragStart ?? navWidth
        navDragStart = start
        let target = start + translation
        // 拖过最小宽度再压 24pt = 拖到边缘收起(§05 逃生口)。
        if target < Self.navWidthRange.lowerBound - 24 {
            navDragStart = nil
            setColumnMode(1)
            return
        }
        navWidth = min(Self.navWidthRange.upperBound, max(Self.navWidthRange.lowerBound, target))
    }

    private func endNavDrag() {
        navDragStart = nil
        UserDefaults.standard.set(Double(navWidth), forKey: Self.navWidthKey)
    }

    private func dragList(by translation: CGFloat) {
        let start = listDragStart ?? listWidth
        listDragStart = start
        let target = start + translation
        if target < Self.listWidthRange.lowerBound - 24 {
            listDragStart = nil
            setColumnMode(2)
            return
        }
        listWidth = min(Self.listWidthRange.upperBound, max(Self.listWidthRange.lowerBound, target))
    }

    private func endListDrag() {
        listDragStart = nil
        UserDefaults.standard.set(Double(listWidth), forKey: Self.listWidthKey)
    }

    // MARK: - 顶栏(全宽,原生红绿灯位)

    /// 全宽顶栏,扮演标题栏角色:三态循环钮(⌃⌘S)、日记名(静态)、
    /// 选中日小注、搜索、新建、右钮(检查器 ⌥⌘0 / 彩蛋模式召唤物理黄历)。
    /// 红绿灯浮在左上角,内容左缘让位;内容行垂直中心用实测的红绿灯中心
    /// 对齐(`TrafficLightProbe`),否则红绿灯会孤零零漂在按钮行上方。
    private func topBar(palette: WickPalette) -> some View {
        HStack(spacing: 10) {
            InkIconButton(
                systemName: columnModeIcon,
                help: L10n.string(.journalCycleColumns, language: settings.language)
            ) {
                cycleColumns()
            }

            journalTitle(palette: palette)

            // 标题小注:选中日的「8月20日 · 星期四」(v4 顶栏标题)。
            Text(selectedDayStamp)
                .font(.system(size: 11))
                .foregroundStyle(palette.textTertiary.color)
                .lineLimit(1)

            Spacer(minLength: 8)

            searchField

            InkIconButton(
                systemName: "square.and.pencil",
                help: L10n.string(.journalNewEntry, language: settings.language)
            ) {
                _ = store.openOrCreateToday()
            }

            if settings.physicalCalendarEnabled {
                InkIconButton(
                    systemName: "calendar",
                    help: L10n.string(.tradingCalendar, language: settings.language)
                ) {
                    TradingCalendarWindowController.shared.openCalendar()
                }
            } else {
                InkIconButton(
                    systemName: "sidebar.right",
                    help: L10n.string(.inspectorToggle, language: settings.language),
                    isOn: settings.journalInspectorVisible
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        settings.journalInspectorVisible.toggle()
                    }
                }
            }
        }
        // 内容左缘避让红绿灯;垂直方向:上下留白相等,且整行中心比红绿灯
        // 中心低 ~3.5pt——原生统一工具栏里内容也坐在灯线偏下,与灯心完全
        // 同线反而读起来偏上。按钮行高 28pt,半高 14;未测量时回退 7/7。
        .padding(.leading, 78)
        .padding(.trailing, 14)
        .padding(.top, trafficLightCenterY > 0 ? max(3, trafficLightCenterY - 11) : 7)
        .padding(.bottom, trafficLightCenterY > 0 ? max(3, trafficLightCenterY - 11) : 7)
        .background(
            LinearGradient(
                colors: [palette.cardTop.color, palette.cardBottom.color],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.divider.color).frame(height: 1)
        }
        .background(alignment: .topLeading) {
            TrafficLightProbe(centerY: $trafficLightCenterY)
                .frame(width: 0, height: 0)
        }
        .windowDragBackground()
    }

    /// 三态循环钮图标:全导航 / 仅列表 / 专注。
    private var columnModeIcon: String {
        switch settings.journalColumnMode {
        case 1: return "rectangle.split.2x1"
        case 2: return "rectangle"
        default: return "sidebar.left"
        }
    }

    /// 顶栏标题小注:选中日的「8月20日 · 星期四」,无选中回退到今天。
    private var selectedDayStamp: String {
        let date: Date
        if let id = store.selectedEntryID,
           let entry = store.entries.first(where: { $0.id == id })
        {
            date = entry.date
        } else {
            date = Date()
        }
        let day = date.formatted(.dateTime.month().day().locale(settings.locale))
        let weekday = date.formatted(.dateTime.weekday(.wide).locale(settings.locale))
        return "\(day) · \(weekday)"
    }

    private func cycleColumns() {
        withAnimation(.easeInOut(duration: 0.18)) {
            settings.journalColumnMode = (settings.journalColumnMode + 1) % 3
        }
    }

    /// 顶栏标题:静态日记名(切换与管理都在栏一,不在这里重复)。
    private func journalTitle(palette: WickPalette) -> some View {
        Text(
            store.activeJournal?.name
                ?? L10n.string(.journalLibraryDefaultName, language: settings.language)
        )
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(palette.textPrimary.color)
        .lineLimit(1)
    }

    /// 顶栏搜索框(短文本,沿用原侧栏的 plain TextField 做法)。
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField(
                L10n.string(.journalSearchPlaceholder, language: settings.language),
                text: $store.searchText
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12))

            if !store.searchText.isEmpty {
                Button {
                    store.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .frame(width: 180)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        }
    }
}

// MARK: - 栏间分隔条(1pt 印刷界线 + 7pt 命中区)

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

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(leadingFill).frame(width: 3)
            Rectangle().fill(fill).frame(width: 1)
            Rectangle().fill(trailingFill).frame(width: 3)
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { onDrag($0.translation.width) }
                .onEnded { _ in onDragEnd() }
        )
        .onTapGesture(count: 2) { onDoubleClick() }
    }
}

// MARK: - 红绿灯位置探针

/// 实测窗口红绿灯(close)按钮行的垂直中心距内容顶缘的距离,写回 binding。
/// AppKit 对 hidden-title 窗口的红绿灯纵向位置没有公开常量(且随系统版本
/// 微调),顶栏内容行靠这个实测值与红绿灯保持在同一水平线上。
private struct TrafficLightProbe: NSViewRepresentable {
    @Binding var centerY: CGFloat

    func makeNSView(context: Context) -> ProbeView {
        ProbeView(onChange: { centerY = $0 })
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.onChange = { centerY = $0 }
    }

    final class ProbeView: NSView {
        var onChange: (CGFloat) -> Void
        private var lastReported: CGFloat = 0

        init(onChange: @escaping (CGFloat) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // The titlebar buttons get their real frames only after the window
            // is on-screen; report once now and once after the runloop settles.
            report()
            DispatchQueue.main.async { [weak self] in self?.report() }
        }

        override func layout() {
            super.layout()
            report()
        }

        override func resize(withOldSuperviewSize oldSize: NSSize) {
            super.resize(withOldSuperviewSize: oldSize)
            report()
        }

        private func report() {
            guard let window,
                  let close = window.standardWindowButton(.closeButton),
                  close.window == window,
                  window.frame.size.height > 0
            else { return }
            // Measure in window base coordinates. Conversion to contentView is
            // unreliable here (the hosting view has a stale frame early on);
            // the titlebar buttons always sit in the window's own coordinate
            // space, so "window height - button midY" is the true top offset.
            let inWindow = close.convert(close.bounds, to: nil)
            guard inWindow != .zero else { return }
            let fromTop = window.frame.size.height - inWindow.midY
            // Sanity gate: standard chrome puts the row center at ~16pt.
            guard (6...60).contains(fromTop), fromTop != lastReported else { return }
            lastReported = fromTop
            onChange(fromTop)
        }
    }
}
