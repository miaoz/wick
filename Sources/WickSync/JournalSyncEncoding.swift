import CryptoKit
import Foundation

/// Canonical JSON encoding + content hashing shared by the store and the sync engine.
///
/// The encoder configuration matches `JournalStore`'s on-disk format (pretty printed,
/// sorted keys, ISO-8601 dates), so encoded bytes are deterministic for a given entry
/// and safe to hash for change detection.
public enum JournalSyncEncoding {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public static func canonicalData(for entry: JournalEntry) throws -> Data {
        try encoder.encode(entry)
    }

    /// Lowercase hex SHA-256 of the payload. This is Wick's own canonical
    /// convention for local change detection and settlement markers.
    ///
    /// NOT comparable with Dropbox's `content_hash` metadata: Dropbox hashes
    /// the concatenation of per-4MB-block SHA-256 digests (hash-of-hashes),
    /// which never equals the plain SHA-256 of the same bytes. Remote change
    /// detection therefore uses file revs, never hash cross-comparisons.
    public static func contentHash(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func contentHash(for entry: JournalEntry) throws -> String {
        contentHash(of: try canonicalData(for: entry))
    }
}
