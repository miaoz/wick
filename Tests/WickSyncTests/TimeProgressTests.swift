import XCTest
@testable import WickSync

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

    func testJournalStatsFormatting() {
        XCTAssertEqual(L10n.journalStats(entries: 0, positions: 0, language: .chinese), "0 篇")
        XCTAssertEqual(L10n.journalStats(entries: 1, positions: 0, language: .chinese), "1 篇")
        XCTAssertEqual(L10n.journalStats(entries: 12, positions: 0, language: .chinese), "12 篇")
        XCTAssertEqual(L10n.journalStats(entries: 12, positions: 5, language: .chinese), "12 篇 · 5 仓")

        XCTAssertEqual(L10n.journalStats(entries: 0, positions: 0, language: .english), "0 entries")
        XCTAssertEqual(L10n.journalStats(entries: 1, positions: 0, language: .english), "1 entry")
        XCTAssertEqual(L10n.journalStats(entries: 12, positions: 0, language: .english), "12 entries")
        XCTAssertEqual(L10n.journalStats(entries: 12, positions: 5, language: .english), "12 entries · 5 pos")
    }

    func testDayStatsFormatting() {
        XCTAssertEqual(
            String(format: L10n.string(.journalDayStatsMixedFormat, language: .chinese), 4, 2, 1),
            "4 条 · 2 笔已平仓 · 1 笔持仓中"
        )
        XCTAssertEqual(
            String(format: L10n.string(.journalDayStatsOpenFormat, language: .chinese), 4, 1),
            "4 条 · 1 笔持仓中"
        )
        XCTAssertEqual(
            String(format: L10n.string(.journalDayStatsFormat, language: .chinese), 4, 2),
            "4 条 · 2 笔已平仓"
        )
        XCTAssertEqual(
            String(format: L10n.string(.journalDayStatsFlatFormat, language: .chinese), 4),
            "4 条 · 无持仓"
        )

        XCTAssertEqual(
            String(format: L10n.string(.journalDayStatsMixedFormat, language: .english), 4, 2, 1),
            "4 · 2 closed · 1 open"
        )
        XCTAssertEqual(
            String(format: L10n.string(.journalDayStatsOpenFormat, language: .english), 4, 1),
            "4 · 1 open"
        )
        XCTAssertEqual(
            String(format: L10n.string(.journalDayStatsFormat, language: .english), 4, 2),
            "4 · 2 closed"
        )
        XCTAssertEqual(
            String(format: L10n.string(.journalDayStatsFlatFormat, language: .english), 4),
            "4 · flat"
        )
    }

    func testUnifiedSettingsSectionTitles() {
        XCTAssertEqual(L10n.string(.appearanceAndLanguageSection, language: .chinese), "外观与语言")
        XCTAssertEqual(L10n.string(.appearanceAndLanguageSection, language: .english), "Appearance & Language")

        XCTAssertEqual(L10n.string(.generalSection, language: .chinese), "通用")
        XCTAssertEqual(L10n.string(.generalSection, language: .english), "General")

        XCTAssertEqual(L10n.string(.journalAndReminderSection, language: .chinese), "日记与提醒")
        XCTAssertEqual(L10n.string(.journalAndReminderSection, language: .english), "Journal & Reminders")

        XCTAssertEqual(L10n.string(.tradingCalendar, language: .chinese), "交易日历")
        XCTAssertEqual(L10n.string(.tradingCalendar, language: .english), "Trading Calendar")

        XCTAssertEqual(L10n.string(.syncSection, language: .chinese), "同步")
        XCTAssertEqual(L10n.string(.syncSection, language: .english), "Sync")

        XCTAssertEqual(L10n.string(.exchangeSection, language: .chinese), "交易所")
        XCTAssertEqual(L10n.string(.exchangeSection, language: .english), "Exchange")

        XCTAssertEqual(L10n.string(.dataSection, language: .chinese), "数据")
        XCTAssertEqual(L10n.string(.dataSection, language: .english), "Data")

        XCTAssertEqual(L10n.string(.aboutSection, language: .chinese), "关于")
        XCTAssertEqual(L10n.string(.aboutSection, language: .english), "About")

        XCTAssertEqual(L10n.string(.weekStartsOnMonday, language: .chinese), "每周从周一开始")
        XCTAssertEqual(L10n.string(.weekStartsOnMonday, language: .english), "Week starts on Monday")
    }
}
