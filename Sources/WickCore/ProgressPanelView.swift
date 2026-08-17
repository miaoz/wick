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
    @State private var showsSettings = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let theme = PanelTheme.resolve(at: DayArcEngine.currentDate(), scheme: colorScheme)
            let language = settings.language

            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
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
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(theme.panelStroke, lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 18) {
                    if showsSettings {
                        settingsHeader(theme: theme, language: language)
                        settingsDivider(theme: theme)
                        ScrollView {
                            SettingsContentView(theme: theme, language: language)
                        }
                        .frame(maxHeight: 520)
                    } else {
                        progressHeader(date: context.date, theme: theme, language: language)
                        settingsDivider(theme: theme)

                        let items = TimeProgressCalculator.allProgress(
                            at: context.date,
                            language: language,
                            calendar: settings.progressCalendar
                        )

                        VStack(spacing: 12) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                MetricProgressCard(
                                    item: item,
                                    theme: theme.metricTheme(for: index),
                                    panelTheme: theme,
                                    language: language
                                )
                            }
                        }
                    }
                }
                .padding(PanelViewLayout.contentPadding)
            }
            .padding(PanelViewLayout.outerPadding)
            .frame(width: PanelViewLayout.width)
            .fixedSize(horizontal: false, vertical: true)
            .animation(.easeInOut(duration: 0.18), value: showsSettings)
            .animation(.easeInOut(duration: 0.18), value: settings.language)
            .animation(.easeInOut(duration: 0.18), value: settings.appearance)
        }
    }

    @ViewBuilder
    private func progressHeader(date: Date, theme: PanelTheme, language: AppLanguage) -> some View {
        HStack(alignment: .top, spacing: 14) {
            themeIcon(theme: theme)

            VStack(alignment: .leading, spacing: 4) {
                Text(theme.title(language: language))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.primaryText)

                Text(L10n.string(.motto, language: language))
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)

                Text(
                    date.formatted(
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
                .font(.caption.monospacedDigit())
                .foregroundStyle(theme.tertiaryText)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                headerButton(
                    systemName: "calendar",
                    help: L10n.string(.tradingCalendar, language: language),
                    theme: theme
                ) {
                    TradingCalendarWindowController.shared.openCalendar()
                }

                headerButton(
                    systemName: "book.closed",
                    help: L10n.string(.journal, language: language),
                    theme: theme
                ) {
                    JournalWindowController.shared.openJournal(createTodayIfNeeded: false)
                }

                headerButton(
                    systemName: "gearshape",
                    help: L10n.string(.settings, language: language),
                    theme: theme
                ) {
                    showsSettings = true
                }
            }
        }
    }

    @ViewBuilder
    private func settingsHeader(theme: PanelTheme, language: AppLanguage) -> some View {
        HStack(alignment: .center, spacing: 14) {
            themeIcon(theme: theme)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string(.settingsTitle, language: language))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.primaryText)

                Text(theme.title(language: language))
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)
            }

            Spacer(minLength: 8)

            headerButton(
                systemName: "chevron.left",
                help: L10n.string(.back, language: language),
                theme: theme
            ) {
                showsSettings = false
            }
        }
    }

    private func themeIcon(theme: PanelTheme) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: theme.iconGradient,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 46, height: 46)
                .shadow(color: theme.iconGlow, radius: 12, y: 4)

            Text(theme.icon)
                .font(.system(size: 23))
        }
    }

    private func settingsDivider(theme: PanelTheme) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.clear, theme.dividerAccent, Color.clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }

    private func headerButton(
        systemName: String,
        help: String,
        theme: PanelTheme,
        action: @escaping () -> Void
    ) -> some View {
        PanelHeaderIconButton(systemName: systemName, help: help, theme: theme, action: action)
    }
}

