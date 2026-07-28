import AppKit
import Combine
import SwiftUI

public struct WickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var journalStore = JournalStore.shared

    public init() {}

    public var body: some Scene {
        MenuBarExtra {
            ProgressPanelView()
                .environmentObject(settings)
                .environmentObject(journalStore)
                .preferredColorScheme(settings.preferredColorScheme)
        } label: {
            MenuBarLabelView()
                .environmentObject(settings)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Menu bar label: candle template icon + optional day-remaining percentage.
///
/// Important: do **not** put `TimelineView` (or other high-frequency invalidators) in the
/// `MenuBarExtra` label. On recent macOS this causes an infinite
/// `MenuBarExtraHost.requestUpdate` → `NSStatusBarButton.setImage` loop at 100% CPU,
/// so the process is alive but the item never becomes usable.
private struct MenuBarLabelView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var dayPercentText = ""

    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: MenuBarIcon.image)
                .renderingMode(.template)
            if settings.showMenuBarPercentage, !dayPercentText.isEmpty {
                Text(dayPercentText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
            }
        }
        .accessibilityLabel(accessibilityText)
        .onAppear(perform: refreshPercentIfNeeded)
        .onReceive(tick) { _ in
            refreshPercentIfNeeded()
        }
        .onChange(of: settings.showMenuBarPercentage) { enabled in
            if enabled {
                refreshPercentIfNeeded()
            } else {
                dayPercentText = ""
            }
        }
    }

    private var accessibilityText: String {
        if settings.showMenuBarPercentage, !dayPercentText.isEmpty {
            return "Wick, \(dayPercentText)"
        }
        return "Wick"
    }

    private func refreshPercentIfNeeded() {
        guard settings.showMenuBarPercentage else {
            if !dayPercentText.isEmpty {
                dayPercentText = ""
            }
            return
        }
        let day = TimeProgressCalculator.dayFractionRemaining()
        let text = day.formatted(.percent.precision(.fractionLength(0)))
        // Only mutate state when the visible string changes — avoids status-item churn.
        if text != dayPercentText {
            dayPercentText = text
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appearanceObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        applyAppearance(AppSettings.shared.appearance)
        AppSettings.shared.applyLaunchAtLoginPreference()

        appearanceObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { _ in
            Task { @MainActor in
                applyAppearance(AppSettings.shared.appearance)
            }
        }

        Task { @MainActor in
            JournalReminderScheduler.shared.configure()
            if AppSettings.shared.checkForUpdatesOnLaunch {
                await UpdateCheckerPresenter.shared.checkInBackgroundIfNeeded()
            }
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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        NotificationCenter.default.post(name: .wickWillFlushJournalDrafts, object: nil)
        JournalStore.shared.flushPendingWrites()
        return .terminateNow
    }
}

@MainActor
private func applyAppearance(_ appearance: AppAppearance) {
    let desired: NSAppearance?
    switch appearance {
    case .light:
        desired = NSAppearance(named: .aqua)
    case .dark:
        desired = NSAppearance(named: .darkAqua)
    case .system:
        desired = nil
    }

    // Avoid redundant assignment (can kick off extra layout / notifications).
    if NSApp.appearance?.name != desired?.name {
        NSApp.appearance = desired
    }
}

/// Lightweight background update probe (no UI spam; settings shows manual check).
@MainActor
final class UpdateCheckerPresenter {
    static let shared = UpdateCheckerPresenter()

    private var lastAutomaticCheck: Date?

    func checkInBackgroundIfNeeded() async {
        if let last = lastAutomaticCheck, Date().timeIntervalSince(last) < 60 * 60 * 12 {
            return
        }
        lastAutomaticCheck = Date()
        let result = await UpdateChecker.check()
        if case .updateAvailable(let version, let url) = result.kind {
            AppSettings.shared.lastKnownRemoteVersion = version
            AppSettings.shared.lastKnownRemoteURL = url.absoluteString
        }
    }
}
