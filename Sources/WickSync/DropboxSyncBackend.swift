import Foundation

/// Dropbox API v2 backend: OAuth 2.0 PKCE sign-in + the four file operations the
/// sync engine needs. No SDK — plain `URLSession` against the documented HTTP API.
///
/// The interactive part of sign-in is injected (`authSession`) by the platform
/// layer (an `ASWebAuthenticationSession` wrapper on macOS/iOS) so this file
/// stays Foundation-only and testable.
@MainActor
public final class DropboxSyncBackend: JournalSyncBackend {
    public static let appKey = "hm5yscsy9a11g0q"
    public static let callbackScheme = "db-hm5yscsy9a11g0q"
    public static let redirectURI = "db-hm5yscsy9a11g0q://2/token"

    private static let authorizeURL = URL(string: "https://www.dropbox.com/oauth2/authorize")!
    private static let tokenURL = URL(string: "https://api.dropboxapi.com/oauth2/token")!
    private static let apiHost = "https://api.dropboxapi.com/2/"
    private static let contentHost = "https://content.dropboxapi.com/2/"

    private let session: URLSession
    private let tokenStore: KeychainTokenStore

    /// Platform hook: opens the system browser at the authorize URL and returns
    /// the callback URL the flow lands on. Arguments: (authorizeURL, callbackScheme).
    public var authSession: ((URL, String) async throws -> URL)?

    public private(set) var accountEmail: String?

    private var accessToken: String?
    private var accessTokenExpiry: Date?
    private var refreshTask: Task<String, Error>?
    /// Loaded lazily from the Keychain on first use.
    private var didProbeKeychain = false
    private var cachedRefreshToken: String?

    public init(
        session: URLSession = {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 30
            return URLSession(configuration: config)
        }(),
        tokenStore: KeychainTokenStore = KeychainTokenStore(
            service: "com.miaoz.wick.dropbox",
            account: "refresh-token"
        )
    ) {
        self.session = session
        self.tokenStore = tokenStore
    }

    // MARK: - Authorization

    public var isAuthorized: Bool {
        refreshToken() != nil
    }