/// Menu-bar panel header icon (calendar / journal / settings / back).
/// Keeps the day-arc control chrome idle; hover adds a soft accent mask.
private struct PanelHeaderIconButton: View {
    let systemName: String
    let help: String
    let theme: PanelTheme
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.primaryText.opacity(0.76))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(theme.controlBackground)
                )
                // Hover mask sits above the control fill — same idea as journal quiet icons.
                .overlay {
                    Circle()
                        .fill(theme.selectionBackground.opacity(isHovered ? 1 : 0))
                }
                .overlay {
                    Circle()
                        .strokeBorder(
                            isHovered
                                ? theme.selectionAccent.opacity(0.35)
                                : theme.controlBorder,
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

private struct SettingsContentView: View {
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
        VStack(spacing: 12) {
            settingsSection(
                title: L10n.string(.language, language: language)
            ) {
                HStack(spacing: 8) {
                    ForEach(AppLanguage.allCases) { option in
                        settingsOptionButton(
                            title: option.displayName,
                            isSelected: settings.language == option
                        ) {
                            settings.language = option
                        }
                    }
                }
            }

            settingsSection(
                title: L10n.string(.appearance, language: language)
            ) {
                VStack(spacing: 8) {
                    ForEach(AppAppearance.allCases) { option in
                        settingsOptionButton(
                            title: option.displayName(language: language),
                            isSelected: settings.appearance == option,
                            expands: true
                        ) {
                            settings.appearance = option
                        }
                    }
                }
            }

            settingsSection(
                title: L10n.string(.generalSection, language: language)
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $settings.showMenuBarPercentage) {
                        Text(L10n.string(.menuBarPercentage, language: language))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.primaryText)
                    }
                    .toggleStyle(.switch)
                    .tint(theme.selectionAccent)

                    Toggle(isOn: $settings.weekStartsOnMonday) {
                        Text(L10n.string(.weekStartsOnMonday, language: language))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.primaryText)
                    }
                    .toggleStyle(.switch)
                    .tint(theme.selectionAccent)

                    Toggle(isOn: $settings.launchAtLoginDesired) {
                        Text(L10n.string(.launchAtLogin, language: language))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.primaryText)
                    }
                    .toggleStyle(.switch)
                    .tint(theme.selectionAccent)

                    if settings.launchAtLoginDesired && settings.launchAtLoginNeedsApproval {
                        Text(L10n.string(.launchAtLoginNeedsApproval, language: language))
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                        Button {
                            LaunchAtLogin.openSystemLoginItems()
                        } label: {
                            Text(L10n.string(.openLoginItems, language: language))
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.selectionAccent)
                    }
                }
            }

            settingsSection(
                title: L10n.string(.journalSection, language: language)
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        JournalWindowController.shared.openJournal()
                    } label: {
                        HStack {
                            Image(systemName: "book.closed")
                            Text(L10n.string(.journalOpenAction, language: language))
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(theme.primaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(theme.controlBackground)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(theme.controlBorder, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)

                    Toggle(isOn: $settings.journalReminderEnabled) {
                        Text(L10n.string(.journalReminderEnabled, language: language))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.primaryText)
                    }
                    .toggleStyle(.switch)
                    .tint(theme.selectionAccent)

                    if settings.journalReminderEnabled {
                        HStack {
                            Text(L10n.string(.journalReminderTime, language: language))
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(theme.secondaryText)
                            Spacer()
                            DatePicker(
                                "",
                                selection: Binding(
                                    get: { settings.journalReminderTime },
                                    set: { settings.journalReminderTime = $0 }
                                ),
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()
                            .datePickerStyle(.field)
                        }
                        .padding(.horizontal, 4)

                        reminderPermissionFooter
                    }
                }
            }

            settingsSection(
                title: L10n.string(.dataSection, language: language)
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    if journalStore.isReadOnlyDueToLoadFailure {
                        Text(L10n.string(.journalLoadFailureTitle, language: language))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.primaryText)
                        Text(L10n.string(.journalLoadFailureBody, language: language))
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                        if let detail = journalStore.loadFailureMessage {
                            Text(detail)
                                .font(.caption2)
                                .foregroundStyle(theme.tertiaryText)
                        }
                        Button {
                            showStartFreshConfirm = true
                        } label: {
                            Text(L10n.string(.journalStartFresh, language: language))
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red.opacity(0.85))
                    } else if journalStore.didRestoreFromBackup {
                        Text(L10n.string(.journalRestoredFromBackup, language: language))
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                    }

                    dataActionButton(
                        title: L10n.string(.journalExport, language: language),
                        systemImage: "square.and.arrow.up"
                    ) {
                        exportJournal()
                    }
                    dataActionButton(
                        title: L10n.string(.journalImport, language: language),
                        systemImage: "square.and.arrow.down"
                    ) {
                        importJournal()
                    }
                    dataActionButton(
                        title: L10n.string(.journalRevealData, language: language),
                        systemImage: "folder"
                    ) {
                        journalStore.revealDataDirectoryInFinder()
                    }

                    if let dataStatusText {
                        Text(dataStatusText)
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
            }

            settingsSection(
                title: L10n.string(.exchangeSection, language: language)
            ) {
                ExchangeSettingsContent(theme: theme, language: language)
            }

            settingsSection(
                title: L10n.string(.syncSection, language: language)
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    if settings.syncEnabled && syncCoordinator.backend.isAuthorized {
                        HStack {
                            Text("Dropbox")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(theme.secondaryText)
                            Spacer()
                            Text(settings.syncAccountEmail.isEmpty ? "—" : settings.syncAccountEmail)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
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
                                    .font(.caption)
                                    .foregroundStyle(theme.secondaryText)
                                    Spacer()
                                    Button {
                                        syncCoordinator.adoptRemoteJournal(manifest)
                                    } label: {
                                        Text(L10n.string(.syncImportJournal, language: language))
                                            .font(.system(size: 13, weight: .medium, design: .rounded))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(theme.selectionAccent)
                                }
                            }
                        }

                        dataActionButton(
                            title: L10n.string(.syncNow, language: language),
                            systemImage: "arrow.triangle.2.circlepath"
                        ) {
                            syncCoordinator.engine.syncNow()
                        }
                        dataActionButton(
                            title: L10n.string(.syncDisconnect, language: language),
                            systemImage: "link"
                        ) {
                            showDisconnectConfirm = true
                        }
                    } else {
                        Text(L10n.string(.syncExplanation, language: language))
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        dataActionButton(
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
                                .font(.caption)
                                .foregroundStyle(theme.secondaryText)
                        }
                        if let authError = syncCoordinator.lastAuthError {
                            Text(authError)
                                .font(.caption2)
                                .foregroundStyle(theme.tertiaryText)
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

            settingsSection(
                title: L10n.string(.aboutSection, language: language)
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(L10n.string(.versionLabel, language: language))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.secondaryText)
                        Spacer()
                        Text(AppInfo.versionDisplay)
                            .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(theme.primaryText)
                            .textSelection(.enabled)
                    }

                    Toggle(isOn: $settings.checkForUpdatesOnLaunch) {
                        Text(L10n.string(.checkUpdatesOnLaunch, language: language))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.primaryText)
                    }
                    .toggleStyle(.switch)
                    .tint(theme.selectionAccent)

                    Button {
                        Task { await checkForUpdates() }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text(
                                isCheckingUpdates
                                    ? L10n.string(.checkingForUpdates, language: language)
                                    : L10n.string(.checkForUpdates, language: language)
                            )
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            Spacer()
                        }
                        .foregroundStyle(theme.primaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(theme.controlBackground)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(theme.controlBorder, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isCheckingUpdates)

                    if let updateStatusText {
                        if let updateOpenURL {
                            Button {
                                NSWorkspace.shared.open(updateOpenURL)
                            } label: {
                                Text(updateStatusText)
                                    .font(.caption)
                                    .foregroundStyle(theme.selectionAccent)
                                    .multilineTextAlignment(.leading)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(updateStatusText)
                                .font(.caption)
                                .foregroundStyle(theme.secondaryText)
                        }
                    } else if !settings.lastKnownRemoteVersion.isEmpty,
                              AppInfo.isVersion(settings.lastKnownRemoteVersion, newerThan: AppInfo.shortVersion)
                    {
                        Button {
                            if let url = URL(string: settings.lastKnownRemoteURL) {
                                NSWorkspace.shared.open(url)
                            } else {
                                NSWorkspace.shared.open(UpdateChecker.releasesPageURL)
                            }
                        } label: {
                            Text(
                                String(
                                    format: L10n.string(.updateAvailableFormat, language: language),
                                    settings.lastKnownRemoteVersion
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(theme.selectionAccent)
                            .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Image(systemName: "power")
                    Text(L10n.string(.quit, language: language))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                    Spacer()
                }
                .foregroundStyle(theme.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(theme.controlBackground)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(theme.controlBorder, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
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
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                Button {
                    reminderScheduler.openSystemNotificationSettings()
                } label: {
                    Text(L10n.string(.openNotificationSettings, language: language))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.selectionAccent)
            }
        case .unavailable:
            Text(L10n.string(.notificationUnavailable, language: language))
                .font(.caption)
                .foregroundStyle(theme.tertiaryText)
        case .notDetermined, .authorized, .provisional:
            EmptyView()
        }
    }

    private func dataActionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                Text(title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                Spacer(minLength: 8)
            }
            .foregroundStyle(theme.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.controlBackground)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(theme.controlBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func exportJournal() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "Wick-Journal-\(AppInfo.shortVersion).zip"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try journalStore.exportArchive(to: url)
            dataStatusText = L10n.string(.journalExportSuccess, language: language)
        } catch {
            dataStatusText = L10n.string(.journalExportFailed, language: language)
                + ": "
                + error.localizedDescription
        }
    }

    private func importJournal() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try journalStore.importArchive(from: url)
            dataStatusText = L10n.string(.journalImportSuccess, language: language)
        } catch {
            dataStatusText = L10n.string(.journalImportFailed, language: language)
                + ": "
                + error.localizedDescription
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
        case .updateAvailable(let version, let url):
            updateStatusText = String(
                format: L10n.string(.updateAvailableFormat, language: language),
                version
            )
            updateOpenURL = url
            settings.lastKnownRemoteVersion = version
            settings.lastKnownRemoteURL = url.absoluteString
        case .unavailable:
            updateStatusText = L10n.string(.updateCheckFailed, language: language)
            updateOpenURL = UpdateChecker.releasesPageURL
        }
    }

    @ViewBuilder
    private var syncStatusFooter: some View {
        switch syncCoordinator.engine.status {
        case .syncing:
            Text(L10n.string(.syncStatusSyncing, language: language))
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        case .offline:
            Text(L10n.string(.syncStatusOffline, language: language))
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        case .needsAuth:
            Text(L10n.string(.syncStatusNeedsAuth, language: language))
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        case .error(let message):
            Text(
                message.contains("remote format")
                    ? L10n.string(.syncRemoteTooNew, language: language)
                    : message
            )
            .font(.caption)
            .foregroundStyle(theme.secondaryText)
        case .idle:
            HStack {
                Text(L10n.string(.syncLastSync, language: language))
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                Spacer()
                if let lastSyncAt = syncCoordinator.engine.lastSyncAt {
                    Text(lastSyncAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(theme.primaryText)
                } else {
                    Text(L10n.string(.syncNeverSynced, language: language))
                        .font(.caption)
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
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(theme.secondaryText)
                .textCase(.uppercase)
                .tracking(0.6)

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: theme.settingsCardColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(theme.cardBorder, lineWidth: 1)
        }
    }

    private func settingsOptionButton(
        title: String,
        isSelected: Bool,
        expands: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? theme.primaryText : theme.secondaryText)

                if expands {
                    Spacer(minLength: 8)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.selectionAccent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: expands ? .infinity : nil, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? theme.selectionBackground : theme.controlBackground)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? theme.selectionAccent.opacity(0.45) : theme.controlBorder,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

private struct MetricProgressCard: View {
    let item: TimeProgress
    let theme: MetricTheme
    let panelTheme: PanelTheme
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 10) {
                Text(item.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.primary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(theme.primary.opacity(0.14), in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(theme.primary.opacity(0.18), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.subtitle)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(panelTheme.primaryText)
                    Text(item.remainingText)
                        .font(.caption)
                        .foregroundStyle(panelTheme.secondaryText)
                }

                Spacer(minLength: 8)

                Text(item.percentageText)
                    .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(panelTheme.primaryText)
            }

            WickProgressBar(value: item.fractionRemaining, theme: theme)
                .frame(height: 12)

            HStack {
                Text(item.endText)
                Spacer()
                Text(progressLabel(for: item.fractionRemaining))
            }
            .font(.caption2)
            .foregroundStyle(panelTheme.tertiaryText)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [theme.cardTop, theme.cardBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(panelTheme.cardBorder, lineWidth: 1)
        }
        .shadow(color: theme.glow, radius: 10, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.percentageText), \(item.remainingText)")
    }

    private func progressLabel(for value: Double) -> String {
        if value < 0.15 {
            return L10n.string(.progressLow, language: language)
        }

        if value < 0.4 {
            return L10n.string(.progressBurning, language: language)
        }

        return L10n.string(.progressPlenty, language: language)
    }
}

private struct WickProgressBar: View {
    let value: Double
    let theme: MetricTheme

    var body: some View {
        GeometryReader { proxy in
            let width = max(0, min(proxy.size.width, proxy.size.width * value))

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(theme.trackFill)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(theme.trackStroke, lineWidth: 1)
                    }

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [theme.primary, theme.secondary],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width)
                    .shadow(color: theme.glow, radius: 8, y: 2)
                    .overlay(alignment: .trailing) {
                        Circle()
                            .fill(theme.spark.opacity(width > 10 ? 1 : 0))
                            .frame(width: 8, height: 8)
                            .blur(radius: 0.4)
                            .padding(.trailing, 2)
                    }
            }
        }
    }
}

/// Resolved day-arc theme for the panel. All roles delegate to `WickPalette`
/// so the view templates below stay unchanged from the static-theme era.
/// (Internal so the exchange settings section in its own file can reuse it.)
struct PanelTheme {
    let palette: WickPalette
    let phase: DayPhase
    let metrics: [MetricTheme]

    static func resolve(at date: Date, scheme: ColorScheme) -> PanelTheme {
        PanelTheme(
            palette: DayArcEngine.palette(at: date, scheme: scheme),
            phase: DayArcEngine.phase(at: date),
            metrics: DayArcEngine.metricThemes(at: date, scheme: scheme)
        )
    }

    var backgroundColors: [Color] {
        [palette.backgroundTop.color, palette.backgroundBottom.color]
    }

    var ambientGlow: Color { palette.glow.color }
    var panelStroke: Color { palette.cardStroke.color }
    var dividerAccent: Color { palette.divider.color }

    var iconGradient: [Color] {
        [palette.accent.lightened(by: 0.25).color, palette.accent.darkened(by: 0.15).color]
    }

    var iconGlow: Color { palette.glow.color }

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

    func metricTheme(for index: Int) -> MetricTheme {
        metrics[index % metrics.count]
    }

    func title(language: AppLanguage) -> String {
        phase.name(language: language)
    }

    var icon: String { phase.emoji }
}
