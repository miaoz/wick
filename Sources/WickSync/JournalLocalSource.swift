import Foundation

/// Typed notification that a remote entry was successfully applied.
/// Editors observe this to rebase their (clean) drafts onto the new store value.
public struct JournalRemoteApply: Sendable, Equatable {
    public let journalID: UUID
    public let entryID: UUID

    public init(journalID: UUID, entryID: UUID) {
        self.journalID = journalID
        self.entryID = entryID
    }
}

public extension Notification.Name {
    /// Posted to ask editors to commit their drafts immediately (before a
    /// remote day apply or a journal switch). Shared by the macOS and iOS
    /// stores so both editor implementations use the same flush protocol.
    static let wickWillFlushJournalDrafts = Notification.Name("wick.willFlushJournalDrafts")
}

/// One remote-sourced change collected during a sync cycle. The engine applies
/// a whole cycle's worth as a single `applySyncedChanges` batch so a first pull
/// of N days does constant-time full-snapshot persistence instead of N.
///
/// Each mutation carries the canonical hash of the local entry at decision time
/// (nil = locally absent). The store re-verifies against it right before
/// committing, so a mid-cycle edit skips the stale mutation (AC-P1-05).
public enum JournalSyncMutation: Sendable, Equatable {
    case upsert(JournalEntry, expectedLocalHash: String?)
    case remove(entryID: UUID, expectedLocalHash: String?)

    public var entryID: UUID {
        switch self {
        case .upsert(let entry, _):
            return entry.id
        case .remove(let entryID, _):
            return entryID
        }
    }

    public var expectedLocalHash: String? {
        switch self {
        case .upsert(_, let hash):
            return hash
        case .remove(_, let hash):
            return hash
        }
    }
}

/// Versioned cloud document for an optional, journal-scoped trading snapshot.
/// `payload` stays opaque to WickSync so the journal sync target does not
/// depend on WickTrading's exchange models. It must never contain credentials.
public struct JournalTradingSnapshotDocument: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var journalID: UUID
    public var venue: String
    public var accountLabel: String
    public var fetchedAtMilliseconds: Int64
    public var payload: Data

    public var fetchedAt: Date {
        Date(timeIntervalSince1970: Double(fetchedAtMilliseconds) / 1_000)
    }

    public init(
        formatVersion: Int = currentFormatVersion,
        journalID: UUID,
        venue: String,
        accountLabel: String,
        fetchedAt: Date,
        payload: Data
    ) {
        self.formatVersion = formatVersion
        self.journalID = journalID
        self.venue = venue
        self.accountLabel = accountLabel
        fetchedAtMilliseconds = Int64((fetchedAt.timeIntervalSince1970 * 1_000).rounded())
        self.payload = payload
    }
}

public struct JournalTradingSnapshotTombstone: Codable, Equatable, Sendable {
    public var journalID: UUID
    public var deletedAtMilliseconds: Int64
    public var deviceID: String

    public var deletedAt: Date {
        Date(timeIntervalSince1970: Double(deletedAtMilliseconds) / 1_000)
    }

    public init(journalID: UUID, deletedAt: Date = Date(), deviceID: String) {
        self.journalID = journalID
        deletedAtMilliseconds = Int64((deletedAt.timeIntervalSince1970 * 1_000).rounded())
        self.deviceID = deviceID
    }
}

/// The sync engine's view of the local journal store.
///
/// Implemented by `JournalStore` on macOS (and by a future iOS store). All calls
/// run on the main actor, matching the store's own isolation. The engine uses
/// this boundary to stay platform- and persistence-agnostic: it only ever sees
/// UUID-keyed entries and content-addressed images.
@MainActor
public protocol JournalLocalSource: AnyObject {
    /// Identity of the journal currently exposed for syncing; nil while no
    /// journal is active (engine idles in that case).
    var syncJournalID: UUID? { get }
    var syncJournalName: String { get }
    /// False while the store is in read-only load-failure protection — the
    /// engine must treat every mutation as a no-op in that state.
    var syncIsWritable: Bool { get }

