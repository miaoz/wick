import XCTest

@testable import WickTrading

private func fill(
    _ id: Int64,
    symbol: String = "BTCUSDT",
    side: String,
    positionSide: String = "BOTH",
    price: Double,
    qty: Double,
    realizedPnl: Double = 0,
    commission: Double = 0,
    commissionAsset: String = "USDT",
    time: Int64
) -> TradingFill {
    TradingFill(
        id: id,
        symbol: symbol,
        side: side,
        positionSide: positionSide,
        price: price,
        qty: qty,
        commission: commission,
        commissionAsset: commissionAsset,
        realizedPnl: realizedPnl,
        time: time
    )
}

final class PositionAggregatorTests: XCTestCase {
    func testRoundTripLong() {
        let positions = PositionAggregator.aggregate(fills: [
            fill(1, side: "BUY", price: 100, qty: 0.002, commission: 0.01, time: 1000),
            fill(2, side: "SELL", price: 110, qty: 0.002, realizedPnl: 0.2, commission: 0.01, time: 2000)
        ])

        XCTAssertEqual(positions.count, 1)
        let position = positions[0]
        XCTAssertEqual(position.side, .long)
        XCTAssertTrue(position.isClosed)
        XCTAssertEqual(position.openTime, Date(timeIntervalSince1970: 1))
        XCTAssertEqual(position.closeTime, Date(timeIntervalSince1970: 2))
        XCTAssertEqual(position.entryPrice, 100, accuracy: 1e-9)
        XCTAssertEqual(position.exitPrice ?? 0, 110, accuracy: 1e-9)
        XCTAssertEqual(position.peakSize, 0.002, accuracy: 1e-9)
        XCTAssertEqual(position.realizedPnl, 0.2, accuracy: 1e-9)
        XCTAssertEqual(position.commissions["USDT"] ?? 0, 0.02, accuracy: 1e-9)
    }

    func testPyramidAndStagedExit() {
        let positions = PositionAggregator.aggregate(fills: [
            fill(1, side: "BUY", price: 100, qty: 1, time: 1000),
            fill(2, side: "BUY", price: 120, qty: 1, time: 2000),
            fill(3, side: "SELL", price: 130, qty: 1, realizedPnl: 20, time: 3000),
            fill(4, side: "SELL", price: 140, qty: 1, realizedPnl: 30, time: 4000)
        ])

        XCTAssertEqual(positions.count, 1)
        XCTAssertEqual(positions[0].entryPrice, 110, accuracy: 1e-9)
        XCTAssertEqual(positions[0].exitPrice ?? 0, 135, accuracy: 1e-9)
        XCTAssertEqual(positions[0].peakSize, 2, accuracy: 1e-9)
        XCTAssertEqual(positions[0].realizedPnl, 50, accuracy: 1e-9)
    }

    func testShortSession() {
        let positions = PositionAggregator.aggregate(fills: [
            fill(1, side: "SELL", price: 100, qty: 1, time: 1000),
            fill(2, side: "BUY", price: 90, qty: 1, realizedPnl: 10, time: 2000)
        ])

        XCTAssertEqual(positions.count, 1)
        XCTAssertEqual(positions[0].side, .short)
        XCTAssertEqual(positions[0].entryPrice, 100, accuracy: 1e-9)
        XCTAssertEqual(positions[0].exitPrice ?? 0, 90, accuracy: 1e-9)
        XCTAssertEqual(positions[0].realizedPnl, 10, accuracy: 1e-9)
    }

    func testFlipSplitsIntoTwoSessions() {
        let positions = PositionAggregator.aggregate(fills: [
            fill(1, side: "BUY", price: 100, qty: 1, time: 1000),
            fill(2, side: "SELL", price: 110, qty: 3, realizedPnl: 10, time: 2000)
        ])

        XCTAssertEqual(positions.count, 2)

        let closed = positions[0]
        XCTAssertEqual(closed.side, .long)
        XCTAssertTrue(closed.isClosed)
        XCTAssertEqual(closed.closeTime, Date(timeIntervalSince1970: 2))
        XCTAssertEqual(closed.realizedPnl, 10, accuracy: 1e-9)
        XCTAssertEqual(closed.exitPrice ?? 0, 110, accuracy: 1e-9)

        let flipped = positions[1]
        XCTAssertEqual(flipped.side, .short)
        XCTAssertFalse(flipped.isClosed)
        XCTAssertEqual(flipped.openTime, Date(timeIntervalSince1970: 2))
        XCTAssertEqual(flipped.entryPrice, 110, accuracy: 1e-9)
        XCTAssertEqual(flipped.peakSize, 2, accuracy: 1e-9)
        XCTAssertNil(flipped.exitPrice)
        // Realized PnL and commission belong to the closing session.
        XCTAssertEqual(flipped.realizedPnl, 0, accuracy: 1e-9)
        XCTAssertNotEqual(closed.id, flipped.id)
    }

