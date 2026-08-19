import XCTest
@testable import WickCalendarKit

final class EarningsCalendarTests: XCTestCase {
    /// Mirrors a real DDC response: `data.fields` carries the column names and
    /// each `data.items` entry is a positional row array.
    private func payload(items: String) -> String {
        """
        { "code": 20000, "message": "OK", "data": {
          "fields": ["id","code","company_name","country","country_id","public_date",
                     "eps_estimate","reported_eps","earnings","earnings_estimate",
                     "surprise","earnings_call_time","flag_uri","observation_date",
                     "market_value","calendar_type"],
          "items": [\(items)]
        } }
        """
    }

    func testDecodeMapsColumnarRows() throws {
        let json = payload(items: """
            [196993,"603259.SH","药明康德","中国","CN",1785772800,0,3.8,0,0,0,"TNS","https://img","",0,"FR"],
            [197045,"PLTR.US","Palantir","美国","US",1785772800,0.347,0,0,0,-1,"AMC","https://img","",0,"FR"],
            [197050,"PFE.US","辉瑞制药","美国","US",1785772800,0.681,0,0,0,-1,"BMO","https://img","",0,"FR"]
        """)
        let reports = try EarningsPayloadDecoder.decode(Data(json.utf8))
        XCTAssertEqual(reports.count, 3)

        let first = reports[0]
        XCTAssertEqual(first.id, "196993")
        XCTAssertEqual(first.code, "603259.SH")
        XCTAssertEqual(first.companyName, "药明康德")
        XCTAssertEqual(first.country, "中国")
        XCTAssertEqual(first.date, Date(timeIntervalSince1970: 1_785_772_800))
        XCTAssertNil(first.epsEstimate)              // the feed's 0 means "no estimate"
        XCTAssertEqual(first.reportedEps, 3.8)
        XCTAssertEqual(first.callTime, .unspecified) // TNS

        XCTAssertEqual(reports[1].callTime, .afterClose)
        XCTAssertEqual(reports[1].epsEstimate, 0.347)
        XCTAssertNil(reports[1].reportedEps)         // 0 until reported
        XCTAssertEqual(reports[2].callTime, .beforeOpen)
    }

    func testDecodeSkipsMalformedRows() throws {
        let json = payload(items: """
            [197045,"PLTR.US","Palantir","美国","US",1785772800,0.347,0,0,0,-1,"AMC","https://img","",0,"FR"],
            ["too","short"],
            [196993,"603259.SH","","中国","CN",1785772800,0,3.8,0,0,0,"TNS","https://img","",0,"FR"]
        """)
        let reports = try EarningsPayloadDecoder.decode(Data(json.utf8))
        XCTAssertEqual(reports.map(\.code), ["PLTR.US"])  // short row and empty name dropped
    }

    func testDecodeRejectsMalformedPayloads() {
        XCTAssertThrowsError(try EarningsPayloadDecoder.decode(Data("not json".utf8)))
        XCTAssertThrowsError(try EarningsPayloadDecoder.decode(Data(#"{"code":20000,"data":{}}"#.utf8))) { error in
            guard case MacroCalendarError.badPayload = error else {
                return XCTFail("expected badPayload, got \(error)")
            }
        }
    }
}
