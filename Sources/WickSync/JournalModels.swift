import Foundation

/// Next-day verdict on a journal item (trade review): was the call right.
public enum JournalReviewVerdict: String, Codable {
    case correct
    case wrong
}

/// Structured review attached to a journal item, editable from the next day on.
public struct JournalReview: Codable, Equatable, Hashable {
    public var verdict: JournalReviewVerdict
    /// Optional one-line annotation shown in italics under the verdict picker.
    public var note: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        verdict: JournalReviewVerdict,
        note: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.verdict = verdict
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// One focus block inside a journal day: a tag, notes, and optional images.
public struct JournalItem: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    /// Single free-form tag for this item (e.g. a symbol, topic, or person).
    public var tag: String
    public var body: String
    /// Relative filenames under the store's images directory.
    public var imageFilenames: [String]
    /// Next-day review; optional key keeps version-1 snapshots decodable.
    public var review: JournalReview?

    public init(
        id: UUID = UUID(),
        tag: String = "",
        body: String = "",
        imageFilenames: [String] = [],
        review: JournalReview? = nil
    ) {
        self.id = id
        self.tag = tag
        self.body = body
        self.imageFilenames = imageFilenames
        self.review = review
    }

    public var isEmpty: Bool {
        tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && imageFilenames.isEmpty
    }

    public var previewText: String {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBody.isEmpty {
            let firstLine = trimmedBody
                .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
                .first
            return String(firstLine ?? Substring(trimmedBody))
        }
        return ""
    }
}

/// A journal document for a calendar day, composed of one or more items.
public struct JournalEntry: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    /// Calendar day this entry is about (start-of-day in local time when created).
    public var date: Date
    /// Stable cross-device identity ("yyyy-MM-dd" in the local timezone when the
    /// entry was created or moved). Never recomputed on plain edits, so timezone
    /// travel cannot silently re-key a day; `JournalStore.updateEntry` refreshes
    /// it only when the entry is actually moved to a different day.
    public var dayKey: String
    /// Optional day-level title.
    public var title: String
    public var items: [JournalItem]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        dayKey: String? = nil,
        title: String = "",
        items: [JournalItem] = [JournalItem()],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.dayKey = dayKey ?? JournalDayKey.make(from: date)
        self.title = title
        self.items = items.isEmpty ? [JournalItem()] : items
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, dayKey, title, items, createdAt, updatedAt
    }

    /// Pre-sync snapshots have no `dayKey`; derive it from `date` once. It is
    /// frozen into the file on the next persist, so this fallback runs at most once.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let decodedDate = try container.decode(Date.self, forKey: .date)
        date = decodedDate
        dayKey = try container.decodeIfPresent(String.self, forKey: .dayKey)
            ?? JournalDayKey.make(from: decodedDate)
        title = try container.decode(String.self, forKey: .title)
        let decodedItems = try container.decode([JournalItem].self, forKey: .items)
        items = decodedItems.isEmpty ? [JournalItem()] : decodedItems
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    /// Tags collected from all non-empty item tags.
    public var tags: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in items {
            let tag = item.tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty else { continue }
            let key = tag.lowercased()
            if seen.insert(key).inserted {
                result.append(tag)
            }
        }
        return result
    }

    public var allImageFilenames: [String] {
        items.flatMap(\.imageFilenames)
    }

    public var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && items.allSatisfy(\.isEmpty)
    }

    public var previewText: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }

        let nonEmptyTags = tags
        if !nonEmptyTags.isEmpty {
            return nonEmptyTags.joined(separator: " · ")
        }

        for item in items {
            let preview = item.previewText
            if !preview.isEmpty {
                return preview
            }
        }

        return ""
    }

    /// Secondary timeline snippet: first item body when title/tags already occupy the primary line.
    public var previewBody: String {
        let firstBody = items.lazy.map(\.previewText).first(where: { !$0.isEmpty }) ?? ""
        guard !firstBody.isEmpty else { return "" }

        let hasTitle = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasTitle || !tags.isEmpty {
            return firstBody
        }
        // Primary line already shows the first body via `previewText`.
        return ""
    }
}

public struct JournalSnapshot: Codable, Equatable {
    public var version: Int
    public var entries: [JournalEntry]

    public static let currentVersion = 1

    public static var empty: JournalSnapshot {
        JournalSnapshot(version: currentVersion, entries: [])
    }

    public init(version: Int, entries: [JournalEntry]) {
        self.version = version
        self.entries = entries
    }
}

// MARK: - Multi-journal catalog

/// Metadata for one journal library (a named container of day entries).
public struct JournalInfo: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// On-disk catalog of all journals under the multi-journal root.
public struct JournalCatalogSnapshot: Codable, Equatable {
    public var version: Int
    public var activeJournalID: UUID
    public var journals: [JournalInfo]

    public static let currentVersion = 1

    public init(version: Int, activeJournalID: UUID, journals: [JournalInfo]) {
        self.version = version
        self.activeJournalID = activeJournalID
        self.journals = journals
    }
}
