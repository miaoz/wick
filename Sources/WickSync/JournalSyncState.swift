import Foundation

// MARK: - Remote layout

/// Paths inside the cloud app folder:
///   /journals/<uuid>/
///     manifest.json               format gate + journal identity (renames
///                                 propagate by rewriting it, rev-guarded)
///     days/<dayKey>.json          one canonical JournalEntry per file
///     images/<uuid>.png|jpg|...   content-addressed, immutable
///     tombstones/<dayKey>.json    deletion marker (GC'd after retention)
///     conflicts/<dayKey>-<ts>.json  losing side of an item-level conflict
///     settlements/<dayKey>-….json  conflict-settlement marker for peers
///   /journal-tombstones/<uuid>.json  journal-level deletion marker - lives
///                                 OUTSIDE the journal folder so deleting the
///                                 folder cannot take the marker with it
public enum JournalSyncLayout {
    public static let formatVersion = 1
    public static let tombstoneRetention: TimeInterval = 30 * 24 * 3600

    public static func journalRoot(for journalID: UUID) -> String {
        "/journals/\(journalID.uuidString.lowercased())"
    }

    public static func manifestPath(for journalID: UUID) -> String {
        "\(journalRoot(for: journalID))/manifest.json"
    }

    public static func dayPath(for journalID: UUID, dayKey: String) -> String {
        "\(journalRoot(for: journalID))/days/\(dayKey).json"
    }

    public static func imagePath(for journalID: UUID, filename: String) -> String {
        "\(journalRoot(for: journalID))/images/\(filename)"
    }

    public static func tombstonePath(for journalID: UUID, dayKey: String) -> String {
        "\(journalRoot(for: journalID))/tombstones/\(dayKey).json"
    }

    /// Deletion marker for a whole journal: `/journal-tombstones/<uuid>.json`.
    public static func journalTombstonePath(for journalID: UUID) -> String {
        "/journal-tombstones/\(journalID.uuidString.lowercased()).json"
    }

    /// Extracts the journal id from a `/journal-tombstones/<uuid>.json` path,
    /// nil for anything else.
    public static func journalTombstoneID(from path: String) -> UUID? {
        guard path.hasPrefix("/journal-tombstones/"), path.hasSuffix(".json") else { return nil }
        let middle = path.dropFirst("/journal-tombstones/".count).dropLast(".json".count)
        return UUID(uuidString: String(middle))
    }

    /// A settlement marker file for a day: `settlements/<dayKey>-<stamp>-<uuid>.json`.
    /// Uploaded by the device that resolved the day's conflict; other devices use
    /// it to drop their stale pending-conflict records without manual action.
    public static func settlementPath(for journalID: UUID, dayKey: String, stamp: Date, uniqueID: UUID = UUID()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let suffix = uniqueID.uuidString.prefix(8)
        return "\(journalRoot(for: journalID))/settlements/\(dayKey)-\(formatter.string(from: stamp))-\(suffix).json"
    }

