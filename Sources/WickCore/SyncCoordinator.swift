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

    private static let ignoredJournalsKey = "wick.sync.ignoredRemoteJournals"
    private static let remotelyDeletedJournalsKey = "wick.sync.remotelyDeletedJournals"

    private let stateStore: JournalSyncStateStore

    /// Remote journals the user deleted locally - never auto-import these again
    /// (the manual import row in settings remains as the escape hatch).
    private var ignoredRemoteJournalIDs: Set<UUID>
    /// Journals whose remote deletion (peer tombstone) this device has already
    /// applied - distinguishes "a remote deletion arrived" from "the user
    /// deleted a journal locally, propagate it to the remote".
    private var remotelyDeletedJournalIDs: Set<UUID>
    /// Previous local catalog, used to detect deletions.
    private var knownLocalJournalIDs: Set<UUID>

    private var cancellables = Set<AnyCancellable>()

    private init() {
        let backend = DropboxSyncBackend()
        backend.authSession = { url, scheme in
            try await DropboxAuthSession.open(url: url, callbackScheme: scheme)
        }
        self.backend = backend
        let stateStore = JournalSyncStateStore(directory: Self.stateDirectory())
        self.stateStore = stateStore
        engine = JournalSyncEngine(
            backend: backend,
            localSource: JournalStore.shared,
            deviceID: AppSettings.shared.deviceID,
            stateStore: stateStore
        )

        ignoredRemoteJournalIDs = Set(
            (UserDefaults.standard.stringArray(forKey: Self.ignoredJournalsKey) ?? [])
                .compactMap(UUID.init)
        )
        remotelyDeletedJournalIDs = Set(
            (UserDefaults.standard.stringArray(forKey: Self.remotelyDeletedJournalsKey) ?? [])
                .compactMap(UUID.init)
        )
        knownLocalJournalIDs = Set(JournalStore.shared.journals.map(\.id))

        // Forward engine state to SwiftUI observers of the coordinator.
        engine.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Auto-import journals discovered on the remote (e.g. created on
        // another device): register them locally under the same id without
        // switching - their content pulls down when the user opens them.
        engine.$discoveredJournals
            .sink { [weak self] in self?.autoImportRemoteJournals($0) }
            .store(in: &cancellables)

        // Journals deleted on another device (tombstone on the remote): drop
        // the local copy and acknowledge, so the deletion converges here too.
        engine.$remoteJournalDeletions
            .sink { [weak self] in self?.applyRemoteJournalDeletions($0) }
            .store(in: &cancellables)

        // Locally deleting a journal must not bring it back via auto-import;
        // it must also propagate to the remote (tombstone + folder cleanup).
        JournalStore.shared.$journals
            .sink { [weak self] in self?.trackLocalJournalDeletions($0) }
            .store(in: &cancellables)

        // Edit-driven sync: engine coalesces these into one cycle 15 s after
        // the last change. Remote applies retrigger harmlessly (hash no-op).
        JournalStore.shared.entriesDidMutate
            .sink { [weak self] in self?.engine.requestSync() }
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

        // Remediation for journals deleted before deletion propagation
        // existed: their folders still sit on Dropbox and every device keeps
        // prompting "discovered journal". Queue the ones this device deleted
        // (they have sync-state remnants); the tombstone then clears the
        // prompt everywhere. Idempotent - cleared entries never re-queue.
        queueLegacyLocalDeletions()

        if AppSettings.shared.syncEnabled {
            startIfPossible()
        }
    }

    // MARK: - Lifecycle

    func startIfPossible() {
        guard AppSettings.shared.syncEnabled, !isRunning else { return }
        engine.start()
        queueLegacyLocalDeletions()
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
    /// the same id) and immediately pulls its contents. Tombstoned journals
    /// are deleted and must never come back this way.
    func adoptRemoteJournal(_ manifest: JournalSyncManifest) {
        guard !engine.isJournalTombstoned(manifest.journalID) else { return }
        ignoredRemoteJournalIDs.remove(manifest.journalID)
        persistIgnoredJournals()
        engine.resetSyncState(for: manifest.journalID)
        _ = JournalStore.shared.adoptRemoteJournal(id: manifest.journalID, name: manifest.journalName)
        engine.syncNow()
    }

    // MARK: - Auto-import

    private func autoImportRemoteJournals(_ manifests: [JournalSyncManifest]) {
        guard AppSettings.shared.syncEnabled, backend.isAuthorized else { return }
        for manifest in manifests {
            guard !ignoredRemoteJournalIDs.contains(manifest.journalID),
                  !JournalStore.shared.journals.contains(where: { $0.id == manifest.journalID })
            else { continue }
            // Reset the baseline first: a stale state file would make the
            // empty local copy look like "deleted everywhere".
            engine.resetSyncState(for: manifest.journalID)
            _ = JournalStore.shared.registerRemoteJournal(
                id: manifest.journalID,
                name: manifest.journalName
            )
            NSLog("Wick sync: auto-imported remote journal \"%@\"", manifest.journalName)
        }
    }

    private func trackLocalJournalDeletions(_ infos: [JournalInfo]) {
        let current = Set(infos.map(\.id))
        let removed = knownLocalJournalIDs.subtracting(current)
        if !removed.isEmpty {
            ignoredRemoteJournalIDs.formUnion(removed)
            persistIgnoredJournals()
            // The deletion propagates to the remote (tombstone + folder
            // cleanup) - except journals removed BECAUSE a peer tombstoned
            // them; those are already gone remotely.
            if AppSettings.shared.syncEnabled, backend.isAuthorized {
                for id in removed where !remotelyDeletedJournalIDs.contains(id) {
                    engine.queueJournalDeletion(id)
                }
            }
        }
        knownLocalJournalIDs = current
    }

    /// Applies journal deletions made on another device: record the UUID,
    /// drop the local copy (if any), and acknowledge so the engine stops
    /// re-publishing the tombstone. Only `deleted`/`notFound` acknowledge; a
    /// read-only or I/O failure leaves the tombstone pending so the next cycle
    /// retries and the user sees the error.
    private func applyRemoteJournalDeletions(_ journalIDs: [UUID]) {
        var acknowledged: [UUID] = []
        var pendingRetry: [UUID] = []
        for id in journalIDs {
            if !JournalStore.shared.journals.contains(where: { $0.id == id }) {
                // Never had it locally (or already applied): just ack.
                remotelyDeletedJournalIDs.insert(id)
                ignoredRemoteJournalIDs.insert(id)
                acknowledged.append(id)
                continue
            }
            // Mark BEFORE the catalog mutation so `$journals` tracking cannot
            // re-queue this peer deletion as a local one.
            remotelyDeletedJournalIDs.insert(id)
            ignoredRemoteJournalIDs.insert(id)
            switch JournalStore.shared.deleteJournalFromRemote(id: id) {
            case .deleted, .notFound:
                acknowledged.append(id)
            case .refusedReadOnly, .ioFailure:
                // Roll back so the next cycle genuinely retries, and keep the
                // tombstone pending (no acknowledge).
                remotelyDeletedJournalIDs.remove(id)
                ignoredRemoteJournalIDs.remove(id)
                pendingRetry.append(id)
            }
        }
        if !acknowledged.isEmpty {
            persistIgnoredJournals()
            UserDefaults.standard.set(
                remotelyDeletedJournalIDs.map(\.uuidString),
                forKey: Self.remotelyDeletedJournalsKey
            )
            for id in acknowledged { engine.acknowledgeRemoteJournalDeletion(id) }
        }
        if !pendingRetry.isEmpty {
            NSLog("Wick sync: remote journal deletions pending retry: %@", pendingRetry.map(\.uuidString))
        }
    }

    /// Journals deleted locally before deletion propagation existed have no
    /// tombstone on the remote, so they resurface as "discovered" forever.
    /// Queue the ones this device has sync-state remnants of; the engine
    /// ignores journals that never had remote presence.
    private func queueLegacyLocalDeletions() {
        guard AppSettings.shared.syncEnabled, backend.isAuthorized else { return }
        for id in ignoredRemoteJournalIDs
        where !remotelyDeletedJournalIDs.contains(id) && stateStore.stateExists(for: id) {
            engine.queueJournalDeletion(id)
        }
    }

    private func persistIgnoredJournals() {
        UserDefaults.standard.set(
            ignoredRemoteJournalIDs.map(\.uuidString),
            forKey: Self.ignoredJournalsKey
        )
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
