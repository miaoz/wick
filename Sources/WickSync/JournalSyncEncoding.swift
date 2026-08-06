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

    /// Lowercase hex SHA-256 of the payload.
    ///
    /// Dropbox computes `content_hash` as plain SHA-256 hex for files up to 4 MB
    /// (all journal payloads qualify), so a locally computed hash compares
    /// directly against remote metadata without a download.
    public static func contentHash(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func contentHash(for entry: JournalEntry) throws -> String {
        contentHash(of: try canonicalData(for: entry))
    }
}
