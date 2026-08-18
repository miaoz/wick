import AuthenticationServices
import Combine
import UIKit
import WickSync

/// iOS counterpart of the macOS SyncCoordinator: owns the Dropbox backend +
/// sync engine, mirrors edit-driven/foreground triggers, auto-imports journals
/// discovered on the remote, and runs the browser sign-in flow.
@MainActor
final class PhoneSyncCoordinator: ObservableObject {
    static let shared = PhoneSyncCoordinator()

    let backend: DropboxSyncBackend
    let engine: JournalSyncEngine

    @Published private(set) var syncEnabled: Bool
    @Published private(set) var accountEmail: String
    @Published private(set) var lastAuthError: String?

    private static let enabledKey = "wick.sync.enabled"
    private static let emailKey = "wick.sync.accountEmail"
    private static let deviceIDKey = "wick.deviceID"
    private static let ignoredJournalsKey = "wick.sync.ignoredRemoteJournals"
    private static let remotelyDeletedJournalsKey = "wick.sync.remotelyDeletedJournals"

    private let deviceID: String
    private let stateStore: JournalSyncStateStore
    private var ignoredRemoteJournalIDs: Set<UUID>
    /// Journals whose remote deletion (peer tombstone) this device applied -
    /// keeps remote deletions from being re-queued as local ones.
    private var remotelyDeletedJournalIDs: Set<UUID>
    private var knownLocalJournalIDs: Set<UUID>
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let defaults = UserDefaults.standard
        syncEnabled = defaults.bool(forKey: Self.enabledKey)
        accountEmail = defaults.string(forKey: Self.emailKey) ?? ""
        if let existing = defaults.string(forKey: Self.deviceIDKey) {
            deviceID = existing
        } else {
            let fresh = UUID().uuidString
            defaults.set(fresh, forKey: Self.deviceIDKey)
            deviceID = fresh
        }
        ignoredRemoteJournalIDs = Set(
            (defaults.stringArray(forKey: Self.ignoredJournalsKey) ?? []).compactMap(UUID.init)
        )
        remotelyDeletedJournalIDs = Set(
            (defaults.stringArray(forKey: Self.remotelyDeletedJournalsKey) ?? []).compactMap(UUID.init)
        )
        knownLocalJournalIDs = Set(PhoneJournalStore.shared.journals.map(\.id))

        let backend = DropboxSyncBackend()
        backend.authSession = { url, scheme in
            try await PhoneAuthSession.open(url: url, callbackScheme: scheme)
        }
        self.backend = backend
        let stateStore = JournalSyncStateStore(directory: Self.stateDirectory())
        self.stateStore = stateStore
        engine = JournalSyncEngine(
            backend: backend,
            localSource: PhoneJournalStore.shared,
            deviceID: deviceID,
            stateStore: stateStore
        )

        engine.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Edit-driven sync; the engine coalesces these (15 s debounce).
        PhoneJournalStore.shared.$entries
            .dropFirst()
            .sink { [weak self] _ in self?.engine.requestSync() }
            .store(in: &cancellables)

        engine.$discoveredJournals
            .sink { [weak self] in self?.autoImportRemoteJournals($0) }
            .store(in: &cancellables)

        // Journals deleted on another device (tombstone on the remote): drop
        // the local copy and acknowledge.
        engine.$remoteJournalDeletions
            .sink { [weak self] in self?.applyRemoteJournalDeletions($0) }
            .store(in: &cancellables)

        // Journal switches re-point the engine (it syncs the active journal).
        PhoneJournalStore.shared.$activeJournalID
            .dropFirst()
            .sink { [weak self] _ in self?.engine.syncNow() }
            .store(in: &cancellables)

        PhoneJournalStore.shared.$journals
            .sink { [weak self] in
                self?.trackLocalJournalDeletions($0)
                // Renames ride the next sync cycle (debounced; no-op otherwise).
                self?.engine.requestSync()
            }
            .store(in: &cancellables)

        queueLegacyLocalDeletions()

