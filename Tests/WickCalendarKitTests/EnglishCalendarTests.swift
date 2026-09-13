import XCTest
@testable import WickCalendarKit

final class EnglishCalendarTests: XCTestCase {
    // MARK: - Biquote macro

    func testBiquoteMapsFieldsRevisedAndImportance() throws {
        let json = """
        [
          {
            "id": "mql5:1",
            "eventId": "mql5:series",
            "time": "2026-09-14T12:30:00Z",
            "countryCode": "US",
            "name": "Core CPI y/y",
            "importance": "high",
            "actual": 2.8,
            "forecast": 2.9,
            "previous": 3.0,
            "revisedPrevious": 2.95,
            "sourceUrl": "https://www.bls.gov/"
          },
          {
            "id": "mql5:2",
            "time": "2026-09-14T01:00:00Z",
            "countryCode": "CN",
            "name": "PBC M2 Money Stock y/y",
            "importance": "low",
            "actual": null,
            "forecast": 7.6,
            "previous": 7.7,
            "revisedPrevious": null
          }
        ]
        """
        let events = try BiquoteMacroPayloadDecoder.decode(Data(json.utf8))
        XCTAssertEqual(events.count, 2)

        let cpi = events[0]
        XCTAssertEqual(cpi.id, "mql5:1")
        XCTAssertEqual(cpi.country, "US")
        XCTAssertEqual(cpi.title, "Core CPI y/y")
        XCTAssertEqual(cpi.importance, 3)
        XCTAssertEqual(cpi.actual, 2.8)
        XCTAssertEqual(cpi.forecast, 2.9)
        XCTAssertEqual(cpi.previous, 2.95) // revision supersedes previous
        XCTAssertEqual(cpi.link?.absoluteString, "https://www.bls.gov/")
        XCTAssertEqual(cpi.time, try Date("2026-09-14T12:30:00Z", strategy: .iso8601))

        let m2 = events[1]
        XCTAssertEqual(m2.importance, 1)
        XCTAssertNil(m2.actual)
        XCTAssertEqual(m2.forecast, 7.6)
        XCTAssertEqual(m2.previous, 7.7)
        XCTAssertNil(m2.link)
    }

    func testBiquoteEmptyArray() throws {
        let events = try BiquoteMacroPayloadDecoder.decode(Data("[]".utf8))
        XCTAssertTrue(events.isEmpty)
    }

    func testBiquoteMalformedPayloadThrows() {
        XCTAssertThrowsError(try BiquoteMacroPayloadDecoder.decode(Data("not json".utf8)))
        XCTAssertThrowsError(try BiquoteMacroPayloadDecoder.decode(Data(#"{"items":[]}"#.utf8))) { error in
            guard case MacroCalendarError.badPayload = error else {
                return XCTFail("expected badPayload, got \(error)")
            }
        }
    }

    func testBiquoteSkipsNamelessAndUntimedRows() throws {
        let json = """
        [
          { "id": "1", "countryCode": "US", "name": "No time" },
          { "id": "2", "time": "2026-09-14T12:30:00Z", "countryCode": "US", "name": "  " },
          { "id": "3", "time": "2026-09-14T12:31:00Z", "countryCode": "EU", "name": "ECB Speech", "importance": "medium" }
        ]
        """
        let events = try BiquoteMacroPayloadDecoder.decode(Data(json.utf8))
        XCTAssertEqual(events.map(\.id), ["3"])
        XCTAssertEqual(events[0].importance, 2)
    }

    func testBiquoteCollapsesDuplicateReleases() throws {
        let json = """
        [
          { "id": "a", "time": "2026-09-14T12:30:00Z", "countryCode": "US", "name": "CPI", "importance": "high" },
          { "id": "b", "time": "2026-09-14T12:30:00Z", "countryCode": "US", "name": "CPI", "importance": "high" }
        ]
        """
        let events = try BiquoteMacroPayloadDecoder.decode(Data(json.utf8))
        XCTAssertEqual(events.map(\.id), ["a"])
    }

    func testBiquoteImportanceMapping() {
        XCTAssertEqual(BiquoteMacroPayloadDecoder.importance("high"), 3)
        XCTAssertEqual(BiquoteMacroPayloadDecoder.importance("MEDIUM"), 2)
        XCTAssertEqual(BiquoteMacroPayloadDecoder.importance("low"), 1)
        XCTAssertEqual(BiquoteMacroPayloadDecoder.importance("nope"), 0)
        XCTAssertEqual(BiquoteMacroPayloadDecoder.importance(NSNumber(value: 2)), 2)
    }

    func testBiquoteQueryRangeCoversChinaDayInUTC() {
        // China 2026-09-14 00:00 CST = 2026-09-13 16:00 UTC
        // China 2026-09-15 00:00 CST = 2026-09-14 16:00 UTC
        // Exclusive-end query must span UTC Sep 13 and Sep 14.
        var china = Calendar(identifier: .gregorian)
        china.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let date = china.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 10))!
        let query = BiquoteMacroCalendarClient.dateQueryRange(for: date, calendar: china)
        XCTAssertEqual(query.from, "2026-09-13")
        XCTAssertEqual(query.to, "2026-09-15")
        XCTAssertNotEqual(query.from, query.to, "biquote 400s when from == to")
    }

    // MARK: - Nasdaq earnings

