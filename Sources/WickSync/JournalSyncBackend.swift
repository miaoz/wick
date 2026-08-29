import Foundation

/// One remote file entry as reported by a backend change listing.
public struct RemoteFileMeta: Equatable, Sendable {
    /// Lowercased full path (Dropbox paths are case-insensitive); used as the map key.
    public var path: String
    public var rev: String?
    /// Backend content hash. Dropbox uses plain SHA-256 hex for files < 4 MB,
    /// which matches `JournalSyncEncoding.contentHash` byte for byte.
    public var contentHash: String?
    public var isDeleted: Bool

    public init(path: String, rev: String?, contentHash: String?, isDeleted: Bool = false) {
        self.path = path
        self.rev = rev
        self.contentHash = contentHash
        self.isDeleted = isDeleted
    }
}

public enum SyncBackendError: Error, Equatable {
    /// No usable credentials (never signed in, or refresh token revoked).
    case needsAuth
    /// User dismissed the sign-in flow.
    case authorizationCancelled
    /// Conditional write lost the race — someone else wrote first.
    case writeConflict(path: String)
    /// Stored listing cursor went stale; caller must re-list from scratch.
    case cursorExpired
    case rateLimited(retryAfter: TimeInterval?)
    case server(status: Int, message: String)
    /// Network-level failure (offline, DNS, timeout) — usually transient.
    case transport(message: String)
}

/// A cloud backend that stores the journal as plain files (Dropbox first;
/// anything else implements the same narrow surface). Interactive sign-in is
/// injected by the platform layer so this module stays UI-free.
@MainActor
public protocol JournalSyncBackend: AnyObject {
    var isAuthorized: Bool { get }
    var accountEmail: String? { get }

    /// Runs the interactive sign-in flow; resolves with the account email.
    func authorize() async throws -> String
    func signOut()

    /// Full recursive listing when `cursor` is nil; incremental deltas after
    /// that. Deleted entries are reported with `isDeleted = true`. The returned
    /// cursor replaces the caller's stored one.
    func listChanges(since cursor: String?) async throws -> (entries: [RemoteFileMeta], cursor: String)

    func download(path: String) async throws -> (data: Data, rev: String)

    /// `ifRev == nil` means add-only (fails with `writeConflict` if the path
    /// exists); otherwise the write only lands while the remote rev matches.
    /// Returns the new rev.
    @discardableResult
    func upload(path: String, data: Data, ifRev: String?) async throws -> String

    /// Missing paths are treated as already deleted.
    func delete(path: String) async throws
}
