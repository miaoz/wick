import XCTest
@testable import WickTrading

private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

final class OKXSwapClientTests: XCTestCase {
    private static let secret = "secret-key-for-okx-test-vector-32b"
    private static let passphrase = "pass-phrase"
    private static let fixedNow: Date = {
        var components = DateComponents()
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2020
        components.month = 12
        components.day = 8
        components.hour = 9
        components.minute = 8
        components.second = 57
        components.nanosecond = 715_000_000
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    private func makeClient(
        transport: @escaping OKXSwapClient.Transport
    ) -> OKXSwapClient {
        OKXSwapClient(
            apiKey: "okx-key",
            secret: Self.secret,
            passphrase: Self.passphrase,
            baseURL: URL(string: "https://okx.example.com")!,
            transport: transport,
            now: { Self.fixedNow },
            pageLimit: 2
        )
    }

    private static func http(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://okx.example.com/")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    func testSignMatchesKnownVector() {
        let timestamp = "2020-12-08T09:08:57.715Z"
        let prehash = OKXSwapClient.prehash(
            timestamp: timestamp,
            method: "GET",
            requestPath: "/api/v5/trade/fills-history?instType=SWAP"
        )
        XCTAssertEqual(
            OKXSwapClient.sign(prehash: prehash, secret: Self.secret),
            "DtPXA1IbRFt3vgzbbsye324pnUboRK29a0HgK2XCq0Q="
        )
    }

    func testTimestampStringIsISO8601UTC() {
        XCTAssertEqual(
            OKXSwapClient.timestampString(from: Self.fixedNow),
            "2020-12-08T09:08:57.715Z"
        )
    }

    func testInstIDMapping() {
        XCTAssertEqual(OKXSwapClient.symbol(fromInstID: "BTC-USDT-SWAP"), "BTCUSDT")
        XCTAssertEqual(OKXSwapClient.symbol(fromInstID: "ETH-USDT-SWAP"), "ETHUSDT")
        XCTAssertEqual(OKXSwapClient.symbol(fromInstID: "BTC-USD-SWAP"), "BTCUSD")
    }

    func testSignedRequestCarriesOKXHeaders() async throws {
        let client = makeClient { _ in
            (Data(#"{"code":"0","data":[]}"#.utf8), Self.http(200))
        }
        let request = try client.signedRequest(
            method: "GET",
            requestPath: "/api/v5/trade/fills-history?instType=SWAP",
            body: ""
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "OK-ACCESS-KEY"), "okx-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "OK-ACCESS-PASSPHRASE"), Self.passphrase)
        XCTAssertEqual(request.value(forHTTPHeaderField: "OK-ACCESS-TIMESTAMP"), "2020-12-08T09:08:57.715Z")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "OK-ACCESS-SIGN"),
            "DtPXA1IbRFt3vgzbbsye324pnUboRK29a0HgK2XCq0Q="
        )
    }

    func testFillsPageMapsAndPaginates() async throws {
        let calls = Box(0)
        let client = makeClient { request in
            calls.value += 1
            XCTAssertTrue(request.url?.absoluteString.contains("instType=SWAP") == true)
            if calls.value == 1 {
                XCTAssertFalse(request.url?.absoluteString.contains("after=") == true)
                let body = #"""
                {"code":"0","data":[
                  {"instId":"BTC-USDT-SWAP","tradeId":"11","billId":"b1","side":"buy","posSide":"long","fillPx":"100","fillSz":"0.2","fillPnl":"1.5","fee":"-0.01","feeCcy":"USDT","ts":"1600000000000"},
                  {"instId":"ETH-USDT-SWAP","tradeId":"12","billId":"b2","side":"sell","posSide":"net","fillPx":"200","fillSz":"1","fillPnl":"0","fee":"0","feeCcy":"USDT","ts":"1600000001000"}
                ]}
                """#
                return (Data(body.utf8), Self.http(200))
            }
            XCTAssertTrue(request.url?.absoluteString.contains("after=b2") == true)
            return (Data(#"{"code":"0","data":[]}"#.utf8), Self.http(200))
        }
        let fills = try await client.fetchFills(
            from: Date(timeIntervalSince1970: 1_600_000_000),
            to: Date(timeIntervalSince1970: 1_600_100_000)
        )
        XCTAssertEqual(calls.value, 2)
        XCTAssertEqual(fills.count, 2)
        XCTAssertEqual(fills[0].symbol, "BTCUSDT")
        XCTAssertEqual(fills[0].side, "BUY")
        XCTAssertEqual(fills[0].positionSide, "LONG")
        XCTAssertEqual(fills[0].price, 100)
        XCTAssertEqual(fills[0].qty, 0.2, accuracy: 0.0001)
        XCTAssertEqual(fills[0].realizedPnl, 1.5, accuracy: 0.0001)
        XCTAssertEqual(fills[1].symbol, "ETHUSDT")
        XCTAssertEqual(fills[1].positionSide, "BOTH")
        XCTAssertEqual(fills[1].side, "SELL")
    }

    func testDropsFillsBeforeRequestedStart() async throws {
        let client = makeClient { _ in
            let body = #"""
            {"code":"0","data":[
              {"instId":"BTC-USDT-SWAP","tradeId":"1","billId":"old","side":"buy","posSide":"net","fillPx":"1","fillSz":"1","fillPnl":"0","fee":"0","feeCcy":"USDT","ts":"1000000000000"},
              {"instId":"BTC-USDT-SWAP","tradeId":"2","billId":"new","side":"buy","posSide":"net","fillPx":"1","fillSz":"1","fillPnl":"0","fee":"0","feeCcy":"USDT","ts":"1600000500000"}
            ]}
            """#
            return (Data(body.utf8), Self.http(200))
        }
        let fills = try await client.fetchFills(
            from: Date(timeIntervalSince1970: 1_600_000_000),
            to: Date(timeIntervalSince1970: 1_600_100_000)
        )
        XCTAssertEqual(fills.map(\.id), [2])
    }

    func testFetchFundingMapsBills() async throws {
        let calls = Box(0)
        let captured = Box<String?>(nil)
        let client = makeClient { request in
            calls.value += 1
            captured.value = request.url?.absoluteString
            if calls.value == 1 {
                let body = #"""
                {"code":"0","data":[
                  {"billId":"b1","instId":"BTC-USDT-SWAP","ts":"1600000000000","type":"8","subType":"8","pnl":"-0.5","fee":"0","ccy":"USDT"},
                  {"billId":"b2","instId":"ETH-USDT-SWAP","ts":"1600000001000","type":"8","subType":"8","pnl":"0","fee":"-0.25","ccy":"USDT"}
                ]}
                """#
                return (Data(body.utf8), Self.http(200))
            }
            return (Data(#"{"code":"0","data":[]}"#.utf8), Self.http(200))
        }
        let events = try await client.fetchFunding(
            from: Date(timeIntervalSince1970: 1_600_000_000),
            to: Date(timeIntervalSince1970: 1_600_100_000)
        )
        XCTAssertEqual(calls.value, 2)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].symbol, "BTCUSDT")
        XCTAssertEqual(events[0].amount, -0.5, accuracy: 1e-12)
        XCTAssertEqual(events[0].time, 1_600_000_000_000)
        XCTAssertEqual(events[1].symbol, "ETHUSDT")
        XCTAssertEqual(events[1].amount, -0.25, accuracy: 1e-12)
        XCTAssertTrue(
            captured.value?.contains("type=8") == true,
            "query must filter funding bills (type=8), got \(captured.value ?? "nil")"
        )
    }

    func testInvalidKeyCode() async {
        let client = makeClient { _ in
            (Data(#"{"code":"50111","msg":"Invalid API Key","data":[]}"#.utf8), Self.http(200))
        }
        do {
            _ = try await client.fetchFills(
                from: Date(timeIntervalSince1970: 1),
                to: Date(timeIntervalSince1970: 2)
            )
            XCTFail("expected throw")
        } catch let error as ExchangeClientError {
            XCTAssertTrue(error.isAuthFailure)
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testRateLimited() async {
        let client = makeClient { _ in (Data(), Self.http(429)) }
        do {
            _ = try await client.fetchFills(
                from: Date(timeIntervalSince1970: 1),
                to: Date(timeIntervalSince1970: 2)
            )
            XCTFail("expected throw")
        } catch let error as ExchangeClientError {
            XCTAssertEqual(error, .rateLimited)
        } catch {
            XCTFail("wrong error \(error)")
        }
    }
}
