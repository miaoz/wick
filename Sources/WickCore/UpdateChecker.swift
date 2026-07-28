import Foundation

struct UpdateCheckResult: Equatable {
    enum Kind: Equatable {
        case upToDate
        case updateAvailable(version: String, htmlURL: URL)
        case unavailable(message: String)
    }

    let kind: Kind
}

/// Checks GitHub Releases for a newer version (no code signing required).
enum UpdateChecker {
    static let githubOwner = "miaoz"
    static let githubRepo = "wick"

    static var latestReleaseAPIURL: URL {
        URL(string: "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases/latest")!
    }

    static var releasesPageURL: URL {
        URL(string: "https://github.com/\(githubOwner)/\(githubRepo)/releases")!
    }

    static func check(currentVersion: String = AppInfo.shortVersion) async -> UpdateCheckResult {
        var request = URLRequest(url: latestReleaseAPIURL)
        request.setValue("Wick/\(currentVersion) (macOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 404 {
                    return UpdateCheckResult(kind: .unavailable(message: "no_releases"))
                }
                guard (200...299).contains(http.statusCode) else {
                    return UpdateCheckResult(kind: .unavailable(message: "http_\(http.statusCode)"))
                }
            }

            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let tag = json["tag_name"] as? String
            else {
                return UpdateCheckResult(kind: .unavailable(message: "bad_payload"))
            }

            let htmlString = (json["html_url"] as? String) ?? releasesPageURL.absoluteString
            let htmlURL = URL(string: htmlString) ?? releasesPageURL
            let remoteVersion = tag.hasPrefix("v") || tag.hasPrefix("V")
                ? String(tag.dropFirst())
                : tag

            if AppInfo.isVersion(remoteVersion, newerThan: currentVersion) {
                return UpdateCheckResult(kind: .updateAvailable(version: remoteVersion, htmlURL: htmlURL))
            }
            return UpdateCheckResult(kind: .upToDate)
        } catch {
            return UpdateCheckResult(kind: .unavailable(message: error.localizedDescription))
        }
    }
}
