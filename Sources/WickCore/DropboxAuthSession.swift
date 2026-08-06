import AppKit
import AuthenticationServices
import WickSync

/// Opens Dropbox sign-in in the system browser via `ASWebAuthenticationSession`
/// and resolves with the callback URL. Lives in WickCore because it needs a
/// window anchor (and a registered `db-…` URL scheme — packaged app only,
/// `swift run` cannot receive the callback).
@MainActor
enum DropboxAuthSession {
    private static var currentSession: ASWebAuthenticationSession?

    static func open(url: URL, callbackScheme: String) async throws -> URL {
        defer { currentSession = nil }
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme,
                completionHandler: makeCompletionHandler(continuation: continuation)
            )
            session.presentationContextProvider = WindowAnchorProvider.shared
            // Keep the shared Safari session so returning users stay signed in.
            session.prefersEphemeralWebBrowserSession = false
            currentSession = session
            session.start()
        }
    }

    /// The completion handler is invoked synchronously on AuthenticationServices'
    /// XPC reply queue. It MUST be created in a nonisolated context: a closure
    /// inheriting MainActor isolation would trap on newer Swift runtimes when
    /// called off the main queue (EXC_BREAKPOINT in swift_task_checkIsolated).
    private nonisolated static func makeCompletionHandler(
        continuation: CheckedContinuation<URL, Error>
    ) -> (URL?, Error?) -> Void {
        { callbackURL, error in
            if let callbackURL {
                continuation.resume(returning: callbackURL)
            } else if let authError = error as? ASWebAuthenticationSessionError,
                      authError.code == .canceledLogin {
                continuation.resume(throwing: SyncBackendError.authorizationCancelled)
            } else {
                continuation.resume(
                    throwing: error ?? SyncBackendError.server(status: 0, message: "auth session failed")
                )
            }
        }
    }

    private final class WindowAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
        static let shared = WindowAnchorProvider()

        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            NSApplication.shared.keyWindow
                ?? NSApplication.shared.windows.first
                ?? NSWindow()
        }
    }
}
