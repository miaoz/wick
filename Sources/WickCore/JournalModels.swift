import Foundation

/// One focus block inside a journal day: a tag, notes, and optional images.
struct JournalItem: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    /// Single free-form tag for this item (e.g. a symbol, topic, or person).
    var tag: String
    var body: String
    /// Relative filenames under the store's images directory.
    var imageFilenames: [String]

    init(
        id: UUID = UUID(),
        tag: String = "",
        body: String = "",
        imageFilenames: [String] = []
    ) {
        self.id = id
        self.tag = tag
        self.body = body
        self.imageFilenames = imageFilenames
    }

    var isEmpty: Bool {
        tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && imageFilenames.isEmpty
    }

    var previewText: String {
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
struct JournalEntry: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    /// Calendar day this entry is about (start-of-day in local time when created).
    var date: Date
    /// Optional day-level title.
    var title: String
    var items: [JournalItem]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        title: String = "",
        items: [JournalItem] = [JournalItem()],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.items = items.isEmpty ? [JournalItem()] : items
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Tags collected from all non-empty item tags.
    var tags: [String] {
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

    var allImageFilenames: [String] {
        items.flatMap(\.imageFilenames)
    }

    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && items.allSatisfy(\.isEmpty)
    }

    var previewText: String {
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
    var previewBody: String {
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

struct JournalSnapshot: Codable, Equatable {
    var version: Int
    var entries: [JournalEntry]

    static let currentVersion = 1

    static var empty: JournalSnapshot {
        JournalSnapshot(version: currentVersion, entries: [])
    }
}
