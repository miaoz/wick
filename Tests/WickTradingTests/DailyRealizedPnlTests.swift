import XCTest

@testable import WickTrading

final class DailyRealizedPnlTests: XCTestCase {
    private static var gmt: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT")!
        return calendar
    }

    private static let day: TimeInterval = 24 * 3600

    private func fill(realizedPnl: Double, at seconds: TimeInterval) -> TradingFill {
        TradingFill(
            id: Int64(seconds),
            symbol: "BTCUSDT",
            side: "SELL",
            price: 50_000,
            qty: 1,
            realizedPnl: realizedPnl,
            time: Int64(seconds * 1000)
        )
    }

    private func dayStart(_ seconds: TimeInterval) -> Date {
        Self.gmt.startOfDay(for: Date(timeIntervalSince1970: seconds))
    }

    func testSameDayFillsAreSummed() {
        // 2023-11-14 is day 17_000 in the Unix epoch.
        let base = TimeInterval(17_000) * Self.day
        let sums = DailyRealizedPnl.sumsByDay(
            fills: [
                fill(realizedPnl: 10.5, at: base + 3600),
                fill(realizedPnl: -4.25, at: base + 7200),
                fill(realizedPnl: 1.0, at: base + 10_000),
            ],
            calendar: Self.gmt
        )
        XCTAssertEqual(sums.count, 1)
        XCTAssertEqual(sums[dayStart(base)] ?? 0, 7.25, accuracy: 1e-12)
    }

    func testOpeningFillsNeverMarkADay() {
        let base = TimeInterval(17_000) * Self.day
        let sums = DailyRealizedPnl.sumsByDay(
            fills: [fill(realizedPnl: 0, at: base + 3600)],
            calendar: Self.gmt
        )
        XCTAssertTrue(sums.isEmpty)
    }

    func testFillsAreBucketedAcrossDaysAndMonths() {
        // 2023-11-30 23:00 UTC and 2023-12-01 01:00 UTC.
        let november = Date(timeIntervalSince1970: TimeInterval(17_016) * Self.day + 23 * 3600)
        let december = Date(timeIntervalSince1970: TimeInterval(17_017) * Self.day + 3600)
        let sums = DailyRealizedPnl.sumsByDay(
            fills: [
                fill(realizedPnl: 5, at: november.timeIntervalSince1970),
                fill(realizedPnl: -8, at: december.timeIntervalSince1970),
            ],
            calendar: Self.gmt
        )
        XCTAssertEqual(sums.count, 2)
        XCTAssertEqual(sums[Self.gmt.startOfDay(for: november)] ?? 0, 5, accuracy: 1e-12)
        XCTAssertEqual(sums[Self.gmt.startOfDay(for: december)] ?? 0, -8, accuracy: 1e-12)
    }

    func testEmptyInputYieldsEmptyResult() {
        XCTAssertTrue(DailyRealizedPnl.sumsByDay(fills: [], calendar: Self.gmt).isEmpty)
    }
}
