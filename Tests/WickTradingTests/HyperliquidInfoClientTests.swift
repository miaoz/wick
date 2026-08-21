import XCTest
@testable import WickTrading

private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

final class HyperliquidInfoClientTests: XCTestCase {
    private static func http(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://hl.example.com/info")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    func testNormalizedAddress() {
        XCTAssertEqual(
            HyperliquidInfoClient.normalizedAddress("0xABCDef0123456789ABCDef0123456789ABCDef01"),
            "0xabcdef0123456789abcdef0123456789abcdef01"
        )
        XCTAssertNil(HyperliquidInfoClient.normalizedAddress("ABCDef0123456789ABCDef0123456789ABCDef01"))
        XCTAssertNil(HyperliquidInfoClient.normalizedAddress("0x123"))
        XCTAssertNil(HyperliquidInfoClient.normalizedAddress(""))
    }

    func testPostBodyAndMapping() async throws {
        let captured = Box<Data?>(nil)
        let client = HyperliquidInfoClient(
            user: "0xabcdef0123456789abcdef0123456789abcdef01",
            baseURL: URL(string: "https://hl.example.com")!,
            transport: { request in
                XCTAssertEqual(request.httpMethod, "POST")
                captured.value = request.httpBody
                let body = #"""
                [{"closedPnl":"1.25","coin":"BTC","px":"40000","side":"B","sz":"0.5","time":1700000000000,"fee":"0.01","feeToken":"USDC","tid":99},
                 {"closedPnl":"0","coin":"ETH","px":"2000","side":"A","sz":"2","time":1700000001000,"fee":"0","feeToken":"USDC","tid":100}]
                """#
                return (Data(body.utf8), Self.http(200))
            },
            pageLimit: 2000
        )
        let fills = try await client.fetchFills(
            from: Date(timeIntervalSince1970: 1_700_000_000),
            to: Date(timeIntervalSince1970: 1_700_100_000)
        )
        XCTAssertEqual(fills.count, 2)
        XCTAssertEqual(fills[0].symbol, "BTC")
        XCTAssertEqual(fills[0].side, "BUY")
        XCTAssertEqual(fills[0].positionSide, "BOTH")
        XCTAssertEqual(fills[0].id, 99)
        XCTAssertEqual(fills[0].realizedPnl, 1.25, accuracy: 0.0001)
        XCTAssertEqual(fills[1].side, "SELL")
        XCTAssertEqual(fills[1].symbol, "ETH")

        let object = try JSONSerialization.jsonObject(with: captured.value!) as? [String: Any]
        XCTAssertEqual(object?["type"] as? String, "userFillsByTime")
        XCTAssertEqual(object?["user"] as? String, "0xabcdef0123456789abcdef0123456789abcdef01")
        XCTAssertEqual(object?["startTime"] as? Int64, 1_700_000_000_000)
    }

    func testPaginatesWhenPageIsFull() async throws {
        let calls = Box(0)
        let client = HyperliquidInfoClient(
            user: "0xabcdef0123456789abcdef0123456789abcdef01",
            baseURL: URL(string: "https://hl.example.com")!,
            transport: { request in
                calls.value += 1
                let body = request.httpBody.flatMap {
                    try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
                }
                if calls.value == 1 {
                    // pageLimit is 1 in this client — treat one row as a full page.
                    let row = #"""
                    [{"closedPnl":"0","coin":"BTC","px":"1","side":"B","sz":"1","time":1000,"fee":"0","feeToken":"USDC","tid":1}]
                    """#
                    return (Data(row.utf8), Self.http(200))
                }
                XCTAssertEqual(body?["startTime"] as? Int64, 1001)
                return (Data("[]".utf8), Self.http(200))
            },
            pageLimit: 1
        )
        let fills = try await client.fetchFills(
            from: Date(timeIntervalSince1970: 1),
            to: Date(timeIntervalSince1970: 5)
        )
        XCTAssertEqual(calls.value, 2)
        XCTAssertEqual(fills.map(\.id), [1])
    }

    func testDropsFillsBeforeRequestedStart() async throws {
        let client = HyperliquidInfoClient(
            user: "0xabcdef0123456789abcdef0123456789abcdef01",
            baseURL: URL(string: "https://hl.example.com")!,
            transport: { _ in
                let body = #"""
                [{"closedPnl":"0","coin":"BTC","px":"1","side":"B","sz":"1","time":500,"fee":"0","feeToken":"USDC","tid":1},
                 {"closedPnl":"0","coin":"BTC","px":"1","side":"B","sz":"1","time":1500,"fee":"0","feeToken":"USDC","tid":2}]
                """#
                return (Data(body.utf8), Self.http(200))
            }
        )
        let fills = try await client.fetchFills(
            from: Date(timeIntervalSince1970: 1),
            to: Date(timeIntervalSince1970: 3)
        )
        XCTAssertEqual(fills.map(\.id), [2])
    }
}