    /// Extracts the day key from a settlements/ path, nil for anything else.
    public static func settlementDayKey(from path: String, journalID: UUID) -> String? {
        let prefix = "\(journalRoot(for: journalID))/settlements/"
        guard path.hasPrefix(prefix), path.hasSuffix(".json") else { return nil }
        let key = path.dropFirst(prefix.count).dropLast(".json".count)
        guard key.range(of: #"^\d{4}-\d{2}-\d{2}-"#, options: .regularExpression) != nil else { return nil }
        return String(key.prefix(10))
    }

    /// True for any file inside `settlements/` (used by marker GC).
    public static func isSettlementPath(_ path: String, journalID: UUID) -> Bool {
        path.hasPrefix("\(journalRoot(for: journalID))/settlements/") && path.hasSuffix(".json")
    }

    public static func conflictPath(for journalID: UUID, dayKey: String, stamp: Date, uniqueID: UUID = UUID()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        // The unique suffix keeps two same-second archives (e.g. two devices
        // merging the same day) from colliding on one remote path.
        let suffix = uniqueID.uuidString.prefix(8)
        return "\(journalRoot(for: journalID))/conflicts/\(dayKey)-\(formatter.string(from: stamp))-\(suffix).json"
    }

    /// Extracts the day key from a remote days/ path, nil for anything else.
    public static func dayKey(fromDayPath path: String, journalID: UUID) -> String? {
        let prefix = "\(journalRoot(for: journalID))/days/"
        guard path.hasPrefix(prefix), path.hasSuffix(".json") else { return nil }
        let key = path.dropFirst(prefix.count).dropLast(".json".count)
        return key.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
            ? String(key)
            : nil
    }
}

// MARK: - Remote documents

/// Written once per journal by whichever device syncs first; every other device
/// refuses to write when its format is newer than what this app understands.
public struct JournalSyncManifest: Codable, Equatable {
    public var formatVersion: Int
    public var journalID: UUID
    public var journalName: String
    public var createdAt: Date
    public var deviceID: String

    public init(formatVersion: Int, journalID: UUID, journalName: String, createdAt: Date, deviceID: String) {
        self.formatVersion = formatVersion
        self.journalID = journalID
        self.journalName = journalName
        self.createdAt = createdAt
        self.deviceID = deviceID
    }
}

/// Deletion marker — the only way a day delete propagates. A missing day file
/// without a tombstone is treated as an accident and re-uploaded, never mirrored.
public struct JournalTombstone: Codable, Equatable {
    public var schemaVersion: Int
    public var dayKey: String
    public var deletedAt: Date
    public var deviceID: String

    public init(dayKey: String, deletedAt: Date, deviceID: String) {
        self.schemaVersion = 1
        self.dayKey = dayKey
        self.deletedAt = deletedAt
        self.deviceID = deviceID
    }
}

/// Deletion marker for a whole journal - the journal-level analogue of
/// `JournalTombstone`. Deleting a journal locally propagates by uploading this
/// marker (outside the journal folder) and then deleting the folder; peers
/// that see the marker remove their local copy and never re-discover or
/// re-import the journal. A missing folder without a marker is an accident
/// and healed by re-upload, exactly like a missing day file.
public struct JournalDeletionTombstone: Codable, Equatable {
    public var schemaVersion: Int
    public var journalID: UUID
    public var deletedAt: Date
    public var deviceID: String

    public init(journalID: UUID, deletedAt: Date, deviceID: String) {
        self.schemaVersion = 1
        self.journalID = journalID
        self.deletedAt = deletedAt
        self.deviceID = deviceID
    }
}

/// Peer signal that a device settled a day's conflict. The resolving device
/// uploads one after settling; a device that still holds a stale pending record
/// for the day clears it automatically once the remote day content hashes (in
/// the local canonical convention - never backend metadata hashes) to
/// `settledHash`. Markers are tiny, best-effort, and GC'd after
/// `tombstoneRetention`.
public struct JournalSettlementMarker: Codable, Equatable {
    public var dayKey: String
    /// Canonical hash of the day content the remote holds after the settlement.
    public var settledHash: String
    public var deviceID: String
    public var stamp: Date

    public init(dayKey: String, settledHash: String, deviceID: String, stamp: Date) {
        self.dayKey = dayKey
        self.settledHash = settledHash
        self.deviceID = deviceID
        self.stamp = stamp
    }
}

/// Losing side of an item-level conflict, archived remotely until the user
/// settles the conflict (keep local/remote/merged); once settled, the next
/// sync cycle deletes the archive - the chosen version supersedes it.
public struct JournalConflictPayload: Codable, Equatable {
    public var dayKey: String
    public var detectedAt: Date
    public var deviceID: String
    public var reason: String
    public var losingItems: [JournalItem]
    public var losingTitle: String?

