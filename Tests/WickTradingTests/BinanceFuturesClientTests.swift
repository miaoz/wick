import XCTest

@testable import WickTrading

/// Mutable state captured by `@Sendable` transport closures.
private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

/// Drives the client with a canned transport: no network, deterministic clock.
final class BinanceFuturesClientTests: XCTestCase {
    private static let secret = "nlC0Ay5sXvBBJ8isNk2PmH7KySZiR0lTQsqx2VDjZ5C4uGeR3foWXgKqM9aEb1pH"
    private static let fixedNow = Date(timeIntervalSince1970: 1_700_000_001)

    private func makeClient(
        transport: @escaping BinanceFuturesClient.Transport
    ) -> BinanceFuturesClient {
        BinanceFuturesClient(
            apiKey: "key-1",
            secret: Self.secret,
            baseURL: URL(string: "https://fapi.example.com")!,
            transport: transport,
            now: { Self.fixedNow }
        )
    }

    private static func serverTimePayload(_ ms: Int64) -> Data {
        Data("{\"serverTime\":\(ms)}".utf8)
    }

    // MARK: - Signing

    func testSignMatchesKnownVector() {
        // Independently generated with: openssl dgst -sha256 -hmac <secret>
        let query = "startTime=1700000000000&endTime=1700604800000&limit=1000&recvWindow=5000&timestamp=1700000001000"
        XCTAssertEqual(
            BinanceFuturesClient.sign(query: query, secret: Self.secret),
            "872fbb4ee15f1f63220696236f9a6ca7042ef30e745edfc0f735b6596bdc9c03"
        )
    }

