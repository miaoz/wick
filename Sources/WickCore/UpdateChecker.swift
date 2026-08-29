import AppKit
import Foundation
import UserNotifications

struct UpdateCheckResult: Equatable {
    enum Kind: Equatable {
        case upToDate
        case updateAvailable(version: String, downloadURL: URL, releaseNotesURL: URL)
        case unavailable(message: String)
    }

    let kind: Kind
}

/// Checks GitHub Releases for a newer version and points download links to Cloudflare R2 CDN.
enum UpdateChecker {
    static let githubOwner = "miaoz"
    static let githubRepo = "wick"

    static let r2DownloadBaseURL = "https://dl.bitfroth.com/wick"

    static var r2LatestDownloadURL: URL {
        URL(string: "\(r2DownloadBaseURL)/Wick.zip")!
    }

    static func r2VersionedDownloadURL(version: String) -> URL {
        URL(string: "\(r2DownloadBaseURL)/Wick-macOS-\(version).zip") ?? r2LatestDownloadURL
    }

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

            let releaseNotesURL = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesPageURL
            let remoteVersion = tag.hasPrefix("v") || tag.hasPrefix("V")
                ? String(tag.dropFirst())
                : tag

            if AppInfo.isVersion(remoteVersion, newerThan: currentVersion) {
                let downloadURL = r2VersionedDownloadURL(version: remoteVersion)
                return UpdateCheckResult(kind: .updateAvailable(version: remoteVersion, downloadURL: downloadURL, releaseNotesURL: releaseNotesURL))
            }
            return UpdateCheckResult(kind: .upToDate)
        } catch {
            return UpdateCheckResult(kind: .unavailable(message: error.localizedDescription))
        }
    }
}

/// Manages automatic background update checks and delivers local system notifications.
@MainActor
final class UpdateCheckerPresenter: ObservableObject {
    static let shared = UpdateCheckerPresenter()

    enum IDs {
        static let notificationID = "wick.app.update-available"
        static let categoryID = "wick.app.update"
        static let downloadActionID = "wick.app.update.download"
    }

    @Published private(set) var isChecking = false

    private var lastAutomaticCheck: Date?
    private var checkTimer: Timer?

    private init() {}

    func startPeriodicChecks() {
        checkTimer?.invalidate()

        guard AppSettings.shared.checkForUpdatesAutomatically else { return }

        // Initial probe on launch
        Task {
            await checkInBackgroundIfNeeded()
        }

        // Schedule background probe every 6 hours
        checkTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard AppSettings.shared.checkForUpdatesAutomatically else { return }
                await self?.checkInBackgroundIfNeeded()
            }
        }
    }

    func checkInBackgroundIfNeeded(force: Bool = false) async {
        if !force, let last = lastAutomaticCheck, Date().timeIntervalSince(last) < 6 * 3600 {
            return
        }
        lastAutomaticCheck = Date()
        isChecking = true
        defer { isChecking = false }

        let result = await UpdateChecker.check()

        switch result.kind {
        case .updateAvailable(let version, let downloadURL, _):
            AppSettings.shared.lastKnownRemoteVersion = version
            AppSettings.shared.lastKnownRemoteURL = downloadURL.absoluteString

            // Deliver notification if not yet notified for this version. The
            // version is marked only when a post actually happened: if the user
            // has not authorized notifications, the post is skipped and the
            // mark must stay unset so the next check retries instead of
            // permanently missing the update (DS-10).
            if AppSettings.shared.lastNotifiedUpdateVersion != version {
                if await postUpdateNotification(version: version, downloadURL: downloadURL) {
                    AppSettings.shared.lastNotifiedUpdateVersion = version
                }
            }
        case .upToDate:
            AppSettings.shared.lastKnownRemoteVersion = ""
            AppSettings.shared.lastKnownRemoteURL = ""
        case .unavailable:
            break
        }
    }

    /// Posts the update notification, returning false (without marking the
    /// version notified) when the post is skipped — notifications unavailable,
    /// permission not granted, or the add failed.
    private func postUpdateNotification(version: String, downloadURL: URL) async -> Bool {
        guard JournalReminderScheduler.notificationsAvailable else { return false }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return false }

        let content = UNMutableNotificationContent()
        let language = AppSettings.shared.language
        content.title = String(format: L10n.string(.updateNotificationTitle, language: language), version)
        content.body = L10n.string(.updateNotificationBody, language: language)
        content.sound = .default
        content.categoryIdentifier = IDs.categoryID
        content.userInfo = [
            "action": "downloadUpdate",
            "downloadURL": downloadURL.absoluteString,
            "version": version
        ]

        let request = UNNotificationRequest(
            identifier: IDs.notificationID,
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
            return true
        } catch {
            NSLog("Wick: failed to post update notification: \(error.localizedDescription)")
            return false
        }
    }
}
