import AppKit

/// Item source for the macOS 13 journal toolbar: classic layout — sidebar
/// toggle leftmost (responder-chain `toggleSidebar:`, same as the system
/// item), journal-library menu next to it, new-entry at the trailing edge.
/// The toggle uses the responder chain so it drives the SwiftUI split view
/// exactly like the system toggle does.
final class LegacyJournalToolbarDelegate: NSObject, NSToolbarDelegate, NSMenuDelegate {
    private enum ItemID {
        static let toggle = NSToolbarItem.Identifier("wick.toggleSidebar")
        static let library = NSToolbarItem.Identifier("wick.journalLibrary")
        static let newEntry = NSToolbarItem.Identifier("wick.newEntry")
    }

    private weak var libraryMenuItem: NSMenuToolbarItem?

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
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            item.image = NSImage(systemSymbolName: "book.closed", accessibilityDescription: nil)
            item.label = L10n.string(.journalLibraryMenu, language: AppSettings.shared.language)
            item.toolTip = item.label
            item.showsIndicator = true
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            libraryMenuItem = item
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
        menu.removeAllItems()
        let language = AppSettings.shared.language

        MainActor.assumeIsolated {
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
    }

    @objc private func toggleSidebar() {
        NSApplication.shared.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
    }

    @objc private func newEntry() {
        MainActor.assumeIsolated {
            _ = JournalStore.shared.openOrCreateToday()
        }
    }

    @objc private func selectJournal(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let id = UUID(uuidString: raw)
        else { return }
        MainActor.assumeIsolated {
            JournalStore.shared.switchToJournal(id: id)
        }
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
