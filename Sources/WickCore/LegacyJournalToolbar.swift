import AppKit

/// Item source for the macOS 13 journal toolbar: classic layout — sidebar
/// toggle leftmost (responder-chain `toggleSidebar:`, same as the system
/// item), journal-library menu next to it, new-entry at the trailing edge.
/// The toggle uses the responder chain so it drives the SwiftUI split view
/// exactly like the system toggle does.
///
/// The library control is a borderless pull-down NSPopUpButton showing the
/// book icon + active journal name (mirroring the macOS 14+ SwiftUI toolbar
/// menu) — `NSMenuToolbarItem` cannot show a title next to its icon, and a
/// bezeled NSButton reads like a text field in the toolbar.
@MainActor
final class LegacyJournalToolbarDelegate: NSObject, NSToolbarDelegate, NSMenuDelegate {
    private enum ItemID {
        static let toggle = NSToolbarItem.Identifier("wick.toggleSidebar")
        static let library = NSToolbarItem.Identifier("wick.journalLibrary")
        static let newEntry = NSToolbarItem.Identifier("wick.newEntry")
    }

    private let libraryMenu = NSMenu()
    private var activeJournalObserver: NSObjectProtocol?

    override init() {
        super.init()
        libraryMenu.delegate = self
        // The delegate lives as long as JournalWindowController.shared (the whole
        // app), and the block only weakly references it — no removal needed.
        activeJournalObserver = NotificationCenter.default.addObserver(
            forName: .wickActiveJournalDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rebuildLibraryMenu()
            }
        }
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case ItemID.toggle:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil)
            item.label = L10n.string(.journalToggleSidebar, language: AppSettings.shared.language)
            item.toolTip = item.label
            item.target = self
            item.action = #selector(toggleSidebar)
            return item
        case ItemID.library:
            let popup = NSPopUpButton(frame: .zero, pullsDown: true)
            popup.isBordered = false
            popup.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            popup.menu = libraryMenu
            popup.setAccessibilityLabel(
                L10n.string(.journalLibraryMenu, language: AppSettings.shared.language)
            )
            rebuildLibraryMenu()

            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.view = popup
            item.label = L10n.string(.journalLibraryMenu, language: AppSettings.shared.language)
            return item
        case ItemID.newEntry:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: nil)
            item.label = L10n.string(.journalNewEntry, language: AppSettings.shared.language)
            item.toolTip = item.label
            item.target = self
            item.action = #selector(newEntry)
            return item
        default:
            return nil
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ItemID.toggle, ItemID.library, .flexibleSpace, ItemID.newEntry]
    }

    // MARK: - NSMenuDelegate (rebuild journal list on open)

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildLibraryMenu()
    }

    /// Rebuilds the shared menu. With `pullsDown`, item 0 is the button's
    /// closed-state title (book icon + active journal name) and never appears
    /// in the opened list — so the whole menu is rebuilt whenever the active
    /// journal or a name changes.
    private func rebuildLibraryMenu() {
        libraryMenu.removeAllItems()
        let language = AppSettings.shared.language
        let store = JournalStore.shared

        let titleItem = NSMenuItem(
            title: store.activeJournal?.name ?? "",
            action: nil,
            keyEquivalent: ""
        )
        titleItem.image = NSImage(systemSymbolName: "book.closed", accessibilityDescription: nil)
        libraryMenu.addItem(titleItem)

        for journal in store.journals {
            let item = NSMenuItem(
                title: journal.name,
                action: #selector(selectJournal(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = journal.id.uuidString
            item.state = journal.id == store.activeJournalID ? .on : .off
            libraryMenu.addItem(item)
        }

        libraryMenu.addItem(.separator())

        let newItem = NSMenuItem(
            title: L10n.string(.journalLibraryNew, language: language),
            action: #selector(requestNewJournal),
            keyEquivalent: ""
        )
        newItem.target = self
        libraryMenu.addItem(newItem)

        let renameItem = NSMenuItem(
            title: L10n.string(.journalLibraryRename, language: language),
            action: #selector(requestRenameJournal),
            keyEquivalent: ""
        )
        renameItem.target = self
        libraryMenu.addItem(renameItem)

        let deleteItem = NSMenuItem(
            title: L10n.string(.journalLibraryDelete, language: language),
            action: #selector(requestDeleteJournal),
            keyEquivalent: ""
        )
        deleteItem.target = self
        deleteItem.isEnabled = store.journals.count > 1
        libraryMenu.addItem(deleteItem)
    }

    @objc private func toggleSidebar() {
        NSApplication.shared.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
    }

    @objc private func newEntry() {
        _ = JournalStore.shared.openOrCreateToday()
    }

    @objc private func selectJournal(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let id = UUID(uuidString: raw)
        else { return }
        JournalStore.shared.switchToJournal(id: id)
    }

    @objc private func requestNewJournal() {
        // Post asynchronously: on macOS 13 a SwiftUI alert presented from inside
        // menu tracking is swallowed while the menu finishes closing.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .wickJournalLibraryNewRequested, object: nil)
        }
    }

    @objc private func requestRenameJournal() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .wickJournalLibraryRenameRequested, object: nil)
        }
    }

    @objc private func requestDeleteJournal() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .wickJournalLibraryDeleteRequested, object: nil)
        }
    }
}
