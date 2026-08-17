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

/// Peer signal that a device settled a day's conflict. The resolving device
/// uploads one after settling; a device that still holds a stale pending record
/// for the day clears it automatically once the live remote content matches
/// `settledHash` (i.e. the day has converged to the settled version). Markers
/// are tiny, best-effort, and GC'd after `tombstoneRetention`.
public struct JournalSettlementMarker: Codable, Equatable {
    public var dayKey: String
    /// Hash of the day content the remote holds after the settlement.
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

/// What this device last agreed on for one day.
public struct DaySyncState: Codable, Equatable {
    /// Hash of the local entry at last sync; nil means "known to be absent locally".
    public var localHash: String?
    public var remoteRev: String?
    public var remoteContentHash: String?
    /// Rev of the remote tombstone already processed; prevents re-processing.
    public var tombstoneRev: String?
    public var tombstoneDeletedAt: Date?
    /// When the user settled this day's conflict with a specific local version
    /// ("keep local"), the next cycle propagates exactly this hash (push
    /// priority, no re-merge) instead of treating it as a plain local edit.
    public var settledPushHash: String?
    /// When the user chose "keep remote", the next cycle adopts whatever is on
    /// the remote right now (pull priority, no re-merge). The recorded
    /// snapshot may be stale, so we follow the live remote instead.
    public var settleAdoptRemote: Bool
    /// Hash of the version this device settled on when nothing needs pushing
    /// ("keep merged" / dismiss — the merge is already applied and uploaded).
    /// The next cycle uploads a settlement marker so peers drop their stale
    /// reminders for the day.
    public var settleMarkHash: String?

    public init(
        localHash: String? = nil,
        remoteRev: String? = nil,
        remoteContentHash: String? = nil,
        tombstoneRev: String? = nil,
        tombstoneDeletedAt: Date? = nil,
        settledPushHash: String? = nil,
        settleAdoptRemote: Bool = false,
        settleMarkHash: String? = nil
    ) {
        self.localHash = localHash
        self.remoteRev = remoteRev
        self.remoteContentHash = remoteContentHash
        self.tombstoneRev = tombstoneRev
        self.tombstoneDeletedAt = tombstoneDeletedAt
        self.settledPushHash = settledPushHash
        self.settleAdoptRemote = settleAdoptRemote
        self.settleMarkHash = settleMarkHash
    }

    public enum CodingKeys: String, CodingKey {
        case localHash, remoteRev, remoteContentHash
        case tombstoneRev, tombstoneDeletedAt
        case settledPushHash, settleAdoptRemote, settleMarkHash
    }

    /// Newer fields decode with defaults so state files written by older
    /// builds keep loading.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        localHash = try container.decodeIfPresent(String.self, forKey: .localHash)
        remoteRev = try container.decodeIfPresent(String.self, forKey: .remoteRev)
        remoteContentHash = try container.decodeIfPresent(String.self, forKey: .remoteContentHash)
        tombstoneRev = try container.decodeIfPresent(String.self, forKey: .tombstoneRev)
        tombstoneDeletedAt = try container.decodeIfPresent(Date.self, forKey: .tombstoneDeletedAt)
        settledPushHash = try container.decodeIfPresent(String.self, forKey: .settledPushHash)
        settleAdoptRemote = try container.decodeIfPresent(Bool.self, forKey: .settleAdoptRemote) ?? false
        settleMarkHash = try container.decodeIfPresent(String.self, forKey: .settleMarkHash)
    }
}

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

/// Loads/saves per-journal state files inside a device-local directory.
public struct JournalSyncStateStore {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func stateURL(for journalID: UUID) -> URL {
        directory.appendingPathComponent("\(journalID.uuidString.lowercased()).json")
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
}
