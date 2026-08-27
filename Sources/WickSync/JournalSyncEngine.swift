import Combine
import Foundation

public enum JournalSyncError: Error, Equatable {
    /// Remote manifest declares a format newer than this app understands.
    case unsupportedRemoteFormat(Int)
    /// Active journal changed mid-cycle; abort quietly and start over.
    case journalSwitched
    /// Optional trading snapshot uses a newer envelope than this build knows.
    case unsupportedTradingSnapshotFormat(Int)
    /// Entry payload UUID does not match the UUID in its remote path.
    case invalidRemoteEntryIdentity(path: String)
}

/// Two-way journal synchronizer. The local store stays the source of truth;
/// the engine reconciles it against the remote file set entry by entry.
///
/// Reconciliation matrix per entry UUID (local vs remote, compared against the
/// per-device `JournalSyncState` snapshot):
/// - only local changed -> conditional upload (rev-guarded)
/// - only remote changed -> download + apply
/// - both changed -> item-union merge; same-item conflicts keep the newer side
///   and archive the loser under `conflicts/` (nothing is ever silently dropped)
/// - local deleted -> write tombstone, then delete the remote entry file
/// - remote tombstone -> delete locally (unless locally edited: edit wins)
/// - remote file missing without a tombstone -> accident; re-upload, never mirror
///
/// Single-writer seamlessness rests on three invariants:
/// 1. **Echo suppression by rev.** Remote change detection compares revs only.
///    The device's own uploads record the rev the server returned, so the
///    delta echo of a self-write carries the same rev and reads as "unchanged".
///    Locally computed canonical hashes are never compared against backend
///    `content_hash` metadata (different algorithms - they can never match).
/// 2. **Pull is a fixed point.** Applying remote content and re-hashing it
///    locally yields the recorded baseline, so an adopting device never
///    re-pushes what it just pulled.
/// 3. **A device never conflicts with itself.** If the "remote" side of a
///    merge is a version this device previously pushed (a stale echo racing
///    newer local edits, or a peer relaying our content back), the day
///    converges by re-pushing local - no archive, no user-facing conflict.
///    Conflicts surface only on genuine cross-device divergence.
///
/// Applies are also freshness-guarded: remote content is never written over a
/// entry that changed locally after the cycle's snapshot (the next cycle
/// re-decides with fresh data), so mid-cycle typing can never be clobbered.
///
/// Journal renames ride the manifest: a local rename pushes a rev-guarded
/// rewrite, a remote rewrite is adopted locally, and a double rename resolves
/// as last-push-wins (the loser adopts the winner on its next cycle).
@MainActor
public final class JournalSyncEngine: ObservableObject {
    public enum Status: Equatable {
        case idle
        case syncing
        case needsAuth
        /// Transient network failure — retries on the next cycle.
        case offline
        /// Permanent sync failure. The kind drives localized UI copy; `detail`
        /// carries the raw message (server body etc.) for copying/debugging.
        case error(SyncErrorKind, detail: String)
    }

    /// Categorizes a sync failure so views can pick localized copy instead of
    /// matching raw English strings (SY-04).
    public enum SyncErrorKind: Equatable {
        /// Remote content was written by a newer Wick than this app supports.
        case remoteFormatTooNew
        /// A server-level failure with no specific remediation.
        case server
        /// Everything else.
        case other
    }

    @Published public private(set) var status: Status = .idle
    @Published public private(set) var lastSyncAt: Date?
    @Published public private(set) var pendingConflicts: [SyncConflictRecord] = []
    /// Manifests of journals found on the remote that are not the active
    /// journal - candidates for adoption on this device.
    @Published public private(set) var discoveredJournals: [JournalSyncManifest] = []
    /// Journals deleted by a peer (tombstone seen on the remote) that this
    /// device has not applied yet - the app removes them locally and calls
    /// `acknowledgeRemoteJournalDeletion`. Re-published after restarts until
    /// acknowledged, so a crash cannot drop a deletion.
    @Published public private(set) var remoteJournalDeletions: [UUID] = []

    private let backend: any JournalSyncBackend
    private let localSource: any JournalLocalSource
    private let deviceID: String
    private let stateStore: JournalSyncStateStore

    private var state = JournalSyncState()
    private var stateJournalID: UUID?
    /// Device-scoped state (journal deletion propagation), shared by all
    /// journals of this device and persisted outside per-journal files.
    private var deviceState = JournalDeviceSyncState()

    private var isSyncing = false
    private var pendingSync = false
    private var debounceTask: Task<Void, Never>?
    private var timer: Timer?