    public init(
        dayKey: String,
        detectedAt: Date,
        deviceID: String,
        reason: String,
        losingItems: [JournalItem],
        losingTitle: String?
    ) {
        self.dayKey = dayKey
        self.detectedAt = detectedAt
        self.deviceID = deviceID
        self.reason = reason
        self.losingItems = losingItems
        self.losingTitle = losingTitle
    }
}

// MARK: - Per-device sync state (never synced itself)

/// How the user settled a day's conflict. Recorded in `DaySyncState` and
/// executed authoritatively by the next sync cycle - the decision bypasses
/// the divergence matrix so it can never re-record the conflict it resolves.
public enum DaySettlement: Codable, Equatable {
    /// "Keep local": canonical hash of the chosen version; the next cycle
    /// pushes exactly this content (overwriting whatever is remote).
    case pushSettled(String)
    /// "Keep remote": the next cycle adopts whatever is on the remote right
    /// now (the recorded snapshot may be stale, so the live content wins).
    case adoptRemote
    /// "Keep merged" / dismiss: the chosen version is already local+remote;
    /// the next cycle only uploads a settlement marker for peers.
    case markSettled(String)
}

/// What this device last agreed on for one day.
///
/// Hash conventions are strictly one-sided and never cross-compared:
/// - `localHash` / `remoteContentHash` / `pushedHashes` are canonical hashes
///   computed locally over canonical JSON (never Dropbox `content_hash`
///   metadata, which uses a different algorithm and can never match);
/// - remote change detection uses `remoteRev` only - the device's own
///   uploads record the rev the server returned, so the delta echo of a
///   self-write carries the same rev and reads as "unchanged".
public struct DaySyncState: Codable, Equatable {
    /// Canonical hash of the local entry at last sync; nil means "known to be absent locally".
    public var localHash: String?
    public var remoteRev: String?
    /// Canonical hash of the remote day content as last known from bytes this
    /// device itself pushed or downloaded (settlement markers compare against this).
    public var remoteContentHash: String?
    /// Rev of the remote tombstone already processed; prevents re-processing.
    public var tombstoneRev: String?
    public var tombstoneDeletedAt: Date?
    /// Recent canonical hashes this device pushed for the day (newest last,
    /// capped). The delta echo of an older own push racing newer local edits
    /// must converge by re-pushing local, never by merging against itself.
    public var pushedHashes: [String]
    /// User's pending conflict decision for the day, executed next cycle.
    public var settlement: DaySettlement?

    public init(
        localHash: String? = nil,
        remoteRev: String? = nil,
        remoteContentHash: String? = nil,
        tombstoneRev: String? = nil,
        tombstoneDeletedAt: Date? = nil,
        pushedHashes: [String] = [],
        settlement: DaySettlement? = nil
    ) {
        self.localHash = localHash
        self.remoteRev = remoteRev
        self.remoteContentHash = remoteContentHash
        self.tombstoneRev = tombstoneRev
        self.tombstoneDeletedAt = tombstoneDeletedAt
        self.pushedHashes = pushedHashes
        self.settlement = settlement
    }

    public enum CodingKeys: String, CodingKey {
        case localHash, remoteRev, remoteContentHash
        case tombstoneRev, tombstoneDeletedAt
        case pushedHashes, settlement
        // Legacy keys written by pre-settlement-enum builds (decoded, never re-encoded).
        case settledPushHash, settleAdoptRemote, settleMarkHash
    }

