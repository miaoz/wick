import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Root

struct JournalRootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: JournalStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var exportStatus: String?
    @State private var showStartFreshConfirm = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

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
                splitLayout
            }
        }
        .environment(\.wickPalette, palette)
        .tint(palette.accent.color)
        .frame(minWidth: 720, minHeight: 480)
        .preferredColorScheme(settings.preferredColorScheme)
        .background(palette.backgroundBottom.color)
        .confirmationDialog(
            L10n.string(.journalStartFresh, language: settings.language),
            isPresented: $showStartFreshConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.string(.journalStartFresh, language: settings.language), role: .destructive) {
                try? store.abandonCorruptDatabaseAndStartFresh()
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

            // The macOS 13 AppKit toolbar has no keyboardShortcut support, so
            // these shortcuts stay as hidden in-view buttons on that path.
            if journalNeedsInViewTopBar {
                Button("") {
                    _ = store.openOrCreateToday()
                }
                .keyboardShortcut("n", modifiers: [.command])
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)

                Button("") {
                    // Same responder-chain action as the system sidebar toggle.
                    NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("s", modifiers: [.control, .command])
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
        }

        // macOS 14+ installs a real window toolbar (the split view's own
        // sidebar toggle plus this new-entry item). On macOS 13 nothing
        // materializes in this manually created window, so
        // JournalWindowController installs an AppKit NSToolbar instead and
        // the shortcut keys below stay as hidden in-view buttons.
        if journalNeedsInViewTopBar {
            base
        } else {
            base.toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        _ = store.openOrCreateToday()
                    } label: {
                        Label(
                            L10n.string(.journalNewEntry, language: settings.language),
                            systemImage: "square.and.pencil"
                        )
                    }
                    .help(L10n.string(.journalNewEntry, language: settings.language))
                    .keyboardShortcut("n", modifiers: [.command])
                }
            }
        }
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
                    showStartFreshConfirm = true
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

    private var splitLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            JournalTimelineSidebar()
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
        } detail: {
            JournalEditorPane()
        }
    }
}

/// True on macOS 13: no toolbar (neither SwiftUI `.toolbar` items nor the
/// split view's sidebar toggle) materializes in the manually created journal
/// window there, so JournalWindowController installs an AppKit NSToolbar and
/// shortcut keys stay as hidden in-view buttons.
/// `WICK_INVIEW_TOPBAR=1` forces the macOS 13 chrome in debug builds.
var journalNeedsInViewTopBar: Bool {
    #if DEBUG
    if ProcessInfo.processInfo.environment["WICK_INVIEW_TOPBAR"] != nil {
        return true
    }
    #endif
    return ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 14
}

