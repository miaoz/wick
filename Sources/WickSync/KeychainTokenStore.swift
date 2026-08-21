import Foundation
import Security

/// Minimal Keychain-backed store for secrets (Dropbox refresh token, exchange
/// API keys).
///
/// Packaged `.app` builds (stable `Wick Local` identity) use the real
/// Keychain. Unpackaged `swift run` / `.build` binaries are a new ad-hoc
/// identity on every rebuild, which would prompt for the login password on
/// every Keychain read — so those builds persist to a 0600 JSON file under
/// Application Support instead. Same API either way.
public struct KeychainTokenStore: Sendable {
    private let service: String
    private let account: String

    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    /// `true` inside a packaged `.app`. False for `swift run` / XCTest.
    public static var isPackagedApp: Bool {
        let url = Bundle.main.bundleURL
        if url.pathExtension == "app" { return true }
        return url.path.contains(".app/")
    }

    public func load() -> String? {
        if !Self.isPackagedApp {
            return DevSecretFile.load(service: service, account: account)
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return token
    }

    public func save(_ token: String) {
        if !Self.isPackagedApp {
            DevSecretFile.save(service: service, account: account, token: token)
            return
        }
        let data = Data(token.utf8)
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        // Update in place when present, otherwise add.
        if SecItemUpdate(match as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var item = match
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    public func clear() {
        if !Self.isPackagedApp {
            DevSecretFile.clear(service: service, account: account)
            return
        }
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(match as CFDictionary)
    }
}

/// 0600 JSON map `service\naccount → token` for unpackaged builds.
enum DevSecretFile {
    private static let lock = NSLock()

    static let fileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("Wick/dev-secrets.json")
    }()

    private static func key(_ service: String, _ account: String) -> String {
        service + "\n" + account
    }

    static func load(service: String, account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return readUnlocked()[key(service, account)]
    }

    static func save(service: String, account: String, token: String) {
        lock.lock()
        defer { lock.unlock() }
        var map = readUnlocked()
        map[key(service, account)] = token
        writeUnlocked(map)
    }

    static func clear(service: String, account: String) {
        lock.lock()
        defer { lock.unlock() }
        var map = readUnlocked()
        map.removeValue(forKey: key(service, account))
        writeUnlocked(map)
    }

    private static func readUnlocked() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let map = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return map
    }

    private static func writeUnlocked(_ map: [String: String]) {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(map) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}