    public func authorize() async throws -> String {
        guard let authSession else {
            throw SyncBackendError.server(status: 0, message: "auth session not configured")
        }
        let verifier = PKCE.verifier()
        let state = UUID().uuidString

        var components = URLComponents(url: Self.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.appKey),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "token_access_type", value: "offline"),
            URLQueryItem(name: "state", value: state)
        ]
        let callback = try await authSession(components.url!, Self.callbackScheme)
        guard let callbackComponents = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              callbackComponents.queryItems?.first(where: { $0.name == "state" })?.value == state,
              let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw SyncBackendError.authorizationCancelled
        }

        let token = try await tokenRequest(parameters: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "code_verifier": verifier,
            "client_id": Self.appKey
        ])
        apply(tokenResponse: token)

        let email = (try? await fetchAccountEmail()) ?? ""
        accountEmail = email
        return email
    }

    public func signOut() {
        cachedRefreshToken = nil
        accessToken = nil
        accessTokenExpiry = nil
        accountEmail = nil
        tokenStore.clear()
    }

    private func refreshToken() -> String? {
        if !didProbeKeychain {
            didProbeKeychain = true
            cachedRefreshToken = tokenStore.load()
        }
        return cachedRefreshToken
    }

    private struct TokenResponse {
        var accessToken: String
        var refreshToken: String?
        var expiresIn: TimeInterval
    }

    private func apply(tokenResponse: TokenResponse) {
        accessToken = tokenResponse.accessToken
        // Refresh 5 minutes early to stay clear of mid-flight expiry.
        accessTokenExpiry = Date().addingTimeInterval(max(0, tokenResponse.expiresIn - 300))
        if let refresh = tokenResponse.refreshToken {
            cachedRefreshToken = refresh
            didProbeKeychain = true
            tokenStore.save(refresh)
        }
    }

    private func tokenRequest(parameters: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = parameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else {
            throw SyncBackendError.transport(message: "no HTTP response")
        }
        guard http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String
        else {
            // invalid_grant means the code/refresh token is dead.
            let body = String(data: data, encoding: .utf8) ?? ""
            if body.contains("invalid_grant") {
                throw SyncBackendError.needsAuth
            }
            throw SyncBackendError.server(status: http.statusCode, message: body)
        }
        return TokenResponse(
            accessToken: access,
            refreshToken: json["refresh_token"] as? String,
            expiresIn: (json["expires_in"] as? NSNumber)?.doubleValue ?? 4 * 3600
        )
    }

    /// Access token, refreshing via the stored refresh token when needed.
    /// Concurrent callers share one in-flight refresh.
    private func validAccessToken() async throws -> String {
        if let accessToken, let accessTokenExpiry, Date() < accessTokenExpiry {
            return accessToken
        }
        if let refreshTask {
            return try await refreshTask.value
        }
        guard let refresh = refreshToken() else {
            throw SyncBackendError.needsAuth
        }
        let task = Task<String, Error> {
            let response = try await tokenRequest(parameters: [
                "grant_type": "refresh_token",
                "refresh_token": refresh,
                "client_id": Self.appKey
            ])
            apply(tokenResponse: response)
            return response.accessToken
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            return try await task.value
        } catch let error as SyncBackendError {
            if error == .needsAuth {
                signOut()
            }
            throw error
        }
    }

    private func fetchAccountEmail() async throws -> String {
        let json = try await rpcCall(path: "users/get_current_account", body: nil)
        return json["email"] as? String ?? ""
    }

    // MARK: - JournalSyncBackend

    public func listChanges(since cursor: String?) async throws -> (entries: [RemoteFileMeta], cursor: String) {
        var collected: [RemoteFileMeta] = []
        var nextCursor: String

        if let cursor {
            nextCursor = cursor
        } else {
            let first = try await rpcCall(path: "files/list_folder", body: [
                "path": "",
                "recursive": true,
                "include_deleted": false,
                "limit": 2000
            ])
            collected.append(contentsOf: parseEntries(first))
            guard let cursor = first["cursor"] as? String else {
                throw SyncBackendError.server(status: 200, message: "list_folder: missing cursor")
            }
            nextCursor = cursor
            var hasMore = first["has_more"] as? Bool ?? false
            while hasMore {
                let page = try await continueListing(nextCursor)
                collected.append(contentsOf: parseEntries(page))
                nextCursor = page["cursor"] as? String ?? nextCursor
                hasMore = page["has_more"] as? Bool ?? false
            }
            return (collected, nextCursor)
        }

        // Incremental: follow continue pagination to the end so the returned
        // cursor always represents "everything up to now".
        while true {
            let page = try await continueListing(nextCursor)
            collected.append(contentsOf: parseEntries(page))
            nextCursor = page["cursor"] as? String ?? nextCursor
            guard page["has_more"] as? Bool ?? false else { break }
        }
        return (collected, nextCursor)
    }

    private func continueListing(_ cursor: String) async throws -> [String: Any] {
        do {
            return try await rpcCall(path: "files/list_folder/continue", body: ["cursor": cursor])
        } catch let error as SyncBackendError {
            // Dropbox reports stale cursors as a 409 'reset' error.
            if case .server(let status, let message) = error,
               status == 409,
               message.contains("reset") || message.contains("expired") {
                throw SyncBackendError.cursorExpired
            }
            throw error
        }
    }

    private func parseEntries(_ json: [String: Any]) -> [RemoteFileMeta] {
        guard let entries = json["entries"] as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            let tag = entry[".tag"] as? String
            guard let path = (entry["path_lower"] as? String) ?? (entry["path_display"] as? String)
            else {
                return nil
            }
            switch tag {
            case "file":
                return RemoteFileMeta(
                    path: path,
                    rev: entry["rev"] as? String,
                    contentHash: entry["content_hash"] as? String
                )
            case "deleted":
                return RemoteFileMeta(path: path, rev: nil, contentHash: nil, isDeleted: true)
            default: // folders carry no data for us
                return nil
            }
        }
    }

    public func download(path: String) async throws -> (data: Data, rev: String) {
        let token = try await validAccessToken()
        var request = contentRequest(path: "files/download", token: token)
        request.setValue(
            try apiArg(["path": path]),
            forHTTPHeaderField: "Dropbox-API-Arg"
        )
        let (data, response) = try await perform(request)
        try validate(response: response, data: data, path: path)
        let header = (response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Dropbox-API-Result")
        let rev = header
            .flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
            .flatMap { $0["rev"] as? String } ?? ""
        return (data, rev)
    }

    @discardableResult
    public func upload(path: String, data: Data, ifRev: String?) async throws -> String {
        let token = try await validAccessToken()
        var request = contentRequest(path: "files/upload", token: token)
        let mode: [String: Any] = ifRev.map { [".tag": "update", "update": $0] } ?? [".tag": "add"]
        request.setValue(
            try apiArg(["path": path, "mode": mode, "autorename": false, "mute": true]),
            forHTTPHeaderField: "Dropbox-API-Arg"
        )
        request.httpBody = data
        let (responseData, response) = try await perform(request)
        do {
            try validate(response: response, data: responseData, path: path)
        } catch let error as SyncBackendError {
            if case .server(let status, let message) = error,
               status == 409,
               message.contains("conflict") {
                throw SyncBackendError.writeConflict(path: path)
            }
            throw error
        }
        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let rev = json["rev"] as? String
        else {
            throw SyncBackendError.server(status: 200, message: "upload: missing rev")
        }
        return rev
    }

    public func delete(path: String) async throws {
        do {
            _ = try await rpcCall(path: "files/delete_v2", body: ["path": path])
        } catch let error as SyncBackendError {
            // Deleting something already gone is success for sync purposes.
            if case .server(let status, let message) = error,
               status == 409,
               message.contains("not_found") {
                return
            }
            throw error
        }
    }

    // MARK: - HTTP plumbing

    /// JSON-in/JSON-out call against api.dropboxapi.com. A nil body sends the
    /// literal `null`, which no-argument RPC endpoints expect.
    @discardableResult
    private func rpcCall(path: String, body: [String: Any]?) async throws -> [String: Any] {
        let token = try await validAccessToken()
        var request = URLRequest(url: URL(string: Self.apiHost + path)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try body.map { try JSONSerialization.data(withJSONObject: $0) }
            ?? Data("null".utf8)

        let (data, response) = try await perform(request)
        try validate(response: response, data: data, path: path)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SyncBackendError.server(status: 200, message: "\(path): unreadable response")
        }
        return json
    }

    private func contentRequest(path: String, token: String) -> URLRequest {
        var request = URLRequest(url: URL(string: Self.contentHost + path)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        return request
    }

    /// Encodes the JSON argument object carried by the `Dropbox-API-Arg` header.
    private func apiArg(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        return String(decoding: data, as: UTF8.self)
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            throw SyncBackendError.transport(message: error.localizedDescription)
        } catch {
            throw SyncBackendError.transport(message: error.localizedDescription)
        }
    }

    private func validate(response: URLResponse, data: Data, path: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SyncBackendError.transport(message: "no HTTP response")
        }
        switch http.statusCode {
        case 200...299:
            return
        case 401:
            // Token rejected outright — refresh didn't help (handled upstream on retry).
            throw SyncBackendError.needsAuth
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw SyncBackendError.rateLimited(retryAfter: retryAfter)
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SyncBackendError.server(status: http.statusCode, message: body)
        }
    }
}