    /// Newer fields decode with defaults so state files written by older
    /// builds keep loading; the three legacy settlement fields migrate into
    /// the `settlement` enum so an in-flight resolution survives an upgrade.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        localHash = try container.decodeIfPresent(String.self, forKey: .localHash)
        remoteRev = try container.decodeIfPresent(String.self, forKey: .remoteRev)
        remoteContentHash = try container.decodeIfPresent(String.self, forKey: .remoteContentHash)
        tombstoneRev = try container.decodeIfPresent(String.self, forKey: .tombstoneRev)
        tombstoneDeletedAt = try container.decodeIfPresent(Date.self, forKey: .tombstoneDeletedAt)
        pushedHashes = try container.decodeIfPresent([String].self, forKey: .pushedHashes) ?? []
        if let settlement = try? container.decodeIfPresent(DaySettlement.self, forKey: .settlement) {
            self.settlement = settlement
        } else if let pushHash = try container.decodeIfPresent(String.self, forKey: .settledPushHash) {
            settlement = .pushSettled(pushHash)
        } else if try container.decodeIfPresent(Bool.self, forKey: .settleAdoptRemote) == true {
            settlement = .adoptRemote
        } else if let markHash = try container.decodeIfPresent(String.self, forKey: .settleMarkHash) {
            settlement = .markSettled(markHash)
        } else {
            settlement = nil
        }
    }

    /// Encodes only current properties (the legacy keys above exist for
    /// decoding old state files and must not re-appear in written ones).
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(localHash, forKey: .localHash)
        try container.encodeIfPresent(remoteRev, forKey: .remoteRev)
        try container.encodeIfPresent(remoteContentHash, forKey: .remoteContentHash)
        try container.encodeIfPresent(tombstoneRev, forKey: .tombstoneRev)
        try container.encodeIfPresent(tombstoneDeletedAt, forKey: .tombstoneDeletedAt)
        try container.encode(pushedHashes, forKey: .pushedHashes)
        try container.encodeIfPresent(settlement, forKey: .settlement)
    }
}

/// Server-reported file identity. `contentHash` is the backend's own hashing
/// convention (Dropbox hashes concatenated per-block digests) - treat it as
/// opaque; it is never comparable with locally computed canonical hashes.
public struct RemoteFileRecord: Codable, Equatable {
    public var rev: String
    public var contentHash: String?

    public init(rev: String, contentHash: String?) {
        self.rev = rev
        self.contentHash = contentHash
    }
}

/// A conflict the local user has not resolved yet. Item-content conflicts
/// carry all three day versions - pre-merge local, remote, and the merged
/// result that was applied - so the user can inspect them and pick a winner
/// (`resolveConflict`). Structural conflicts (delete-vs-edit and friends)
/// have no meaningful choice and only carry the summary.
public struct SyncConflictRecord: Codable, Equatable, Identifiable {
    public var id: UUID
    public var dayKey: String
    /// Remote path of the archived losing side.
    public var remotePath: String
    public var summary: String
    public var detectedAt: Date
    /// Local version before the merge (item-content conflicts only).
    public var localEntry: JournalEntry?
    public var remoteEntry: JournalEntry?
    /// The merged version that was applied locally and uploaded.
    public var mergedEntry: JournalEntry?

    public init(
        id: UUID = UUID(),
        dayKey: String,
        remotePath: String,
        summary: String,
        detectedAt: Date,
        localEntry: JournalEntry? = nil,
        remoteEntry: JournalEntry? = nil,
        mergedEntry: JournalEntry? = nil
    ) {
        self.id = id
        self.dayKey = dayKey
        self.remotePath = remotePath
        self.summary = summary
        self.detectedAt = detectedAt
        self.localEntry = localEntry
        self.remoteEntry = remoteEntry
        self.mergedEntry = mergedEntry
    }

    /// True when the record carries both pre-merge versions and a choice
    /// between them (and the merged result) makes sense.
    public var offersChoice: Bool {
        localEntry != nil && remoteEntry != nil
    }
}

/// A journal found on the remote that this device may not have locally.
/// Cached (with its rev) so discovery survives relaunches without re-downloading.
public struct DiscoveredJournalRecord: Codable, Equatable {
    public var manifest: JournalSyncManifest
    public var manifestRev: String

    public init(manifest: JournalSyncManifest, manifestRev: String) {
        self.manifest = manifest
        self.manifestRev = manifestRev
    }
}

