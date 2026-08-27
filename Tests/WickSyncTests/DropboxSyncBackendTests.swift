import Foundation
import XCTest
@testable import WickSync

/// URLProtocol stand-in for Dropbox's HTTP API. Routes to a per-test handler
/// so the backend's 401-refresh-retry behavior can be exercised without
/// touching the network or the Keychain.
private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

@MainActor
final class DropboxSyncBackendTests: XCTestCase {
    private static func http(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.dropboxapi.com/2/files/list_folder")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    private func makeBackend(
        _ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> DropboxSyncBackend {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.handler = handler
        let store = KeychainTokenStore(
            service: "com.miaoz.wick.test.dropbox.\(UUID().uuidString)",
            account: "refresh-token"
        )
        store.save("test-refresh-token")
        return DropboxSyncBackend(
            session: URLSession(configuration: config),
            tokenStore: store
        )
    }

    private func tokenResponse(_ request: URLRequest) throws -> (HTTPURLResponse, Data) {
        guard request.url?.path == "/oauth2/token" else {
            return (Self.http(404), Data())
        }
        let json = #"{"access_token":"token-A","expires_in":14400}"#
        return (Self.http(200), Data(json.utf8))
    }

    private func listFolderResponse(_ request: URLRequest) throws -> (HTTPURLResponse, Data) {
        guard request.url?.path == "/2/files/list_folder" else {
            return (Self.http(404), Data())
        }
        let json = #"{"entries":[],"cursor":"c1","has_more":false}"#
        return (Self.http(200), Data(json.utf8))
    }

    func testRevokedAccessTokenRefreshesAndRetries() async throws {
        // First list_folder call carries a token the server rejects (401). The
        // backend must invalidate it, refresh via the (still-valid) refresh
        // token, and retry once — landing on success instead of a 4-hour
        // needsAuth deadlock.
        let tokenCalls = Box(0)
        let apiCalls = Box(0)
        let apiTokens = Box<[String]>([])

        let backend = makeBackend { request in
            if request.url?.path == "/oauth2/token" {
                tokenCalls.value += 1
                let json = #"{"access_token":"token-\#(tokenCalls.value)","expires_in":14400}"#
                return (Self.http(200), Data(json.utf8))
            }
            if request.url?.path == "/2/files/list_folder" {
                apiCalls.value += 1
                apiTokens.value.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
                if apiCalls.value == 1 {
                    return (Self.http(401), Data("{\"error\":\"expired_access_token\"}".utf8))
                }
                return try self.listFolderResponse(request)
            }
            return (Self.http(404), Data())
        }

        let result = try await backend.listChanges(since: nil)
        XCTAssertEqual(apiCalls.value, 2, "a revoked access token must be retried once after refresh")
        XCTAssertEqual(tokenCalls.value, 2, "the 401 mid-flight must trigger exactly one refresh")
        XCTAssertNotEqual(apiTokens.value[0], apiTokens.value[1], "the retry must carry a fresh access token")
        XCTAssertEqual(result.cursor, "c1")
    }

    func testConsecutive401YieldsNeedsAuth() async throws {
        // Refresh also produces a rejected token: the refresh token itself is
        // dead, so the backend must give up with needsAuth instead of looping.
        let tokenCalls = Box(0)
        let apiCalls = Box(0)

        let backend = makeBackend { request in
            if request.url?.path == "/oauth2/token" {
                tokenCalls.value += 1
                let json = #"{"access_token":"token-\#(tokenCalls.value)","expires_in":14400}"#
                return (Self.http(200), Data(json.utf8))
            }
            if request.url?.path == "/2/files/list_folder" {
                apiCalls.value += 1
                return (Self.http(401), Data("{\"error\":\"expired_access_token\"}".utf8))
            }
            return (Self.http(404), Data())
        }

        do {
            _ = try await backend.listChanges(since: nil)
            XCTFail("expected needsAuth")
        } catch let error as SyncBackendError {
            XCTAssertEqual(error, .needsAuth)
        }
        XCTAssertEqual(apiCalls.value, 2, "exactly one retry before giving up")
        XCTAssertEqual(tokenCalls.value, 2)
    }
}
