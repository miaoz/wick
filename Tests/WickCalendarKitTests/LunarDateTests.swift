import XCTest
@testable import WickCalendarKit

final class LunarDateTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testChineseNewYearDates() {
        // 2025-01-29 is 乙巳年正月初一.
        let a = LunarCalendar.lunar(from: date(2025, 1, 29), calendar: calendar)!
        XCTAssertEqual(a.year, 2025)
        XCTAssertEqual(a.month, 1)
        XCTAssertEqual(a.day, 1)
        XCTAssertEqual(LunarCalendar.ganzhiYear(a.year), "乙巳")
        XCTAssertEqual(LunarCalendar.zodiac(a.year), "蛇")

        // 2024-02-10 is 甲辰年正月初一.
        let b = LunarCalendar.lunar(from: date(2024, 2, 10), calendar: calendar)!
        XCTAssertEqual(b.year, 2024)
        XCTAssertEqual(b.month, 1)
        XCTAssertEqual(b.day, 1)
        XCTAssertEqual(LunarCalendar.ganzhiYear(b.year), "甲辰")
        XCTAssertEqual(LunarCalendar.zodiac(b.year), "龙")
    }

    func testKnownMidYearDate() {
        // 2026-08-08 is 农历 2026 年六月廿六 (verified).
        let l = LunarCalendar.lunar(from: date(2026, 8, 8), calendar: calendar)!
        XCTAssertEqual(l.year, 2026)
        XCTAssertEqual(l.month, 6)
        XCTAssertEqual(l.day, 26)
        XCTAssertEqual(LunarCalendar.monthName(l.month), "六月")
        XCTAssertEqual(LunarCalendar.dayName(l.day), "廿六")
    }

    func testMonthNames() {
        XCTAssertEqual(LunarCalendar.monthName(1), "正月")
        XCTAssertEqual(LunarCalendar.monthName(6), "六月")
        XCTAssertEqual(LunarCalendar.monthName(11), "冬月")
        XCTAssertEqual(LunarCalendar.monthName(12), "腊月")
    }

    func testDayNames() {
        XCTAssertEqual(LunarCalendar.dayName(1), "初一")
        XCTAssertEqual(LunarCalendar.dayName(10), "初十")
        XCTAssertEqual(LunarCalendar.dayName(15), "十五")
        XCTAssertEqual(LunarCalendar.dayName(20), "二十")
        XCTAssertEqual(LunarCalendar.dayName(23), "廿三")
        XCTAssertEqual(LunarCalendar.dayName(30), "三十")
    }
}
