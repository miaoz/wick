import AppKit
import Combine
import Foundation
import WickSync

/// Owns the sync engine + Dropbox backend and wires them to app lifecycle:
/// starts at launch when enabled, follows journal switches, debounces edit-driven
/// syncs, and runs one bounded final sync before quit.
///
/// The engine is created eagerly against `JournalStore.shared`; `start()` only
/// schedules cycles, so constructing this is cheap and side-effect free until
/// `wick.sync.enabled` is on.
@MainActor
final class SyncCoordinator: ObservableObject {
    static let shared = SyncCoordinator()

    let backend: DropboxSyncBackend
    let engine: JournalSyncEngine

    @Published private(set) var isRunning = false
    @Published private(set) var lastAuthError: String?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        let backend = DropboxSyncBackend()
        backend.authSession = { url, scheme in
            try await DropboxAuthSession.open(url: url, callbackScheme: scheme)
        }
        self.backend = backend
        engine = JournalSyncEngine(
            backend: backend,
            localSource: JournalStore.shared,
            deviceID: AppSettings.shared.deviceID,
            stateStore: JournalSyncStateStore(directory: Self.stateDirectory())
        )

        // Forward engine state to SwiftUI observers of the coordinator.
        engine.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Edit-driven sync: engine coalesces these into one cycle 15 s after
        // the last change. Remote applies retrigger harmlessly (hash no-op).
        JournalStore.shared.$entries
            .dropFirst()
            .sink { [weak self] _ in self?.engine.requestSync() }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: .wickActiveJournalDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.engine.syncNow() }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.engine.requestSync() }
        }

        if AppSettings.shared.syncEnabled {
            startIfPossible()
        }
    }

    // MARK: - Lifecycle

    func startIfPossible() {
        guard AppSettings.shared.syncEnabled, !isRunning else { return }
        engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.stop()
        isRunning = false
    }

    /// Interactive connect: browser sign-in, then enable + start on success.
    func connectDropbox() async {
        lastAuthError = nil
        do {
            let email = try await backend.authorize()
            AppSettings.shared.syncAccountEmail = email
            AppSettings.shared.syncEnabled = true
            startIfPossible()
            engine.syncNow()
        } catch SyncBackendError.authorizationCancelled {
            // User dismissed the browser — nothing to report.
        } catch {
            lastAuthError = error.localizedDescription
        }
    }

    /// Disconnect keeps all data (local and remote); it only stops syncing.
    func disconnectDropbox() {
        stop()
        backend.signOut()
        AppSettings.shared.syncEnabled = false
        AppSettings.shared.syncAccountEmail = ""
    }

    /// Adopts a journal discovered on the remote (registering it locally under
    /// the same id) and immediately pulls its contents.
    func adoptRemoteJournal(_ manifest: JournalSyncManifest) {
        _ = JournalStore.shared.adoptRemoteJournal(id: manifest.journalID, name: manifest.journalName)
        engine.syncNow()
    }

    // MARK: - Quit

    var needsFinalSync: Bool {
        isRunning && backend.isAuthorized
    }

    /// One last cycle, bounded so quitting never hangs on a dead network.
    func finalSyncBeforeQuit() async {
        guard needsFinalSync else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [engine] in
                await engine.syncOnce()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
            await group.next()
            group.cancelAll()
        }
    }

    private static func stateDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("Wick/SyncState", isDirectory: true)
    }
}
