import Foundation

// MARK: - Journal deletion propagation
//
// Extracted from JournalSyncEngine.swift so the engine class stays focused on
// the per-journal reconcile loop (SY-06). Pure behavior-preserving move.

extension JournalSyncEngine {
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

    /// Clears any tombstone record for a journal known to be valid locally.
    public func clearJournalTombstone(_ journalID: UUID) {
        deviceState.unackedRemoteDeletions.removeAll { $0 == journalID }
        deviceState.processedJournalTombstones.removeAll { $0 == journalID }
        deviceState.pendingJournalDeletions.removeAll { $0.journalID == journalID }
        saveDeviceStateAndPublish()
    }

    /// Flushes locally-queued journal deletions: tombstone first, then the
    /// folder - the same ordering as day deletions. Runs before any other
    /// cycle work so a deleted journal cannot be resurrected by this cycle.
    func flushPendingJournalDeletions() async {
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
    func detectPeerJournalTombstones() async {
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

    func pruneRemoteFiles(under root: String) {
        for path in state.remoteFiles.keys where path.hasPrefix(root + "/") {
            state.remoteFiles.removeValue(forKey: path)
        }
    }

    func saveDeviceStateAndPublish() {
        stateStore.saveDeviceState(deviceState)
        publishFromState()
    }
}
