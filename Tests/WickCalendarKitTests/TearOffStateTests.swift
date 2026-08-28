import XCTest
@testable import WickCalendarKit

final class TearOffStateTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    override func setUp() {
        super.setUp()
        suiteName = "TearOffStateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testDefaultsToNowWhenNeverShown() {
        let now = day(2026, 8, 28, hour: 15)
        XCTAssertEqual(
            TearOffState.displayedDate(now: now, defaults: defaults, calendar: calendar),
            now
        )
    }

    func testDisplayedDateIsStartOfPersistedDay() {
        // A page torn-to (or first shown) mid-afternoon pins the whole day.
        TearOffState.saveDisplayedDate(day(2026, 8, 27, hour: 15), defaults: defaults, calendar: calendar)
        XCTAssertEqual(
            TearOffState.displayedDate(now: day(2026, 8, 28, hour: 9), defaults: defaults, calendar: calendar),
            day(2026, 8, 27)
        )
    }

    func testTornAheadDaysStick() {
        // Tearing many pages ahead must survive relaunch: the pad stays ahead.
        TearOffState.saveDisplayedDate(day(2026, 9, 5), defaults: defaults, calendar: calendar)
        XCTAssertEqual(
            TearOffState.displayedDate(now: day(2026, 8, 28), defaults: defaults, calendar: calendar),
            day(2026, 9, 5)
        )
    }

    func testResetToTodayIsTheOnlyRestore() {
        TearOffState.saveDisplayedDate(day(2026, 9, 5), defaults: defaults, calendar: calendar)
        TearOffState.resetToToday(now: day(2026, 8, 28, hour: 22), defaults: defaults, calendar: calendar)
        XCTAssertEqual(
            TearOffState.displayedDate(now: day(2026, 8, 29), defaults: defaults, calendar: calendar),
            day(2026, 8, 28)
        )
    }
}