    public static let periodicInterval: TimeInterval = 60
    public static let debounceInterval: TimeInterval = 15
    /// How many recent own-push hashes to remember per day for the self-merge
    /// guard (a stale echo can trail the newest push by a cycle or two).
    public static let pushedHashHistoryLimit = 5

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
        self.deviceState = stateStore.loadDeviceState()
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
        guard let index = state.pendingConflicts.firstIndex(where: { $0.id == id }) else { return }
        let record = state.pendingConflicts[index]
        // Dismissing means "keep what is already applied" - upload a marker so
        // peers drop their stale reminder for the day too.
        if let merged = record.mergedEntry,
           let hash = try? JournalSyncEncoding.contentHash(for: merged) {
            state.entries[record.entryID, default: EntrySyncState()].settlement = .markSettled(hash)
        }
        queueConflictArchiveCleanup(state.pendingConflicts[index])
        state.pendingConflicts.remove(at: index)
        saveAndPublish()
        requestSync()
    }

    /// How the user settled a recorded conflict.
    public enum SyncConflictResolution {
        /// Restore the pre-merge local version (discards remote-only content).
        case local
        /// Take the remote version as-is (discards local-only content).
        case remote
        /// Keep the already-applied union merge - just clears the notice.
        case merged
    }

    /// Applies the user's choice for a recorded conflict. The choice is
    /// recorded as a one-shot `EntrySettlement` the next cycle executes
    /// authoritatively (bypassing the divergence matrix, so it can never
    /// re-record the conflict it resolves):
    /// - `.local`  -> apply now, push that exact content next cycle;
    /// - `.remote` -> adopt the *live* remote (the recorded snapshot may be
    ///   stale), so "keep Dropbox" follows what is actually on Dropbox;
    /// - `.merged` -> the merge is already in place locally and remotely, so
    ///   the cycle just uploads a settlement marker for peers.
    public func resolveConflict(id: UUID, resolution: SyncConflictResolution) {
        guard let index = state.pendingConflicts.firstIndex(where: { $0.id == id }) else { return }
        let record = state.pendingConflicts[index]

        let writable = stateJournalID != nil
            && localSource.syncJournalID == stateJournalID
            && localSource.syncIsWritable

        var dayState = state.entries[record.entryID] ?? EntrySyncState()
        switch resolution {
        case .local:
            // Keep this device's version: write it now; the next cycle pushes
            // that exact content authoritatively. Only the store write needs a
            // writable source; a read-only store keeps the record so the
            // conflict stays visible.
            guard let chosen = record.localEntry, writable, let journalID = stateJournalID else { return }
            // Flush any in-flight editor draft first (SY-05) so the chosen
            // resolution is not later clobbered by a stale draft the editor
            // still holds for this day.
            localSource.prepareForRemoteApply(entryID: record.entryID)
            localSource.applySyncedEntry(chosen, journalID: journalID)
            if let hash = try? JournalSyncEncoding.contentHash(for: chosen) {
                dayState.settlement = .pushSettled(hash)
            }
        case .remote:
            // Keep what is on Dropbox: the recorded snapshot may be stale, so
            // do not resurrect it locally - the next cycle adopts the live
            // remote, which converges on every device without re-merging.
            dayState.settlement = .adoptRemote
        case .merged:
            // The merge is already applied and on the remote - mark it so
            // peers drop their stale reminders for the day.
            if let merged = record.mergedEntry,
               let hash = try? JournalSyncEncoding.contentHash(for: merged) {
                dayState.settlement = .markSettled(hash)
            }
        }
        state.entries[record.entryID] = dayState

        queueConflictArchiveCleanup(record)
        state.pendingConflicts.remove(at: index)
        saveAndPublish()
        requestSync()
    }

    /// Once the user has settled on one version, the archived losing side is
    /// dead weight - queue its remote deletion (flushed next cycle so an
    /// offline resolution survives relaunches).
    private func queueConflictArchiveCleanup(_ record: SyncConflictRecord) {
        guard !record.remotePath.isEmpty,
              !state.pendingConflictCleanups.contains(record.remotePath)
        else { return }
        state.pendingConflictCleanups.append(record.remotePath)
    }

    private func flushConflictArchiveCleanups() async {
        guard !state.pendingConflictCleanups.isEmpty else { return }
        var remaining: [String] = []
        for path in state.pendingConflictCleanups {
            do {
                try await backend.delete(path: path)
                state.remoteFiles.removeValue(forKey: path)
            } catch {
                remaining.append(path)
            }
        }
        state.pendingConflictCleanups = remaining
    }

    /// Resets a journal's sync baseline. Required before (re-)importing a
    /// journal from the remote: with a stale baseline the empty local copy
    /// would look like "deleted everywhere" and the engine would tombstone
    /// the remote content instead of pulling it.
    public func resetSyncState(for journalID: UUID) {
        if stateJournalID == journalID {
            state = JournalSyncState()
        }
        stateStore.clear(for: journalID)
    }

    /// Queues removal of the optional derived trading file. The request is
    /// persisted device-wide so it survives offline periods and journal switches.
    public func queueTradingSnapshotDeletion(_ journalID: UUID) {
        if !deviceState.pendingTradingSnapshotDeletions.contains(where: { $0.journalID == journalID }) {
            deviceState.pendingTradingSnapshotDeletions.append(
                JournalTradingSnapshotTombstone(journalID: journalID, deviceID: deviceID)
            )
            saveDeviceStateAndPublish()
        }
        syncNow()
    }

    // MARK: - Journal deletion propagation

    /// Queues a journal deleted on this device for remote propagation: the
    /// next cycle uploads a journal tombstone (outside the journal folder)
    /// and then deletes the remote folder, mirroring day-deletion semantics.
    /// Journals without remote presence (never synced, manifest unknown) are
    /// ignored - there is nothing on the remote to delete.
    public func queueJournalDeletion(_ journalID: UUID) {
        guard !deviceState.isTombstoned(journalID) else { return }
        let knownRemotely = stateStore.stateExists(for: journalID)
            || state.remoteFiles[JournalSyncLayout.manifestPath(for: journalID)] != nil
        guard knownRemotely else { return }
        deviceState.pendingJournalDeletions.append(
            JournalDeletionTombstone(journalID: journalID, deletedAt: Date(), deviceID: deviceID)
        )
        saveDeviceStateAndPublish()
        requestSync()
    }

    /// Confirms that a peer-deleted journal has been applied locally (removed
    /// from the store / ignored); the tombstone will not be re-published.
    public func acknowledgeRemoteJournalDeletion(_ journalID: UUID) {
        deviceState.unackedRemoteDeletions.removeAll { $0 == journalID }
        if !deviceState.processedJournalTombstones.contains(journalID) {
            deviceState.processedJournalTombstones.append(journalID)
        }
        saveDeviceStateAndPublish()
    }

    /// Flushes locally-queued journal deletions: tombstone first, then the
    /// folder - the same ordering as day deletions. Runs before any other
    /// cycle work so a deleted journal cannot be resurrected by this cycle.
    private func flushPendingJournalDeletions() async {
        var failedDeletions: [JournalDeletionTombstone] = []
        for marker in deviceState.pendingJournalDeletions {
            do {
                let tombPath = JournalSyncLayout.journalTombstonePath(for: marker.journalID)
                if state.remoteFiles[tombPath] == nil {
                    let data = try JournalSyncEncoding.encoder.encode(marker)
                    do {
                        let rev = try await backend.upload(path: tombPath, data: data, ifRev: nil)
                        state.remoteFiles[tombPath] = RemoteFileRecord(rev: rev, contentHash: nil)
                    } catch SyncBackendError.writeConflict {
                        // Another device tombstoned the same journal first -
                        // the marker being present is all that matters.
                    }
                }
                // Folder delete always runs; a missing folder is success.
                try await backend.delete(path: JournalSyncLayout.journalRoot(for: marker.journalID))
                pruneRemoteFiles(under: JournalSyncLayout.journalRoot(for: marker.journalID))
                state.discoveredJournals.removeValue(forKey: marker.journalID.uuidString.lowercased())
                stateStore.clear(for: marker.journalID)
                deviceState.unackedRemoteDeletions.removeAll { $0 == marker.journalID }
                if !deviceState.processedJournalTombstones.contains(marker.journalID) {
                    deviceState.processedJournalTombstones.append(marker.journalID)
                }
            } catch {
                // Offline/transient - retry next cycle.
                failedDeletions.append(marker)
            }
        }
        deviceState.pendingJournalDeletions = failedDeletions
        saveDeviceStateAndPublish()
    }

    /// Surfaces peer tombstones this device has not processed yet (published
    /// via `remoteJournalDeletions` until the app acknowledges), and cleans
    /// up any journal folder a racing push resurrected after its deletion.
    /// Runs right after the delta listing so it sees this cycle's fresh view.
    private func detectPeerJournalTombstones() async {
        for path in state.remoteFiles.keys {
            guard let id = JournalSyncLayout.journalTombstoneID(from: path),
                  !deviceState.isTombstoned(id)
            else { continue }
            deviceState.unackedRemoteDeletions.append(id)
            state.discoveredJournals.removeValue(forKey: id.uuidString.lowercased())
        }

        // Anti-resurrection: a tombstoned journal's folder must not linger
        // (a racing push could have recreated files after the delete).
        for id in deviceState.processedJournalTombstones + deviceState.unackedRemoteDeletions {
            let root = JournalSyncLayout.journalRoot(for: id)
            guard state.remoteFiles.keys.contains(where: { $0.hasPrefix(root + "/") }) else { continue }
            try? await backend.delete(path: root)
            pruneRemoteFiles(under: root)
        }

        saveDeviceStateAndPublish()
    }

    /// True when the journal must not be synced, discovered, or imported on
    /// this device (its deletion is pending, published, or processed).
    public func isJournalTombstoned(_ journalID: UUID) -> Bool {
        deviceState.isTombstoned(journalID)
    }

    private func pruneRemoteFiles(under root: String) {
        for path in state.remoteFiles.keys where path.hasPrefix(root + "/") {
            state.remoteFiles.removeValue(forKey: path)
        }
    }

    private func saveDeviceStateAndPublish() {
        stateStore.saveDeviceState(deviceState)
        publishFromState()
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
            status = .error(errorKind(for: error), detail: message(for: error))
        } catch {
            status = .error(.other, detail: error.localizedDescription)
        }
        saveAndPublish()
    }

    private func syncCycleBody(journalID: UUID) async throws {
        try requireJournal(journalID)
        // Freeze identity + days before any await. After a network round-trip
        // the user may have switched journals; live `syncJournalName` /
        // `syncEntrySnapshots()` would then describe the NEW journal while
        // `journalID` still names the old one, which is how one journal's
        // remote days get written into another.
        let frozenName = localSource.syncJournalName
        var localEntries: [UUID: (entry: JournalEntry, hash: String)] = [:]
        for (key, entry) in localSource.syncEntrySnapshots() {
            guard let data = try? JournalSyncEncoding.canonicalData(for: entry) else { continue }
            localEntries[key] = (entry, JournalSyncEncoding.contentHash(of: data))
        }

        // 0. Journal deletion propagation (own queue) runs BEFORE any
        // active-journal work, so a deleted journal can never be resurrected
        // by this cycle's manifest/day syncing.
        await flushPendingJournalDeletions()
        await flushPendingTradingSnapshotDeletions()
        if deviceState.isTombstoned(journalID) {
            // The active journal was deleted somewhere (tombstone seen or
            // queued): syncing it would recreate its manifest and days. The
            // app side removes it locally via `remoteJournalDeletions`.
            return
        }

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
        try requireJournal(journalID)

        // 1b. Peer tombstone detection + anti-resurrection, on the fresh view.
        await detectPeerJournalTombstones()
        if deviceState.isTombstoned(journalID) {
            return
        }

        // 0b. Housekeeping: settled conflicts delete their remote archive.
        await flushConflictArchiveCleanups()

        // 2. A v1 remote is replaced from this device's local source of truth.
        // The v2 manifest then fences old clients, which refuse newer formats.
        try await migrateLegacyRemoteIfNeeded(journalID: journalID, localName: frozenName)

        // 2a. Manifest format gate — refuses to touch newer-format remotes.
        try requireJournal(journalID)
        try await ensureManifest(journalID: journalID, localName: frozenName)

        // 2b. Discovery: collect manifests of OTHER journals on the remote so
        // the app can offer adopting them (best effort, never blocks sync).
        await refreshDiscoveredJournals(currentJournalID: journalID)

        try requireJournal(journalID)

        var entryIDs = Set(localEntries.keys).union(state.entries.keys)
        for path in state.remoteFiles.keys {
            if let key = JournalSyncLayout.entryID(fromEntryPath: path, journalID: journalID) {
                entryIDs.insert(key)
            }
            if let key = tombstoneEntryID(from: path, journalID: journalID) {
                entryIDs.insert(key)
            }
        }

        // Collect remote-sourced mutations during day reconciliation and apply
        // them in ONE batch afterwards, so a first pull of N days does a
        // constant number of full-snapshot writes (PF-01). Failed days simply
        // do not enter the batch; their errors still surface below.
        var pending: [PendingEntryMutation] = []
        var supersededEntries: Set<UUID> = []
        var firstError: Error?
        for entryID in entryIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            do {
                try await reconcileEntry(
                    entryID,
                    journalID: journalID,
                    localEntries: localEntries,
                    mutations: &pending,
                    supersededEntries: &supersededEntries
                )
            } catch JournalSyncError.journalSwitched {
                throw JournalSyncError.journalSwitched
            } catch {
                if firstError == nil { firstError = error }
                NSLog("Wick sync: day \(entryID) failed: \(error.localizedDescription)")
            }
        }

        // Final commit re-flushes editor drafts and re-verifies each mutation
        // against its decision-time local hash; only actually-applied days get
        // their baseline advanced (AC-P1-05), so a mid-cycle edit on an
        // enqueued day is never clobbered and re-reconciles next cycle.
        if !pending.isEmpty {
            try requireJournal(journalID)
            let appliedEntries = localSource.applySyncedChanges(
                pending.map(\.mutation),
                journalID: journalID
            )
            for item in pending where appliedEntries.contains(item.mutation.entryID) {
                if let baseline = item.baseline {
                    state.entries[item.mutation.entryID] = baseline
                } else {
                    state.entries.removeValue(forKey: item.mutation.entryID)
                }
            }
        }

        // Settlement housekeeping needs each day's FINAL `remoteContentHash`,
        // which is only available after the batch commit.
        for entryID in entryIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            if supersededEntries.contains(entryID), let hash = state.entries[entryID]?.remoteContentHash {
                await uploadSettlementMarker(entryID: entryID, settledHash: hash, journalID: journalID)
            }
            if state.pendingConflicts.contains(where: { $0.entryID == entryID }),
               let hash = state.entries[entryID]?.remoteContentHash,
               try await hasSettlingMarker(for: entryID, journalID: journalID, hash: hash) {
                removeConflicts(for: entryID)
            }
        }

        // 4. Images (after the batch so references from applied entries resolve).
        do {
            try await reconcileImages(journalID: journalID)
        } catch {
            if firstError == nil { firstError = error }
            NSLog("Wick sync: images failed: \(error.localizedDescription)")
        }

        // 4b. Trading data is an optional derived whole-file snapshot. It is
        // intentionally reconciled after days so auto-created position tags
        // arrive before the receipts that attach to them.
        do {
            try await reconcileTradingSnapshot(journalID: journalID)
        } catch JournalSyncError.journalSwitched {
            throw JournalSyncError.journalSwitched
        } catch {
            if firstError == nil { firstError = error }
            NSLog("Wick sync: trading snapshot failed: \(error.localizedDescription)")
        }

        // 5. Garbage-collect ancient tombstones (best effort).
        await collectGarbageTombstones(journalID: journalID)

        if let firstError {
            throw firstError
        }
    }

    // MARK: - Entry reconciliation

    /// A remote-sourced local change collected during reconciliation, plus the
    /// `state.entries` baseline to record IF the mutation actually commits.
    private struct PendingEntryMutation {
        let mutation: JournalSyncMutation
        /// Recorded only when the store commits the mutation; nil means the
        /// day's bookkeeping is pruned (a committed remove of an absent day).
        let baseline: EntrySyncState?
    }

    private func reconcileEntry(
        _ entryID: UUID,
        journalID: UUID,
        localEntries: [UUID: (entry: JournalEntry, hash: String)],
        mutations: inout [PendingEntryMutation],
        supersededEntries: inout Set<UUID>
    ) async throws {
        let entryPath = JournalSyncLayout.entryPath(for: journalID, entryID: entryID)
        let tombPath = JournalSyncLayout.entryTombstonePath(for: journalID, entryID: entryID)
        let local = localEntries[entryID]
        let prev = state.entries[entryID]
        let remoteFile = state.remoteFiles[entryPath]
        let remoteTomb = state.remoteFiles[tombPath]

        // A user-settled conflict executes authoritatively - the decision
        // bypasses the divergence matrix, which is exactly what would
        // re-record the conflict it is meant to resolve.
        var settlementSuperseded = false
        if let settlement = prev?.settlement {
            switch await executeSettlement(
                settlement,
                entryID: entryID,
                journalID: journalID,
                localEntries: localEntries,
                remoteFile: remoteFile,
                mutations: &mutations
            ) {
            case .executed:
                return
            case .continueMatrix:
                break
            case .superseded:
                // The store moved past the chosen version (the user kept
                // typing); the matrix converges the day, and a marker goes up
                // afterwards so peers still drop their stale reminders.
                settlementSuperseded = true
            }
        }

        let localChanged = local != nil && local!.hash != prev?.localHash
        let localDeleted = local == nil && prev?.localHash != nil
        // Rev-only: our own uploads record the server-returned rev, so the
        // delta echo of a self-write reads as unchanged. Backend content
        // hashes are never compared here - they use a different algorithm
        // than our canonical hashes and could never match.
        let remoteChanged: Bool = remoteFile?.rev != prev?.remoteRev
        let hasNewTombstone = remoteTomb != nil && remoteTomb?.rev != prev?.tombstoneRev

        // A remote tombstone remains authoritative while it exists. This also
        // cleans up a day file resurrected beside an already-acknowledged
        // tombstone by a stale client. A genuine local edit can still restore
        // the day and explicitly clear the marker.
        if let remoteTomb {
            let tombstoneDeletedAt: Date
            if hasNewTombstone || prev?.tombstoneDeletedAt == nil {
                tombstoneDeletedAt = try await downloadTombstone(path: tombPath).deletedAt
            } else {
                tombstoneDeletedAt = prev!.tombstoneDeletedAt!
            }
            if let local, localChanged {
                // Delete vs edit: the actively edited side wins and the
                // tombstone is cleared (resolution is recorded as a conflict).
                try await pushEntry(local, journalID: journalID, currentRemoteRev: remoteFile?.rev, mutations: &mutations)
                try await backend.delete(path: tombPath)
                state.remoteFiles.removeValue(forKey: tombPath)
                recordConflict(
                    entryID: entryID,
                    summary: "delete-vs-edit",
                    remotePath: ""
                )
                return
            }
            if local != nil, localEntryMatchesSnapshot(entryID, snapshot: localEntries[entryID]) {
                try requireJournal(journalID)
                let tombstoneState = EntrySyncState(
                    tombstoneRev: remoteTomb.rev,
                    tombstoneDeletedAt: tombstoneDeletedAt
                )
                mutations.append(PendingEntryMutation(
                    mutation: .remove(entryID: entryID, expectedLocalHash: localEntries[entryID]?.hash),
                    baseline: tombstoneState
                ))
            } else {
                // Local already absent: the tombstone is authoritative without
                // any local write.
                state.entries[entryID] = EntrySyncState(
                    tombstoneRev: remoteTomb.rev,
                    tombstoneDeletedAt: tombstoneDeletedAt
                )
            }
            // Clean up a day file that outlived its tombstone (crash between writes).
            if remoteFile != nil {
                try await backend.delete(path: entryPath)
                state.remoteFiles.removeValue(forKey: entryPath)
            }
            return
        }

        // Local delete propagates: tombstone first, then the file delete.
        if localDeleted, remoteFile != nil, !remoteChanged {
            try requireJournal(journalID)
            let tombstone = JournalTombstone(entryID: entryID, deletedAt: Date(), deviceID: deviceID)
            let data = try JournalSyncEncoding.encoder.encode(tombstone)
            let tombRev = try await backend.upload(path: tombPath, data: data, ifRev: nil)
            state.remoteFiles[tombPath] = RemoteFileRecord(
                rev: tombRev,
                contentHash: JournalSyncEncoding.contentHash(of: data)
            )
            try await backend.delete(path: entryPath)
            state.remoteFiles.removeValue(forKey: entryPath)
            state.entries[entryID] = EntrySyncState(
                tombstoneRev: tombRev,
                tombstoneDeletedAt: tombstone.deletedAt
            )
            return
        }

        // Delete vs remote edit: remote wins, the day resurrects locally.
        if localDeleted, remoteChanged, let remoteFile {
            try await pullEntry(
                remoteFile: remoteFile,
                entryPath: entryPath,
                entryID: entryID,
                journalID: journalID,
                expectedLocal: localEntries[entryID],
                mutations: &mutations
            )
            recordConflict(
                entryID: entryID,
                summary: "deletion overridden by remote edit",
                remotePath: entryPath
            )
            return
        }

        // Remote day vanished without a tombstone: accident - heal by re-upload.
        if remoteFile == nil, prev?.remoteRev != nil, let local {
            try await pushEntry(local, journalID: journalID, currentRemoteRev: nil, mutations: &mutations)
            return
        }

        // Both changed: item-union merge.
        if let local, localChanged, remoteChanged {
            try await mergeEntry(
                local: local,
                entryID: entryID,
                journalID: journalID,
                entryPath: entryPath,
                mutations: &mutations
            )
        } else if let remoteFile, remoteChanged, !localChanged {
            // Only remote changed (incl. brand-new remote day): pull.
            try await pullEntry(
                remoteFile: remoteFile,
                entryPath: entryPath,
                entryID: entryID,
                journalID: journalID,
                expectedLocal: localEntries[entryID],
                mutations: &mutations
            )
        } else if let local, localChanged {
            // Only local changed (incl. brand-new local day): push.
            try await pushEntry(local, journalID: journalID, currentRemoteRev: remoteFile?.rev, mutations: &mutations)
        } else if local == nil, remoteFile == nil, prev?.tombstoneRev == nil {
            // Nothing left anywhere: prune stale bookkeeping.
            state.entries.removeValue(forKey: entryID)
        }

        // A superseded settlement still owes peers a marker. The actual upload
        // runs after the batch commit in `syncCycleBody`, which needs the
        // day's final `remoteContentHash`.
        if settlementSuperseded {
            supersededEntries.insert(entryID)
        }
    }

    // MARK: - Settlement execution

    private enum SettlementOutcome {
        /// The settlement converged the day - skip the divergence matrix.
        case executed
        /// The day still needs the regular matrix (mark-only settlement, or
        /// the local store moved past the chosen version).
        case continueMatrix
        /// The user's newer edits superseded the decision; the matrix runs and
        /// a settlement marker follows whatever it lands on the remote.
        case superseded
    }

    /// Executes a pending user decision for a day.
    private func executeSettlement(
        _ settlement: EntrySettlement,
        entryID: UUID,
        journalID: UUID,
        localEntries: [UUID: (entry: JournalEntry, hash: String)],
        remoteFile: RemoteFileRecord?,
        mutations: inout [PendingEntryMutation]
    ) async -> SettlementOutcome {
        state.entries[entryID]?.settlement = nil

        switch settlement {
        case .pushSettled(let settledHash):
            // The user edited past the chosen version - their newer content
            // supersedes the decision; sync it the regular way.
            guard let local = localEntries[entryID], local.hash == settledHash else { return .superseded }
            await authoritativePush(local, entryID: entryID, journalID: journalID, remoteFile: remoteFile)
            await uploadSettlementMarker(entryID: entryID, settledHash: settledHash, journalID: journalID)
            return .executed

        case .adoptRemote:
            // Adopt whatever is live on the remote right now.
            guard let remoteFile else { return .superseded }
            do {
                let result = try await pullEntry(
                    remoteFile: remoteFile,
                    entryPath: JournalSyncLayout.entryPath(for: journalID, entryID: entryID),
                    entryID: entryID,
                    journalID: journalID,
                    expectedLocal: localEntries[entryID],
                    mutations: &mutations
                )
                guard result.applied else { return .superseded }
                if let hash = result.remoteContentHash {
                    await uploadSettlementMarker(entryID: entryID, settledHash: hash, journalID: journalID)
                }
                return .executed
            } catch {
                // Offline or raced: retry the settlement next cycle.
                state.entries[entryID]?.settlement = .adoptRemote
                return .executed
            }

        case .markSettled(let settledHash):
            // Nothing to move - signal peers so they drop stale reminders,
            // then let the matrix converge this device too.
            await uploadSettlementMarker(entryID: entryID, settledHash: settledHash, journalID: journalID)
            return .continueMatrix
        }
    }

    /// Pushes local content as the decided winner: rev-guarded against the
    /// current remote, and on a lost race re-targets the winner's rev instead
    /// of merging (the user's choice outranks convergence by merge).
    private func authoritativePush(
        _ local: (entry: JournalEntry, hash: String),
        entryID: UUID,
        journalID: UUID,
        remoteFile: RemoteFileRecord?
    ) async {
        let entryPath = JournalSyncLayout.entryPath(for: journalID, entryID: entryID)
        let data = try? JournalSyncEncoding.canonicalData(for: local.entry)
        guard let data else { return }
        do {
            let rev = try await backend.upload(path: entryPath, data: data, ifRev: remoteFile?.rev)
            recordPushedEntry(local, entryID: entryID, entryPath: entryPath, rev: rev)
            return
        } catch SyncBackendError.writeConflict {
            // The remote moved after the listing: fetch its rev and overwrite.
            if let (_, freshRev) = try? await backend.download(path: entryPath) {
                if let rev = try? await backend.upload(path: entryPath, data: data, ifRev: freshRev) {
                    recordPushedEntry(local, entryID: entryID, entryPath: entryPath, rev: rev)
                }
            }
        } catch {
            NSLog("Wick sync: settlement push failed for \(entryID): \(error.localizedDescription)")
        }
    }

    /// Records a successful push as the day's new baseline (canonical hashes
    /// on both sides).
    private func recordPushedEntry(
        _ local: (entry: JournalEntry, hash: String),
        entryID: UUID,
        entryPath: String,
        rev: String
    ) {
        state.remoteFiles[entryPath] = RemoteFileRecord(rev: rev, contentHash: local.hash)
        var dayState = state.entries[entryID] ?? EntrySyncState()
        dayState.localHash = local.hash
        dayState.remoteRev = rev
        dayState.remoteContentHash = local.hash
        dayState.pushedHashes.appendUniqueHash(local.hash, limit: Self.pushedHashHistoryLimit)
        state.entries[entryID] = dayState
    }

    // MARK: - Entry operations

    private func pushEntry(
        _ local: (entry: JournalEntry, hash: String),
        journalID: UUID,
        currentRemoteRev: String?,
        mutations: inout [PendingEntryMutation]
    ) async throws {
        try requireJournal(journalID)
        let entryID = local.entry.id
        let entryPath = JournalSyncLayout.entryPath(for: journalID, entryID: entryID)
        let data = try JournalSyncEncoding.canonicalData(for: local.entry)
        do {
            let rev = try await backend.upload(path: entryPath, data: data, ifRev: currentRemoteRev)
            recordPushedEntry(local, entryID: entryID, entryPath: entryPath, rev: rev)
        } catch SyncBackendError.writeConflict {
            // Lost the race against another device: merge with the winner.
            try await mergeEntry(
                local: local,
                entryID: entryID,
                journalID: journalID,
                entryPath: entryPath,
                mutations: &mutations
            )
        }
    }

    /// Downloads and queues the remote day. Returns `applied == false` when the
    /// local day changed after the cycle's snapshot (nothing applied - the next
    /// cycle re-decides with the fresher local content), along with the remote
    /// content's canonical hash for settlement-marker bookkeeping.
    @discardableResult
    private func pullEntry(
        remoteFile: RemoteFileRecord,
        entryPath: String,
        entryID: UUID,
        journalID: UUID,
        expectedLocal snapshot: (entry: JournalEntry, hash: String)?,
        mutations: inout [PendingEntryMutation]
    ) async throws -> (applied: Bool, remoteContentHash: String?) {
        let (data, downloadedRev) = try await backend.download(path: entryPath)
        let entry = try JournalSyncEncoding.decoder.decode(JournalEntry.self, from: data)
        guard entry.id == entryID else {
            throw JournalSyncError.invalidRemoteEntryIdentity(path: entryPath)
        }

        // Commit any in-flight editor draft FIRST so the freshness check sees
        // it: a draft that changed the day since the cycle snapshot must abort
        // this apply (the next cycle merges instead of clobbering the typing).
        localSource.prepareForRemoteApply(entryID: entryID)

        // Freshness guard: never apply remote content over a day that changed
        // locally after the cycle's snapshot - the next cycle re-decides with
        // the fresher local content (which then merges instead of clobbering).
        guard localEntryMatchesSnapshot(entryID, snapshot: snapshot) else { return (false, nil) }

        try requireJournal(journalID)

        // Baselines use the canonical hash of the downloaded bytes - never the
        // backend's metadata hash - so re-hashing the applied content
        // reproduces this baseline and a pull never turns into a push.
        let canonical = JournalSyncEncoding.contentHash(of: data)
        let rev = downloadedRev.isEmpty ? remoteFile.rev : downloadedRev
        var dayState = state.entries[entryID] ?? EntrySyncState()
        dayState.localHash = canonical
        dayState.remoteRev = rev
        dayState.remoteContentHash = canonical
        mutations.append(PendingEntryMutation(
            mutation: .upsert(entry, expectedLocalHash: snapshot?.hash),
            baseline: dayState
        ))
        return (true, canonical)
    }

    private func mergeEntry(
        local: (entry: JournalEntry, hash: String),
        entryID: UUID,
        journalID: UUID,
        entryPath: String,
        mutations: inout [PendingEntryMutation]
    ) async throws {
        let (remoteData, remoteRev) = try await backend.download(path: entryPath)
        let remoteEntry = try JournalSyncEncoding.decoder.decode(JournalEntry.self, from: remoteData)
        let remoteHash = JournalSyncEncoding.contentHash(of: remoteData)

        // Self-merge guard: the "remote" side is one of this device's own
        // pushed versions - a stale echo of our upload racing newer local
        // edits, or a peer relaying our content back. Not a conflict: the day
        // converges by re-pushing local, with no archive and no user-facing
        // conflict record.
        if remoteHash != local.hash,
           let pushedHashes = state.entries[entryID]?.pushedHashes,
           pushedHashes.contains(remoteHash) {
            let data = try JournalSyncEncoding.canonicalData(for: local.entry)
            if let rev = try? await backend.upload(path: entryPath, data: data, ifRev: remoteRev) {
                recordPushedEntry(local, entryID: entryID, entryPath: entryPath, rev: rev)
            }
            // A writeConflict here means the remote moved again under us - the
            // next cycle re-runs the day with the fresh inputs.
            return
        }

        guard remoteEntry.id == entryID else {
            throw JournalSyncError.invalidRemoteEntryIdentity(path: entryPath)
        }
        let result = JournalEntryMerge.merge(local: local.entry, remote: remoteEntry)
        let mergedData = try JournalSyncEncoding.canonicalData(for: result.merged)
        let mergedHash = JournalSyncEncoding.contentHash(of: mergedData)

        if mergedHash == local.hash, mergedHash == remoteHash {
            // Identical already (bookkeeping drifted) - align state only.
            state.remoteFiles[entryPath] = RemoteFileRecord(rev: remoteRev, contentHash: remoteHash)
            var dayState = state.entries[entryID] ?? EntrySyncState()
            dayState.localHash = local.hash
            dayState.remoteRev = remoteRev
            dayState.remoteContentHash = remoteHash
            state.entries[entryID] = dayState
            return
        }

        // Commit any in-flight editor draft before the freshness check so a
        // mid-cycle edit aborts this merge and the next cycle re-merges.
        localSource.prepareForRemoteApply(entryID: entryID)

        // Freshness guard before any write: the merge was computed from the
        // cycle's snapshot, so a day that changed locally since would make
        // both the upload and the apply stale. Abort untouched - the next
        // cycle re-merges with the fresh local content.
        guard localEntryMatchesSnapshot(entryID, snapshot: local) else { return }

        // Archive the losing side before overwriting anything.
        if !result.losingItems.isEmpty || result.losingTitle != nil {
            let archivePath = await archiveConflict(result: result, entryID: entryID, journalID: journalID)
            recordConflict(
                entryID: entryID,
                summary: "item-content-conflict",
                remotePath: archivePath,
                local: local.entry,
                remote: remoteEntry,
                merged: result.merged
            )
        }

        if mergedHash != remoteHash {
            let newRev = try await backend.upload(path: entryPath, data: mergedData, ifRev: remoteRev)
            state.remoteFiles[entryPath] = RemoteFileRecord(rev: newRev, contentHash: mergedHash)
            if mergedHash != local.hash {
                var dayState = state.entries[entryID] ?? EntrySyncState()
                dayState.localHash = mergedHash
                dayState.remoteRev = newRev
                dayState.remoteContentHash = mergedHash
                dayState.pushedHashes.appendUniqueHash(mergedHash, limit: Self.pushedHashHistoryLimit)
                try requireJournal(journalID)
                mutations.append(PendingEntryMutation(
                    mutation: .upsert(result.merged, expectedLocalHash: local.hash),
                    baseline: dayState
                ))
            } else {
                // Merged result equals local — align bookkeeping only.
                var dayState = state.entries[entryID] ?? EntrySyncState()
                dayState.localHash = mergedHash
                dayState.remoteRev = newRev
                dayState.remoteContentHash = mergedHash
                dayState.pushedHashes.appendUniqueHash(mergedHash, limit: Self.pushedHashHistoryLimit)
                state.entries[entryID] = dayState
            }
        } else {
            // Remote already holds the merged result.
            state.remoteFiles[entryPath] = RemoteFileRecord(rev: remoteRev, contentHash: mergedHash)
            if mergedHash != local.hash {
                var dayState = state.entries[entryID] ?? EntrySyncState()
                dayState.localHash = mergedHash
                dayState.remoteRev = remoteRev
                dayState.remoteContentHash = mergedHash
                try requireJournal(journalID)
                mutations.append(PendingEntryMutation(
                    mutation: .upsert(result.merged, expectedLocalHash: local.hash),
                    baseline: dayState
                ))
            } else {
                var dayState = state.entries[entryID] ?? EntrySyncState()
                dayState.localHash = mergedHash
                dayState.remoteRev = remoteRev
                dayState.remoteContentHash = mergedHash
                state.entries[entryID] = dayState
            }
        }
    }

    /// True when the day in the store still hashes (canonically) to `snapshot`
    /// - nothing changed locally since the cycle's snapshot was taken. Applied
    /// remote content must never clobber mid-cycle local edits.
    private func localEntryMatchesSnapshot(
        _ entryID: UUID,
        snapshot: (entry: JournalEntry, hash: String)?
    ) -> Bool {
        guard let fresh = localSource.syncEntrySnapshots()[entryID] else {
            return snapshot == nil
        }
        guard let hash = try? JournalSyncEncoding.contentHash(for: fresh) else { return false }
        return hash == snapshot?.hash
    }

    /// Uploads the losing side to `conflicts/`; returns the archive path, or an
    /// empty string when the upload fails (the archive is a best-effort safety
    /// net — a failed archive must never block the merge itself).
    private func archiveConflict(
        result: JournalEntryMergeResult,
        entryID: UUID,
        journalID: UUID
    ) async -> String {
        let now = Date()
        let payload = JournalConflictPayload(
            entryID: entryID,
            detectedAt: now,
            deviceID: deviceID,
            reason: "item-content-conflict",
            losingItems: result.losingItems,
            losingTitle: result.losingTitle
        )
        let data = try? JournalSyncEncoding.encoder.encode(payload)
        guard let data else { return "" }
        let path = JournalSyncLayout.conflictPath(for: journalID, entryID: entryID, stamp: now)
        do {
            _ = try await backend.upload(path: path, data: data, ifRev: nil)
        } catch {
            NSLog("Wick sync: conflict archive failed for \(entryID): \(String(describing: error))")
            return ""
        }
        return path
    }

    private func recordConflict(
        entryID: UUID,
        summary: String,
        remotePath: String,
        local: JournalEntry? = nil,
        remote: JournalEntry? = nil,
        merged: JournalEntry? = nil
    ) {
        // SY-03: dedupe by (entryID, summary). The record is written before the
        // upload can be confirmed, so a network blip that retries the merge on
        // the next cycle must not accumulate a duplicate conflict record.
        guard !state.pendingConflicts.contains(where: { $0.entryID == entryID && $0.summary == summary }) else {
            return
        }
        state.pendingConflicts.append(
            SyncConflictRecord(
                entryID: entryID,
                displayDay: (merged ?? local ?? remote).map {
                    JournalDayKey.make(from: $0.date)
                } ?? "",
                remotePath: remotePath,
                summary: summary,
                detectedAt: Date(),
                localEntry: local,
                remoteEntry: remote,
                mergedEntry: merged
            )
        )
    }

    /// Drops every pending conflict record for a day (used when the day is
    /// settled, so a resolved conflict cannot linger and nag again).
    private func removeConflicts(for entryID: UUID) {
        state.pendingConflicts.removeAll { $0.entryID == entryID }
    }

    /// Uploads a settlement marker so other devices can drop their stale
    /// pending-conflict records for this day. Best-effort — a failed marker
    /// never blocks the settlement itself.
    private func uploadSettlementMarker(entryID: UUID, settledHash: String, journalID: UUID) async {
        let marker = JournalSettlementMarker(
            entryID: entryID,
            settledHash: settledHash,
            deviceID: deviceID,
            stamp: Date()
        )
        guard let data = try? JournalSyncEncoding.encoder.encode(marker) else { return }
        let path = JournalSyncLayout.settlementPath(for: journalID, entryID: entryID, stamp: Date())
        do {
            let rev = try await backend.upload(path: path, data: data, ifRev: nil)
            state.remoteFiles[path] = RemoteFileRecord(
                rev: rev,
                contentHash: JournalSyncEncoding.contentHash(of: data)
            )
        } catch {
            NSLog("Wick sync: settlement marker failed for \(entryID): \(String(describing: error))")
        }
    }

    /// True when ANY peer settlement marker for this day carries `hash`.
    /// Iterates every marker rather than stopping at the first match (SY-02):
    /// a stale marker from an older settlement must never shadow a newer,
    /// matching one, or the day's conflicts would be stuck forever.
    private func hasSettlingMarker(for entryID: UUID, journalID: UUID, hash: String) async throws -> Bool {
        for path in state.remoteFiles.keys where JournalSyncLayout.isSettlementPath(path, journalID: journalID) {
            guard JournalSyncLayout.settlementEntryID(from: path, journalID: journalID) == entryID else { continue }
            let (data, _) = try await backend.download(path: path)
            if let marker = try? JournalSyncEncoding.decoder.decode(JournalSettlementMarker.self, from: data),
               marker.settledHash == hash {
                return true
            }
        }
        return false
    }

    // MARK: - Images

    private func reconcileImages(journalID: UUID) async throws {
        // Defense in depth: model-level validation already rejects unsafe
        // references at decode time, but a remote path built from a bad name
        // could still escape the journal folder on the backend.
        let referenced = localSource.syncedImageFilenames()
            .filter { JournalImageFilename.isValid($0) }
            .sorted()

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
                localSource.storeSyncedImage(filename: filename, data: data, journalID: journalID)
            }
        }
    }

    // MARK: - Trading snapshot

    private func reconcileTradingSnapshot(journalID: UUID) async throws {
        guard localSource.syncTradingSnapshotEnabled else { return }
        guard !deviceState.pendingTradingSnapshotDeletions.contains(where: { $0.journalID == journalID }) else {
            return
        }
        try requireJournal(journalID)

        let path = JournalSyncLayout.tradingSnapshotPath(for: journalID)
        let key = path.lowercased()
        let local = localSource.syncedTradingSnapshot(journalID: journalID)
        let entryTombstonePath = JournalSyncLayout.tradingSnapshotTombstonePath(for: journalID)
        let tombstoneKey = entryTombstonePath.lowercased()

        if let tombstoneRecord = state.remoteFiles[tombstoneKey] {
            var deletedAt = state.tradingSnapshotDeletedAtMilliseconds
            if tombstoneRecord.rev != state.tradingSnapshotTombstoneRev || deletedAt == nil {
                let (data, rev) = try await backend.download(path: entryTombstonePath)
                let marker = try JournalSyncEncoding.decoder.decode(
                    JournalTradingSnapshotTombstone.self,
                    from: data
                )
                guard marker.journalID == journalID else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                state.tradingSnapshotTombstoneRev = rev
                state.tradingSnapshotDeletedAtMilliseconds = marker.deletedAtMilliseconds
                deletedAt = marker.deletedAtMilliseconds
            }

            if let local, let deletedAt, local.fetchedAtMilliseconds > deletedAt {
                // A genuinely newer exchange refresh intentionally resurrects
                // cloud sharing and removes the old deletion marker.
                try await backend.delete(path: entryTombstonePath)
                state.remoteFiles.removeValue(forKey: tombstoneKey)
                state.tradingSnapshotTombstoneRev = nil
                state.tradingSnapshotDeletedAtMilliseconds = nil
            } else {
                localSource.removeSyncedTradingSnapshot(journalID: journalID)
                if state.remoteFiles[key] != nil {
                    try? await backend.delete(path: path)
                    state.remoteFiles.removeValue(forKey: key)
                }
                state.tradingSnapshotRev = nil
                state.tradingSnapshotFetchedAtMilliseconds = nil
                return
            }
        }

        guard let remoteRecord = state.remoteFiles[key] else {
            state.tradingSnapshotRev = nil
            state.tradingSnapshotFetchedAtMilliseconds = nil
            guard let local else { return }
            try validateTradingSnapshot(local, journalID: journalID)
            let data = try JournalSyncEncoding.encoder.encode(local)
            let rev = try await backend.upload(path: path, data: data, ifRev: nil)
            try requireJournal(journalID)
            recordTradingSnapshotUpload(data: data, rev: rev, document: local, path: key)
            return
        }

        // A changed rev must be inspected even when the local timestamp did
        // not move: another device may have published a newer snapshot.
        if state.tradingSnapshotRev != remoteRecord.rev {
            let (data, downloadedRev) = try await backend.download(path: path)
            let remote = try JournalSyncEncoding.decoder.decode(
                JournalTradingSnapshotDocument.self,
                from: data
            )
            try validateTradingSnapshot(remote, journalID: journalID)
            try requireJournal(journalID)

            if let local, local.fetchedAtMilliseconds > remote.fetchedAtMilliseconds {
                try validateTradingSnapshot(local, journalID: journalID)
                let localData = try JournalSyncEncoding.encoder.encode(local)
                let rev = try await backend.upload(path: path, data: localData, ifRev: downloadedRev)
                try requireJournal(journalID)
                recordTradingSnapshotUpload(
                    data: localData,
                    rev: rev,
                    document: local,
                    path: key
                )
            } else {
                localSource.applySyncedTradingSnapshot(remote, journalID: journalID)
                state.tradingSnapshotRev = downloadedRev
                state.tradingSnapshotFetchedAtMilliseconds = remote.fetchedAtMilliseconds
            }
            return
        }

        let baseline = state.tradingSnapshotFetchedAtMilliseconds
        let localIsMissingOrOlder = local.map { snapshot in
            baseline.map { snapshot.fetchedAtMilliseconds < $0 } ?? false
        } ?? true
        if let local, baseline.map({ local.fetchedAtMilliseconds > $0 }) ?? true {
            try validateTradingSnapshot(local, journalID: journalID)
            let data = try JournalSyncEncoding.encoder.encode(local)
            let rev = try await backend.upload(path: path, data: data, ifRev: remoteRecord.rev)
            try requireJournal(journalID)
            recordTradingSnapshotUpload(data: data, rev: rev, document: local, path: key)
        } else if localIsMissingOrOlder {
            // Restore a cloud snapshot removed or replaced locally while the
            // opt-in remains enabled. Disabling the setting skips this path.
            let (data, downloadedRev) = try await backend.download(path: path)
            let remote = try JournalSyncEncoding.decoder.decode(
                JournalTradingSnapshotDocument.self,
                from: data
            )
            try validateTradingSnapshot(remote, journalID: journalID)
            try requireJournal(journalID)
            localSource.applySyncedTradingSnapshot(remote, journalID: journalID)
            state.tradingSnapshotRev = downloadedRev
            state.tradingSnapshotFetchedAtMilliseconds = remote.fetchedAtMilliseconds
        }
    }

    private func validateTradingSnapshot(
        _ document: JournalTradingSnapshotDocument,
        journalID: UUID
    ) throws {
        guard document.formatVersion <= JournalTradingSnapshotDocument.currentFormatVersion else {
            throw JournalSyncError.unsupportedTradingSnapshotFormat(document.formatVersion)
        }
        guard document.journalID == journalID else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    private func recordTradingSnapshotUpload(
        data: Data,
        rev: String,
        document: JournalTradingSnapshotDocument,
        path: String
    ) {
        state.remoteFiles[path] = RemoteFileRecord(
            rev: rev,
            contentHash: JournalSyncEncoding.contentHash(of: data)
        )
        state.tradingSnapshotRev = rev
        state.tradingSnapshotFetchedAtMilliseconds = document.fetchedAtMilliseconds
    }

    private func flushPendingTradingSnapshotDeletions() async {
        guard !deviceState.pendingTradingSnapshotDeletions.isEmpty else { return }
        var failed: [JournalTradingSnapshotTombstone] = []
        for marker in deviceState.pendingTradingSnapshotDeletions {
            let journalID = marker.journalID
            let path = JournalSyncLayout.tradingSnapshotPath(for: journalID)
            let entryTombstonePath = JournalSyncLayout.tradingSnapshotTombstonePath(for: journalID)
            do {
                let data = try JournalSyncEncoding.encoder.encode(marker)
                let knownRev = state.remoteFiles[entryTombstonePath.lowercased()]?.rev
                let tombstoneRev = try await backend.upload(
                    path: entryTombstonePath,
                    data: data,
                    ifRev: knownRev
                )
                try await backend.delete(path: path)
                state.remoteFiles.removeValue(forKey: path.lowercased())
                state.remoteFiles[entryTombstonePath.lowercased()] = RemoteFileRecord(
                    rev: tombstoneRev,
                    contentHash: JournalSyncEncoding.contentHash(of: data)
                )
                if stateJournalID == journalID {
                    state.tradingSnapshotRev = nil
                    state.tradingSnapshotFetchedAtMilliseconds = nil
                    state.tradingSnapshotTombstoneRev = tombstoneRev
                    state.tradingSnapshotDeletedAtMilliseconds = marker.deletedAtMilliseconds
                }
            } catch {
                failed.append(marker)
            }
        }
        deviceState.pendingTradingSnapshotDeletions = failed
        saveDeviceStateAndPublish()
    }

    // MARK: - Manifest / tombstones

    /// Hard-cuts a legacy day-keyed journal to v2. Local journal files are the
    /// authority: the manifest is upgraded first to fence old clients, then all
    /// legacy identity-bearing directories are removed. UUID entries are
    /// uploaded by the normal reconciliation pass immediately afterwards.
    private func migrateLegacyRemoteIfNeeded(journalID: UUID, localName: String) async throws {
        let manifestPath = JournalSyncLayout.manifestPath(for: journalID)
        guard let meta = state.remoteFiles[manifestPath] else { return }
        guard state.manifestFormatVersion != JournalSyncLayout.formatVersion else { return }
        let (data, downloadedRev) = try await backend.download(path: manifestPath)
        let manifest = try JournalSyncEncoding.decoder.decode(JournalSyncManifest.self, from: data)
        guard manifest.formatVersion < JournalSyncLayout.formatVersion else {
            state.manifestFormatVersion = manifest.formatVersion
            return
        }

        var upgraded = manifest
        upgraded.formatVersion = JournalSyncLayout.formatVersion
        upgraded.journalName = localName
        upgraded.deviceID = deviceID
        let upgradedData = try JournalSyncEncoding.encoder.encode(upgraded)
        let rev = try await backend.upload(
            path: manifestPath,
            data: upgradedData,
            ifRev: downloadedRev.isEmpty ? meta.rev : downloadedRev
        )
        state.remoteFiles[manifestPath] = RemoteFileRecord(
            rev: rev,
            contentHash: JournalSyncEncoding.contentHash(of: upgradedData)
        )
        state.manifestRev = rev
        state.manifestFormatVersion = JournalSyncLayout.formatVersion
        state.manifestName = localName

        let root = JournalSyncLayout.journalRoot(for: journalID)
        let legacyFolders = ["days", "tombstones", "conflicts", "settlements"]
        for folder in legacyFolders {
            let path = "\(root)/\(folder)"
            try await backend.delete(path: path)
            for remotePath in Array(state.remoteFiles.keys) where remotePath.hasPrefix(path + "/") {
                state.remoteFiles.removeValue(forKey: remotePath)
            }
        }
        state.entries = [:]
        state.pendingConflicts = []
        state.pendingConflictCleanups = []
    }

    private func ensureManifest(journalID: UUID, localName: String) async throws {
        try requireJournal(journalID)
        let path = JournalSyncLayout.manifestPath(for: journalID)

        guard let meta = state.remoteFiles[path] else {
            // First device to sync creates the manifest; a create race is harmless.
            let manifest = JournalSyncManifest(
                formatVersion: JournalSyncLayout.formatVersion,
                journalID: journalID,
                journalName: localName,
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
                state.manifestFormatVersion = JournalSyncLayout.formatVersion
                state.manifestName = localName
            }
            return
        }

        let revChanged = meta.rev != state.manifestRev

        // One-time seed for state files written before journal names synced:
        // take the remote name as the baseline. A divergence then reads as a
        // local rename the old app never pushed — unless the remote manifest
        // also moved, which only a rename-capable peer can do, so it wins.
        var seededFromLegacyState = false
        if state.manifestName == nil, state.manifestRev != nil {
            let seeded = try await downloadManifest(path: path)
            state.manifestName = seeded.journalName
            seededFromLegacyState = true
        }

        let localRenamed = state.manifestName != nil && localName != state.manifestName
        guard revChanged || localRenamed else { return }

        if revChanged, !localRenamed || seededFromLegacyState {
            // Only the remote renamed (fresh imports land here too — the
            // remote name is authoritative for an adopted journal).
            let manifest = try await downloadManifest(path: path)
            state.manifestRev = meta.rev
            state.manifestFormatVersion = manifest.formatVersion
            try adoptJournalName(manifest.journalName, journalID: journalID)
            return
        }

        // A local rename wins and is pushed, rev-guarded. A double rename
        // resolves as last-push-wins: the other device adopts the winner on
        // its next cycle.
        let current = try await downloadManifest(path: path)
        var updated = current
        updated.journalName = localName
        updated.deviceID = deviceID
        let data = try JournalSyncEncoding.encoder.encode(updated)
        do {
            let rev = try await backend.upload(path: path, data: data, ifRev: meta.rev)
            state.remoteFiles[path] = RemoteFileRecord(
                rev: rev,
                contentHash: JournalSyncEncoding.contentHash(of: data)
            )
            state.manifestRev = rev
            state.manifestFormatVersion = updated.formatVersion
            state.manifestName = localName
        } catch SyncBackendError.writeConflict {
            // Lost the race against another device's rename: adopt the winner.
            let (winnerData, winnerRev) = try await backend.download(path: path)
            let winner = try JournalSyncEncoding.decoder.decode(JournalSyncManifest.self, from: winnerData)
            guard winner.formatVersion <= JournalSyncLayout.formatVersion else {
                throw JournalSyncError.unsupportedRemoteFormat(winner.formatVersion)
            }
            state.remoteFiles[path] = RemoteFileRecord(
                rev: winnerRev,
                contentHash: JournalSyncEncoding.contentHash(of: winnerData)
            )
            state.manifestRev = winnerRev
            state.manifestFormatVersion = winner.formatVersion
            try adoptJournalName(winner.journalName, journalID: journalID)
        }
    }

    private func downloadManifest(path: String) async throws -> JournalSyncManifest {
        let (data, _) = try await backend.download(path: path)
        let manifest = try JournalSyncEncoding.decoder.decode(JournalSyncManifest.self, from: data)
        guard manifest.formatVersion <= JournalSyncLayout.formatVersion else {
            throw JournalSyncError.unsupportedRemoteFormat(manifest.formatVersion)
        }
        return manifest
    }

    /// Applies a remote rename locally and records the APPLIED name as the new
    /// baseline. Stores may uniquify on collision, so the applied name can
    /// differ from the remote one — the baseline must follow the local result,
    /// otherwise the next cycle would misread it as a local rename and fight.
    private func adoptJournalName(_ name: String, journalID: UUID) throws {
        guard name != localSource.syncJournalName else {
            state.manifestName = name
            return
        }
        try requireJournal(journalID)
        state.manifestName = localSource.applySyncedJournalName(name, journalID: journalID)
    }

    private func downloadTombstone(path: String) async throws -> JournalTombstone {
        let (data, _) = try await backend.download(path: path)
        return try JournalSyncEncoding.decoder.decode(JournalTombstone.self, from: data)
    }

    // MARK: - Journal discovery

    /// Scans the remote view for manifests of journals other than the active
    /// one and caches them in state. Each manifest is downloaded once per rev;
    /// records whose manifest vanished from the remote are pruned.
    private func refreshDiscoveredJournals(currentJournalID: UUID) async {
        for path in state.remoteFiles.keys.sorted() {
            guard let manifestJournalID = Self.manifestJournalID(from: path),
                  manifestJournalID != currentJournalID,
                  // Deleted journals (own queue or peer tombstone) never
                  // resurface as adoptable - that is the whole point of the
                  // journal tombstone.
                  !deviceState.isTombstoned(manifestJournalID),
                  let meta = state.remoteFiles[path]
            else { continue }

            let key = manifestJournalID.uuidString.lowercased()
            guard state.discoveredJournals[key]?.manifestRev != meta.rev else { continue }

            guard let (data, _) = try? await backend.download(path: path),
                  let manifest = try? JournalSyncEncoding.decoder.decode(JournalSyncManifest.self, from: data),
                  manifest.journalID == manifestJournalID,
                  manifest.formatVersion == JournalSyncLayout.formatVersion
            else { continue }

            state.discoveredJournals[key] = DiscoveredJournalRecord(
                manifest: manifest,
                manifestRev: meta.rev
            )
        }

        // Prune records whose manifest is gone from the remote view.
        for key in state.discoveredJournals.keys {
            guard let uuid = UUID(uuidString: key),
                  state.remoteFiles[JournalSyncLayout.manifestPath(for: uuid)] == nil
            else { continue }
            state.discoveredJournals.removeValue(forKey: key)
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

    private func tombstoneEntryID(from path: String, journalID: UUID) -> UUID? {
        let prefix = "\(JournalSyncLayout.journalRoot(for: journalID))/entry-tombstones/"
        guard path.hasPrefix(prefix), path.hasSuffix(".json") else { return nil }
        let value = path.dropFirst(prefix.count).dropLast(".json".count)
        return UUID(uuidString: String(value))
    }

    private func collectGarbageTombstones(journalID: UUID) async {
        let now = Date()
        for (entryID, dayState) in state.entries {
            guard let deletedAt = dayState.tombstoneDeletedAt,
                  now.timeIntervalSince(deletedAt) > JournalSyncLayout.tombstoneRetention
            else { continue }
            let tombPath = JournalSyncLayout.entryTombstonePath(for: journalID, entryID: entryID)
            if state.remoteFiles[tombPath] != nil {
                try? await backend.delete(path: tombPath)
                state.remoteFiles.removeValue(forKey: tombPath)
            }
            if dayState.localHash == nil, dayState.remoteRev == nil {
                state.entries.removeValue(forKey: entryID)
            } else {
                state.entries[entryID]?.tombstoneRev = nil
                state.entries[entryID]?.tombstoneDeletedAt = nil
            }
        }

        // Settlement markers nobody consumed (e.g. the resolving device's own)
        // age out like tombstones.
        for path in state.remoteFiles.keys where JournalSyncLayout.isSettlementPath(path, journalID: journalID) {
            guard let (data, _) = try? await backend.download(path: path),
                  let marker = try? JournalSyncEncoding.decoder.decode(JournalSettlementMarker.self, from: data),
                  now.timeIntervalSince(marker.stamp) > JournalSyncLayout.tombstoneRetention
            else { continue }
            try? await backend.delete(path: path)
            state.remoteFiles.removeValue(forKey: path)
        }

        // Journal tombstones age out the same way once every peer has had a
        // retention window to see them. Devices keep the UUID in their local
        // ignore lists, so a GC'd marker cannot lead to re-import.
        for path in state.remoteFiles.keys
        where JournalSyncLayout.journalTombstoneID(from: path) != nil {
            guard let (data, _) = try? await backend.download(path: path),
                  let marker = try? JournalSyncEncoding.decoder.decode(JournalDeletionTombstone.self, from: data),
                  now.timeIntervalSince(marker.deletedAt) > JournalSyncLayout.tombstoneRetention
            else { continue }
            try? await backend.delete(path: path)
            state.remoteFiles.removeValue(forKey: path)
            deviceState.processedJournalTombstones.removeAll { $0 == marker.journalID }
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
            status = .error(.server, detail: "Dropbox \(code): \(message)")
        default:
            status = .error(.other, detail: error.localizedDescription)
        }
    }

    private func errorKind(for error: JournalSyncError) -> SyncErrorKind {
        switch error {
        case .unsupportedRemoteFormat, .unsupportedTradingSnapshotFormat:
            return .remoteFormatTooNew
        case .journalSwitched, .invalidRemoteEntryIdentity:
            return .other
        }
    }

    private func message(for error: JournalSyncError) -> String {
        switch error {
        case .unsupportedRemoteFormat(let version):
            return "remote format v\(version) is newer than this app supports"
        case .unsupportedTradingSnapshotFormat(let version):
            return "trading snapshot format v\(version) is newer than this app supports"
        case .journalSwitched:
            return "journal switched"
        case .invalidRemoteEntryIdentity(let path):
            return "remote entry identity does not match its path: \(path)"
        }
    }

    private func publishFromState() {
        lastSyncAt = state.lastSyncAt
        pendingConflicts = state.pendingConflicts
        remoteJournalDeletions = deviceState.unackedRemoteDeletions
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

extension Array where Element == String {
    /// Appends `hash` to the push history unless it is already the newest
    /// entry; trims the oldest beyond `limit`.
    mutating func appendUniqueHash(_ hash: String, limit: Int) {
        if last != hash { append(hash) }
        if count > limit { removeFirst(count - limit) }
    }
}