/// Whole per-journal sync state, persisted locally as JSON.
public struct JournalSyncState: Codable, Equatable {
    public var cursor: String?
    /// This device's view of the remote file set (path -> record), maintained
    /// from full listings + cursor deltas.
    public var remoteFiles: [String: RemoteFileRecord]
    public var days: [String: DaySyncState]
    public var pendingConflicts: [SyncConflictRecord]
    /// Remote `conflicts/` archives whose conflict was settled - deleted on
    /// the next cycle. Queued (not deleted inline) so offline resolutions
    /// survive relaunches.
    public var pendingConflictCleanups: [String]
    public var manifestRev: String?
    /// Journal name this device last agreed on with the remote manifest - the
    /// baseline rename detection compares `syncJournalName` against. Nil in
    /// state files written before journal names synced (seeded once from the
    /// remote manifest on the first cycle of a rename-capable build).
    public var manifestName: String?
    public var lastSyncAt: Date?
    /// Manifests of OTHER journals found on the remote (journalID -> record),
    /// used to offer adoption on this device.
    public var discoveredJournals: [String: DiscoveredJournalRecord]

    public init(
        cursor: String? = nil,
        remoteFiles: [String: RemoteFileRecord] = [:],
        days: [String: DaySyncState] = [:],
        pendingConflicts: [SyncConflictRecord] = [],
        pendingConflictCleanups: [String] = [],
        manifestRev: String? = nil,
        manifestName: String? = nil,
        lastSyncAt: Date? = nil,
        discoveredJournals: [String: DiscoveredJournalRecord] = [:]
    ) {
        self.cursor = cursor
        self.remoteFiles = remoteFiles
        self.days = days
        self.pendingConflicts = pendingConflicts
        self.pendingConflictCleanups = pendingConflictCleanups
        self.manifestRev = manifestRev
        self.manifestName = manifestName
        self.lastSyncAt = lastSyncAt
        self.discoveredJournals = discoveredJournals
    }

    public enum CodingKeys: String, CodingKey {
        case cursor, remoteFiles, days, pendingConflicts, pendingConflictCleanups
        case manifestRev, manifestName, lastSyncAt, discoveredJournals
    }

    /// Everything except `cursor`/`manifestRev`/`manifestName` decodes with a
    /// default so state files written by older builds keep loading as fields
    /// are added.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cursor = try container.decodeIfPresent(String.self, forKey: .cursor)
        remoteFiles = try container.decodeIfPresent([String: RemoteFileRecord].self, forKey: .remoteFiles) ?? [:]
        days = try container.decodeIfPresent([String: DaySyncState].self, forKey: .days) ?? [:]
        pendingConflicts = try container.decodeIfPresent([SyncConflictRecord].self, forKey: .pendingConflicts) ?? []
        pendingConflictCleanups = try container.decodeIfPresent([String].self, forKey: .pendingConflictCleanups) ?? []
        manifestRev = try container.decodeIfPresent(String.self, forKey: .manifestRev)
        manifestName = try container.decodeIfPresent(String.self, forKey: .manifestName)
        lastSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncAt)
        discoveredJournals = try container.decodeIfPresent([String: DiscoveredJournalRecord].self, forKey: .discoveredJournals) ?? [:]
    }
}

/// Device-scoped sync state shared by ALL journals of this device, persisted
/// as `device.json` next to the per-journal state files. Owns journal-level
/// deletion propagation: a journal deleted locally has its per-journal state
/// cleared, so the pending remote deletion must live somewhere that survives it.
public struct JournalDeviceSyncState: Codable, Equatable {
    /// Locally deleted journals awaiting their remote tombstone + folder
    /// cleanup (flushed by the next cycle; survives offline deletions and
    /// relaunches).
    public var pendingJournalDeletions: [JournalDeletionTombstone]
    /// Peer tombstones detected and published to the app (`remoteJournalDeletions`)
    /// but not yet acknowledged - republished after a restart so a crash
    /// between detection and the local removal cannot drop the deletion.
    public var unackedRemoteDeletions: [UUID]
    /// Journal tombstones this device has fully processed (its own deletions
    /// plus acknowledged peer deletions). Suppresses rediscovery/reimport.
    public var processedJournalTombstones: [UUID]

