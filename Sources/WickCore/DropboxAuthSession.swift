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
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                currentSession = nil
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
            session.presentationContextProvider = WindowAnchorProvider.shared
            // Keep the shared Safari session so returning users stay signed in.
            session.prefersEphemeralWebBrowserSession = false
            currentSession = session
            session.start()
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