    func testSignedRequestCarriesSignatureAndHeader() async throws {
        let client = makeClient { _ in (Data("[]".utf8), Self.http(200)) }
        let request = try await client.signedRequest(
            path: "fapi/v1/userTrades",
            params: [
                ("startTime", "1700000000000"),
                ("endTime", "1700604800000"),
                ("limit", "1000"),
                ("recvWindow", "5000"),
                ("timestamp", "1700000001000")
            ]
        )

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-MBX-APIKEY"), "key-1")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://fapi.example.com/fapi/v1/userTrades"
                + "?startTime=1700000000000&endTime=1700604800000&limit=1000"
                + "&recvWindow=5000&timestamp=1700000001000"
                + "&signature=872fbb4ee15f1f63220696236f9a6ca7042ef30e745edfc0f735b6596bdc9c03"
        )
    }

    // MARK: - Fetch pipeline

    func testFetchFillsPagesThroughFullPages() async throws {
        let windowStart = Date(timeIntervalSince1970: 1000)
        let windowEnd = windowStart.addingTimeInterval(10)
        let allFills = (0..<5).map { index in
            TradingFill(
                id: Int64(index),
                symbol: index.isMultiple(of: 2) ? "BTCUSDT" : "ETHUSDT",
                side: "BUY",
                price: 100,
                qty: 1,
                time: 1_000_000 + Int64(index) * 1000
            )
        }
        let requestCount = Box(0)

        let client = BinanceFuturesClient(
            apiKey: "key-1",
            secret: "secret",
            baseURL: URL(string: "https://fapi.example.com")!,
            transport: { request in
                requestCount.value += 1
                if request.url!.path.hasSuffix("/time") {
                    return (Self.serverTimePayload(0), Self.http(200))
                }
                let queryItems = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                let start = Int64(queryItems.first { $0.name == "startTime" }!.value!)!
                let limit = Int(queryItems.first { $0.name == "limit" }!.value!)!
                let page = allFills
                    .filter { $0.time >= start }
                    .prefix(limit)
                let encoded = try JSONEncoder().encode(Array(page))
                return (encoded, Self.http(200))
            },
            now: { Date(timeIntervalSince1970: 2000) },
            chunkInterval: 60,
            pageLimit: 2
        )

        let fills = try await client.fetchFills(from: windowStart, to: windowEnd)

        XCTAssertEqual(fills.count, 5)
        XCTAssertEqual(requestCount.value, 4, "server time + 3 pages (2 + 2 + 1)")
    }

    func testPositiveBinanceCommissionIsNegatedOnIngestion() async throws {
        // Binance reports commission as a POSITIVE cost. The app's unified
        // convention is negative = paid (TR-03); if the fee were left positive
        // it would be treated as a rebate and inflate net PnL by 2× the fee.
        let client = BinanceFuturesClient(
            apiKey: "key-1",
            secret: "secret",
            baseURL: URL(string: "https://fapi.example.com")!,
            transport: { request in
                if request.url!.path.hasSuffix("/time") {
                    return (Self.serverTimePayload(0), Self.http(200))
                }
                let body = #"""
                [{"id":1,"symbol":"BTCUSDT","side":"BUY","price":"100","qty":"1","time":1000000,"commission":"0.5","commissionAsset":"USDT","realizedPnl":"0"}]
                """#
                return (Data(body.utf8), Self.http(200))
            },
            now: { Date(timeIntervalSince1970: 2000) },
            chunkInterval: 60,
            pageLimit: 1000
        )
        let fills = try await client.fetchFills(
            from: Date(timeIntervalSince1970: 1000),
            to: Date(timeIntervalSince1970: 1010)
        )
        XCTAssertEqual(fills.count, 1)
        XCTAssertEqual(
            fills[0].commission,
            -0.5,
            accuracy: 1e-12,
            "a positive Binance fee must be stored negative (cost)"
        )
    }

    func testFetchFillsSplitsChunks() async throws {
        let windowStart = Date(timeIntervalSince1970: 1000)
        let seenWindows = Box<[(Int64, Int64)]>([])
        let client = BinanceFuturesClient(
            apiKey: "key-1",
            secret: "secret",
            baseURL: URL(string: "https://fapi.example.com")!,
            transport: { request in
                if request.url!.path.hasSuffix("/time") {
                    return (Self.serverTimePayload(0), Self.http(200))
                }
                let queryItems = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                let start = Int64(queryItems.first { $0.name == "startTime" }!.value!)!
                let end = Int64(queryItems.first { $0.name == "endTime" }!.value!)!
                seenWindows.value.append((start, end))
                return (Data("[]".utf8), Self.http(200))
            },
            now: { Date(timeIntervalSince1970: 2000) },
            chunkInterval: 5,
            pageLimit: 1000
        )

        _ = try await client.fetchFills(from: windowStart, to: windowStart.addingTimeInterval(12))
        XCTAssertEqual(seenWindows.value.count, 3, "12s window / 5s chunks")
    }

    func testChunkBoundaryFillIsNotDuplicated() async throws {
        // Binance's endTime filter is INCLUSIVE: a fill exactly at a chunk
        // boundary would be returned by both the chunk that ends there and the
        // one that starts there, duplicating it (TR-04). Chunk starts must
        // advance by 1ms past the boundary.
        let windowStart = Date(timeIntervalSince1970: 1000)
        // 5s chunkInterval → first chunk covers [1000s, 1005s); the boundary
        // between chunk 1 and chunk 2 is 1005s in ms.
        let boundary = Int64(1_005_000)
        let client = BinanceFuturesClient(
            apiKey: "key-1",
            secret: "secret",
            baseURL: URL(string: "https://fapi.example.com")!,
            transport: { request in
                if request.url!.path.hasSuffix("/time") {
                    return (Self.serverTimePayload(0), Self.http(200))
                }
                let queryItems = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                let start = Int64(queryItems.first { $0.name == "startTime" }!.value!)!
                let end = Int64(queryItems.first { $0.name == "endTime" }!.value!)!
                // A fill at the boundary is in range for any chunk whose
                // inclusive [start, end] spans it.
                if start <= boundary && boundary <= end {
                    let row = #"{"id":1,"symbol":"BTCUSDT","side":"BUY","price":"100","qty":"1","time":\#(boundary),"isBuyer":true,"commission":"0","commissionAsset":"USDT","realizedPnl":"0"}"#
                    return (Data("[\(row)]".utf8), Self.http(200))
                }
                return (Data("[]".utf8), Self.http(200))
            },
            now: { Date(timeIntervalSince1970: 2000) },
            chunkInterval: 5,
            pageLimit: 1000
        )

        let fills = try await client.fetchFills(
            from: windowStart,
            to: windowStart.addingTimeInterval(12)
        )
        XCTAssertEqual(fills.count, 1, "the boundary fill must be fetched by exactly one chunk")
    }

    func testServerTimeOffsetAppliedToSignedParams() async throws {
        let capturedQuery = Box<String?>(nil)
        let client = BinanceFuturesClient(
            apiKey: "key-1",
            secret: "secret",
            baseURL: URL(string: "https://fapi.example.com")!,
            transport: { request in
                if request.url!.path.hasSuffix("/time") {
                    return (BinanceFuturesClientTests.serverTimePayload(2_060_000), Self.http(200))
                }
                capturedQuery.value = request.url?.query
                return (Data("[]".utf8), Self.http(200))
            },
            now: { Date(timeIntervalSince1970: 2000) },
            chunkInterval: 60,
            pageLimit: 1000
        )

        _ = try await client.fetchFills(
            from: Date(timeIntervalSince1970: 1000),
            to: Date(timeIntervalSince1970: 1010)
        )

        let query = try XCTUnwrap(capturedQuery.value)
        // Local 2000s + 60s offset = 2060s in ms.
        XCTAssertTrue(query.contains("timestamp=2060000"), query)
    }

    func testAuthFailureMapping() async {
        let client = makeClient { request in
            if request.url!.path.hasSuffix("/time") {
                return (Self.serverTimePayload(0), Self.http(200))
            }
            return (
                Data("{\"code\":-2015,\"msg\":\"Invalid API-key, IP, or permissions for action.\"}".utf8),
                Self.http(401)
            )
        }

        do {
            _ = try await client.fetchFills(
                from: Date(timeIntervalSince1970: 1000),
                to: Date(timeIntervalSince1970: 1010)
            )
            XCTFail("expected invalidCredentials")
        } catch let error as BinanceError {
            guard case .invalidCredentials = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertTrue(error.isAuthFailure)
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testRateLimitAndMalformedMapping() async {
        let rateLimited = makeClient { request in
            if request.url!.path.hasSuffix("/time") {
                return (Self.serverTimePayload(0), Self.http(200))
            }
            return (Data("{\"code\":429,\"msg\":\"Too many requests\"}".utf8), Self.http(429))
        }
        do {
            _ = try await rateLimited.fetchFills(
                from: Date(timeIntervalSince1970: 1000),
                to: Date(timeIntervalSince1970: 1010)
            )
            XCTFail("expected rateLimited")
        } catch let error as BinanceError {
            XCTAssertEqual(error, .rateLimited)
        } catch {
            XCTFail("unexpected error type: \(error)")
        }

        let malformed = makeClient { request in
            if request.url!.path.hasSuffix("/time") {
                return (Self.serverTimePayload(0), Self.http(200))
            }
            return (Data("not json".utf8), Self.http(200))
        }
        do {
            _ = try await malformed.fetchFills(
                from: Date(timeIntervalSince1970: 1000),
                to: Date(timeIntervalSince1970: 1010)
            )
            XCTFail("expected malformedResponse")
        } catch let error as BinanceError {
            XCTAssertEqual(error, .malformedResponse)
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testFetchPositionsAggregatesFetchedFills() async throws {
        let fills = [
            TradingFill(id: 1, symbol: "BTCUSDT", side: "BUY", price: 100, qty: 1, time: 1_000_000),
            TradingFill(id: 2, symbol: "BTCUSDT", side: "SELL", price: 110, qty: 1, realizedPnl: 10, time: 2_000_000)
        ]
        let encoded = try JSONEncoder().encode(fills)
        let client = BinanceFuturesClient(
            apiKey: "key-1",
            secret: "secret",
            baseURL: URL(string: "https://fapi.example.com")!,
            transport: { request in
                if request.url!.path.hasSuffix("/time") {
                    return (Self.serverTimePayload(0), Self.http(200))
                }
                return (encoded, Self.http(200))
            },
            now: { Date(timeIntervalSince1970: 3000) },
            chunkInterval: 3600,
            pageLimit: 1000
        )

        let positions = try await client.fetchPositions(
            window: 1000,
            asOf: Date(timeIntervalSince1970: 3000)
        )
        XCTAssertEqual(positions.count, 1)
        XCTAssertTrue(positions[0].isClosed)
    }

    // MARK: - Funding fees

    func testFetchFundingMapsIncomeRowsAndFiltersType() async throws {
        let capturedQuery = Box<String?>(nil)
        let client = BinanceFuturesClient(
            apiKey: "key-1",
            secret: "secret",
            baseURL: URL(string: "https://fapi.example.com")!,
            transport: { request in
                if request.url!.path.hasSuffix("/time") {
                    return (Self.serverTimePayload(0), Self.http(200))
                }
                capturedQuery.value = request.url?.query
                let queryItems = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                let start = Int64(queryItems.first { $0.name == "startTime" }!.value!)!
                guard start <= 1_700_000_000_000 else {
                    return (Data("[]".utf8), Self.http(200))
                }
                let body = #"""
                [{"symbol":"BTCUSDT","incomeType":"FUNDING_FEE","income":"-0.0023","asset":"USDT","time":1700000000000},
                 {"symbol":"ETHUSDT","incomeType":"FUNDING_FEE","income":"0.0011","asset":"USDT","time":1700000100000}]
                """#
                return (Data(body.utf8), Self.http(200))
            },
            now: { Date(timeIntervalSince1970: 2000) },
            chunkInterval: 3600,
            pageLimit: 1000
        )

        let events = try await client.fetchFunding(
            from: Date(timeIntervalSince1970: 1_700_000_000),
            to: Date(timeIntervalSince1970: 1_700_100_000)
        )
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].symbol, "BTCUSDT")
        XCTAssertEqual(events[0].amount, -0.0023, accuracy: 1e-12)
        XCTAssertEqual(events[0].time, 1_700_000_000_000)
        XCTAssertEqual(events[1].symbol, "ETHUSDT")
        XCTAssertEqual(events[1].amount, 0.0011, accuracy: 1e-12)
        XCTAssertEqual(events[1].time, 1_700_000_100_000)
        XCTAssertTrue(
            capturedQuery.value?.contains("incomeType=FUNDING_FEE") == true,
            "query must request FUNDING_FEE income, got \(capturedQuery.value ?? "nil")"
        )
    }

    private static func http(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://fapi.example.com")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}