    public init(
        pendingJournalDeletions: [JournalDeletionTombstone] = [],
        unackedRemoteDeletions: [UUID] = [],
        processedJournalTombstones: [UUID] = []
    ) {
        self.pendingJournalDeletions = pendingJournalDeletions
        self.unackedRemoteDeletions = unackedRemoteDeletions
        self.processedJournalTombstones = processedJournalTombstones
    }

    public enum CodingKeys: String, CodingKey {
        case pendingJournalDeletions, unackedRemoteDeletions, processedJournalTombstones
    }

    /// Fields decode with defaults so files written by older builds keep loading.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pendingJournalDeletions = try container.decodeIfPresent([JournalDeletionTombstone].self, forKey: .pendingJournalDeletions) ?? []
        unackedRemoteDeletions = try container.decodeIfPresent([UUID].self, forKey: .unackedRemoteDeletions) ?? []
        processedJournalTombstones = try container.decodeIfPresent([UUID].self, forKey: .processedJournalTombstones) ?? []
    }

    /// True when a journal's deletion must not surface anywhere on this device
    /// (discovery, auto-import, active syncing).
    public func isTombstoned(_ journalID: UUID) -> Bool {
        processedJournalTombstones.contains(journalID)
            || unackedRemoteDeletions.contains(journalID)
            || pendingJournalDeletions.contains { $0.journalID == journalID }
    }
}

/// Loads/saves per-journal state files inside a device-local directory.
public struct JournalSyncStateStore {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func stateURL(for journalID: UUID) -> URL {
        directory.appendingPathComponent("\(journalID.uuidString.lowercased()).json")
    }

    /// True when this device has ever synced the journal - the signal that a
    /// local deletion of it must propagate to the remote.
    public func stateExists(for journalID: UUID) -> Bool {
        FileManager.default.fileExists(atPath: stateURL(for: journalID).path)
    }

    public func load(for journalID: UUID) -> JournalSyncState {
        let url = stateURL(for: journalID)
        guard let data = try? Data(contentsOf: url),
              let state = try? JournalSyncEncoding.decoder.decode(JournalSyncState.self, from: data)
        else {
            return JournalSyncState()
        }
        return state
    }

    public func save(_ state: JournalSyncState, for journalID: UUID) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JournalSyncEncoding.encoder.encode(state)
            try data.write(to: stateURL(for: journalID), options: .atomic)
        } catch {
            NSLog("Wick sync state save failed: \(error.localizedDescription)")
        }
    }

    /// Drops all stored state for a journal (used when it is (re-)imported
    /// from the remote: a stale baseline would misread the empty local copy
    /// as "deleted everywhere" and tombstone the remote content).
    public func clear(for journalID: UUID) {
        try? FileManager.default.removeItem(at: stateURL(for: journalID))
    }

    // MARK: Device-scoped state (journal deletion propagation)

    private var deviceStateURL: URL {
        directory.appendingPathComponent("device.json")
    }

    public func loadDeviceState() -> JournalDeviceSyncState {
        guard let data = try? Data(contentsOf: deviceStateURL),
              let state = try? JournalSyncEncoding.decoder.decode(JournalDeviceSyncState.self, from: data)
        else {
            return JournalDeviceSyncState()
        }
        return state
    }

    public func saveDeviceState(_ state: JournalDeviceSyncState) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JournalSyncEncoding.encoder.encode(state)
            try data.write(to: deviceStateURL, options: .atomic)
        } catch {
            NSLog("Wick sync device state save failed: \(error.localizedDescription)")
        }
    }
}
