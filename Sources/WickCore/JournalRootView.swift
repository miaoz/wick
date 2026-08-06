import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Root

struct JournalRootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: JournalStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var exportStatus: String?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // Multi-journal library actions (shared by toolbar menu). The dialog KIND
    // is stored separately from the show flag so dismissing never swaps content
    // mid-animation, and one modifier per dialog type avoids the macOS 13
    // multiple-alert bug class.
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
            journalConfirmDialog == .deleteJournal
                ? L10n.string(.journalLibraryDeleteConfirm, language: settings.language)
                : L10n.string(.journalStartFresh, language: settings.language),
            isPresented: $showJournalConfirmDialog,
            titleVisibility: .visible
        ) {
            switch journalConfirmDialog {
            case .deleteJournal:
                Button(L10n.string(.journalLibraryDelete, language: settings.language), role: .destructive) {
                    if let id = store.activeJournalID {
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
                    if let id = store.activeJournalID {
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
        // Bridge AppKit toolbar (macOS 13) journal-library actions into SwiftUI alerts.
        .onReceive(NotificationCenter.default.publisher(for: .wickJournalLibraryNewRequested)) { _ in
            beginNewJournal()
        }
        .onReceive(NotificationCenter.default.publisher(for: .wickJournalLibraryRenameRequested)) { _ in
            beginRenameJournal()
        }
        .onReceive(NotificationCenter.default.publisher(for: .wickJournalLibraryDeleteRequested)) { _ in
            beginDeleteJournal()
        }

        // macOS 14+ installs a real window toolbar (the split view's own
        // sidebar toggle plus journal switcher + new-entry). On macOS 13 nothing
        // materializes in this manually created window, so
        // JournalWindowController installs an AppKit NSToolbar instead and
        // the shortcut keys below stay as hidden in-view buttons.
        if journalNeedsInViewTopBar {
            base
        } else {
            base.toolbar {
                ToolbarItem(placement: .navigation) {
                    journalLibraryMenu
                }
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

    /// Dropdown next to the sidebar toggle: select / create / rename / delete journals.
    private var journalLibraryMenu: some View {
        Menu {
            ForEach(store.journals) { journal in
                Button {
                    store.switchToJournal(id: journal.id)
                } label: {
                    if journal.id == store.activeJournalID {
                        Label(journal.name, systemImage: "checkmark")
                    } else {
                        Text(journal.name)
                    }
                }
            }

            Divider()

            Button(L10n.string(.journalLibraryNew, language: settings.language)) {
                beginNewJournal()
            }
            Button(L10n.string(.journalLibraryRename, language: settings.language)) {
                beginRenameJournal()
            }
            Button(
                L10n.string(.journalLibraryDelete, language: settings.language),
                role: .destructive
            ) {
                beginDeleteJournal()
            }
            .disabled(store.journals.count <= 1)
        } label: {
            Label {
                Text(store.activeJournal?.name ?? L10n.string(.journalLibraryDefaultName, language: settings.language))
                    .lineLimit(1)
            } icon: {
                Image(systemName: "book.closed")
            }
        }
        .help(L10n.string(.journalLibraryMenu, language: settings.language))
        .menuIndicator(.visible)
    }

    private func beginNewJournal() {
        journalNameAlert = .new
        journalNameDraft = store.defaultJournalName(for: settings.language)
        showJournalNameAlert = true
    }

    private func beginRenameJournal() {
        journalNameAlert = .rename
        journalNameDraft = store.activeJournal?.name
            ?? L10n.string(.journalLibraryDefaultName, language: settings.language)
        showJournalNameAlert = true
    }

    private func beginDeleteJournal() {
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
