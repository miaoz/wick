import Foundation

/// Single source of truth for journal image filename safety, shared by the
/// macOS store, the iOS store, and the sync engine.
///
/// A safe name is a non-empty single-level relative filename: no path
/// separators, no `.`/`..`, no NUL, and no name that changes when normalized.
/// Rejecting the whole input (rather than cleaning it) means an unsafe
/// reference can never be silently downgraded to a different file.
public enum JournalImageFilename: Sendable {
    /// The named file reference is unsafe (traversal, path separator, or empty).
    public struct InvalidReference: Error, Equatable, Sendable {
        public let filename: String
        public init(filename: String) { self.filename = filename }
    }

    /// True when `filename` is safe to resolve inside an images directory.
    public static func isValid(_ filename: String) -> Bool {
        guard !filename.isEmpty else { return false }
        guard !filename.contains("\0") else { return false }
        guard !filename.contains("/"), !filename.contains("\\") else { return false }
        guard filename != ".", filename != ".." else { return false }
        // Must be a single path component: resolving it against the root must
        // not split it (`a/b.png`) or normalize it away (`../x`, `.`, `..`).
        let url = URL(fileURLWithPath: filename, relativeTo: URL(fileURLWithPath: "/"))
        guard url.lastPathComponent == filename else { return false }
        guard url.standardizedFileURL.path == "/" + filename else { return false }
        return true
    }

    /// Throws when any name is unsafe — used at decode time so a snapshot or
    /// remote entry with an unsafe reference is rejected wholesale.
    public static func validateAll(_ filenames: [String]) throws {
        for filename in filenames {
            guard isValid(filename) else { throw InvalidReference(filename: filename) }
        }
    }
}

/// Next-day verdict on a journal item (trade review): was the call right.
public enum JournalReviewVerdict: String, Codable, Sendable {
    case correct
    case wrong
}

/// Structured review attached to a journal item, editable from the next day on.
public struct JournalReview: Codable, Equatable, Hashable, Sendable {
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
public struct JournalItem: Identifiable, Codable, Equatable, Hashable, Sendable {
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

    private enum CodingKeys: String, CodingKey {
        case id, tag, body, imageFilenames, review
    }

    /// Image references are validated at decode time: an entry whose snapshot
    /// or remote payload carries an unsafe filename fails to decode wholesale
    /// (no partial cleaning, no silent drop). The store turns that into its
    /// read-only load-failure protection; the sync engine reports the day as
    /// failed without touching local data.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        tag = try container.decode(String.self, forKey: .tag)
        body = try container.decode(String.self, forKey: .body)
        let filenames = try container.decode([String].self, forKey: .imageFilenames)
        try JournalImageFilename.validateAll(filenames)
        imageFilenames = filenames
        review = try container.decodeIfPresent(JournalReview.self, forKey: .review)
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
public struct JournalEntry: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    /// Calendar day this entry is about (start-of-day in local time when created).
    public var date: Date
    /// Optional day-level title.
    public var title: String
    public var items: [JournalItem]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
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

public struct JournalSnapshot: Codable, Equatable, Sendable {
    public var version: Int
    public var entries: [JournalEntry]

    /// v2 removes the persisted date-derived `dayKey`; entry UUID is the only
    /// stable identity and `date` remains freely editable.
    public static let currentVersion = 2

    public static var empty: JournalSnapshot {
        JournalSnapshot(version: currentVersion, entries: [])
    }

    public init(version: Int, entries: [JournalEntry]) {
        self.version = version
        self.entries = entries
    }
}

// MARK: - Multi-journal catalog

/// Which venue a journal is bound to. One journal ≤ one account.
public enum ExchangeVenue: String, Codable, Sendable, CaseIterable, Identifiable {
    case binance
    case okx
    case hyperliquid

    public var id: String { rawValue }
}

/// Non-secret binding stored in the catalog. Secrets stay in the Keychain
/// (or the unpackaged dev-secrets file).
public struct JournalExchangeBinding: Codable, Equatable, Hashable, Sendable {
    public var venue: ExchangeVenue
    /// Hyperliquid: `0x` address. Centralized venues: display name ("OKX").
    public var accountLabel: String