    func testHedgeModeLanesAreIndependent() {
        let positions = PositionAggregator.aggregate(fills: [
            fill(1, side: "BUY", positionSide: "LONG", price: 100, qty: 1, time: 1000),
            fill(2, side: "SELL", positionSide: "SHORT", price: 105, qty: 1, time: 2000)
        ])

        XCTAssertEqual(positions.count, 2)
        XCTAssertTrue(positions.contains { $0.side == .long && !$0.isClosed })
        XCTAssertTrue(positions.contains { $0.side == .short && !$0.isClosed })
    }

    func testStillOpenPositionHasNoCloseTime() {
        let positions = PositionAggregator.aggregate(fills: [
            fill(1, side: "BUY", price: 100, qty: 1, time: 1000)
        ])

        XCTAssertEqual(positions.count, 1)
        XCTAssertFalse(positions[0].isClosed)
        XCTAssertNil(positions[0].closeTime)
        XCTAssertNil(positions[0].exitPrice)
    }

    func testSequentialSessionsInOneLane() {
        let positions = PositionAggregator.aggregate(fills: [
            fill(1, side: "BUY", price: 100, qty: 1, time: 1000),
            fill(2, side: "SELL", price: 110, qty: 1, realizedPnl: 10, time: 2000),
            fill(3, side: "BUY", price: 200, qty: 1, time: 3000)
        ])

        XCTAssertEqual(positions.count, 2)
        XCTAssertTrue(positions[0].isClosed)
        XCTAssertFalse(positions[1].isClosed)
        XCTAssertEqual(positions[1].entryPrice, 200, accuracy: 1e-9)
    }

    func testPeakSizeSurvivesPartialReductions() {
        let positions = PositionAggregator.aggregate(fills: [
            fill(1, side: "BUY", price: 100, qty: 2, time: 1000),
            fill(2, side: "SELL", price: 110, qty: 1, realizedPnl: 10, time: 2000),
            fill(3, side: "SELL", price: 120, qty: 1, realizedPnl: 20, time: 3000)
        ])

        XCTAssertEqual(positions.count, 1)
        XCTAssertEqual(positions[0].peakSize, 2, accuracy: 1e-9)
        XCTAssertEqual(positions[0].exitPrice ?? 0, 115, accuracy: 1e-9)
    }

    func testIgnoresZeroQuantityAndUnsortedInput() {
        let positions = PositionAggregator.aggregate(fills: [
            fill(3, side: "SELL", price: 140, qty: 2, realizedPnl: 60, time: 4000),
            fill(2, side: "BUY", price: 120, qty: 1, time: 2000),
            fill(4, side: "BUY", price: 999, qty: 0, time: 5000),
            fill(1, side: "BUY", price: 100, qty: 1, time: 1000)
        ])

        XCTAssertEqual(positions.count, 1)
        XCTAssertTrue(positions[0].isClosed)
        XCTAssertEqual(positions[0].entryPrice, 110, accuracy: 1e-9)
    }

    func testMultipleSymbolsSortedByOpenTime() {
        let positions = PositionAggregator.aggregate(fills: [
            fill(1, symbol: "ETHUSDT", side: "BUY", price: 3, qty: 1, time: 2000),
            fill(2, symbol: "BTCUSDT", side: "BUY", price: 100, qty: 1, time: 1000)
        ])

        XCTAssertEqual(positions.map(\.symbol), ["BTCUSDT", "ETHUSDT"])
    }

    // MARK: Floating-point residue (the phantom "tiny open position" bug)

