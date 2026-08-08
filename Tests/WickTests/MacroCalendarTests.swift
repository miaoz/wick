import XCTest
@testable import WickCore

final class MacroCalendarTests: XCTestCase {
    // MARK: - Day range

    func testDayUnixRangeSpansOneLocalDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 8))!
        let range = MacroCalendarClient.dayUnixRange(for: date, calendar: calendar)

        XCTAssertEqual(range.end - range.start, 86_400)
        let startComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: Date(timeIntervalSince1970: Double(range.start))
        )
        XCTAssertEqual(startComponents.year, 2026)
        XCTAssertEqual(startComponents.month, 8)
        XCTAssertEqual(startComponents.day, 8)
        XCTAssertEqual(startComponents.hour, 0)
        XCTAssertEqual(startComponents.minute, 0)
        XCTAssertEqual(startComponents.second, 0)
    }

    // MARK: - Payload decoding

    func testDecodeMapsFieldsAndAppliesRevisedFallback() throws {
        let json = """
        {
          "code": 0,
          "message": "ok",
          "data": { "items": [
            {
              "id": 1, "public_date": 1715594400, "country": "美国",
              "title": "4月国内企业商品物价指数环比", "importance": 2,
              "actual": "0.2%", "forecast": "0.1%", "previous": "0.3%", "revised": "",
              "uri": "https://wallstreetcn.com/calendar/JP111746/overview",
              "calendar_key": "JP111746"
            },
            {
              "id": 2, "public_date": 1715600000, "country": "日本",
              "title": "OpenAI新品发布会", "importance": 1,
              "actual": "", "forecast": "", "previous": "abc", "revised": "0.5",
              "uri": ""
            }
          ] }
        }
        """
        let events = try MacroCalendarPayloadDecoder.decode(Data(json.utf8))
        XCTAssertEqual(events.count, 2)

        let first = events[0]
        XCTAssertEqual(first.country, "美国")
        XCTAssertEqual(first.title, "4月国内企业商品物价指数环比")
        XCTAssertEqual(first.importance, 2)
        XCTAssertEqual(first.actual, 0.2)
        XCTAssertEqual(first.forecast, 0.1)
        XCTAssertEqual(first.previous, 0.3) // no revision → previous used
        XCTAssertEqual(first.link?.absoluteString, "https://wallstreetcn.com/calendar/JP111746/overview")
        XCTAssertEqual(first.id, "JP111746")
        XCTAssertEqual(first.time, Date(timeIntervalSince1970: 1_715_594_400))

        let second = events[1]
        XCTAssertEqual(second.country, "日本")
        XCTAssertEqual(second.previous, 0.5) // revision supersedes previous
        XCTAssertNil(second.actual)
        XCTAssertNil(second.forecast)
        XCTAssertNil(second.link)
    }

    func testDecodeEmptyItems() throws {
        let events = try MacroCalendarPayloadDecoder.decode(Data(#"{"code":0,"data":{"items":[]}}"#.utf8))
        XCTAssertTrue(events.isEmpty)
    }

    func testDecodeMalformedPayloadThrows() {
        XCTAssertThrowsError(
            try MacroCalendarPayloadDecoder.decode(Data(#"{"code":1}"#.utf8))
        ) { error in
            guard case MacroCalendarError.badPayload = error else {
                return XCTFail("expected badPayload, got \(error)")
            }
        }
        XCTAssertThrowsError(
            try MacroCalendarPayloadDecoder.decode(Data("not json".utf8))
        )
    }

    func testDecodeSkipsItemWithoutReleaseTime() throws {
        let json = """
        { "code": 0, "data": { "items": [
          { "id": 9, "title": "No time", "country": "美国" }
        ] } }
        """
        let events = try MacroCalendarPayloadDecoder.decode(Data(json.utf8))
        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - Number coercion

    func testNumberCoercion() {
        // nil / empty / non-numeric become nil; "%" is tolerated.
        XCTAssertNil(MacroCalendarPayloadDecoder.number(nil))
        XCTAssertNil(MacroCalendarPayloadDecoder.number(""))
        XCTAssertNil(MacroCalendarPayloadDecoder.number("abc"))
        XCTAssertEqual(MacroCalendarPayloadDecoder.number("0.2%"), 0.2)
        XCTAssertEqual(MacroCalendarPayloadDecoder.number("42"), 42)
    }
}
