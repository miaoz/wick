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
        case cancel
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

        // Journal
        case journal
        case journalTitle
        case journalNewEntry
        case journalSearchPlaceholder
        case journalAllTags
        case journalEmptyTitle
        case journalEmptySubtitle
        case journalUntitled
        case journalToday
        case journalYesterday
        case journalSelectPrompt
        case journalTitlePlaceholder
        case journalTags
        case journalTagPlaceholder
        case journalAddTag
        case journalTagHint
        case journalBody
        case journalBodyPlaceholder
        case journalImages
        case journalImagesHint
        case journalAddImage
        case journalPasteImage
        case journalPasteImageHelp
        case journalDelete
        case journalDeleteConfirm
        case journalAutosaved
        case journalLayoutSplit
        case journalLayoutSingle
        case journalReminder
        case journalReminderEnabled
        case journalReminderTime
        case journalReminderTitle
        case journalReminderBody
        case journalOpenAction
        case journalSection

        var chinese: String {
            switch self {
            case .motto: return "一寸光阴一寸金。"
            case .quit: return "退出"
            case .settings: return "设置"
            case .back: return "返回"
            case .cancel: return "取消"
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

            case .journal: return "日记"
            case .journalTitle: return "日记"
            case .journalNewEntry: return "新建日记"
            case .journalSearchPlaceholder: return "搜索正文或标签…"
            case .journalAllTags: return "全部"
            case .journalEmptyTitle: return "还没有日记"
            case .journalEmptySubtitle: return "写下今天的记录，可添加标签与图片，方便日后回顾。"
            case .journalUntitled: return "未命名日记"
            case .journalToday: return "今天"
            case .journalYesterday: return "昨天"
            case .journalSelectPrompt: return "从左侧时间轴选择一条日记"
            case .journalTitlePlaceholder: return "标题（可选）"
            case .journalTags: return "标签"
            case .journalTagPlaceholder: return "输入标签，回车添加"
            case .journalAddTag: return "添加"
            case .journalTagHint: return "可为日记添加标签，并按标签筛选。"
            case .journalBody: return "正文"
            case .journalBodyPlaceholder: return "写点什么…"
            case .journalImages: return "图片"
            case .journalImagesHint: return "拖入图片，或从剪贴板粘贴。"
            case .journalAddImage: return "添加图片"
            case .journalPasteImage: return "粘贴图片"
            case .journalPasteImageHelp: return "从剪贴板粘贴图片"
            case .journalDelete: return "删除日记"
            case .journalDeleteConfirm: return "确定删除这条日记？图片也会一并删除。"
            case .journalAutosaved: return "已自动保存"
            case .journalLayoutSplit: return "双栏布局"
            case .journalLayoutSingle: return "单栏布局"
            case .journalReminder: return "日记提醒"
            case .journalReminderEnabled: return "每日提醒写日记"
            case .journalReminderTime: return "提醒时间"
            case .journalReminderTitle: return "该写日记了"
            case .journalReminderBody: return "点击打开 Wick，记下今天想留住的内容。"
            case .journalOpenAction: return "打开日记"
            case .journalSection: return "日记"
            }
        }

        var english: String {
            switch self {
            case .motto: return "Time is precious."
            case .quit: return "Quit"
            case .settings: return "Settings"
            case .back: return "Back"
            case .cancel: return "Cancel"
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

            case .journal: return "Journal"
            case .journalTitle: return "Journal"
            case .journalNewEntry: return "New Entry"
            case .journalSearchPlaceholder: return "Search text or tags…"
            case .journalAllTags: return "All"
            case .journalEmptyTitle: return "No entries yet"
            case .journalEmptySubtitle: return "Write a note for today. Add tags and images if you like."
            case .journalUntitled: return "Untitled entry"
            case .journalToday: return "Today"
            case .journalYesterday: return "Yesterday"
            case .journalSelectPrompt: return "Select an entry from the timeline"
            case .journalTitlePlaceholder: return "Title (optional)"
            case .journalTags: return "Tags"
            case .journalTagPlaceholder: return "Add a tag, press Return"
            case .journalAddTag: return "Add"
            case .journalTagHint: return "Tags help you find entries later."
            case .journalBody: return "Body"
            case .journalBodyPlaceholder: return "Write something…"
            case .journalImages: return "Images"
            case .journalImagesHint: return "Drop images here, or paste from the clipboard."
            case .journalAddImage: return "Add Image"
            case .journalPasteImage: return "Paste Image"
            case .journalPasteImageHelp: return "Paste an image from the clipboard"
            case .journalDelete: return "Delete Entry"
            case .journalDeleteConfirm: return "Delete this entry? Attached images will be removed too."
            case .journalAutosaved: return "Autosaved"
            case .journalLayoutSplit: return "Split layout"
            case .journalLayoutSingle: return "Single column"
            case .journalReminder: return "Journal Reminder"
            case .journalReminderEnabled: return "Daily journal reminder"
            case .journalReminderTime: return "Reminder time"
            case .journalReminderTitle: return "Time to journal"
            case .journalReminderBody: return "Open Wick and write today’s entry."
            case .journalOpenAction: return "Open Journal"
            case .journalSection: return "Journal"
            }
        }
    }
}
