import AppKit
import SwiftUI

@main
struct WickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var journalStore = JournalStore.shared

    var body: some Scene {
        MenuBarExtra {
            ProgressPanelView()
                .environmentObject(settings)
                .environmentObject(journalStore)
                .preferredColorScheme(settings.preferredColorScheme)
        } label: {
            Image(nsImage: MenuBarIcon.image)
                .renderingMode(.template)
                .accessibilityLabel("Wick")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        Task { @MainActor in
            JournalReminderScheduler.shared.configure()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            Task { @MainActor in
                JournalWindowController.shared.openJournal()
            }
        }
        return true
    }
}
