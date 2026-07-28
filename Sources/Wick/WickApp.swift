import AppKit
import SwiftUI

@main
struct WickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var settings = AppSettings.shared

    var body: some Scene {
        MenuBarExtra {
            ProgressPanelView()
                .environmentObject(settings)
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
    }
}
