import Foundation

/// A single journal entry (text, tags, images, and a date).
struct JournalEntry: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    /// Calendar day this entry is about (start-of-day in local time when created).
    var date: Date
    var title: String
    var body: String
    /// Free-form tags for filtering and organization.
    var tags: [String]
    /// Relative filenames under the store's images directory.
    var imageFilenames: [String]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        title: String = "",
        body: String = "",
        tags: [String] = [],
        imageFilenames: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.body = body
        self.tags = tags
        self.imageFilenames = imageFilenames
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && tags.isEmpty
            && imageFilenames.isEmpty
    }

    var previewText: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }

        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBody.isEmpty {
            let firstLine = trimmedBody.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first
            return String(firstLine ?? Substring(trimmedBody))
        }

        if !tags.isEmpty {
            return tags.joined(separator: " · ")
        }

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
