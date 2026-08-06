import Foundation

// MARK: - Remote layout

/// Paths inside the cloud app folder:
///   /journals/<uuid>/
///     manifest.json               format gate + journal identity
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

    public static func conflictPath(for journalID: UUID, dayKey: String, stamp: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(journalRoot(for: journalID))/conflicts/\(dayKey)-\(formatter.string(from: stamp)).json"
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

/// Archived losing side of an item-level conflict (both versions kept forever).
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

    public init(
        localHash: String? = nil,
        remoteRev: String? = nil,
        remoteContentHash: String? = nil,
        tombstoneRev: String? = nil,
        tombstoneDeletedAt: Date? = nil
    ) {
        self.localHash = localHash
        self.remoteRev = remoteRev
        self.remoteContentHash = remoteContentHash
        self.tombstoneRev = tombstoneRev
        self.tombstoneDeletedAt = tombstoneDeletedAt
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

/// A conflict the local user has not dismissed yet.
public struct SyncConflictRecord: Codable, Equatable, Identifiable {
    public var id: UUID
    public var dayKey: String
    /// Remote path of the archived losing side.
    public var remotePath: String
    public var summary: String
    public var detectedAt: Date

    public init(id: UUID = UUID(), dayKey: String, remotePath: String, summary: String, detectedAt: Date) {
        self.id = id
        self.dayKey = dayKey
        self.remotePath = remotePath
        self.summary = summary
        self.detectedAt = detectedAt
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
    /// This device's view of the remote file set (path → record), maintained
    /// from full listings + cursor deltas.
    public var remoteFiles: [String: RemoteFileRecord]
    public var days: [String: DaySyncState]
    public var pendingConflicts: [SyncConflictRecord]
    public var manifestRev: String?
    public var lastSyncAt: Date?
    /// Manifests of OTHER journals found on the remote (journalID → record),
    /// used to offer adoption on this device.
    public var discoveredJournals: [String: DiscoveredJournalRecord]

    public init(
        cursor: String? = nil,
        remoteFiles: [String: RemoteFileRecord] = [:],
        days: [String: DaySyncState] = [:],
        pendingConflicts: [SyncConflictRecord] = [],
        manifestRev: String? = nil,
        lastSyncAt: Date? = nil,
        discoveredJournals: [String: DiscoveredJournalRecord] = [:]
    ) {
        self.cursor = cursor
        self.remoteFiles = remoteFiles
        self.days = days
        self.pendingConflicts = pendingConflicts
        self.manifestRev = manifestRev
        self.lastSyncAt = lastSyncAt
        self.discoveredJournals = discoveredJournals
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
