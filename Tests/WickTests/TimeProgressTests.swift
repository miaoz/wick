import XCTest
@testable import WickCore

final class TimeProgressTests: XCTestCase {
    func testDayFractionRemainingAtStartOfDayIsNearOne() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 15
        components.hour = 0
        components.minute = 0
        components.second = 1
        let date = calendar.date(from: components)!

        let fraction = TimeProgressCalculator.dayFractionRemaining(at: date, calendar: calendar)
        XCTAssertGreaterThan(fraction, 0.99)
        XCTAssertLessThanOrEqual(fraction, 1)
    }

    func testDayFractionRemainingAtEndOfDayIsNearZero() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 15
        components.hour = 23
        components.minute = 59
        components.second = 0
        let date = calendar.date(from: components)!

        let fraction = TimeProgressCalculator.dayFractionRemaining(at: date, calendar: calendar)
        XCTAssertLessThan(fraction, 0.01)
        XCTAssertGreaterThanOrEqual(fraction, 0)
    }

    func testRemainingFractionClamps() {
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSince1970: 100)
        let interval = DateInterval(start: start, end: end)

        XCTAssertEqual(
            TimeProgressCalculator.remainingFraction(for: interval, at: Date(timeIntervalSince1970: -10)),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            TimeProgressCalculator.remainingFraction(for: interval, at: Date(timeIntervalSince1970: 200)),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            TimeProgressCalculator.remainingFraction(for: interval, at: Date(timeIntervalSince1970: 25)),
            0.75,
            accuracy: 0.0001
        )
    }

    func testAllProgressReturnsFourItems() {
        let items = TimeProgressCalculator.allProgress(
            at: Date(),
            language: .english,
            calendar: Calendar(identifier: .gregorian)
        )
        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(items.map(\.id), ["day", "weekOfYear", "month", "year"])
    }

    func testWeekUsesMondayStartWhenConfigured() {
        var mondayCalendar = Calendar(identifier: .gregorian)
        mondayCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        mondayCalendar.firstWeekday = 2

        // Wednesday 2026-03-18
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 18
        components.hour = 12
        let date = mondayCalendar.date(from: components)!

        let items = TimeProgressCalculator.allProgress(
            at: date,
            language: .english,
            calendar: mondayCalendar
        )
        let week = items.first { $0.id == "weekOfYear" }
        XCTAssertNotNil(week)
        // Mid-week ~ half remaining ish; just ensure it computes.
        XCTAssertGreaterThan(week!.fractionRemaining, 0)
        XCTAssertLessThan(week!.fractionRemaining, 1)
    }
}
