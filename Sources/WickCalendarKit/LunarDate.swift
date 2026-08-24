import Foundation

/// A Chinese lunar date.
public struct LunarDate: Equatable, Sendable {
    public let year: Int
    public let isLeapMonth: Bool
    public let month: Int // 1-12
    public let day: Int   // 1-30

    public init(year: Int, isLeapMonth: Bool, month: Int, day: Int) {
        self.year = year
        self.isLeapMonth = isLeapMonth
        self.month = month
        self.day = day
    }
}

/// Gregorian → Chinese lunar conversion using the standard 1900–2100 month-length table
/// (the same algorithm used by common Chinese-calendar libraries). Pure & testable.
public enum LunarCalendar {
    // Each year (1900+i) encodes: low 4 bits = leap month (0 = none), bit 4..15 = which
    // months have 30 days, bit 16 = whether the leap month has 30 days.
    private static let lunarInfo: [Int] = [
        0x04bd8, 0x04ae0, 0x0a570, 0x054d5, 0x0d260, 0x0d950, 0x16554, 0x056a0, 0x09ad0, 0x055d2,
        0x04ae0, 0x0a5b6, 0x0a4d0, 0x0d250, 0x1d255, 0x0b540, 0x0d6a0, 0x0ada2, 0x095b0, 0x14977,
        0x04970, 0x0a4b0, 0x0b4b5, 0x06a50, 0x06d40, 0x1ab54, 0x02b60, 0x09570, 0x052f2, 0x04970,
        0x06566, 0x0d4a0, 0x0ea50, 0x06e95, 0x05ad0, 0x02b60, 0x186e3, 0x092e0, 0x1c8d7, 0x0c950,
        0x0d4a0, 0x1d8a6, 0x0b550, 0x056a0, 0x1a5b4, 0x025d0, 0x092d0, 0x0d2b2, 0x0a950, 0x0b557,
        0x06ca0, 0x0b550, 0x15355, 0x04da0, 0x0a5b0, 0x14573, 0x052b0, 0x0a9a8, 0x0e950, 0x06aa0,
        0x0aea6, 0x0ab50, 0x04b60, 0x0aae4, 0x0a570, 0x05260, 0x0f263, 0x0d950, 0x05b57, 0x056a0,
        0x096d0, 0x04dd5, 0x04ad0, 0x0a4d0, 0x0d4d4, 0x0d250, 0x0d558, 0x0b540, 0x0b6a0, 0x195a6,
        0x095b0, 0x049b0, 0x0a974, 0x0a4b0, 0x0b27a, 0x06a50, 0x06d40, 0x0af46, 0x0ab60, 0x09570,
        0x04af5, 0x04970, 0x064b0, 0x074a3, 0x0ea50, 0x06b58, 0x055c0, 0x0ab60, 0x096d5, 0x092e0,
        0x0c960, 0x0d954, 0x0d4a0, 0x0da50, 0x07552, 0x056a0, 0x0abb7, 0x025d0, 0x092d0, 0x0cab5,
        0x0a950, 0x0b4a0, 0x0baa4, 0x0ad50, 0x055d9, 0x04ba0, 0x0a5b0, 0x15176, 0x052b0, 0x0a930,
        0x07954, 0x06aa0, 0x0ad50, 0x05b52, 0x04b60, 0x0a6e6, 0x0a4e0, 0x0d260, 0x0ea65, 0x0d530,
        0x05aa0, 0x076a3, 0x096d0, 0x04afb, 0x04ad0, 0x0a4d0, 0x1d0b6, 0x0d250, 0x0d520, 0x0dd45,
        0x0b5a0, 0x056d0, 0x055b2, 0x049b0, 0x0a577, 0x0a4b0, 0x0aa50, 0x1b255, 0x06d20, 0x0ada0,
        0x14b63, 0x09370, 0x049f8, 0x04970, 0x064b0, 0x168a6, 0x0ea50, 0x06b20, 0x1a6c4, 0x0aae0,
        0x0a2e0, 0x0d2e3, 0x0c960, 0x0d557, 0x0d4a0, 0x0da50, 0x05d55, 0x056a0, 0x0a6d0, 0x055d4,
        0x052d0, 0x0a9b8, 0x0a950, 0x0b4a0, 0x0b6a6, 0x0ad50, 0x055a0, 0x0aba4, 0x0a5b0, 0x052b0,
        0x0b273, 0x06930, 0x07337, 0x06aa0, 0x0ad50, 0x14b55, 0x04b60, 0x0a570, 0x054e4, 0x0d160,
        0x0e968, 0x0d520, 0x0daa0, 0x16aa6, 0x056d0, 0x04ae0, 0x0a9d4, 0x0a2d0, 0x0d150, 0x0f252,
        0x0d520
    ]

