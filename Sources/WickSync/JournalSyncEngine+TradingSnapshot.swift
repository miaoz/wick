import Foundation

// MARK: - Trading snapshot
//
// Extracted from JournalSyncEngine.swift so the engine class stays focused on
// the per-journal reconcile loop (SY-06). Pure behavior-preserving move.

extension JournalSyncEngine {
    // MARK: - Trading snapshot

    func reconcileTradingSnapshot(journalID: UUID) async throws {
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

    func validateTradingSnapshot(
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

    func recordTradingSnapshotUpload(
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

    func flushPendingTradingSnapshotDeletions() async {
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
}