    /// Decimal-exact full closes must not leave a session open: 0.004 + 0.014
    /// - 0.018 is ~3.5e-18 in binary doubles, not zero.
    func testFullCloseWithResidueClosesCleanly() {
        let residue = 0.004 + 0.014 - 0.018
        XCTAssertNotEqual(residue, 0, "fixture must actually produce FP residue")

        let positions = PositionAggregator.aggregate(fills: [
            fill(1, symbol: "XAUTUSDT", side: "BUY", price: 2400, qty: 0.004, time: 1000),
            fill(2, symbol: "XAUTUSDT", side: "BUY", price: 2500, qty: 0.014, time: 2000),
            fill(3, symbol: "XAUTUSDT", side: "SELL", price: 2600, qty: 0.018, realizedPnl: 2.1, time: 3000)
        ])

        XCTAssertEqual(positions.count, 1, "no phantom residue session")
        XCTAssertTrue(positions[0].isClosed)
        XCTAssertEqual(positions[0].peakSize, 0.018, accuracy: 1e-9)
        XCTAssertEqual(positions[0].realizedPnl, 2.1, accuracy: 1e-9)
    }

    /// A close that lands epsilon *past* zero must not spawn a ~1e-18 flip
    /// session - that is exactly the "0.00000xx still-open position" symptom.
    func testResidueFlipPastZeroSpawnsNoDustSession() {
        let residue = -0.004 - 0.014 + 0.018
        XCTAssertNotEqual(residue, 0, "fixture must actually produce FP residue")

        let positions = PositionAggregator.aggregate(fills: [
            fill(1, symbol: "XAUTUSDT", side: "SELL", price: 2400, qty: 0.004, time: 1000),
            fill(2, symbol: "XAUTUSDT", side: "SELL", price: 2500, qty: 0.014, time: 2000),
            fill(3, symbol: "XAUTUSDT", side: "BUY", price: 2600, qty: 0.018, realizedPnl: -2.1, time: 3000)
        ])

        XCTAssertEqual(positions.count, 1, "no dust session from the flip past zero")
        XCTAssertEqual(positions[0].side, .short)
        XCTAssertTrue(positions[0].isClosed)
        XCTAssertEqual(positions[0].peakSize, 0.018, accuracy: 1e-9)
    }

    /// The epsilon must not swallow genuinely small open positions.
    func testGenuineDustPositionStaysOpen() {
        let positions = PositionAggregator.aggregate(fills: [
            fill(1, symbol: "XAUTUSDT", side: "BUY", price: 2400, qty: 0.000004, time: 1000)
        ])

        XCTAssertEqual(positions.count, 1)
        XCTAssertFalse(positions[0].isClosed)
        XCTAssertEqual(positions[0].peakSize, 0.000004, accuracy: 1e-12)
    }

    /// A later real position after a residue-producing close stays one clean
    /// session instead of merging through the leaked epsilon.
    func testNextSessionAfterResidueCloseIsIndependent() {
        let positions = PositionAggregator.aggregate(fills: [
            fill(1, symbol: "XAUTUSDT", side: "BUY", price: 2400, qty: 0.004, time: 1000),
            fill(2, symbol: "XAUTUSDT", side: "BUY", price: 2500, qty: 0.014, time: 2000),
            fill(3, symbol: "XAUTUSDT", side: "SELL", price: 2600, qty: 0.018, time: 3000),
            fill(4, symbol: "XAUTUSDT", side: "BUY", price: 2700, qty: 0.002, time: 4000)
        ])

        XCTAssertEqual(positions.count, 2)
        XCTAssertTrue(positions[0].isClosed)
        XCTAssertFalse(positions[1].isClosed)
        XCTAssertEqual(positions[1].entryPrice, 2700, accuracy: 1e-9)
        XCTAssertEqual(positions[1].peakSize, 0.002, accuracy: 1e-9)
    }
}

final class SymbolTagMatcherTests: XCTestCase {
    func testBaseAssetTagMatchesPairs() {
        XCTAssertTrue(SymbolTagMatcher.matches(tag: "BTC", symbol: "BTCUSDT"))
        XCTAssertTrue(SymbolTagMatcher.matches(tag: "BTC", symbol: "BTCUSDC"))
        XCTAssertTrue(SymbolTagMatcher.matches(tag: "btc", symbol: "btcusdt"))
    }

    func testSeparatorAndCaseNormalization() {
        XCTAssertTrue(SymbolTagMatcher.matches(tag: "BTC/USDT", symbol: "BTCUSDT"))
        XCTAssertTrue(SymbolTagMatcher.matches(tag: "btc-usdt", symbol: "BTCUSDT"))
        XCTAssertTrue(SymbolTagMatcher.matches(tag: " btc ", symbol: "BTCUSDT"))
    }

