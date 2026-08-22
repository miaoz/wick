import XCTest
@testable import WickTrading

private func position(
    id: String,
    symbol: String = "BTCUSDT",
    openTime: Int64,
    closeTime: Int64? = nil
) -> TradingPosition {
    TradingPosition(
        id: id,
        symbol: symbol,
        side: .long,
        openTime: Date(timeIntervalSince1970: Double(openTime) / 1000),
        closeTime: closeTime.map { Date(timeIntervalSince1970: Double($0) / 1000) },
        entryPrice: 100,
        exitPrice: closeTime == nil ? nil : 110,
        peakSize: 1,
        realizedPnl: 0
    )
}

private func funding(_ symbol: String, _ amount: Double, _ time: Int64) -> FundingEvent {
    FundingEvent(symbol: symbol, amount: amount, time: time)
}

final class FundingAttributorTests: XCTestCase {
    func testAttachesFundingInsideOpenWindow() {
        let attached = FundingAttributor.attach(
            positions: [position(id: "A", openTime: 1000, closeTime: 5000)],
            funding: [
                funding("BTCUSDT", -1.0, 2000),
                funding("BTCUSDT", -0.5, 4000),
                funding("BTCUSDT", -9.0, 9000), // after close — dropped
            ]
        )
        XCTAssertEqual(attached[0].fundingPnl, -1.5, accuracy: 1e-12)
    }

    func testOpenPositionReceivesFundingThroughLastEvent() {
        let attached = FundingAttributor.attach(
            positions: [position(id: "A", openTime: 1000)],
            funding: [
                funding("BTCUSDT", -0.2, 2000),
                funding("BTCUSDT", -0.3, 4000),
            ]
        )
        XCTAssertEqual(attached[0].fundingPnl, -0.5, accuracy: 1e-12)
    }

    func testFundingBeforeOpenIsIgnored() {
        let attached = FundingAttributor.attach(
            positions: [position(id: "A", openTime: 5000)],
            funding: [funding("BTCUSDT", -1.0, 1000)]
        )
        XCTAssertEqual(attached[0].fundingPnl, 0, accuracy: 1e-12)
    }

    func testSymbolMismatchIsIgnored() {
        let attached = FundingAttributor.attach(
            positions: [position(id: "A", symbol: "BTCUSDT", openTime: 1000, closeTime: 5000)],
            funding: [funding("ETHUSDT", -1.0, 2000)]
        )
        XCTAssertEqual(attached[0].fundingPnl, 0, accuracy: 1e-12)
    }

    func testHedgeOverlapAssignsEachEventExactlyOnce() {
        // Both lanes open and overlapping: the event must land on exactly one
        // position (earliest-opened) so it is never double-counted.
        let long = position(id: "BTCUSDT|LONG|1000|1", openTime: 1000)
        let short = position(id: "BTCUSDT|SHORT|2000|2", openTime: 2000)
        let attached = FundingAttributor.attach(
            positions: [long, short],
            funding: [funding("BTCUSDT", -1.0, 3000)]
        )
        let longPnl = attached.first { $0.id == long.id }!.fundingPnl
        let shortPnl = attached.first { $0.id == short.id }!.fundingPnl
        XCTAssertEqual(longPnl + shortPnl, -1.0, accuracy: 1e-12)
        XCTAssertEqual(abs(longPnl) + abs(shortPnl), 1.0, accuracy: 1e-12)
    }

    func testEmptyFundingLeavesPositionsUntouched() {
        let source = [position(id: "A", openTime: 1000, closeTime: 5000)]
        let attached = FundingAttributor.attach(positions: source, funding: [])
        XCTAssertEqual(attached, source)
    }

    func testNoMatchingSymbolYieldsPositionsWithZeroFunding() {
        let attached = FundingAttributor.attach(
            positions: [position(id: "A", symbol: "BTCUSDT", openTime: 1000)],
            funding: [funding("ETHUSDT", -1.0, 2000)]
        )
        XCTAssertEqual(attached[0].fundingPnl, 0, accuracy: 1e-12)
    }
}
