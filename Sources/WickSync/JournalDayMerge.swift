import Foundation

/// Outcome of merging two device versions of the same journal day.
public struct JournalDayMergeResult: Equatable {
    /// The union entry both devices should converge to.
    public var merged: JournalEntry
    /// Same-item-id conflicts whose contents differed — the losing copies.
    /// Surfaced to the user (and archived remotely) so nothing vanishes silently.
    public var losingItems: [JournalItem]
    /// The discarded title when both sides had different non-empty titles.
    public var losingTitle: String?
}

/// Merges two versions of one day (same `dayKey`) that diverged on two devices.
///
/// Rules (deterministic so all devices converge to the same result):
/// - Entry identity (id/date/dayKey) comes from the older entry by `createdAt`.
/// - Items are unioned by item id — the data model's one-day-many-items shape
///   means concurrent edits usually touch different items and merge cleanly.
/// - Same item id with different contents: the side with the newer
///   `entry.updatedAt` wins; the loser is preserved in `losingItems`.
/// - Title: identical or one-sided-empty resolves trivially; two different
///   non-empty titles go to the newer side, loser recorded in `losingTitle`.
public enum JournalDayMerge {
    public static func merge(local: JournalEntry, remote: JournalEntry) -> JournalDayMergeResult {
        let localIsBase = local.createdAt <= remote.createdAt
        let base = localIsBase ? local : remote
        let other = localIsBase ? remote : local
        // Newer side wins per-item conflicts; exact ties go to local (the rev
        // race afterwards converges devices even if they pick differently).
        let localWinsConflicts = local.updatedAt >= remote.updatedAt

        var itemsByID: [UUID: JournalItem] = [:]
        var order: [UUID] = []
        for item in base.items {
            itemsByID[item.id] = item
            order.append(item.id)
        }

        var losingItems: [JournalItem] = []
        for item in other.items {
            guard let existing = itemsByID[item.id] else {
                itemsByID[item.id] = item
                order.append(item.id)
                continue
            }
            guard existing != item else { continue }

            // `existing` came from base, `item` from other — map back to
            // local/remote to apply the newer-updatedAt rule.
            let localCopy = localIsBase ? existing : item
            let remoteCopy = localIsBase ? item : existing
            let winner = localWinsConflicts ? localCopy : remoteCopy
            let loser = localWinsConflicts ? remoteCopy : localCopy
            itemsByID[item.id] = winner
            if !loser.isEmpty {
                losingItems.append(loser)
            }
        }

        var items = order.compactMap { itemsByID[$0] }
        // Placeholder empty items add nothing once real content exists.
        let nonEmpty = items.filter { !$0.isEmpty }
        if !nonEmpty.isEmpty {
            items = nonEmpty
        }
        if items.isEmpty {
            items = [JournalItem()]
        }

        let localTitle = local.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteTitle = remote.title.trimmingCharacters(in: .whitespacesAndNewlines)
        var title = base.title
        var losingTitle: String?
        if localTitle != remoteTitle {
            if localTitle.isEmpty {
                title = remote.title
            } else if remoteTitle.isEmpty {
                title = local.title
            } else {
                title = localWinsConflicts ? local.title : remote.title
                losingTitle = localWinsConflicts ? remote.title : local.title
            }
        }

        var merged = base
        merged.title = title
        merged.items = items
        merged.createdAt = min(local.createdAt, remote.createdAt)
        merged.updatedAt = max(local.updatedAt, remote.updatedAt)

        return JournalDayMergeResult(merged: merged, losingItems: losingItems, losingTitle: losingTitle)
    }
}
