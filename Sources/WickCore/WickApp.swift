import AppKit
import Combine
import SwiftUI

public struct WickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var journalStore = JournalStore.shared

    public init() {}

    @ViewBuilder
    private var menuBarPanelRoot: some View {
        if #available(macOS 14, *) {
            ProgressPanelView()
                .environmentObject(settings)
                .environmentObject(journalStore)
                .preferredColorScheme(settings.preferredColorScheme)
        } else {
            MenuBarExtraContentHost {
                ProgressPanelView()
            }
            .environmentObject(settings)
            .environmentObject(journalStore)
            .preferredColorScheme(settings.preferredColorScheme)
        }
    }

    public var body: some Scene {
        MenuBarExtra {
            // macOS 13 lays MenuBarExtra `.window` SwiftUI out against a
            // placeholder panel frame; Text origins from that pass stick.
            // Route through our own host so the first in-window layout of
            // the panel already sees the live bounds (no-op wrapper on 14+).
            menuBarPanelRoot
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

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: MenuBarIcon.image)
                .renderingMode(.template)
            if settings.showMenuBarPercentage, !dayPercentText.isEmpty {
                Text(dayPercentText)
                    .font(AppFont.ui(11, weight: .semibold, design: .rounded, monospacedDigit: true))
            }
        }
        .accessibilityLabel(accessibilityText)
        .onAppear(perform: refreshPercentIfNeeded)
        // Combine's Timer publisher can outlive the macOS 26 MenuBarExtra
        // label host. Its next delivery then reaches a released SwiftUI
        // subscription and crashes in `swift_task_isMainExecutor`. A
        // view-scoped task is cancelled with the label instead.
        .task(id: settings.showMenuBarPercentage) {
            guard settings.showMenuBarPercentage else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                refreshPercentIfNeeded()
            }
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
        // Default to menu-bar-only presence. Skip if the journal is already
        // (or is about to be) fronted — e.g. launched by a notification tap —
        // so we do not race `openJournal`'s `.regular` promotion.
        if !JournalWindowController.shared.hasOpenJournalWindow {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
        applyAppearance(AppSettings.shared.appearance)
        AppSettings.shared.applyLaunchAtLoginPreference()

        #if DEBUG
        // `-wick-open-journal` fronts the journal window at launch (UI checks).
        if ProcessInfo.processInfo.arguments.contains("-wick-open-journal") {
            Task { @MainActor in
                JournalWindowController.shared.openJournal()
            }
        }
        // `-wick-screenshot-journal <path>` opens the journal and writes a PNG
        // snapshot (including window chrome) after it settles, for headless UI
        // checks. Capturing one's own window needs no Screen Recording consent.
        // Sync is skipped so a fresh build never blocks on a Keychain prompt.
        let screenshotPath: String? = {
            guard let flagIndex = ProcessInfo.processInfo.arguments.firstIndex(of: "-wick-screenshot-journal"),
                  ProcessInfo.processInfo.arguments.indices.contains(flagIndex + 1)
            else { return nil }
            ExchangePositionCoordinator.skipKeychainAccess = true
            return ProcessInfo.processInfo.arguments[flagIndex + 1]
        }()
        if let screenshotPath {
            Task { @MainActor in
                JournalWindowController.shared.openJournal()
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    JournalWindowController.shared.snapshotWindowToPNG(path: screenshotPath)
                }
            }
        }
        #endif

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
            // Constructing the coordinator starts the sync engine when enabled.
            // Screenshot mode stays fully offline (and Keychain-free).
            #if DEBUG
            let screenshotMode = ExchangePositionCoordinator.skipKeychainAccess
            #else
            let screenshotMode = false
            #endif
            if !screenshotMode {
                _ = SyncCoordinator.shared
                ExchangePositionCoordinator.shared.start()
            }
            JournalReminderScheduler.shared.configure()
            UpdateCheckerPresenter.shared.startPeriodicChecks()
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
        let coordinator = SyncCoordinator.shared
        guard coordinator.needsFinalSync else {
            return .terminateNow
        }
        // One bounded final sync so the last keystrokes reach Dropbox too.
        Task { @MainActor in
            await coordinator.finalSyncBeforeQuit()
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
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
