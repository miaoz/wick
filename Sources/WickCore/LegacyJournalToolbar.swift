import AppKit

/// Item source for the macOS 13 journal toolbar: classic layout — sidebar
/// toggle leftmost (responder-chain `toggleSidebar:`, same as the system
/// item), new-entry at the trailing edge. The toggle uses the responder chain
/// so it drives the SwiftUI split view exactly like the system toggle does.
final class LegacyJournalToolbarDelegate: NSObject, NSToolbarDelegate {
    private enum ItemID {
        static let toggle = NSToolbarItem.Identifier("wick.toggleSidebar")
        static let newEntry = NSToolbarItem.Identifier("wick.newEntry")
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
            item.target = self
            item.action = #selector(toggleSidebar)
            return item
        case ItemID.newEntry:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: nil)
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
        [ItemID.toggle, .flexibleSpace, ItemID.newEntry]
    }

    @objc private func toggleSidebar() {
        NSApplication.shared.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
    }

    @objc private func newEntry() {
        MainActor.assumeIsolated {
            _ = JournalStore.shared.openOrCreateToday()
        }
    }
}