    func testDerivativePrefixStripping() {
        XCTAssertTrue(SymbolTagMatcher.matches(tag: "PEPE", symbol: "1000PEPEUSDT"))
        XCTAssertTrue(SymbolTagMatcher.matches(tag: "MOG", symbol: "1000000MOGUSDT"))
        XCTAssertTrue(SymbolTagMatcher.matches(tag: "1000PEPE", symbol: "1000PEPEUSDT"))
    }

    func testExactPairTagMatchesOnlyThatPair() {
        XCTAssertTrue(SymbolTagMatcher.matches(tag: "BTCUSDT", symbol: "BTCUSDT"))
        XCTAssertFalse(SymbolTagMatcher.matches(tag: "BTCUSDT", symbol: "BTCUSDC"))
    }

    func testBareBaseMatchesHyperliquidCoinAndPair() {
        XCTAssertTrue(SymbolTagMatcher.matches(tag: "BTC", symbol: "BTC"))
        XCTAssertTrue(SymbolTagMatcher.matches(tag: "BTCUSDT", symbol: "BTC"))
        XCTAssertFalse(SymbolTagMatcher.matches(tag: "ETH", symbol: "ETHBTC"))
    }

    func testNonMatches() {
        XCTAssertFalse(SymbolTagMatcher.matches(tag: "ETH", symbol: "BTCUSDT"))
        XCTAssertFalse(SymbolTagMatcher.matches(tag: "USDT", symbol: "BTCUSDT"))
        XCTAssertFalse(SymbolTagMatcher.matches(tag: "", symbol: "BTCUSDT"))
        XCTAssertFalse(SymbolTagMatcher.matches(tag: "BTC", symbol: ""))
        XCTAssertFalse(SymbolTagMatcher.matches(tag: "  ", symbol: "BTCUSDT"))
    }

    func testFilterByTag() {
        let positions = [
            TradingPosition(
                id: "1", symbol: "BTCUSDT", side: .long,
                openTime: Date(timeIntervalSince1970: 1000), closeTime: nil,
                entryPrice: 100, exitPrice: nil, peakSize: 1, realizedPnl: 0
            ),
            TradingPosition(
                id: "2", symbol: "ETHUSDT", side: .long,
                openTime: Date(timeIntervalSince1970: 1000), closeTime: nil,
                entryPrice: 3, exitPrice: nil, peakSize: 1, realizedPnl: 0
            ),
            TradingPosition(
                id: "3", symbol: "BTCUSDC", side: .short,
                openTime: Date(timeIntervalSince1970: 1000), closeTime: nil,
                entryPrice: 100, exitPrice: nil, peakSize: 1, realizedPnl: 0
            )
        ]

        XCTAssertEqual(
            SymbolTagMatcher.filter(positions, matchingTag: "BTC").map(\.symbol),
            ["BTCUSDT", "BTCUSDC"]
        )
        XCTAssertEqual(SymbolTagMatcher.filter(positions, matchingTag: "").count, 0)
    }

    // MARK: Preferred (user's own) tag naming for auto-created items

    func testPreferredTagPicksMostUsedMatchingSpelling() {
        XCTAssertEqual(
            SymbolTagMatcher.preferredTag(
                matching: "BTCUSDT",
                tagCounts: ["BTC": 5, "btc": 2, "ETH": 9]
            ),
            "BTC"
        )
    }

    func testPreferredTagTiePrefersShorterSpelling() {
        XCTAssertEqual(
            SymbolTagMatcher.preferredTag(
                matching: "BTCUSDT",
                tagCounts: ["BTCUSDT": 3, "BTC": 3]
            ),
            "BTC"
        )
    }

    func testPreferredTagReusesExactSymbolSpelling() {
        XCTAssertEqual(
            SymbolTagMatcher.preferredTag(
                matching: "BTCUSDT",
                tagCounts: ["BTCUSDT": 4, "BTC": 1]
            ),
            "BTCUSDT"
        )
    }

    func testPreferredTagReturnsNilWithoutAnyMatch() {
        XCTAssertNil(
            SymbolTagMatcher.preferredTag(matching: "BTCUSDT", tagCounts: ["ETH": 3, "SOL": 1])
        )
        XCTAssertNil(SymbolTagMatcher.preferredTag(matching: "BTCUSDT", tagCounts: [:]))
    }

    // MARK: Base-asset derivation (auto-created item tags)

