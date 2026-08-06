import Combine
import Foundation

public enum JournalSyncError: Error, Equatable {
    /// Remote manifest declares a format newer than this app understands.
    case unsupportedRemoteFormat(Int)
    /// Active journal changed mid-cycle; abort quietly and start over.
    case journalSwitched
}

/// Two-way journal synchronizer. The local store stays the source of truth;
/// the engine reconciles it against the remote file set day by day.
///
/// Reconciliation matrix per day key (local vs remote, compared against the
/// per-device `JournalSyncState` snapshot):
/// - only local changed → conditional upload (rev-guarded)
/// - only remote changed → download + apply
/// - both changed → item-union merge; same-item conflicts keep the newer side
///   and archive the loser under `conflicts/` (nothing is ever silently dropped)
/// - local deleted → write tombstone, then delete the remote day file
/// - remote tombstone → delete locally (unless locally edited: edit wins)
/// - remote file missing without a tombstone → accident; re-upload, never mirror
///
/// The single-writer assumption makes conflicts rare; every conflict path still
/// preserves both sides.
@MainActor
public final class JournalSyncEngine: ObservableObject {
    public enum Status: Equatable {
        case idle
        case syncing
        case needsAuth
        /// Transient network failure — retries on the next cycle.
        case offline
        case error(String)
    }

    @Published public private(set) var status: Status = .idle
    @Published public private(set) var lastSyncAt: Date?
    @Published public private(set) var pendingConflicts: [SyncConflictRecord] = []
    /// Manifests of journals found on the remote that are not the active
    /// journal — candidates for adoption on this device.
    @Published public private(set) var discoveredJournals: [JournalSyncManifest] = []

    private let backend: any JournalSyncBackend
    private let localSource: any JournalLocalSource
    private let deviceID: String
    private let stateStore: JournalSyncStateStore

    private var state = JournalSyncState()
    private var stateJournalID: UUID?

    private var isSyncing = false
    private var pendingSync = false
    private var debounceTask: Task<Void, Never>?
    private var timer: Timer?

    public static let periodicInterval: TimeInterval = 60
    public static let debounceInterval: TimeInterval = 15

    public init(
        backend: any JournalSyncBackend,
        localSource: any JournalLocalSource,
        deviceID: String,
        stateStore: JournalSyncStateStore
    ) {
        self.backend = backend
        self.localSource = localSource
        self.deviceID = deviceID
        self.stateStore = stateStore
    }

    // MARK: - Triggers