    func testNasdaqMapsRowsAndCallTimes() throws {
        let json = """
        { "data": { "asOf": "Mon, Sep 14, 2026", "rows": [
          { "symbol": "GRFS", "name": "Grifols, S.A.", "time": "time-not-supplied",
            "epsForecast": "$0.27", "eps": "N/A" },
          { "symbol": "KMTS", "name": "Kestra Medical", "time": "time-after-hours",
            "epsForecast": "($0.61)" },
          { "symbol": "CSHR", "name": "CoinShares PLC", "time": "time-pre-market",
            "epsForecast": "" }
        ] } }
        """
        let day = Date(timeIntervalSince1970: 1_789_344_000) // 2026-09-14 00:00 UTC
        let reports = try NasdaqEarningsPayloadDecoder.decode(Data(json.utf8), date: day)
        XCTAssertEqual(reports.count, 3)

        XCTAssertEqual(reports[0].code, "GRFS.US")
        XCTAssertEqual(reports[0].companyName, "Grifols, S.A.")
        XCTAssertEqual(reports[0].country, "US")
        XCTAssertEqual(reports[0].callTime, .unspecified)
        XCTAssertEqual(reports[0].epsEstimate, 0.27)
        XCTAssertNil(reports[0].reportedEps)

        XCTAssertEqual(reports[1].callTime, .afterClose)
        XCTAssertEqual(reports[1].epsEstimate, -0.61)

        XCTAssertEqual(reports[2].callTime, .beforeOpen)
        XCTAssertNil(reports[2].epsEstimate)
    }

    func testNasdaqPastDateKeepsReportedEps() throws {
        let json = """
        { "data": { "rows": [
          { "symbol": "KB", "name": "KB Financial Group Inc", "time": "time-not-supplied",
            "eps": "$3.67", "epsForecast": "$3.51" },
          { "symbol": "LPL", "name": "LG Display Co., Ltd.", "time": "time-not-supplied",
            "eps": "($0.27)", "epsForecast": "($0.13)" }
        ] } }
        """
        let reports = try NasdaqEarningsPayloadDecoder.decode(
            Data(json.utf8),
            date: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(reports[0].reportedEps, 3.67)
        XCTAssertEqual(reports[0].epsEstimate, 3.51)
        XCTAssertEqual(reports[1].reportedEps, -0.27)
        XCTAssertEqual(reports[1].epsEstimate, -0.13)
    }

    func testNasdaqNullRowsIsQuietDay() throws {
        let json = #"{"data":{"asOf":"Sun, Sep 13, 2026","headers":null,"rows":null}}"#
        let reports = try NasdaqEarningsPayloadDecoder.decode(Data(json.utf8), date: Date())
        XCTAssertTrue(reports.isEmpty)
    }

    func testNasdaqMalformedPayloadThrows() {
        XCTAssertThrowsError(try NasdaqEarningsPayloadDecoder.decode(Data("not json".utf8), date: Date()))
        XCTAssertThrowsError(try NasdaqEarningsPayloadDecoder.decode(Data(#"{"status":{}}"#.utf8), date: Date())) { error in
            guard case MacroCalendarError.badPayload = error else {
                return XCTFail("expected badPayload, got \(error)")
            }
        }
    }

    func testNasdaqSkipsRowsWithoutSymbolOrName() throws {
        let json = """
        { "data": { "rows": [
          { "symbol": "", "name": "Nameless", "time": "time-pre-market" },
          { "symbol": "AAPL", "name": "", "time": "time-pre-market" },
          { "symbol": "AAPL", "name": "Apple Inc.", "time": "time-after-hours", "epsForecast": "$1.50" }
        ] } }
        """
        let reports = try NasdaqEarningsPayloadDecoder.decode(Data(json.utf8), date: Date())
        XCTAssertEqual(reports.map(\.code), ["AAPL.US"])
    }

    func testNasdaqMoneyCoercion() {
        XCTAssertEqual(NasdaqEarningsPayloadDecoder.money("$3.67"), 3.67)
        XCTAssertEqual(NasdaqEarningsPayloadDecoder.money("($0.27)"), -0.27)
        XCTAssertEqual(NasdaqEarningsPayloadDecoder.money("$1,234.50"), 1234.50)
        XCTAssertNil(NasdaqEarningsPayloadDecoder.money("N/A"))
        XCTAssertNil(NasdaqEarningsPayloadDecoder.money(""))
        XCTAssertNil(NasdaqEarningsPayloadDecoder.money(nil))
        XCTAssertEqual(NasdaqEarningsPayloadDecoder.money("$0"), 0)
    }

    func testNasdaqDoesNotDoubleSuffix() throws {
        let json = """
        { "data": { "rows": [
          { "symbol": "PLTR.US", "name": "Palantir", "time": "time-pre-market" }
        ] } }
        """
        let reports = try NasdaqEarningsPayloadDecoder.decode(Data(json.utf8), date: Date())
        XCTAssertEqual(reports[0].code, "PLTR.US")
    }

    // MARK: - Attribution / L10n

    func testFeedAttributionFollowsLanguageAndTab() {
        XCTAssertEqual(
            MacroCalendarTab.macro.attribution(language: .chinese),
            "宏观数据源 · 华尔街见闻"
        )
        XCTAssertEqual(
            MacroCalendarTab.macro.attribution(language: .english),
            "Macro · biquote"
        )
        XCTAssertEqual(
            MacroCalendarTab.earnings.attribution(language: .chinese),
            "财报数据源 · 华尔街见闻"
        )
        XCTAssertEqual(
            MacroCalendarTab.earnings.attribution(language: .english),
            "Earnings · Nasdaq"
        )
    }
}
