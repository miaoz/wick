import XCTest
import WickSync
@testable import WickCalendarKit

final class TraderAlmanacTests: XCTestCase {
    
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    func testDeterministicEntryForSameDate() {
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25))!
        let entry1 = TraderAlmanac.entry(for: date)
        let entry2 = TraderAlmanac.entry(for: date)
        
        XCTAssertEqual(entry1, entry2)
        XCTAssertFalse(entry1.yi.isEmpty)
        XCTAssertFalse(entry1.ji.isEmpty)
        XCTAssertFalse(entry1.yiEn.isEmpty)
        XCTAssertFalse(entry1.jiEn.isEmpty)
        XCTAssertNotNil(entry1.seal)
        XCTAssertNotNil(entry1.lucky)
        XCTAssertNotNil(entry1.sha)
    }

    func testWeekendRouting() {
        // 2026-08-23 is Sunday
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 8, day: 23))!
        let entry = TraderAlmanac.entry(for: sunday)
        
        XCTAssertEqual(entry.category, TraderAlmanacCategory.contextual)
        XCTAssertTrue(entry.yi.contains("周末") || entry.yi.contains("漫游") || entry.yi.contains("烹茶") || entry.yi.contains("整顿") || entry.yi.contains("复盘"))
        XCTAssertNotNil(entry.sealText(language: .chinese))
    }

    func testHighImpactMacroDayRouting() {
        // Tuesday with high impact CPI event
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25))!
        let cpiEvent = MacroCalendarEvent(
            id: "test-cpi",
            time: date,
            country: "US",
            title: "美国7月未季调CPI年率",
            importance: 2,
            actual: 3.2,
            forecast: 3.1,
            previous: 3.0,
            link: nil
        )
        
        let entry = TraderAlmanac.entry(for: date, events: [cpiEvent])
        XCTAssertEqual(entry.category, TraderAlmanacCategory.contextual)
        XCTAssertTrue(entry.yi.contains("防线") || entry.yi.contains("风云") || entry.yi.contains("防守"))
        XCTAssertNotNil(entry.lucky)
        XCTAssertNotNil(entry.sha)
    }

    func testNoNegativeTabooGuarantee() {
        // Iterate through all 365 days of a year and verify no "诸事不宜"
        for day in 1...365 {
            let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: day))!
            let entry = TraderAlmanac.entry(for: date)
            
            XCTAssertFalse(entry.yi.contains("诸事不宜"))
            XCTAssertFalse(entry.ji.contains("诸事不宜"))
            XCTAssertFalse(entry.yiText(language: .chinese).isEmpty)
            XCTAssertFalse(entry.jiText(language: .chinese).isEmpty)
            XCTAssertFalse(entry.yiText(language: .english).isEmpty)
            XCTAssertFalse(entry.jiText(language: .english).isEmpty)
            XCTAssertNotNil(entry.sealText(language: .chinese))
            XCTAssertNotNil(entry.sealText(language: .english))
        }
    }

    func testBilingualTextRetrieval() {
        let entry = TraderAlmanacEntry(
            yi: "喝冰美式 · 假装看盘",
            ji: "盯着1分K · 精神内耗",
            yiEn: "Iced Americano · Chill",
            jiEn: "1m chart doom · Overthinking",
            lucky: "冰美式 · 咖啡机旁",
            luckyEn: "Iced Americano · Coffee corner",
            sha: "1分K线 · 精神内耗",
            shaEn: "1m noise · Doom-scroll",
            seal: "摸鱼",
            sealEn: "CHILL",
            category: .humor
        )

        XCTAssertEqual(entry.yiText(language: .chinese), "喝冰美式 · 假装看盘")
        XCTAssertEqual(entry.jiText(language: .chinese), "盯着1分K · 精神内耗")
        XCTAssertEqual(entry.luckyText(language: .chinese), "冰美式 · 咖啡机旁")
        XCTAssertEqual(entry.shaText(language: .chinese), "1分K线 · 精神内耗")
        XCTAssertEqual(entry.sealText(language: .chinese), "摸鱼")

        XCTAssertEqual(entry.yiText(language: .english), "Iced Americano · Chill")
        XCTAssertEqual(entry.jiText(language: .english), "1m chart doom · Overthinking")
        XCTAssertEqual(entry.luckyText(language: .english), "Iced Americano · Coffee corner")
        XCTAssertEqual(entry.shaText(language: .english), "1m noise · Doom-scroll")
        XCTAssertEqual(entry.sealText(language: .english), "CHILL")
    }

    @MainActor
    func testAccentColorForConvention() {
        XCTAssertEqual(TradingCalendarTheme.accentColor(for: .redUp), TradingCalendarTheme.red)
        XCTAssertEqual(TradingCalendarTheme.accentColor(for: .greenUp), TradingCalendarTheme.green)
    }

    @MainActor
    func testDynamicAccentFollowsPnlConvention() {
        TradingCalendarTheme.pnlConvention = .redUp
        XCTAssertEqual(TradingCalendarTheme.accent, TradingCalendarTheme.red)

        TradingCalendarTheme.pnlConvention = .greenUp
        XCTAssertEqual(TradingCalendarTheme.accent, TradingCalendarTheme.green)

        // Restore default
        TradingCalendarTheme.pnlConvention = .redUp
    }

    @MainActor
    func testTraderAlmanacComponentsDefaultToAccentColor() {
        TradingCalendarTheme.pnlConvention = .greenUp
        let badge = TraderAlmanacSealBadge(text: "大吉")
        XCTAssertEqual(badge.accent, TradingCalendarTheme.green)

        let entry = TraderAlmanac.entry(for: Date())
        let yiJiRow = TraderYiJiRow(entry: entry, language: .chinese)
        XCTAssertEqual(yiJiRow.yiColor, TradingCalendarTheme.green)

        let metaRow = TraderAlmanacMetaRow(entry: entry, language: .chinese)
        XCTAssertEqual(metaRow.accentColor, TradingCalendarTheme.green)

        // Switch to redUp and verify
        TradingCalendarTheme.pnlConvention = .redUp
        let badgeRed = TraderAlmanacSealBadge(text: "大吉")
        XCTAssertEqual(badgeRed.accent, TradingCalendarTheme.red)

        let yiJiRowRed = TraderYiJiRow(entry: entry, language: .chinese)
        XCTAssertEqual(yiJiRowRed.yiColor, TradingCalendarTheme.red)

        let metaRowRed = TraderAlmanacMetaRow(entry: entry, language: .chinese)
        XCTAssertEqual(metaRowRed.accentColor, TradingCalendarTheme.red)
    }

    @MainActor
    func testMacroDayPageViewDefaultConvention() {
        TradingCalendarTheme.pnlConvention = .greenUp
        let pageGreen = MacroDayPageView(
            date: Date(),
            events: [],
            earnings: [],
            isLoading: false,
            errorText: nil,
            language: .chinese,
            eventsPage: 0,
            tab: .macro,
            layout: .desktop
        )
        XCTAssertEqual(pageGreen.convention, .greenUp)

        TradingCalendarTheme.pnlConvention = .redUp
        let pageRed = MacroDayPageView(
            date: Date(),
            events: [],
            earnings: [],
            isLoading: false,
            errorText: nil,
            language: .chinese,
            eventsPage: 0,
            tab: .macro,
            layout: .desktop
        )
        XCTAssertEqual(pageRed.convention, .redUp)
    }
}

