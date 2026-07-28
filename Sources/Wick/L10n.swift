import Foundation

enum L10n {
    static func string(_ key: Key, language: AppLanguage) -> String {
        switch language {
        case .chinese:
            return key.chinese
        case .english:
            return key.english
        }
    }

    enum Key {
        case motto
        case quit
        case settings
        case back
        case language
        case appearance
        case dayTitle
        case daySubtitle
        case weekTitle
        case weekSubtitle
        case monthTitle
        case monthSubtitle
        case yearTitle
        case yearSubtitle
        case remainingLessThanOneMinute
        case remainingPrefix
        case remainingSuffix
        case unitMonth
        case unitDay
        case unitHour
        case unitMinute
        case endPrefix
        case endUnavailable
        case progressLow
        case progressBurning
        case progressPlenty
        case themeCandlelight
        case themeMidnight
        case settingsTitle

        var chinese: String {
            switch self {
            case .motto: return "一寸光阴一寸金。"
            case .quit: return "退出"
            case .settings: return "设置"
            case .back: return "返回"
            case .language: return "语言"
            case .appearance: return "外观"
            case .dayTitle: return "日"
            case .daySubtitle: return "今天"
            case .weekTitle: return "周"
            case .weekSubtitle: return "本周"
            case .monthTitle: return "月"
            case .monthSubtitle: return "本月"
            case .yearTitle: return "年"
            case .yearSubtitle: return "今年"
            case .remainingLessThanOneMinute: return "还剩不到 1 分钟"
            case .remainingPrefix: return "还剩 "
            case .remainingSuffix: return ""
            case .unitMonth: return "个月"
            case .unitDay: return "天"
            case .unitHour: return "小时"
            case .unitMinute: return "分钟"
            case .endPrefix: return "到 "
            case .endUnavailable: return "时间边界不可用"
            case .progressLow: return "所剩不多"
            case .progressBurning: return "正在燃尽"
            case .progressPlenty: return "余量充足"
            case .themeCandlelight: return "烛火进度"
            case .themeMidnight: return "夜幕进度"
            case .settingsTitle: return "设置"
            }
        }

        var english: String {
            switch self {
            case .motto: return "Time is precious."
            case .quit: return "Quit"
            case .settings: return "Settings"
            case .back: return "Back"
            case .language: return "Language"
            case .appearance: return "Appearance"
            case .dayTitle: return "Day"
            case .daySubtitle: return "Today"
            case .weekTitle: return "Week"
            case .weekSubtitle: return "This week"
            case .monthTitle: return "Month"
            case .monthSubtitle: return "This month"
            case .yearTitle: return "Year"
            case .yearSubtitle: return "This year"
            case .remainingLessThanOneMinute: return "Less than 1 minute left"
            case .remainingPrefix: return ""
            case .remainingSuffix: return " left"
            case .unitMonth: return "mo"
            case .unitDay: return "d"
            case .unitHour: return "h"
            case .unitMinute: return "m"
            case .endPrefix: return "Until "
            case .endUnavailable: return "Time boundary unavailable"
            case .progressLow: return "Running low"
            case .progressBurning: return "Burning down"
            case .progressPlenty: return "Plenty left"
            case .themeCandlelight: return "Candle Progress"
            case .themeMidnight: return "Midnight Progress"
            case .settingsTitle: return "Settings"
            }
        }
    }
}