    /// All locally present entries keyed by their permanent UUID identity.
    func syncEntrySnapshots() -> [UUID: JournalEntry]

    /// The locally present entry with this UUID, or nil when absent. A
    /// single-point read: unlike `syncEntrySnapshots()` this must NOT copy the
    /// whole journal, because the sync engine calls it per-entry on the
    /// freshness path (SY-09 — an O(N) snapshot per decision is O(N²) a cycle).
    /// It still reads the freshest on-disk state on every call (ED-01).
    func syncEntrySnapshot(entryID: UUID) -> JournalEntry?

    /// Called before a remote entry apply so the platform can commit any
    /// in-flight editor draft for that entry. The engine runs this BEFORE its
    /// freshness check: once the draft is on disk, re-hashing the entry shows
    /// whether the user edited mid-cycle, and the apply is skipped if so
    /// (the next cycle then merges instead of clobbering).
    func prepareForRemoteApply(entryID: UUID)

    /// Applies a whole cycle's remote-sourced changes in ONE pass: the store
    /// does a single sort, selection reconcile, persist, catalog touch, and UI
    /// publish (instead of one full-snapshot write per entry). Must not bump
    /// `updatedAt` (the remote timestamp drives last-writer-wins decisions).
    /// No-op when `journalID` is not the currently active journal.
    ///
    /// Each mutation is re-verified against its `expectedLocalHash` right
    /// before committing; an entry edited since the decision is skipped. Returns
    /// the entry ids actually applied so the engine only advances baselines for
    /// those (AC-P1-05).
    @discardableResult
    func applySyncedChanges(_ changes: [JournalSyncMutation], journalID: UUID) -> Set<UUID>

    /// Inserts or replaces the entry with the same UUID. Must not bump
    /// `updatedAt` (the remote timestamp drives last-writer-wins decisions).
    /// No-op when `journalID` is not the currently active journal — a cycle
    /// that outlives a user switch must not write the previous journal's
    /// remote entries into the one now on screen.
    func applySyncedEntry(_ entry: JournalEntry, journalID: UUID)

    /// Removes the entry with the given UUID together with its image files.
    /// Same active-journal guard as `applySyncedEntry`.
    func removeSyncedEntry(entryID: UUID, journalID: UUID)

    /// Renames the journal identified by `journalID` to the remote manifest's
    /// name and returns the name actually applied (stores may uniquify on
    /// collision with another local journal). The engine records the returned
    /// name as the new rename baseline, so the result must stay stable across
    /// cycles. No-op when `journalID` is not currently active.
    @discardableResult
    func applySyncedJournalName(_ name: String, journalID: UUID) -> String

    /// Image filenames referenced by any local entry.
    func syncedImageFilenames() -> Set<String>
    func syncedImageData(filename: String) -> Data?
    func hasSyncedImage(filename: String) -> Bool
    /// Stores image bytes under an existing referenced filename (no renaming —
    /// filenames are content-addressed UUIDs chosen at import time).
    /// Same active-journal guard as `applySyncedEntry`.
    func storeSyncedImage(filename: String, data: Data, journalID: UUID)

    /// Optional Dropbox transport for derived trading data. The setting is
    /// deliberately off by default; disabling it leaves any remote snapshot
    /// untouched and performs no upload or download.
    var syncTradingSnapshotEnabled: Bool { get }
    func syncedTradingSnapshot(journalID: UUID) -> JournalTradingSnapshotDocument?
    func applySyncedTradingSnapshot(_ document: JournalTradingSnapshotDocument, journalID: UUID)
    func removeSyncedTradingSnapshot(journalID: UUID)
}

public extension JournalLocalSource {
    var syncTradingSnapshotEnabled: Bool { false }

    func syncedTradingSnapshot(journalID: UUID) -> JournalTradingSnapshotDocument? {
        nil
    }

    func applySyncedTradingSnapshot(_ document: JournalTradingSnapshotDocument, journalID: UUID) {}

    func removeSyncedTradingSnapshot(journalID: UUID) {}
}