    func testBaseAssetStripsQuoteSuffix() {
        XCTAssertEqual(SymbolTagMatcher.baseAsset(of: "BTCUSDT"), "BTC")
        XCTAssertEqual(SymbolTagMatcher.baseAsset(of: "BTCUSDC"), "BTC")
        XCTAssertEqual(SymbolTagMatcher.baseAsset(of: "XAUTUSDT"), "XAUT")
        XCTAssertEqual(SymbolTagMatcher.baseAsset(of: "ETHBTC"), "ETH")
    }

    func testBaseAssetStripsDerivativePrefix() {
        XCTAssertEqual(SymbolTagMatcher.baseAsset(of: "1000PEPEUSDT"), "PEPE")
        XCTAssertEqual(SymbolTagMatcher.baseAsset(of: "1000000MOGUSDT"), "MOG")
    }

    func testBaseAssetFallsBackToSymbolWithoutKnownQuote() {
        XCTAssertEqual(SymbolTagMatcher.baseAsset(of: "SUPERSTRANGE"), "SUPERSTRANGE")
    }
}

final class TradingModelTests: XCTestCase {
    func testFillDecodesBinanceStringNumbers() throws {
        let json = """
        [{"buyer":false,"commission":"-0.07819010","commissionAsset":"USDT",
        "id":698759,"maker":false,"orderId":25851813,"price":"7819.99",
        "qty":"0.002","quoteQty":"15.639","realizedPnl":"-0.91539999",
        "side":"SELL","positionSide":"SHORT","symbol":"BTCUSDT","time":1706261372000}]
        """.data(using: .utf8)!

        let fills = try JSONDecoder().decode([TradingFill].self, from: json)
        XCTAssertEqual(fills.count, 1)
        XCTAssertEqual(fills[0].id, 698759)
        XCTAssertEqual(fills[0].positionSide, "SHORT")
        XCTAssertEqual(fills[0].price, 7819.99, accuracy: 1e-9)
        XCTAssertEqual(fills[0].qty, 0.002, accuracy: 1e-9)
        XCTAssertEqual(fills[0].commission, -0.07819010, accuracy: 1e-9)
        XCTAssertEqual(fills[0].realizedPnl, -0.91539999, accuracy: 1e-9)
        XCTAssertEqual(fills[0].time, 1706261372000)
    }

    func testSnapshotRoundTrip() throws {
        let snapshot = TradingPositionSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1700000000),
            windowStart: Date(timeIntervalSince1970: 1_699_000_000),
            positions: [
                TradingPosition(
                    id: "BTCUSDT|BOTH|1000|1",
                    symbol: "BTCUSDT",
                    side: .long,
                    openTime: Date(timeIntervalSince1970: 1),
                    closeTime: Date(timeIntervalSince1970: 2),
                    entryPrice: 100,
                    exitPrice: 110,
                    peakSize: 0.5,
                    realizedPnl: 5,
                    commissions: ["USDT": 0.02]
                )
            ],
            fills: [
                TradingFill(
                    id: 1,
                    symbol: "BTCUSDT",
                    side: "BUY",
                    price: 100,
                    qty: 0.5,
                    time: 1000
                )
            ],
            handledPositionIDs: ["BTCUSDT|BOTH|1000|1"]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(TradingPositionSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func testSnapshotDecodesLegacyShapeWithoutFills() throws {
        // windowStart missing => legacy cache discarded by caller (nil on
        // decode), so only the soft-defaulted fields need to stay decodable
        // when the key exists. Verify fills/handled default when absent.
        let json = """
        {"version":1,"fetchedAt":1700000000,"windowStart":1699000000,
         "positions":[]}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TradingPositionSnapshot.self, from: json)
        XCTAssertEqual(decoded.fills, [])
        XCTAssertEqual(decoded.handledPositionIDs, [])
    }

    func testQuoteAssetInference() {
        func position(_ symbol: String) -> TradingPosition {
            TradingPosition(
                id: symbol, symbol: symbol, side: .long,
                openTime: Date(), closeTime: nil,
                entryPrice: 1, exitPrice: nil, peakSize: 1, realizedPnl: 0
            )
        }
        XCTAssertEqual(position("BTCUSDT").quoteAsset, "USDT")
        XCTAssertEqual(position("BTCUSDC").quoteAsset, "USDC")
        XCTAssertNil(position("SUPERSTRANGE").quoteAsset)
    }
}
