import XCTest

@testable import WickTrading

final class PositionEntryPlannerTests: XCTestCase {
    private func position(
        _ id: String,
        symbol: String,
        openTime: TimeInterval
    ) -> TradingPosition {
        TradingPosition(
            id: id,
            symbol: symbol,
            side: .long,
            openTime: Date(timeIntervalSince1970: openTime),
            closeTime: nil,
            entryPrice: 100,
            exitPrice: nil,
            peakSize: 1,
            realizedPnl: 0
        )
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private var dayKey: (Date) -> String {
        { date in
            let components = self.calendar.dateComponents([.year, .month, .day], from: date)
            return String(
                format: "%04d-%02d-%02d",
                components.year!,
                components.month!,
                components.day!
            )
        }
    }

    private var startOfDay: (Date) -> Date {
        { date in self.calendar.startOfDay(for: date) }
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 15) -> TimeInterval {
        calendar.date(
            from: DateComponents(year: y, month: m, day: d, hour: hour)
        )!.timeIntervalSince1970
    }

    func testPlansEntryPerMissingDayWithDistinctSymbols() {
        let plan = PositionEntryPlanner.plan(
            positions: [
                position("a", symbol: "BTCUSDT", openTime: date(2026, 8, 1)),
                position("b", symbol: "BTCUSDC", openTime: date(2026, 8, 1, hour: 9)),
                position("c", symbol: "ETHUSDT", openTime: date(2026, 8, 2))
            ],
            existingTagsByDay: [:],
            dayKey: dayKey,
            startOfDay: startOfDay
        )

        XCTAssertEqual(plan.count, 2)
        XCTAssertEqual(plan[0].dayKey, "2026-08-01")
        XCTAssertEqual(plan[0].symbols, ["BTCUSDC", "BTCUSDT"])
        XCTAssertEqual(plan[0].day, startOfDay(Date(timeIntervalSince1970: date(2026, 8, 1))))
        XCTAssertEqual(plan[1].dayKey, "2026-08-02")
        XCTAssertEqual(plan[1].symbols, ["ETHUSDT"])
    }

    func testSkipsPositionWhenExistingDayHasMatchingTag() {
        let plan = PositionEntryPlanner.plan(
            positions: [position("a", symbol: "BTCUSDT", openTime: date(2026, 8, 1))],
            existingTagsByDay: ["2026-08-01": ["BTC"]],
            dayKey: dayKey,
            startOfDay: startOfDay
        )
        XCTAssertTrue(plan.isEmpty)
    }

    func testPlansMissingTagForExistingDay() {
        let plan = PositionEntryPlanner.plan(
            positions: [position("a", symbol: "BTCUSDT", openTime: date(2026, 8, 1))],
            existingTagsByDay: ["2026-08-01": ["ETH"]],
            dayKey: dayKey,
            startOfDay: startOfDay
        )
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].dayKey, "2026-08-01")
        XCTAssertEqual(plan[0].symbols, ["BTCUSDT"])
    }

    func testMultipleSessionsSameSymbolSameDayCollapseToOneItem() {
        let plan = PositionEntryPlanner.plan(
            positions: [
                position("a", symbol: "BTCUSDT", openTime: date(2026, 8, 1, hour: 1)),
                position("b", symbol: "BTCUSDT", openTime: date(2026, 8, 1, hour: 22))
            ],
            existingTagsByDay: [:],
            dayKey: dayKey,
            startOfDay: startOfDay
        )
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].symbols, ["BTCUSDT"])
    }

    func testPlansSortedByDayAscending() {
        let plan = PositionEntryPlanner.plan(
            positions: [
                position("late", symbol: "BTCUSDT", openTime: date(2026, 8, 5)),
                position("early", symbol: "BTCUSDT", openTime: date(2026, 7, 20))
            ],
            existingTagsByDay: [:],
            dayKey: dayKey,
            startOfDay: startOfDay
        )
        XCTAssertEqual(plan.map(\.dayKey), ["2026-07-20", "2026-08-05"])
    }

    func testStableItemIDConvergesAcrossDevices() {
        let journalID = UUID(uuidString: "449E4948-DA92-4DC6-9317-0E49CFEFD7D0")!
        let first = PositionEntryPlanner.stableItemID(
            journalID: journalID,
            dayKey: "2026-08-09",
            symbol: "BTC"
        )
        let second = PositionEntryPlanner.stableItemID(
            journalID: journalID,
            dayKey: "2026-08-09",
            symbol: " btc "
        )

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(
            first,
            PositionEntryPlanner.stableItemID(
                journalID: journalID,
                dayKey: "2026-08-10",
                symbol: "BTC"
            )
        )
        XCTAssertNotEqual(
            first,
            PositionEntryPlanner.stableItemID(
                journalID: journalID,
                dayKey: "2026-08-09",
                symbol: "ETH"
            )
        )
    }
}
