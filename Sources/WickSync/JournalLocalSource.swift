import Foundation

/// The sync engine's view of the local journal store.
///
/// Implemented by `JournalStore` on macOS (and by a future iOS store). All calls
/// run on the main actor, matching the store's own isolation. The engine uses
/// this boundary to stay platform- and persistence-agnostic: it only ever sees
/// day-keyed entries and content-addressed images.
@MainActor
public protocol JournalLocalSource: AnyObject {
    /// Identity of the journal currently exposed for syncing; nil while no
    /// journal is active (engine idles in that case).
    var syncJournalID: UUID? { get }
    var syncJournalName: String { get }
    /// False while the store is in read-only load-failure protection — the
    /// engine must treat every mutation as a no-op in that state.
    var syncIsWritable: Bool { get }

    /// All locally present days keyed by `JournalEntry.dayKey`. When (corrupt
    /// legacy) duplicates share a day key, the newest `updatedAt` wins.
    func syncDaySnapshots() -> [String: JournalEntry]

    /// Inserts or replaces the day with the same day key. Must not bump
    /// `updatedAt` (the remote timestamp drives last-writer-wins decisions).
    func applySyncedEntry(_ entry: JournalEntry)

    /// Removes the day with the given key together with its image files.
    func removeSyncedDay(dayKey: String)

    /// Image filenames referenced by any local entry.
    func syncedImageFilenames() -> Set<String>
    func syncedImageData(filename: String) -> Data?
    func hasSyncedImage(filename: String) -> Bool
    /// Stores image bytes under an existing referenced filename (no renaming —
    /// filenames are content-addressed UUIDs chosen at import time).
    func storeSyncedImage(filename: String, data: Data)
}