    public func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.periodicInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncNow()
            }
        }
        syncNow()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        debounceTask?.cancel()
        debounceTask = nil
    }

    /// Coalesced trigger for edit-driven sync (fires 15 s after the last call).
    public func requestSync() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.debounceInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.syncNow()
        }
    }

    public func syncNow() {
        guard !isSyncing else {
            pendingSync = true
            return
        }
        Task { await performSyncCycle() }
    }

    /// Single cycle, awaitable (used before app quit and by tests).
    public func syncOnce() async {
        await performSyncCycle()
    }

    public func dismissConflict(id: UUID) {
        state.pendingConflicts.removeAll { $0.id == id }
        saveAndPublish()
    }

    // MARK: - Sync cycle

    func performSyncCycle() async {
        guard !isSyncing else {
            pendingSync = true
            return
        }
        isSyncing = true
        defer {
            isSyncing = false
            if pendingSync {
                pendingSync = false
                syncNow()
            }
        }

        guard let journalID = localSource.syncJournalID else {
            status = .idle
            return
        }
        if stateJournalID != journalID {
            state = stateStore.load(for: journalID)
            stateJournalID = journalID
            publishFromState()
        }
        guard backend.isAuthorized else {
            status = .needsAuth
            return
        }
        // Read-only store (load failure / newer format): never push from it.
        guard localSource.syncIsWritable else {
            status = .idle
            return
        }

        status = .syncing
        do {
            try await syncCycleBody(journalID: journalID)
            state.lastSyncAt = Date()
            status = .idle
        } catch JournalSyncError.journalSwitched {
            // Not an error — the next cycle re-reads the new journal's state.
            status = .idle
        } catch let error as SyncBackendError {
            handleBackendError(error)
        } catch let error as JournalSyncError {
            status = .error(message(for: error))
        } catch {
            status = .error(error.localizedDescription)
        }
        saveAndPublish()
    }

    private func syncCycleBody(journalID: UUID) async throws {
        // 1. Pull remote deltas into the local remote-view.
        let (metas, newCursor) = try await backend.listChanges(since: state.cursor)
        if state.cursor == nil {
            state.remoteFiles = [:]
        }
        for meta in metas {
            if meta.isDeleted {
                state.remoteFiles.removeValue(forKey: meta.path)
            } else if let rev = meta.rev {
                state.remoteFiles[meta.path] = RemoteFileRecord(rev: rev, contentHash: meta.contentHash)
            }
        }
        state.cursor = newCursor

        // 2. Manifest format gate — refuses to touch newer-format remotes.
        try await ensureManifest(journalID: journalID)

        // 2b. Discovery: collect manifests of OTHER journals on the remote so
        // the app can offer adopting them (best effort, never blocks sync).
        await refreshDiscoveredJournals(currentJournalID: journalID)

        // 3. Reconcile every known day key.
        let snapshots = localSource.syncDaySnapshots()
        var localDays: [String: (entry: JournalEntry, hash: String)] = [:]
        for (key, entry) in snapshots {
            guard let data = try? JournalSyncEncoding.canonicalData(for: entry) else { continue }
            localDays[key] = (entry, JournalSyncEncoding.contentHash(of: data))
        }

        var dayKeys = Set(localDays.keys).union(state.days.keys)
        for path in state.remoteFiles.keys {
            if let key = JournalSyncLayout.dayKey(fromDayPath: path, journalID: journalID) {
                dayKeys.insert(key)
            }
            if let key = tombstoneDayKey(from: path, journalID: journalID) {
                dayKeys.insert(key)
            }
        }

        var firstError: Error?
        for dayKey in dayKeys.sorted() {
            do {
                try await reconcileDay(dayKey, journalID: journalID, localDays: localDays)
            } catch JournalSyncError.journalSwitched {
                throw JournalSyncError.journalSwitched
            } catch {
                if firstError == nil { firstError = error }
                NSLog("Wick sync: day \(dayKey) failed: \(error.localizedDescription)")
            }
        }

        // 4. Images (after days so references from applied entries resolve).
        do {
            try await reconcileImages(journalID: journalID)
        } catch {
            if firstError == nil { firstError = error }
            NSLog("Wick sync: images failed: \(error.localizedDescription)")
        }

        // 5. Garbage-collect ancient tombstones (best effort).
        await collectGarbageTombstones(journalID: journalID)

        if let firstError {
            throw firstError
        }
    }

    // MARK: - Day reconciliation

    private func reconcileDay(
        _ dayKey: String,
        journalID: UUID,
        localDays: [String: (entry: JournalEntry, hash: String)]
    ) async throws {
        let dayPath = JournalSyncLayout.dayPath(for: journalID, dayKey: dayKey)
        let tombPath = JournalSyncLayout.tombstonePath(for: journalID, dayKey: dayKey)
        let local = localDays[dayKey]
        let prev = state.days[dayKey]
        let remoteFile = state.remoteFiles[dayPath]
        let remoteTomb = state.remoteFiles[tombPath]

        let localChanged = local != nil && local!.hash != prev?.localHash
        let localDeleted = local == nil && prev?.localHash != nil
        let remoteChanged: Bool = {
            guard let remoteFile else { return false }
            if let hash = remoteFile.contentHash {
                return hash != prev?.remoteContentHash
            }
            return remoteFile.rev != prev?.remoteRev
        }()
        let hasNewTombstone = remoteTomb != nil && remoteTomb?.rev != prev?.tombstoneRev

        // Remote tombstone: the only authoritative delete signal.
        if let remoteTomb, hasNewTombstone {
            let tombstone = try await downloadTombstone(path: tombPath)
            if let local, localChanged {
                // Delete vs edit: the actively edited side wins and the
                // tombstone is cleared (resolution is recorded as a conflict).
                try await pushDay(local, journalID: journalID, currentRemoteRev: remoteFile?.rev)
                try await backend.delete(path: tombPath)
                state.remoteFiles.removeValue(forKey: tombPath)
                recordConflict(
                    dayKey: dayKey,
                    summary: "delete-vs-edit",
                    remotePath: ""
                )
                return
            }
            if local != nil {
                try requireJournal(journalID)
                localSource.removeSyncedDay(dayKey: dayKey)
            }
            // Clean up a day file that outlived its tombstone (crash between writes).
            if remoteFile != nil {
                try await backend.delete(path: dayPath)
                state.remoteFiles.removeValue(forKey: dayPath)
            }
            state.days[dayKey] = DaySyncState(
                tombstoneRev: remoteTomb.rev,
                tombstoneDeletedAt: tombstone.deletedAt
            )
            return
        }

        // Local delete propagates: tombstone first, then the file delete.
        if localDeleted, remoteFile != nil, !remoteChanged {
            let tombstone = JournalTombstone(dayKey: dayKey, deletedAt: Date(), deviceID: deviceID)
            let data = try JournalSyncEncoding.encoder.encode(tombstone)
            let tombRev = try await backend.upload(path: tombPath, data: data, ifRev: nil)
            state.remoteFiles[tombPath] = RemoteFileRecord(
                rev: tombRev,
                contentHash: JournalSyncEncoding.contentHash(of: data)
            )
            try await backend.delete(path: dayPath)
            state.remoteFiles.removeValue(forKey: dayPath)
            state.days[dayKey] = DaySyncState(
                tombstoneRev: tombRev,
                tombstoneDeletedAt: tombstone.deletedAt
            )
            return
        }

        // Delete vs remote edit: remote wins, the day resurrects locally.
        if localDeleted, remoteChanged, let remoteFile {
            try await pullDay(remoteFile: remoteFile, dayPath: dayPath, dayKey: dayKey, journalID: journalID)
            recordConflict(
                dayKey: dayKey,
                summary: "deletion overridden by remote edit",
                remotePath: dayPath
            )
            return
        }

        // Remote day vanished without a tombstone: accident — heal by re-upload.
        if remoteFile == nil, prev?.remoteRev != nil, let local {
            try await pushDay(local, journalID: journalID, currentRemoteRev: nil)
            return
        }

        // Both changed: item-union merge.
        if let local, localChanged, remoteChanged {
            try await mergeDay(local: local, dayKey: dayKey, journalID: journalID, dayPath: dayPath)
            return
        }

        // Only remote changed (incl. brand-new remote day): pull.
        if let remoteFile, remoteChanged, !localChanged {
            try await pullDay(remoteFile: remoteFile, dayPath: dayPath, dayKey: dayKey, journalID: journalID)
            return
        }

        // Only local changed (incl. brand-new local day): push.
        if let local, localChanged {
            try await pushDay(local, journalID: journalID, currentRemoteRev: remoteFile?.rev)
            return
        }

        // Nothing left anywhere: prune stale bookkeeping.
        if local == nil, remoteFile == nil, prev?.tombstoneRev == nil {
            state.days.removeValue(forKey: dayKey)
        }
    }

    // MARK: - Day operations

    private func pushDay(
        _ local: (entry: JournalEntry, hash: String),
        journalID: UUID,
        currentRemoteRev: String?
    ) async throws {
        let dayKey = local.entry.dayKey
        let dayPath = JournalSyncLayout.dayPath(for: journalID, dayKey: dayKey)
        let data = try JournalSyncEncoding.canonicalData(for: local.entry)
        do {
            let rev = try await backend.upload(path: dayPath, data: data, ifRev: currentRemoteRev)
            state.remoteFiles[dayPath] = RemoteFileRecord(rev: rev, contentHash: local.hash)
            state.days[dayKey] = DaySyncState(
                localHash: local.hash,
                remoteRev: rev,
                remoteContentHash: local.hash
            )
        } catch SyncBackendError.writeConflict {
            // Lost the race against another device: merge with the winner.
            try await mergeDay(local: local, dayKey: dayKey, journalID: journalID, dayPath: dayPath)
        }
    }

    private func pullDay(
        remoteFile: RemoteFileRecord,
        dayPath: String,
        dayKey: String,
        journalID: UUID
    ) async throws {
        let (data, rev) = try await backend.download(path: dayPath)
        let entry = try JournalSyncEncoding.decoder.decode(JournalEntry.self, from: data)
        try requireJournal(journalID)
        localSource.applySyncedEntry(entry)
        let hash = remoteFile.contentHash ?? JournalSyncEncoding.contentHash(of: data)
        state.days[dayKey] = DaySyncState(localHash: hash, remoteRev: rev, remoteContentHash: hash)
    }

    private func mergeDay(
        local: (entry: JournalEntry, hash: String),
        dayKey: String,
        journalID: UUID,
        dayPath: String
    ) async throws {
        let (remoteData, remoteRev) = try await backend.download(path: dayPath)
        let remoteEntry = try JournalSyncEncoding.decoder.decode(JournalEntry.self, from: remoteData)
        let remoteHash = JournalSyncEncoding.contentHash(of: remoteData)

        let result = JournalDayMerge.merge(local: local.entry, remote: remoteEntry)
        let mergedData = try JournalSyncEncoding.canonicalData(for: result.merged)
        let mergedHash = JournalSyncEncoding.contentHash(of: mergedData)

        if mergedHash == local.hash, mergedHash == remoteHash {
            // Identical already (bookkeeping drifted) — align state only.
            state.remoteFiles[dayPath] = RemoteFileRecord(rev: remoteRev, contentHash: remoteHash)
            state.days[dayKey] = DaySyncState(
                localHash: local.hash,
                remoteRev: remoteRev,
                remoteContentHash: remoteHash
            )
            return
        }

        // Archive the losing side before overwriting anything.
        if !result.losingItems.isEmpty || result.losingTitle != nil {
            try await archiveConflict(result: result, dayKey: dayKey, journalID: journalID)
        }

        if mergedHash != remoteHash {
            let newRev = try await backend.upload(path: dayPath, data: mergedData, ifRev: remoteRev)
            state.remoteFiles[dayPath] = RemoteFileRecord(rev: newRev, contentHash: mergedHash)
            state.days[dayKey] = DaySyncState(
                localHash: mergedHash,
                remoteRev: newRev,
                remoteContentHash: mergedHash
            )
        } else {
            // Remote already holds the merged result.
            state.remoteFiles[dayPath] = RemoteFileRecord(rev: remoteRev, contentHash: mergedHash)
            state.days[dayKey] = DaySyncState(
                localHash: mergedHash,
                remoteRev: remoteRev,
                remoteContentHash: mergedHash
            )
        }

        if mergedHash != local.hash {
            try requireJournal(journalID)
            localSource.applySyncedEntry(result.merged)
        }
    }

    private func archiveConflict(
        result: JournalDayMergeResult,
        dayKey: String,
        journalID: UUID
    ) async throws {
        let now = Date()
        let payload = JournalConflictPayload(
            dayKey: dayKey,
            detectedAt: now,
            deviceID: deviceID,
            reason: "item-content-conflict",
            losingItems: result.losingItems,
            losingTitle: result.losingTitle
        )
        let data = try JournalSyncEncoding.encoder.encode(payload)
        let path = JournalSyncLayout.conflictPath(for: journalID, dayKey: dayKey, stamp: now)
        _ = try await backend.upload(path: path, data: data, ifRev: nil)
        recordConflict(dayKey: dayKey, summary: "item-content-conflict", remotePath: path)
    }

    private func recordConflict(dayKey: String, summary: String, remotePath: String) {
        state.pendingConflicts.append(
            SyncConflictRecord(
                dayKey: dayKey,
                remotePath: remotePath,
                summary: summary,
                detectedAt: Date()
            )
        )
    }

    // MARK: - Images

    private func reconcileImages(journalID: UUID) async throws {
        let referenced = localSource.syncedImageFilenames().sorted()

        // Upload referenced images the remote does not have.
        for filename in referenced {
            let path = JournalSyncLayout.imagePath(for: journalID, filename: filename)
            guard state.remoteFiles[path.lowercased()] == nil else { continue }
            guard let data = localSource.syncedImageData(filename: filename) else { continue }
            do {
                let rev = try await backend.upload(path: path, data: data, ifRev: nil)
                state.remoteFiles[path.lowercased()] = RemoteFileRecord(
                    rev: rev,
                    contentHash: JournalSyncEncoding.contentHash(of: data)
                )
            } catch SyncBackendError.writeConflict {
                // Same content-addressed file uploaded concurrently — the next
                // delta listing picks up its record.
            }
        }

        // Download referenced images missing locally (e.g. from applied entries).
        for filename in referenced where !localSource.hasSyncedImage(filename: filename) {
            let path = JournalSyncLayout.imagePath(for: journalID, filename: filename)
            guard state.remoteFiles[path.lowercased()] != nil else { continue }
            if let (data, _) = try? await backend.download(path: path) {
                try requireJournal(journalID)
                localSource.storeSyncedImage(filename: filename, data: data)
            }
        }
    }

    // MARK: - Manifest / tombstones

    private func ensureManifest(journalID: UUID) async throws {
        let path = JournalSyncLayout.manifestPath(for: journalID)
        if let meta = state.remoteFiles[path] {
            guard meta.rev != state.manifestRev else { return }
            let (data, _) = try await backend.download(path: path)
            let manifest = try JournalSyncEncoding.decoder.decode(JournalSyncManifest.self, from: data)
            guard manifest.formatVersion <= JournalSyncLayout.formatVersion else {
                throw JournalSyncError.unsupportedRemoteFormat(manifest.formatVersion)
            }
            state.manifestRev = meta.rev
            return
        }

        // First device to sync creates the manifest; a create race is harmless.
        let manifest = JournalSyncManifest(
            formatVersion: JournalSyncLayout.formatVersion,
            journalID: journalID,
            journalName: localSource.syncJournalName,
            createdAt: Date(),
            deviceID: deviceID
        )
        let data = try JournalSyncEncoding.encoder.encode(manifest)
        if let rev = try? await backend.upload(path: path, data: data, ifRev: nil) {
            state.remoteFiles[path] = RemoteFileRecord(
                rev: rev,
                contentHash: JournalSyncEncoding.contentHash(of: data)
            )
            state.manifestRev = rev
        }
    }

    private func downloadTombstone(path: String) async throws -> JournalTombstone {
        let (data, _) = try await backend.download(path: path)
        return try JournalSyncEncoding.decoder.decode(JournalTombstone.self, from: data)
    }

    // MARK: - Journal discovery

    /// Scans the remote view for manifests of journals other than the active
    /// one and caches them in state. Each manifest is downloaded once per rev.
    private func refreshDiscoveredJournals(currentJournalID: UUID) async {
        for path in state.remoteFiles.keys.sorted() {
            guard let manifestJournalID = Self.manifestJournalID(from: path),
                  manifestJournalID != currentJournalID,
                  let meta = state.remoteFiles[path]
            else { continue }

            let key = manifestJournalID.uuidString.lowercased()
            guard state.discoveredJournals[key]?.manifestRev != meta.rev else { continue }

            guard let (data, _) = try? await backend.download(path: path),
                  let manifest = try? JournalSyncEncoding.decoder.decode(JournalSyncManifest.self, from: data),
                  manifest.journalID == manifestJournalID,
                  manifest.formatVersion <= JournalSyncLayout.formatVersion
            else { continue }

            state.discoveredJournals[key] = DiscoveredJournalRecord(
                manifest: manifest,
                manifestRev: meta.rev
            )
        }
    }

    /// Parses `/journals/<uuid>/manifest.json` (nothing else matches).
    private static func manifestJournalID(from path: String) -> UUID? {
        let prefix = "/journals/"
        let suffix = "/manifest.json"
        guard path.hasPrefix(prefix), path.hasSuffix(suffix) else { return nil }
        let middle = path.dropFirst(prefix.count).dropLast(suffix.count)
        guard !middle.contains("/") else { return nil }
        return UUID(uuidString: String(middle))
    }

    private func tombstoneDayKey(from path: String, journalID: UUID) -> String? {
        let prefix = "\(JournalSyncLayout.journalRoot(for: journalID))/tombstones/"
        guard path.hasPrefix(prefix), path.hasSuffix(".json") else { return nil }
        let key = path.dropFirst(prefix.count).dropLast(".json".count)
        return key.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
            ? String(key)
            : nil
    }

    private func collectGarbageTombstones(journalID: UUID) async {
        let now = Date()
        for (dayKey, dayState) in state.days {
            guard let deletedAt = dayState.tombstoneDeletedAt,
                  now.timeIntervalSince(deletedAt) > JournalSyncLayout.tombstoneRetention
            else { continue }
            let tombPath = JournalSyncLayout.tombstonePath(for: journalID, dayKey: dayKey)
            if state.remoteFiles[tombPath] != nil {
                try? await backend.delete(path: tombPath)
                state.remoteFiles.removeValue(forKey: tombPath)
            }
            if dayState.localHash == nil, dayState.remoteRev == nil {
                state.days.removeValue(forKey: dayKey)
            } else {
                state.days[dayKey]?.tombstoneRev = nil
                state.days[dayKey]?.tombstoneDeletedAt = nil
            }
        }
    }

    // MARK: - Housekeeping

    private func requireJournal(_ journalID: UUID) throws {
        guard localSource.syncJournalID == journalID else {
            throw JournalSyncError.journalSwitched
        }
    }

    private func handleBackendError(_ error: SyncBackendError) {
        switch error {
        case .needsAuth:
            status = .needsAuth
        case .cursorExpired:
            // Re-list from scratch on the next cycle.
            state.cursor = nil
            state.remoteFiles = [:]
            status = .idle
            requestSync()
        case .transport, .rateLimited:
            status = .offline
        case .server(let code, let message):
            status = .error("Dropbox \(code): \(message)")
        default:
            status = .error(error.localizedDescription)
        }
    }

    private func message(for error: JournalSyncError) -> String {
        switch error {
        case .unsupportedRemoteFormat(let version):
            return "remote format v\(version) is newer than this app supports"
        case .journalSwitched:
            return "journal switched"
        }
    }

    private func publishFromState() {
        lastSyncAt = state.lastSyncAt
        pendingConflicts = state.pendingConflicts
        discoveredJournals = state.discoveredJournals.values
            .map(\.manifest)
            .filter { $0.journalID != stateJournalID }
            .sorted { $0.journalName.localizedCaseInsensitiveCompare($1.journalName) == .orderedAscending }
    }

    private func saveAndPublish() {
        guard let stateJournalID else { return }
        stateStore.save(state, for: stateJournalID)
        publishFromState()
    }
}