    public init(venue: ExchangeVenue, accountLabel: String) {
        self.venue = venue
        self.accountLabel = accountLabel
    }
}

/// Metadata for one journal library (a named container of day entries).
public struct JournalInfo: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    public var exchangeBinding: JournalExchangeBinding?

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        exchangeBinding: JournalExchangeBinding? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.exchangeBinding = exchangeBinding
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

/// Shared catalog file-load matrix, used by both the macOS and iOS stores so
/// identical fixtures produce identical conclusions (acceptance AC-P1-02 /
/// AC-P0-01). The primary wins when usable; the sidecar backup is consulted
/// only when the primary is missing or corrupt.
public enum JournalCatalogLoader {
    public enum Outcome: Equatable {
        /// Neither primary nor backup exists — the only case that may
        /// first-create a library.
        case missing
        case loaded(JournalCatalogSnapshot)
        case restoredFromBackup(JournalCatalogSnapshot)
        case corrupt
        case unsupportedVersion(Int)
    }

    private enum FileOutcome {
        case valid(JournalCatalogSnapshot)
        case unsupportedVersion(Int)
        case corrupt
        case absent
    }

    private static func decodeFile(at url: URL, currentVersion: Int) -> FileOutcome {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return .absent }
        do {
            let data = try Data(contentsOf: url)
            let catalog = try JournalCatalogCodec.decode(data, currentVersion: currentVersion)
            return .valid(catalog)
        } catch let error as JournalCatalogCodec.LoadError {
            switch error {
            case .corrupt, .empty:
                return .corrupt
            case .unsupportedVersion(let version):
                return .unsupportedVersion(version)
            }
        } catch {
            return .corrupt
        }
    }

    public static func load(primaryURL: URL, backupURL: URL, currentVersion: Int) -> Outcome {
        switch decodeFile(at: primaryURL, currentVersion: currentVersion) {
        case .valid(let catalog):
            return .loaded(catalog)
        case .unsupportedVersion(let version):
            // Future format: never rewrite the primary or consult the backup.
            return .unsupportedVersion(version)
        case .corrupt:
            // Primary corrupt: restore from a valid, supported backup.
            switch decodeFile(at: backupURL, currentVersion: currentVersion) {
            case .valid(let catalog):
                return .restoredFromBackup(catalog)
            case .unsupportedVersion(let version):
                return .unsupportedVersion(version)
            case .corrupt, .absent:
                return .corrupt
            }
        case .absent:
            // Primary missing: recover from a valid backup (AC-P1-02).
            switch decodeFile(at: backupURL, currentVersion: currentVersion) {
            case .valid(let catalog):
                return .restoredFromBackup(catalog)
            case .unsupportedVersion(let version):
                return .unsupportedVersion(version)
            case .corrupt:
                return .corrupt
            case .absent:
                return .missing
            }
        }
    }
}

/// Shared catalog decode + version validation, used by both the macOS and iOS
/// stores so identical fixtures produce identical load conclusions.
public enum JournalCatalogCodec {
    public enum LoadError: Error, Equatable {
        /// Not decodable (truncated JSON, missing required fields, garbage).
        case corrupt
        /// Decodable but declares no journals — an empty library is not a
        /// "missing" one and must never be silently re-seeded.
        case empty
        /// Written by a newer app; old clients must not rewrite known fields
        /// or drop unknown ones.
        case unsupportedVersion(Int)
    }

    public static func decode(_ data: Data, currentVersion: Int) throws -> JournalCatalogSnapshot {
        guard !data.isEmpty else { throw LoadError.corrupt }
        let catalog: JournalCatalogSnapshot
        do {
            catalog = try JournalSyncEncoding.decoder.decode(JournalCatalogSnapshot.self, from: data)
        } catch {
            throw LoadError.corrupt
        }
        guard catalog.version <= currentVersion else {
            throw LoadError.unsupportedVersion(catalog.version)
        }
        guard !catalog.journals.isEmpty else {
            throw LoadError.empty
        }
        return catalog
    }
}
