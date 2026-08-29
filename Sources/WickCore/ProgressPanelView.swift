import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum PanelViewLayout {
    static let width: CGFloat = 360
    static let outerPadding: CGFloat = 12
    static let contentPadding: CGFloat = 18
}

struct ProgressPanelView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: AppSettings
    @State private var showsSettings: Bool
    /// False until the probe confirms the panel window is really on screen.
    /// MenuBarExtra keeps the SwiftUI scene alive after dismissal, so the
    /// default must be "hidden": the minute ticks and the hero flame's
    /// breathing only run while the panel is visible (P4 + CPU audit).
    @State private var isPanelVisible = false

    init(showsSettings: Bool = false) {
        _showsSettings = State(initialValue: showsSettings)
    }

    var body: some View {
        let language = settings.language
        let theme = PanelTheme.resolve(at: Self.minuteDate(), scheme: colorScheme)
        Group {
            if showsSettings {
                panelChrome(theme: theme) {
                    settingsHeader(theme: theme, language: language)
                    settingsDivider(theme: theme)
                    ScrollView {
                        SettingsContentView(theme: theme, language: language)
                    }
                    .scrollIndicators(.never)
                    .hidesAppKitScrollers()
                    .frame(maxHeight: 520)
                }
            } else {
                // Header buttons stay outside TimelineView: macOS 26 MenuBarExtra
                // windows drop clicks on controls nested in a periodic timeline.
                panelChrome(theme: theme) {
                    progressHeader(theme: theme, language: language)
                    settingsDivider(theme: theme)
                    if isPanelVisible {
                        TimelineView(.periodic(from: .distantPast, by: 60)) { context in
                            slipContent(
                                date: Self.minuteTruncated(context.date),
                                theme: theme,
                                language: language,
                                flameAnimates: true
                            )
                        }
                    } else {
                        slipContent(
                            date: Self.minuteDate(),
                            theme: theme,
                            language: language,
                            flameAnimates: false
                        )
                    }
                }
            }
        }
        .background {
            WindowVisibilityProbe(isVisible: $isPanelVisible)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .wickMenuBarPanelDidDismiss)) { _ in
            // Belt and braces: an explicit dismissal must silence the flame
            // even if the occlusion KVO callback races this notification.
            isPanelVisible = false
        }
    }

    @ViewBuilder
    private func slipContent(date: Date, theme: PanelTheme, language: AppLanguage, flameAnimates: Bool) -> some View {
        let items = TimeProgressCalculator.allProgress(
            at: date,
            language: language,
            calendar: settings.progressCalendar
        )
        ProgressSlipContent(items: items, date: date, theme: theme, language: language, flameAnimates: flameAnimates)
    }

    /// Paper slip shell. Kept outside the ticking content so settings can reuse
    /// it without a `TimelineView`. No implicit `.animation` on this root:
    /// when progress *is* inside TimelineView, macOS 13 `.animation(value:)`
    /// leaks into those ticks and every layout change glides around.
    private func panelChrome<Content: View>(
        theme: PanelTheme,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack(alignment: .topLeading) {
            TornSlipShape()
                .fill(
                    LinearGradient(
                        colors: theme.backgroundColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [theme.ambientGlow, theme.ambientGlow.opacity(0)],
                                center: .center,
                                startRadius: 4,
                                endRadius: 180
                            )
                        )
                        .frame(width: 220, height: 220)
                        .offset(x: -40, y: -70)
                }
                .overlay {
                    TornSlipShape()
                        .stroke(theme.panelStroke, lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 18) {
                content()
            }
            .padding(PanelViewLayout.contentPadding)
        }
        .padding(PanelViewLayout.outerPadding)
        .frame(width: PanelViewLayout.width, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Drop seconds so the day-arc palette is stable between minute ticks.
    private static func minuteTruncated(_ date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        return calendar.date(from: components) ?? date
    }

    private static func minuteDate() -> Date {
        minuteTruncated(DayArcEngine.currentDate())
    }

    @ViewBuilder
    private func progressHeader(theme: PanelTheme, language: AppLanguage) -> some View {
        HStack(alignment: .center, spacing: 12) {
            CandleTileView(size: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string(.panelWordmark, language: language))
                    .font(AppFont.ui(17, weight: .bold, design: .serif))
                    .foregroundStyle(theme.primaryText)

                // Same visibility switch as the content below: the header's
                // minute tick must not keep a hidden panel on the display cycle.
                if isPanelVisible {
                    TimelineView(.periodic(from: .distantPast, by: 60)) { context in
                        Text(
                            Self.minuteTruncated(context.date).formatted(
                                .dateTime
                                .year()
                                .month()
                                .day()
                                .weekday(.abbreviated)
                                .hour()
                                .minute()
                                .locale(language.locale)
                            )
                        )
                        .font(AppFont.ui(10, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.tertiaryText)
                    }
                } else {
                    Text(
                        Self.minuteDate().formatted(
                            .dateTime
                            .year()
                            .month()
                            .day()
                            .weekday(.abbreviated)
                            .hour()
                            .minute()
                            .locale(language.locale)
                        )
                    )
                    .font(AppFont.ui(10, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.tertiaryText)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                InkIconButton(
                    systemName: "book.closed",
                    help: L10n.string(.journal, language: language)
                ) {
                    JournalWindowController.shared.openJournal(createTodayIfNeeded: false)
                }

                InkIconButton(
                    systemName: "gearshape",
                    help: L10n.string(.settings, language: language)
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showsSettings = true
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func settingsHeader(theme: PanelTheme, language: AppLanguage) -> some View {
        HStack(alignment: .center, spacing: 12) {
            CandleTileView(size: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string(.settingsTitle, language: language))
                    .font(AppFont.ui(17, weight: .bold, design: .serif))
                    .foregroundStyle(theme.primaryText)

                Text(L10n.string(.panelWordmark, language: language))
                    .font(AppFont.preset(.footnote))
                    .foregroundStyle(theme.secondaryText)
            }

            Spacer(minLength: 8)

            InkIconButton(
                systemName: "chevron.left",
                help: L10n.string(.back, language: language)
            ) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showsSettings = false
                }
            }
        }
    }

    private func settingsDivider(theme: PanelTheme) -> some View {
        Rectangle()
            .fill(theme.dividerAccent)
            .frame(height: 1)
    }
}

struct SettingsContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var reminderScheduler = JournalReminderScheduler.shared
    @EnvironmentObject private var journalStore: JournalStore

    let theme: PanelTheme
    let language: AppLanguage

    @ObservedObject private var syncCoordinator = SyncCoordinator.shared
    @State private var isCheckingUpdates = false
    @State private var updateStatusText: String?
    @State private var updateOpenURL: URL?
    @State private var dataStatusText: String?
    @State private var showStartFreshConfirm = false
    @State private var isConnectingDropbox = false
    @State private var showDisconnectConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // 1. 外观与语言
            settingsSection(
                title: L10n.string(.appearanceAndLanguageSection, language: language)
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L10n.string(.language, language: language))
                            .font(AppFont.ui(12, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.secondaryText)
                        HStack(spacing: 6) {
                            ForEach(AppLanguage.allCases) { option in
                                settingsOptionButton(
                                    title: option.displayName,
                                    isSelected: settings.language == option
                                ) {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        settings.language = option
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(L10n.string(.appearance, language: language))
                            .font(AppFont.ui(12, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.secondaryText)
                        HStack(spacing: 6) {
                            ForEach(AppAppearance.allCases) { option in
                                settingsOptionButton(
                                    title: option.displayName(language: language),
                                    isSelected: settings.appearance == option,
                                    expands: true
                                ) {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        settings.appearance = option
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(L10n.string(.pnlColorConvention, language: language))
                            .font(AppFont.ui(12, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.secondaryText)
                        HStack(spacing: 6) {
                            ForEach(PnlColorConvention.allCases) { option in
                                settingsOptionButton(
                                    title: option.displayName(language: language),
                                    isSelected: settings.pnlColorConvention == option,
                                    expands: true
                                ) {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        settings.pnlColorConvention = option
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(L10n.string(.journalFontStyle, language: language))
                            .font(AppFont.ui(12, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.secondaryText)
                        FontPickerSettingRow(theme: theme)
                    }
                }
            }

            // 2. 通用
            settingsSection(
                title: L10n.string(.generalSection, language: language)
            ) {
                VStack(alignment: .leading, spacing: 9) {
                    Toggle(isOn: $settings.weekStartsOnMonday) {
                        Text(L10n.string(.weekStartsOnMonday, language: language))
                            .font(AppFont.ui(13, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.primaryText)
                    }
                    .toggleStyle(.switch)
                    .tint(theme.selectionAccent)

                    Toggle(isOn: $settings.launchAtLoginDesired) {
                        Text(L10n.string(.launchAtLogin, language: language))
                            .font(AppFont.ui(13, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.primaryText)
                    }
                    .toggleStyle(.switch)
                    .tint(theme.selectionAccent)

                    if settings.launchAtLoginDesired && settings.launchAtLoginNeedsApproval {
                        Text(L10n.string(.launchAtLoginNeedsApproval, language: language))
                            .font(AppFont.preset(.caption))
                            .foregroundStyle(theme.secondaryText)
                        Button {
                            LaunchAtLogin.openSystemLoginItems()
                        } label: {
                            Text(L10n.string(.openLoginItems, language: language))
                                .font(AppFont.ui(12, weight: .medium, design: .rounded))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.selectionAccent)
                    }

                    Toggle(isOn: $settings.showMenuBarPercentage) {
                        Text(L10n.string(.menuBarPercentage, language: language))
                            .font(AppFont.ui(13, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.primaryText)
                    }
                    .toggleStyle(.switch)
                    .tint(theme.selectionAccent)
                }
            }

            // 3. 日记与提醒
            settingsSection(
                title: L10n.string(.journalAndReminderSection, language: language)
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $settings.journalReminderEnabled) {
                        Text(L10n.string(.journalReminderEnabled, language: language))
                            .font(AppFont.ui(13, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.primaryText)
                    }
                    .toggleStyle(.switch)
                    .tint(theme.selectionAccent)

                    if settings.journalReminderEnabled {
                        ReminderTimePickerSettingRow(theme: theme, language: language)

                        reminderPermissionFooter
                    }
                }
            }

            // 4. 交易日历
            settingsSection(
                title: L10n.string(.tradingCalendar, language: language)
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $settings.physicalCalendarEnabled) {
                        HStack(spacing: 6) {
                            Text(L10n.string(.calendarEasterEggTitle, language: language))
                                .font(AppFont.ui(13, weight: .semibold, design: .rounded))
                                .foregroundStyle(theme.primaryText)
                            Text("彩蛋")
                                .font(AppFont.paper(9, weight: .bold))
                                .foregroundStyle(theme.palette.pnlUp.color)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(theme.palette.pnlUp.color.opacity(0.12))
                                )
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(theme.selectionAccent)

                    Text(L10n.string(.calendarEasterEggNote, language: language))
                        .font(AppFont.paper(10.5))
                        .foregroundStyle(theme.secondaryText)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(9)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(theme.palette.stain1.color.opacity(0.4))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(theme.palette.pnlUp.color.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }

            // 5. 同步
            settingsSection(
                title: L10n.string(.syncSection, language: language)
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    if settings.syncEnabled && syncCoordinator.backend.isAuthorized {
                        HStack {
                            Text("Dropbox")
                                .font(AppFont.ui(12.5, weight: .medium, design: .rounded))
                                .foregroundStyle(theme.secondaryText)
                            Spacer()
                            Text(settings.syncAccountEmail.isEmpty ? "—" : settings.syncAccountEmail)
                                .font(AppFont.ui(12.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(theme.primaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        syncStatusFooter

                        let adoptableJournals = syncCoordinator.engine.discoveredJournals.filter { manifest in
                            !journalStore.journals.contains { $0.id == manifest.journalID }
                        }
                        if !adoptableJournals.isEmpty {
                            ForEach(adoptableJournals, id: \.journalID) { manifest in
                                HStack(spacing: 8) {
                                    Text(
                                        String(
                                            format: L10n.string(.syncRemoteJournalFormat, language: language),
                                            manifest.journalName
                                        )
                                    )
                                    .font(AppFont.preset(.caption))
                                    .foregroundStyle(theme.secondaryText)
                                    Spacer()
                                    Button {
                                        syncCoordinator.adoptRemoteJournal(manifest)
                                    } label: {
                                        Text(L10n.string(.syncImportJournal, language: language))
                                            .font(AppFont.ui(12, weight: .medium, design: .rounded))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(theme.selectionAccent)
                                }
                            }
                        }

                        actionRowButton(
                            title: L10n.string(.syncNow, language: language),
                            systemImage: "arrow.triangle.2.circlepath"
                        ) {
                            syncCoordinator.engine.syncNow()
                        }
                        actionRowButton(
                            title: L10n.string(.syncDisconnect, language: language),
                            systemImage: "link",
                            isDestructive: true
                        ) {
                            showDisconnectConfirm = true
                        }
                    } else {
                        Text(L10n.string(.syncExplanation, language: language))
                            .font(AppFont.preset(.caption))
                            .foregroundStyle(theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        actionRowButton(
                            title: isConnectingDropbox
                                ? L10n.string(.syncConnecting, language: language)
                                : L10n.string(.syncConnect, language: language),
                            systemImage: "link"
                        ) {
                            connectDropbox()
                        }
                        .disabled(isConnectingDropbox)

                        if settings.syncEnabled, !syncCoordinator.backend.isAuthorized {
                            Text(L10n.string(.syncStatusNeedsAuth, language: language))
                                .font(AppFont.preset(.caption))
                                .foregroundStyle(theme.secondaryText)
                        }
                        if let authError = syncCoordinator.lastAuthError {
                            CopyableErrorNotice(message: authError, language: language)
                        }
                    }

                    if !syncCoordinator.engine.pendingConflicts.isEmpty {
                        SyncConflictResolutionList(
                            engine: syncCoordinator.engine,
                            theme: theme,
                            language: language
                        )
                    }
                }
            }

            // 6. 交易所
            settingsSection(
                title: L10n.string(.exchangeSection, language: language)
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    ExchangeSettingsContent(theme: theme, language: language)

                    Toggle(isOn: $settings.syncTradingSnapshots) {
                        Text(L10n.string(.syncTradingSnapshots, language: language))
                            .font(AppFont.ui(13, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.primaryText)
                    }
                    .toggleStyle(.switch)
                    .tint(theme.selectionAccent)

                    Text(L10n.string(.syncTradingSnapshotsHint, language: language))
                        .font(AppFont.preset(.caption2))
                        .foregroundStyle(theme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // 7. 数据
            settingsSection(
                title: L10n.string(.dataSection, language: language)
            ) {
                VStack(alignment: .leading, spacing: 7) {
                    if journalStore.isReadOnlyDueToLoadFailure {
                        Text(L10n.string(.journalLoadFailureTitle, language: language))
                            .font(AppFont.ui(12.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.primaryText)
                        Text(L10n.string(.journalLoadFailureBody, language: language))
                            .font(AppFont.preset(.caption))
                            .foregroundStyle(theme.secondaryText)
                        if let detail = journalStore.loadFailureMessage {
                            Text(detail)
                                .font(AppFont.preset(.caption2))
                                .foregroundStyle(theme.tertiaryText)
                        }
                        Button {
                            showStartFreshConfirm = true
                        } label: {
                            Text(L10n.string(.journalStartFresh, language: language))
                                .font(AppFont.ui(12.5, weight: .medium, design: .rounded))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.palette.pnlUp.color)
                    } else if journalStore.didRestoreFromBackup {
                        Text(L10n.string(.journalRestoredFromBackup, language: language))
                            .font(AppFont.preset(.caption))
                            .foregroundStyle(theme.secondaryText)
                    }

                    actionRowButton(
                        title: L10n.string(.journalExport, language: language),
                        systemImage: "square.and.arrow.up"
                    ) {
                        exportJournal()
                    }
                    actionRowButton(
                        title: L10n.string(.journalImport, language: language),
                        systemImage: "square.and.arrow.down"
                    ) {
                        importJournal()
                    }
                    actionRowButton(
                        title: L10n.string(.journalRevealData, language: language),
                        systemImage: "folder"
                    ) {
                        journalStore.revealDataDirectoryInFinder()
                    }

                    if let dataStatusText {
                        Text(dataStatusText)
                            .font(AppFont.preset(.caption))
                            .foregroundStyle(theme.secondaryText)
                    }
                }
            }

            // 8. 关于
            settingsSection(
                title: L10n.string(.aboutSection, language: language)
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $settings.checkForUpdatesAutomatically) {
                        Text(L10n.string(.checkForUpdatesAutomatically, language: language))
                            .font(AppFont.ui(13, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.primaryText)
                    }
                    .toggleStyle(.switch)
                    .tint(theme.selectionAccent)

                    actionRowButton(
                        title: isCheckingUpdates
                            ? L10n.string(.checkingForUpdates, language: language)
                            : L10n.string(.checkForUpdates, language: language),
                        systemImage: "arrow.triangle.2.circlepath"
                    ) {
                        Task { await checkForUpdates() }
                    }
                    .disabled(isCheckingUpdates)

                    if let updateStatusText {
                        if let updateOpenURL {
                            Button {
                                NSWorkspace.shared.open(updateOpenURL)
                            } label: {
                                Text(updateStatusText)
                                    .font(AppFont.preset(.caption))
                                    .foregroundStyle(theme.selectionAccent)
                                    .multilineTextAlignment(.leading)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(updateStatusText)
                                .font(AppFont.preset(.caption))
                                .foregroundStyle(theme.secondaryText)
                        }
                    } else if !settings.lastKnownRemoteVersion.isEmpty,
                              AppInfo.isVersion(settings.lastKnownRemoteVersion, newerThan: AppInfo.shortVersion)
                    {
                        Button {
                            if let url = URL(string: settings.lastKnownRemoteURL) {
                                NSWorkspace.shared.open(url)
                            } else {
                                NSWorkspace.shared.open(UpdateChecker.r2LatestDownloadURL)
                            }
                        } label: {
                            Text(
                                String(
                                    format: L10n.string(.updateAvailableFormat, language: language),
                                    settings.lastKnownRemoteVersion
                                )
                            )
                            .font(AppFont.preset(.caption))
                            .foregroundStyle(theme.selectionAccent)
                            .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            actionRowButton(
                title: L10n.string(.quit, language: language),
                systemImage: "power",
                isDestructive: true
            ) {
                NSApplication.shared.terminate(nil)
            }
            .padding(.top, 10)

            // 版本号与品牌底部小注
            VStack(spacing: 3) {
                Text(language == .chinese ? "Wick for macOS · 秉烛日记" : "Wick for macOS")
                    .font(AppFont.paper(11.5, weight: .bold))
                    .foregroundStyle(theme.secondaryText)
                Text("v\(AppInfo.versionDisplay)")
                    .font(AppFont.paper(10, weight: .medium))
                    .foregroundStyle(theme.tertiaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 6)
        }
        .confirmationDialog(
            L10n.string(.syncDisconnectConfirmTitle, language: language),
            isPresented: $showDisconnectConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.string(.syncDisconnect, language: language), role: .destructive) {
                syncCoordinator.disconnectDropbox()
            }
            Button(L10n.string(.cancel, language: language), role: .cancel) {}
        } message: {
            Text(L10n.string(.syncDisconnectConfirmBody, language: language))
        }
        .confirmationDialog(
            L10n.string(.journalStartFresh, language: language),
            isPresented: $showStartFreshConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.string(.journalStartFresh, language: language), role: .destructive) {
                try? journalStore.abandonCorruptDatabaseAndStartFresh()
            }
            Button(L10n.string(.cancel, language: language), role: .cancel) {}
        }
        .onAppear {
            Task { await reminderScheduler.refreshAuthorizationState() }
        }
    }

    @ViewBuilder
    private var reminderPermissionFooter: some View {
        switch reminderScheduler.authorizationState {
        case .denied:
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string(.notificationDenied, language: language))
                    .font(AppFont.preset(.caption))
                    .foregroundStyle(theme.secondaryText)
                Button {
                    reminderScheduler.openSystemNotificationSettings()
                } label: {
                    Text(L10n.string(.openNotificationSettings, language: language))
                        .font(AppFont.ui(13, weight: .medium, design: .rounded))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.selectionAccent)
            }
        case .unavailable:
            Text(L10n.string(.notificationUnavailable, language: language))
                .font(AppFont.preset(.caption))
                .foregroundStyle(theme.tertiaryText)
        case .notDetermined, .authorized, .provisional:
            EmptyView()
        }
    }

    private func actionRowButton(
        title: String,
        systemImage: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(AppFont.ui(12, weight: .medium))
                    .frame(width: 16)
                Text(title)
                    .font(AppFont.ui(12.5, weight: .medium, design: .rounded))
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(AppFont.ui(9, weight: .bold))
                    .foregroundStyle(theme.palette.textTertiary.color)
            }
            .foregroundStyle(
                isDestructive ? theme.palette.pnlUp.color
                    : theme.palette.textPrimary.color
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 6.5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(theme.palette.controlBackground.color.opacity(0.45))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(theme.palette.divider.color.opacity(0.8), lineWidth: 0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func exportJournal() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "Wick-Journal-\(AppInfo.shortVersion).zip"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // UI-06: the archive build (encode + copy + ditto) runs off the main
        // thread; only the status text is set here after it completes.
        Task {
            do {
                try await journalStore.exportArchive(to: url)
                dataStatusText = L10n.string(.journalExportSuccess, language: language)
            } catch {
                dataStatusText = L10n.string(.journalExportFailed, language: language)
                    + ": "
                    + error.localizedDescription
            }
        }
    }

    private func importJournal() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // UI-06: the unzip + validation run off the main thread.
        Task {
            do {
                try await journalStore.importArchive(from: url)
                dataStatusText = L10n.string(.journalImportSuccess, language: language)
            } catch {
                dataStatusText = L10n.string(.journalImportFailed, language: language)
                    + ": "
                    + error.localizedDescription
            }
        }
    }

    private func checkForUpdates() async {
        isCheckingUpdates = true
        updateOpenURL = nil
        defer { isCheckingUpdates = false }

        let result = await UpdateChecker.check()
        switch result.kind {
        case .upToDate:
            updateStatusText = L10n.string(.upToDate, language: language)
            settings.lastKnownRemoteVersion = ""
            settings.lastKnownRemoteURL = ""
        case .updateAvailable(let version, let downloadURL, _):
            updateStatusText = String(
                format: L10n.string(.updateAvailableFormat, language: language),
                version
            )
            updateOpenURL = downloadURL
            settings.lastKnownRemoteVersion = version
            settings.lastKnownRemoteURL = downloadURL.absoluteString
        case .unavailable:
            updateStatusText = L10n.string(.updateCheckFailed, language: language)
            updateOpenURL = UpdateChecker.r2LatestDownloadURL
        }
    }

    @ViewBuilder
    private var syncStatusFooter: some View {
        switch syncCoordinator.engine.status {
        case .syncing:
            Text(L10n.string(.syncStatusSyncing, language: language))
                .font(AppFont.preset(.caption))
                .foregroundStyle(theme.secondaryText)
        case .offline:
            Text(L10n.string(.syncStatusOffline, language: language))
                .font(AppFont.preset(.caption))
                .foregroundStyle(theme.secondaryText)
        case .needsAuth:
            Text(L10n.string(.syncStatusNeedsAuth, language: language))
                .font(AppFont.preset(.caption))
                .foregroundStyle(theme.secondaryText)
        case .error(let kind, let message):
            // SY-04: localized copy is keyed on the typed kind, never on a raw
            // English substring match of the detail.
            let display = kind == .remoteFormatTooNew
                ? L10n.string(.syncRemoteTooNew, language: language)
                : message
            CopyableErrorNotice(message: display, language: language, rawMessage: message)
        case .idle:
            HStack {
                Text(L10n.string(.syncLastSync, language: language))
                    .font(AppFont.preset(.caption))
                    .foregroundStyle(theme.secondaryText)
                Spacer()
                if let lastSyncAt = syncCoordinator.engine.lastSyncAt {
                    Text(lastSyncAt, style: .relative)
                        .font(AppFont.preset(.caption))
                        .foregroundStyle(theme.primaryText)
                } else {
                    Text(L10n.string(.syncNeverSynced, language: language))
                        .font(AppFont.preset(.caption))
                        .foregroundStyle(theme.primaryText)
                }
            }
        }
    }

    private func connectDropbox() {
        guard !isConnectingDropbox else { return }
        isConnectingDropbox = true
        Task {
            await syncCoordinator.connectDropbox()
            isConnectingDropbox = false
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppFont.paper(11.5, weight: .bold))
                .foregroundStyle(theme.palette.textSecondary.color)
                .tracking(0.4)

            content()
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.palette.divider.color.opacity(0.75))
                .frame(height: 1)
        }
    }

    private func settingsOptionButton(
        title: String,
        isSelected: Bool,
        expands: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(AppFont.ui(12.5, weight: isSelected ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(
                        isSelected ? Color(red: 1, green: 0.95, blue: 0.88)
                            : theme.palette.textPrimary.color
                    )

                if expands {
                    Spacer(minLength: 4)
                }

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(AppFont.ui(10, weight: .bold))
                        .foregroundStyle(Color(red: 1, green: 0.95, blue: 0.88))
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .frame(maxWidth: expands ? .infinity : nil, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isSelected ? theme.palette.accent.color : theme.palette.controlBackground.color.opacity(0.45))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(
                        isSelected ? theme.palette.accent.color : theme.palette.divider.color.opacity(0.8),
                        lineWidth: 0.8
                    )
            }
            .shadow(color: isSelected ? theme.palette.glow.color.opacity(0.6) : .clear, radius: 3)
        }
        .buttonStyle(.plain)
    }
}

private struct ReminderTimePickerSettingRow: View {
    let theme: PanelTheme
    let language: AppLanguage
    @ObservedObject private var settings = AppSettings.shared
    @State private var showPicker = false

    var body: some View {
        HStack {
            Text(L10n.string(.journalReminderTime, language: language))
                .font(AppFont.ui(12.5, weight: .medium, design: .rounded))
                .foregroundStyle(theme.secondaryText)
            Spacer()
            Button {
                showPicker = true
            } label: {
                HStack(spacing: 4) {
                    Text(formattedTime(settings.journalReminderTime))
                        .font(AppFont.paper(12.5, weight: .medium))
                        .foregroundStyle(theme.primaryText)
                    Image(systemName: "clock")
                        .font(AppFont.ui(10))
                        .foregroundStyle(theme.tertiaryText)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(theme.controlBackground.opacity(0.45))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(theme.palette.divider.color.opacity(0.8), lineWidth: 0.8)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPicker, arrowEdge: .top) {
                VStack(spacing: 6) {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { settings.journalReminderTime },
                            set: { settings.journalReminderTime = $0 }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .datePickerStyle(.stepperField)
                }
                .padding(10)
            }
        }
        .padding(.horizontal, 2)
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

/// 纸签的进度内容:今日大烛痕条 + 周/月/年三条细条,页脚印着格言。
/// 层级来自尺寸,不再来自色相(时间四象多色体系已退役)。
private struct ProgressSlipContent: View {
    @Environment(\.wickPalette) private var palette

    let items: [TimeProgress]
    let date: Date
    let theme: PanelTheme
    let language: AppLanguage
    /// Only true while the panel window is on screen — drives the hero flame.
    let flameAnimates: Bool

    /// Tick semantics: day 24 / week 7 / month = days in month / year 12.
    private func ticks(for index: Int) -> Int {
        switch index {
        case 0: return 24
        case 1: return 7
        case 2:
            var calendar = Calendar.current
            calendar.timeZone = .current
            return calendar.range(of: .day, in: .month, for: date)?.count ?? 31
        default: return 12
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let today = items.first {
                // Hero:今日
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(L10n.string(.panelHeroToday, language: language))
                            .font(AppFont.ui(11, weight: .bold, design: .rounded))
                            .tracking(1.4)
                            .foregroundStyle(theme.secondaryText)
                        Spacer()
                        Text(today.percentageText)
                            .font(AppFont.ui(32, weight: .black, design: .serif, monospacedDigit: true))
                            .foregroundStyle(theme.primaryText)
                    }

                    BurnStripView(
                        elapsed: 1 - today.fractionRemaining,
                        ticks: 24,
                        showsFlame: true,
                        flameAnimates: flameAnimates
                    )
                    .frame(height: 34)

                    HStack {
                        Text("00:00")
                        Spacer()
                        Text(today.endText)
                    }
                    .font(AppFont.ui(9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.tertiaryText)
                }
            }

            // 细条:周 / 月 / 年
            VStack(spacing: 10) {
                ForEach(Array(items.dropFirst().enumerated()), id: \.element.id) { offset, item in
                    let index = offset + 1
                    HStack(spacing: 10) {
                        Text(item.subtitle)
                            .font(AppFont.ui(11, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.secondaryText)
                            .frame(width: 30, alignment: .leading)

                        BurnStripView(elapsed: 1 - item.fractionRemaining, ticks: ticks(for: index))
                            .frame(height: 12)

                        Text(item.percentageText)
                            .font(AppFont.ui(10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.secondaryText)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
            .padding(.top, 2)

            HStack {
                Text(L10n.string(.motto, language: language))
                    .font(AppFont.paper(11))
                    .foregroundStyle(theme.tertiaryText)
                Spacer()
                Text(AppInfo.shortVersion)
                    .font(AppFont.ui(9, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.tertiaryText.opacity(0.7))
            }
            .padding(.top, 2)
        }
    }
}

/// Resolved day-arc theme for the panel. All roles delegate to `WickPalette`
/// so the view templates below stay unchanged from the static-theme era.
/// (Internal so the exchange settings section in its own file can reuse it.)
struct PanelTheme {
    let palette: WickPalette

    static func resolve(at date: Date, scheme: ColorScheme) -> PanelTheme {
        PanelTheme(
            palette: DayArcEngine.palette(at: date, scheme: scheme)
        )
    }

    var backgroundColors: [Color] {
        [palette.cardTop.color, palette.cardBottom.color]
    }

    var ambientGlow: Color { palette.glow.color }
    var panelStroke: Color { palette.cardStroke.color }
    var dividerAccent: Color { palette.divider.color }

    var primaryText: Color { palette.textPrimary.color }
    var secondaryText: Color { palette.textSecondary.color }
    var tertiaryText: Color { palette.textTertiary.color }

    var controlBackground: Color { palette.controlBackground.color }
    var controlBorder: Color { palette.controlBorder.color }
    var cardBorder: Color { palette.cardStroke.color }

    var settingsCardColors: [Color] {
        [palette.cardTop.color, palette.cardBottom.color]
    }

    var selectionBackground: Color { palette.accentSoft.color }
    var selectionAccent: Color { palette.accent.color }
}

// MARK: - Panel visibility (P4)

/// Reports whether this view sits in a visible window. MenuBarExtra `.window`
/// keeps the SwiftUI scene alive after dismiss; unmounting `TimelineView` and
/// the hero flame when `isVisible` goes false stops the minute tick and the
/// flame loop.
///
/// Both `isVisible` and `occlusionState` are watched and the verdict is
/// recomputed from the window: on Sequoia a dismissed MenuBarExtra panel can
/// keep `isVisible == true` while its occlusion state no longer contains
/// `.visible` (the audit sample caught AppKit still laying it out every frame).
private struct WindowVisibilityProbe: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = { isVisible = $0 }
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.onChange = { isVisible = $0 }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ProbeView, context: Context) -> CGSize? {
        .zero
    }

    final class ProbeView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observations: [NSKeyValueObservation] = []
        private var lastReported: Bool?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observations.removeAll()
            guard let window else {
                report(false)
                return
            }
            observations.append(window.observe(\.isVisible, options: [.initial]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.syncFromWindow() }
            })
            observations.append(window.observe(\.occlusionState) { [weak self] _, _ in
                DispatchQueue.main.async { self?.syncFromWindow() }
            })
        }

        private func syncFromWindow() {
            guard let window else {
                report(false)
                return
            }
            report(window.isVisible && window.occlusionState.contains(.visible))
        }

        private func report(_ visible: Bool) {
            guard lastReported != visible else { return }
            lastReported = visible
            onChange?(visible)
        }
    }
}
