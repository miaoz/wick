import XCTest
@testable import WickCore

final class AppInfoTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(AppInfo.isVersion("1.3", newerThan: "1.2"))
        XCTAssertTrue(AppInfo.isVersion("1.2.1", newerThan: "1.2"))
        XCTAssertTrue(AppInfo.isVersion("v2.0", newerThan: "1.9.9"))
        XCTAssertFalse(AppInfo.isVersion("1.2", newerThan: "1.2"))
        XCTAssertFalse(AppInfo.isVersion("1.1.9", newerThan: "1.2"))
        XCTAssertTrue(AppInfo.isVersion("1.10", newerThan: "1.9"))
    }
}
