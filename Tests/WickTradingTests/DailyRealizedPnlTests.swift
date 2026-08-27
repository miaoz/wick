import XCTest

@testable import WickTrading

final class DailyRealizedPnlTests: XCTestCase {
    private static var gmt: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT")!
        return calendar
    }

    private static let day: TimeInterval = 24 * 3600

    private func position(
        id: String,
        symbol: String = "BTCUSDT",
        realizedPnl: Double,
        openedAt: TimeInterval,
        closedAt: TimeInterval? = nil,
        commissions: [String: Double] = [:],
        fundingPnl: Double = 0
    ) -> TradingPosition {
        TradingPosition(
            id: id,
            symbol: symbol,
            side: .long,
            openTime: Date(timeIntervalSince1970: openedAt),
            closeTime: closedAt.map(Date.init(timeIntervalSince1970:)),
            entryPrice: 50_000,
            exitPrice: closedAt == nil ? nil : 51_000,
            peakSize: 1,
            realizedPnl: realizedPnl,
            commissions: commissions,
            fundingPnl: fundingPnl
        )
    }

    private func dayStart(_ seconds: TimeInterval) -> Date {
        Self.gmt.startOfDay(for: Date(timeIntervalSince1970: seconds))
    }

    func testSameOpenDayPositionsAreSummed() {
        let base = TimeInterval(17_000) * Self.day
        let sums = DailyRealizedPnl.sumsByOpenDay(
            positions: [
                position(id: "one", realizedPnl: 10.5, openedAt: base + 3600),
                position(id: "two", realizedPnl: -4.25, openedAt: base + 7200),
                position(id: "three", realizedPnl: 1, openedAt: base + 10_000),
            ],
            calendar: Self.gmt
        )

        XCTAssertEqual(sums.count, 1)
        XCTAssertEqual(sums[dayStart(base)] ?? 0, 7.25, accuracy: 1e-12)
    }

    func testZeroRealizedPnlDoesNotMarkAnOpenDay() {
        let base = TimeInterval(17_000) * Self.day
        let sums = DailyRealizedPnl.sumsByOpenDay(
            positions: [position(id: "open", realizedPnl: 0, openedAt: base + 3600)],
            calendar: Self.gmt
        )

        XCTAssertTrue(sums.isEmpty)
    }

    func testPnlIsAttributedToOpenDayRatherThanCloseDay() {
        let openDay = TimeInterval(17_000) * Self.day
        let closeDay = openDay + 2 * Self.day
        let sums = DailyRealizedPnl.sumsByOpenDay(
            positions: [
                position(
                    id: "multi-day",
                    realizedPnl: -137.9994,
                    openedAt: openDay + 3 * 3600,
                    closedAt: closeDay + 16 * 3600
                )
            ],
            calendar: Self.gmt
        )

        XCTAssertEqual(sums.count, 1)
        XCTAssertEqual(sums[dayStart(openDay)] ?? 0, -137.9994, accuracy: 1e-12)
        XCTAssertNil(sums[dayStart(closeDay)])
    }

    func testPositionsAreBucketedByOpenDayAcrossMonths() {
        let november = Date(timeIntervalSince1970: TimeInterval(17_016) * Self.day + 23 * 3600)
        let december = Date(timeIntervalSince1970: TimeInterval(17_017) * Self.day + 3600)
        let sums = DailyRealizedPnl.sumsByOpenDay(
            positions: [
                position(id: "november", realizedPnl: 5, openedAt: november.timeIntervalSince1970),
                position(id: "december", realizedPnl: -8, openedAt: december.timeIntervalSince1970),
            ],
            calendar: Self.gmt
        )

        XCTAssertEqual(sums.count, 2)
        XCTAssertEqual(sums[Self.gmt.startOfDay(for: november)] ?? 0, 5, accuracy: 1e-12)
        XCTAssertEqual(sums[Self.gmt.startOfDay(for: december)] ?? 0, -8, accuracy: 1e-12)
    }

    func testEmptyInputYieldsEmptyResult() {
        XCTAssertTrue(
            DailyRealizedPnl.sumsByOpenDay(positions: [], calendar: Self.gmt).isEmpty
        )
    }

    // MARK: - Net PnL (realized − commission − funding)

    func testNetSumsSubtractQuoteCommissionAndFunding() {
        let base = TimeInterval(17_000) * Self.day
        let sums = DailyRealizedPnl.netSumsByOpenDay(
            positions: [
                position(
                    id: "one",
                    realizedPnl: 10,
                    openedAt: base + 3600,
                    commissions: ["USDT": -0.5],
                    fundingPnl: -1.5 // paid out → reduces net
                )
            ],
            calendar: Self.gmt
        )
        XCTAssertEqual(sums[dayStart(base)] ?? 0, 8.0, accuracy: 1e-12)
    }

    func testNetIgnoresNonQuoteCommission() {
        let base = TimeInterval(17_000) * Self.day
        let sums = DailyRealizedPnl.netSumsByOpenDay(
            positions: [
                position(
                    id: "one",
                    realizedPnl: 10,
                    openedAt: base + 3600,
                    commissions: ["BNB": -2.0]
                )
            ],
            calendar: Self.gmt
        )
        // BNB commission is not the quote asset, so it is not netted.
        XCTAssertEqual(sums[dayStart(base)] ?? 0, 10.0, accuracy: 1e-12)
    }

    func testNetFallsBackToAllCommissionsWhenQuoteUnknown() {
        let base = TimeInterval(17_000) * Self.day
        let sums = DailyRealizedPnl.netSumsByOpenDay(
            positions: [
                position(
                    id: "one",
                    symbol: "FOO",
                    realizedPnl: 10,
                    openedAt: base + 3600,
                    commissions: ["USDT": -3.0, "USDC": -2.0]
                )
            ],
            calendar: Self.gmt
        )
        XCTAssertEqual(sums[dayStart(base)] ?? 0, 5.0, accuracy: 1e-12)
    }

    func testNetSkipsDayWhenNetIsZero() {
        let base = TimeInterval(17_000) * Self.day
        let sums = DailyRealizedPnl.netSumsByOpenDay(
            positions: [
                position(
                    id: "one",
                    realizedPnl: 1.0,
                    openedAt: base + 3600,
                    commissions: ["USDT": -1.0]
                )
            ],
            calendar: Self.gmt
        )
        XCTAssertTrue(sums.isEmpty)
    }

    func testNetAddsRebateInsteadOfTreatingItAsCost() {
        // A positive commission is a REBATE (e.g. OKX fee > 0), never a cost —
        // it must ADD to net, not be subtracted as if it were a fee (TR-03).
        let base = TimeInterval(17_000) * Self.day
        let sums = DailyRealizedPnl.netSumsByOpenDay(
            positions: [
                position(
                    id: "one",
                    realizedPnl: 10,
                    openedAt: base + 3600,
                    commissions: ["USDT": 1.5]
                )
            ],
            calendar: Self.gmt
        )
        XCTAssertEqual(sums[dayStart(base)] ?? 0, 11.5, accuracy: 1e-12)
    }

    func testNetIsAttributedToOpenDay() {
        let openDay = TimeInterval(17_000) * Self.day
        let closeDay = openDay + 2 * Self.day
        let sums = DailyRealizedPnl.netSumsByOpenDay(
            positions: [
                position(
                    id: "multi-day",
                    realizedPnl: 100,
                    openedAt: openDay + 3 * 3600,
                    closedAt: closeDay + 16 * 3600,
                    commissions: ["USDT": -1],
                    fundingPnl: -2 // paid out → reduces net
                )
            ],
            calendar: Self.gmt
        )
        XCTAssertEqual(sums[dayStart(openDay)] ?? 0, 97.0, accuracy: 1e-12)
        XCTAssertNil(sums[dayStart(closeDay)])
    }

    func testNetEmptyInputYieldsEmptyResult() {
        XCTAssertTrue(
            DailyRealizedPnl.netSumsByOpenDay(positions: [], calendar: Self.gmt).isEmpty
        )
    }
}
