import CryptoKit
import Foundation

/// OAuth 2.0 PKCE helpers (RFC 7636). Lets the app run the code flow as a
/// public client — no app secret is ever embedded in the binary.
public enum PKCE {
    /// 43-character base64url verifier from 32 random bytes.
    public static func verifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64url(Data(bytes))
    }

    public static func challenge(for verifier: String) -> String {
        base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// Base64url without padding, per RFC 7636 §3.
    public static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