    private static func leapMonth(_ y: Int) -> Int { lunarInfo[y - 1900] & 0xf }

    private static func leapDays(_ y: Int) -> Int {
        if leapMonth(y) != 0 {
            return (lunarInfo[y - 1900] & 0x10000) != 0 ? 30 : 29
        }
        return 0
    }

    private static func monthDays(_ y: Int, _ m: Int) -> Int {
        (lunarInfo[y - 1900] & (0x10000 >> m)) != 0 ? 30 : 29
    }

    private static func lYearDays(_ y: Int) -> Int {
        var sum = 348
        var i = 0x8000
        while i > 0x8 {
            sum += (lunarInfo[y - 1900] & i) != 0 ? 1 : 0
            i >>= 1
        }
        return sum + leapDays(y)
    }

    /// Converts a (local-midnight) `Date` to its lunar date.
    public static func lunar(from date: Date, calendar: Calendar = .current) -> LunarDate? {
        var cal = calendar
        cal.timeZone = calendar.timeZone
        guard let epoch = cal.date(from: DateComponents(year: 1900, month: 1, day: 31)) else { return nil }
        guard let dayDiff = cal.dateComponents([.day], from: epoch, to: date).day else { return nil }
        var offset = dayDiff
        guard offset >= 0 else { return nil }

        var i = 1900
        var daysInYear = 0
        while i < 2101 && offset > 0 {
            daysInYear = lYearDays(i)
            offset -= daysInYear
            i += 1
        }
        if offset < 0 { offset += daysInYear; i -= 1 }
        let lunarYear = i

        let leap = leapMonth(lunarYear)
        var isLeap = false
        var lunarMonth = 1
        var temp2 = 0
        var j = 1
        while j < 13 && offset > 0 {
            if leap > 0 && j == (leap + 1) && !isLeap {
                j -= 1
                isLeap = true
                temp2 = leapDays(lunarYear)
            } else {
                temp2 = monthDays(lunarYear, j)
            }
            if isLeap && j == (leap + 1) { isLeap = false }
            offset -= temp2
            if !isLeap { lunarMonth = j }
            j += 1
        }
        if offset == 0 && leap > 0 && j == (leap + 1) {
            if isLeap { isLeap = false } else { isLeap = true; j -= 1 }
        }
        if offset < 0 { offset += temp2; j -= 1 }
        let lunarDay = offset + 1

        return LunarDate(year: lunarYear, isLeapMonth: isLeap, month: lunarMonth, day: lunarDay)
    }

    // MARK: - Display helpers

    public static let stems = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
    public static let branches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
    public static let zodiacs = ["鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪"]

    /// 天干地支 of a lunar (or Gregorian) year, e.g. 2026 → 丙午.
    /// The sexagenary cycle anchors at year 4 AD = 甲子.
    public static func ganzhiYear(_ year: Int) -> String {
        stems[mod(year - 4, 10)] + branches[mod(year - 4, 12)]
    }

    /// 生肖 of a lunar year, e.g. 2026 → 马.
    public static func zodiac(_ year: Int) -> String {
        zodiacs[mod(year - 4, 12)]
    }

    /// Chinese lunar month name: 正月 / 二…十 / 冬月 / 腊月 (闰 prefix for leap months).
    public static func monthName(_ month: Int) -> String {
        switch month {
        case 1: return "正月"
        case 11: return "冬月"
        case 12: return "腊月"
        default: return ["二", "三", "四", "五", "六", "七", "八", "九", "十"][month - 2] + "月"
        }
    }

    /// Chinese lunar day name: 初一 … 三十.
    public static func dayName(_ day: Int) -> String {
        let tens = ["初", "十", "廿", "三"]
        let units = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
        if day == 10 { return "初十" }
        if day == 20 { return "二十" }
        if day == 30 { return "三十" }
        let t = (day - 1) / 10
        let u = (day - 1) % 10
        if day > 10, day < 20 { return "十" + units[u] } // 十一…十九
        return tens[t] + units[u]
    }

    private static func mod(_ v: Int, _ m: Int) -> Int {
        let r = v % m
        return r >= 0 ? r : r + m
    }
}

/// Public one-liner for surfaces outside the kit (journal inspector):
/// 农历七月初八 · 丙午年. Returns nil outside 1900–2100.
public enum LunarLine {
    public static func string(for date: Date, calendar: Calendar = .current) -> String? {
        guard let lunar = LunarCalendar.lunar(from: date, calendar: calendar) else { return nil }
        let month = (lunar.isLeapMonth ? "闰" : "") + LunarCalendar.monthName(lunar.month)
        let day = LunarCalendar.dayName(lunar.day)
        return "\(month)\(day) · \(LunarCalendar.ganzhiYear(lunar.year))年"
    }
}
