import AppKit

/// Item source for the macOS 13 journal toolbar: classic layout — sidebar
/// toggle leftmost (responder-chain `toggleSidebar:`, same as the system
/// item), journal-library menu next to it, new-entry at the trailing edge.
/// The toggle uses the responder chain so it drives the SwiftUI split view
/// exactly like the system toggle does.
///
/// The library control is a view-based button (book icon + active journal
/// name, mirroring the macOS 14+ SwiftUI toolbar label) that pops a shared
/// NSMenu — `NSMenuToolbarItem` cannot show a title next to its icon.
@MainActor
final class LegacyJournalToolbarDelegate: NSObject, NSToolbarDelegate, NSMenuDelegate {
    private enum ItemID {
        static let toggle = NSToolbarItem.Identifier("wick.toggleSidebar")
        static let library = NSToolbarItem.Identifier("wick.journalLibrary")
        static let newEntry = NSToolbarItem.Identifier("wick.newEntry")
    }

    private let libraryMenu = NSMenu()
    private weak var libraryButton: NSButton?
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
                self?.updateLibraryButtonTitle()
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
            let button = NSButton(
                image: NSImage(systemSymbolName: "book.closed", accessibilityDescription: nil)
                    ?? NSImage(),
                target: self,
                action: #selector(showLibraryMenu(_:))
            )
            button.bezelStyle = .texturedRounded
            button.imagePosition = .imageLeading
            button.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            button.lineBreakMode = .byTruncatingTail
            button.title = JournalStore.shared.activeJournal?.name ?? ""
            button.setAccessibilityLabel(
                L10n.string(.journalLibraryMenu, language: AppSettings.shared.language)
            )

            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.view = button
            item.label = L10n.string(.journalLibraryMenu, language: AppSettings.shared.language)
            item.minSize = NSSize(width: 80, height: 26)
            item.maxSize = NSSize(width: 200, height: 28)
            libraryButton = button
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

    // MARK: - Library button title

    private func updateLibraryButtonTitle() {
        libraryButton?.title = JournalStore.shared.activeJournal?.name ?? ""
    }

    // MARK: - NSMenuDelegate (rebuild journal list on open)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let language = AppSettings.shared.language

        let store = JournalStore.shared
        for journal in store.journals {
            let item = NSMenuItem(
                title: journal.name,
                action: #selector(selectJournal(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = journal.id.uuidString
            item.state = journal.id == store.activeJournalID ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let newItem = NSMenuItem(
            title: L10n.string(.journalLibraryNew, language: language),
            action: #selector(requestNewJournal),
            keyEquivalent: ""
        )
        newItem.target = self
        menu.addItem(newItem)

        let renameItem = NSMenuItem(
            title: L10n.string(.journalLibraryRename, language: language),
            action: #selector(requestRenameJournal),
            keyEquivalent: ""
        )
        renameItem.target = self
        menu.addItem(renameItem)

        let deleteItem = NSMenuItem(
            title: L10n.string(.journalLibraryDelete, language: language),
            action: #selector(requestDeleteJournal),
            keyEquivalent: ""
        )
        deleteItem.target = self
        deleteItem.isEnabled = store.journals.count > 1
        menu.addItem(deleteItem)
    }

    @objc private func toggleSidebar() {
        NSApplication.shared.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
    }

    @objc private func newEntry() {
        _ = JournalStore.shared.openOrCreateToday()
    }

    @objc private func showLibraryMenu(_ sender: NSButton) {
        // Rebuild contents right before showing (the delegate also does this on
        // open, but an explicit pass keeps the checkmark/title guaranteed fresh).
        menuNeedsUpdate(libraryMenu)
        libraryMenu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: sender.bounds.height + 4),
            in: sender
        )
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
