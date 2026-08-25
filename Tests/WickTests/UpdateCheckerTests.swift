import XCTest
@testable import WickCore

final class UpdateCheckerTests: XCTestCase {
    func testR2DownloadURLs() {
        XCTAssertEqual(
            UpdateChecker.r2LatestDownloadURL.absoluteString,
            "https://dl.bitfroth.com/wick/Wick.zip"
        )
        XCTAssertEqual(
            UpdateChecker.r2VersionedDownloadURL(version: "1.2.3").absoluteString,
            "https://dl.bitfroth.com/wick/Wick-macOS-1.2.3.zip"
        )
    }

    func testUpdateCheckerEndpoints() {
        XCTAssertEqual(
            UpdateChecker.latestReleaseAPIURL.absoluteString,
            "https://api.github.com/repos/miaoz/wick/releases/latest"
        )
        XCTAssertEqual(
            UpdateChecker.releasesPageURL.absoluteString,
            "https://github.com/miaoz/wick/releases"
        )
    }
}