        if syncEnabled {
            engine.start()
        }
    }

    // MARK: - Connect / disconnect

    func connectDropbox() async {
        lastAuthError = nil
        do {
            let email = try await backend.authorize()
            accountEmail = email
            UserDefaults.standard.set(email, forKey: Self.emailKey)
            syncEnabled = true
            UserDefaults.standard.set(true, forKey: Self.enabledKey)
            engine.start()
            engine.syncNow()
        } catch SyncBackendError.authorizationCancelled {
            // User dismissed the browser — nothing to report.
        } catch {
            lastAuthError = error.localizedDescription
        }
    }

    func disconnectDropbox() {
        engine.stop()
        backend.signOut()
        syncEnabled = false
        accountEmail = ""
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        UserDefaults.standard.set("", forKey: Self.emailKey)
    }

    func adoptRemoteJournal(_ manifest: JournalSyncManifest) {
        guard !engine.isJournalTombstoned(manifest.journalID) else { return }
        ignoredRemoteJournalIDs.remove(manifest.journalID)
        persistIgnoredJournals()
        engine.resetSyncState(for: manifest.journalID)
        _ = PhoneJournalStore.shared.registerRemoteJournal(
            id: manifest.journalID,
            name: manifest.journalName
        )
        engine.syncNow()
    }

    // MARK: - Auto-import

    private func autoImportRemoteJournals(_ manifests: [JournalSyncManifest]) {
        guard syncEnabled, backend.isAuthorized else { return }
        let store = PhoneJournalStore.shared
        for manifest in manifests {
            guard !ignoredRemoteJournalIDs.contains(manifest.journalID),
                  !store.journals.contains(where: { $0.id == manifest.journalID })
            else { continue }
            engine.resetSyncState(for: manifest.journalID)
            _ = store.registerRemoteJournal(id: manifest.journalID, name: manifest.journalName)
        }
    }

    private func trackLocalJournalDeletions(_ infos: [JournalInfo]) {
        let current = Set(infos.map(\.id))
        let removed = knownLocalJournalIDs.subtracting(current)
        if !removed.isEmpty {
            ignoredRemoteJournalIDs.formUnion(removed)
            persistIgnoredJournals()
            // Local deletions propagate to the remote - except journals
            // removed BECAUSE a peer tombstoned them.
            if syncEnabled, backend.isAuthorized {
                for id in removed where !remotelyDeletedJournalIDs.contains(id) {
                    engine.queueJournalDeletion(id)
                }
            }
        }
        knownLocalJournalIDs = current
    }

    /// Applies journal deletions made on another device: record the UUID,
    /// drop the local copy (if any), and acknowledge.
    private func applyRemoteJournalDeletions(_ journalIDs: [UUID]) {
        var applied = false
        for id in journalIDs where !remotelyDeletedJournalIDs.contains(id) {
            remotelyDeletedJournalIDs.insert(id)
            ignoredRemoteJournalIDs.insert(id)
            applied = true
            if PhoneJournalStore.shared.journals.contains(where: { $0.id == id }) {
                PhoneJournalStore.shared.deleteJournal(id: id)
            }
        }
        if applied {
            persistIgnoredJournals()
            UserDefaults.standard.set(
                remotelyDeletedJournalIDs.map(\.uuidString),
                forKey: Self.remotelyDeletedJournalsKey
            )
        }
        for id in journalIDs { engine.acknowledgeRemoteJournalDeletion(id) }
    }

    /// Journals deleted locally before deletion propagation existed keep
    /// resurfacing as "discovered"; queue the ones with sync-state remnants.
    private func queueLegacyLocalDeletions() {
        guard syncEnabled, backend.isAuthorized else { return }
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

    private static func stateDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Wick/SyncState", isDirectory: true)
    }
}

/// Presents the Dropbox sign-in page via ASWebAuthenticationSession and
/// resolves with the callback URL (the app registers the `db-…` scheme).
@MainActor
enum PhoneAuthSession {
    private static var currentSession: ASWebAuthenticationSession?

    static func open(url: URL, callbackScheme: String) async throws -> URL {
        defer { currentSession = nil }
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme,
                completionHandler: makeCompletionHandler(continuation: continuation)
            )
            session.presentationContextProvider = AnchorProvider.shared
            session.prefersEphemeralWebBrowserSession = false
            currentSession = session
            session.start()
        }
    }

    /// The completion handler is invoked synchronously off the main queue;
    /// creating it in a nonisolated factory avoids an actor-isolation trap.
    private nonisolated static func makeCompletionHandler(
        continuation: CheckedContinuation<URL, Error>
    ) -> (URL?, Error?) -> Void {
        { callbackURL, error in
            if let callbackURL {
                continuation.resume(returning: callbackURL)
            } else if let authError = error as? ASWebAuthenticationSessionError,
                      authError.code == .canceledLogin {
                continuation.resume(throwing: SyncBackendError.authorizationCancelled)
            } else {
                continuation.resume(
                    throwing: error ?? SyncBackendError.server(status: 0, message: "auth session failed")
                )
            }
        }
    }

    private final class AnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
        static let shared = AnchorProvider()

        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            let scenes = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
            let keyWindow = scenes
                .first { $0.activationState == .foregroundActive }?
                .windows.first { $0.isKeyWindow }
            return keyWindow ?? scenes.flatMap(\.windows).first ?? UIWindow()
        }
    }
}
