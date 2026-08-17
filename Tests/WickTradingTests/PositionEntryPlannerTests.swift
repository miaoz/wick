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
            existingDayKeys: [],
            handledPositionIDs: [],
            dayKey: dayKey,
            startOfDay: startOfDay
        )

        XCTAssertEqual(plan.count, 2)
        XCTAssertEqual(plan[0].dayKey, "2026-08-01")
        XCTAssertEqual(plan[0].symbols, ["BTCUSDC", "BTCUSDT"])
        XCTAssertEqual(Set(plan[0].positionIDs), ["a", "b"])
        XCTAssertEqual(plan[0].day, startOfDay(Date(timeIntervalSince1970: date(2026, 8, 1))))
        XCTAssertEqual(plan[1].dayKey, "2026-08-02")
        XCTAssertEqual(plan[1].symbols, ["ETHUSDT"])
    }

    func testSkipsDaysThatAlreadyHaveAnEntry() {
        let plan = PositionEntryPlanner.plan(
            positions: [position("a", symbol: "BTCUSDT", openTime: date(2026, 8, 1))],
            existingDayKeys: ["2026-08-01"],
            handledPositionIDs: [],
            dayKey: dayKey,
            startOfDay: startOfDay
        )
        XCTAssertTrue(plan.isEmpty)
    }

    func testSkipsHandledPositionsEvenWhenTheirEntryWasDeleted() {
        let plan = PositionEntryPlanner.plan(
            positions: [position("a", symbol: "BTCUSDT", openTime: date(2026, 8, 1))],
            existingDayKeys: [],
            handledPositionIDs: ["a"],
            dayKey: dayKey,
            startOfDay: startOfDay
        )
        XCTAssertTrue(plan.isEmpty)
    }

    func testMultipleSessionsSameSymbolSameDayCollapseToOneItem() {
        let plan = PositionEntryPlanner.plan(
            positions: [
                position("a", symbol: "BTCUSDT", openTime: date(2026, 8, 1, hour: 1)),
                position("b", symbol: "BTCUSDT", openTime: date(2026, 8, 1, hour: 22))
            ],
            existingDayKeys: [],
            handledPositionIDs: [],
            dayKey: dayKey,
            startOfDay: startOfDay
        )
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].symbols, ["BTCUSDT"])
        XCTAssertEqual(Set(plan[0].positionIDs), ["a", "b"])
    }

    func testPlansSortedByDayAscending() {
        let plan = PositionEntryPlanner.plan(
            positions: [
                position("late", symbol: "BTCUSDT", openTime: date(2026, 8, 5)),
                position("early", symbol: "BTCUSDT", openTime: date(2026, 7, 20))
            ],
            existingDayKeys: [],
            handledPositionIDs: [],
            dayKey: dayKey,
            startOfDay: startOfDay
        )
        XCTAssertEqual(plan.map(\.dayKey), ["2026-07-20", "2026-08-05"])
    }
}
