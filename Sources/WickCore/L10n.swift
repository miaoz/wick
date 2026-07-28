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
        case phaseDawn
        case phaseDay
        case phaseDusk
        case phaseNight
        case dayArcNowLabel
        case settingsTitle

        // Journal
        case journal
        case journalTitle
        case journalNewEntry
        case journalSearchPlaceholder
        case journalAllTags
        case journalTagsMoreFormat
        case journalTagsCollapse
        case journalEmptyTitle
        case journalEmptySubtitle
        case journalUntitled
        case journalToday
        case journalYesterday
        case journalSelectPrompt
        case journalTitlePlaceholder
        case journalItemsHint
        case journalAddItem
        case journalDeleteItem
        case journalItemNumberFormat
        case journalItemCountFormat
        case journalItemTag
        case journalItemTagPlaceholder
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
        case journalReminder
        case journalReminderEnabled
        case journalReminderTime
        case journalReminderTitle
        case journalReminderBody
        case journalOpenAction
        case journalSection
        case journalItemScopeHint
        case journalFilterEmptyTitle
        case journalFilterEmptySubtitle
        case journalOpenFullDay
        case journalUntitledItem
        case journalItemScopeBadge
        case journalItemScopeEditorHint
        case journalDeleteItemConfirm
        case journalExport
        case journalImport
        case journalExportSuccess
        case journalImportSuccess
        case journalExportFailed
        case journalImportFailed
        case journalRevealData
        case journalLoadFailureTitle
        case journalLoadFailureBody
        case journalStartFresh
        case journalRestoredFromBackup
        case journalReadOnly
        case journalChangeDate
        case journalToggleSidebar

        // Settings extras
        case generalSection
        case menuBarPercentage
        case weekStartsOnMonday
        case launchAtLogin
        case launchAtLoginNeedsApproval
        case openLoginItems
        case notificationDenied
        case openNotificationSettings
        case notificationUnavailable
        case aboutSection
        case versionLabel
        case checkForUpdates
        case checkingForUpdates
        case updateAvailableFormat
        case upToDate
        case updateCheckFailed
        case openReleasePage
        case checkUpdatesOnLaunch
        case dataSection

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
            case .phaseDawn: return "晨光"
            case .phaseDay: return "白昼"
            case .phaseDusk: return "暮色"
            case .phaseNight: return "夜幕"
            case .dayArcNowLabel: return "今天 · 此刻"
            case .settingsTitle: return "设置"

            case .journal: return "日记"
            case .journalTitle: return "日记"
            case .journalNewEntry: return "今日日记"
            case .journalSearchPlaceholder: return "搜索正文或标签…"
            case .journalAllTags: return "全部"
            case .journalTagsMoreFormat: return "更多 %d"
            case .journalTagsCollapse: return "收起"
            case .journalEmptyTitle: return "还没有日记"
            case .journalEmptySubtitle: return "新建一篇日记，用多条条目分别记录不同主题，每条可带标签、正文与图片。"
            case .journalUntitled: return "未命名日记"
            case .journalToday: return "今天"
            case .journalYesterday: return "昨天"
            case .journalSelectPrompt: return "从左侧时间轴选择一篇日记"
            case .journalTitlePlaceholder: return "标题（可选）"
            case .journalItemsHint: return "一篇日记可包含多条条目；每条对应一个标签、正文和图片。"
            case .journalAddItem: return "添加条目"
            case .journalDeleteItem: return "删除条目"
            case .journalItemNumberFormat: return "条目 %d"
            case .journalItemCountFormat: return "%d 条"
            case .journalItemTag: return "标签"
            case .journalItemTagPlaceholder: return "为此条目添加标签"
            case .journalBody: return "正文"
            case .journalBodyPlaceholder: return "写点什么…"
            case .journalImages: return "图片"
            case .journalImagesHint: return "拖入图片，或从剪贴板粘贴。"
            case .journalAddImage: return "添加图片"
            case .journalPasteImage: return "粘贴图片"
            case .journalPasteImageHelp: return "从剪贴板粘贴图片"
            case .journalDelete: return "删除日记"
            case .journalDeleteConfirm: return "确定删除这篇日记？其中的条目与图片都会一并删除。"
            case .journalAutosaved: return "已自动保存"
            case .journalReminder: return "日记提醒"
            case .journalReminderEnabled: return "每日提醒写日记"
            case .journalReminderTime: return "提醒时间"
            case .journalReminderTitle: return "该写日记了"
            case .journalReminderBody: return "点击打开 Wick，记下今天想留住的内容。"
            case .journalOpenAction: return "打开日记"
            case .journalSection: return "日记"
            case .journalItemScopeHint: return "筛选中：列表与编辑区只显示匹配的条目，不会带出当天其他条目。"
            case .journalFilterEmptyTitle: return "没有匹配的条目"
            case .journalFilterEmptySubtitle: return "试试其他标签或清空搜索。"
            case .journalOpenFullDay: return "查看当天全部"
            case .journalUntitledItem: return "未命名条目"
            case .journalItemScopeBadge: return "单条"
            case .journalItemScopeEditorHint: return "当前只编辑这一条。可打开「查看当天全部」管理同日其他条目。"
            case .journalDeleteItemConfirm: return "确定删除这条条目？相关图片也会删除。"
            case .journalExport: return "导出日记…"
            case .journalImport: return "导入日记…"
            case .journalExportSuccess: return "日记已导出"
            case .journalImportSuccess: return "日记已导入"
            case .journalExportFailed: return "导出失败"
            case .journalImportFailed: return "导入失败"
            case .journalRevealData: return "在 Finder 中显示数据"
            case .journalLoadFailureTitle: return "日记文件无法读取"
            case .journalLoadFailureBody: return "已阻止覆盖，以免丢失数据。可尝试导入备份，或在确认后清空并重新开始。"
            case .journalStartFresh: return "清空并重新开始"
            case .journalRestoredFromBackup: return "已从备份恢复日记"
            case .journalReadOnly: return "只读（加载失败）"
            case .journalChangeDate: return "修改日期"
            case .journalToggleSidebar: return "切换侧栏"

            case .generalSection: return "通用"
            case .menuBarPercentage: return "菜单栏显示今日剩余"
            case .weekStartsOnMonday: return "周从周一开始"
            case .launchAtLogin: return "登录时启动"
            case .launchAtLoginNeedsApproval: return "请在系统设置中允许 Wick 登录启动"
            case .openLoginItems: return "打开登录项设置"
            case .notificationDenied: return "通知权限已关闭，提醒无法送达"
            case .openNotificationSettings: return "打开通知设置"
            case .notificationUnavailable: return "开发运行中无法使用通知（请打开打包后的 Wick.app）"
            case .aboutSection: return "关于"
            case .versionLabel: return "版本"
            case .checkForUpdates: return "检查更新"
            case .checkingForUpdates: return "正在检查…"
            case .updateAvailableFormat: return "发现新版本 %@，点击打开下载页"
            case .upToDate: return "已是最新版本"
            case .updateCheckFailed: return "检查更新失败"
            case .openReleasePage: return "打开发布页"
            case .checkUpdatesOnLaunch: return "启动时检查更新"
            case .dataSection: return "数据"
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
            case .phaseDawn: return "Dawn"
            case .phaseDay: return "Daylight"
            case .phaseDusk: return "Dusk"
            case .phaseNight: return "Nightfall"
            case .dayArcNowLabel: return "Today · now"
            case .settingsTitle: return "Settings"

            case .journal: return "Journal"
            case .journalTitle: return "Journal"
            case .journalNewEntry: return "Today’s Journal"
            case .journalSearchPlaceholder: return "Search text or tags…"
            case .journalAllTags: return "All"
            case .journalTagsMoreFormat: return "%d More"
            case .journalTagsCollapse: return "Less"
            case .journalEmptyTitle: return "No entries yet"
            case .journalEmptySubtitle: return "Create a journal day with multiple items — each item has a tag, text, and images."
            case .journalUntitled: return "Untitled journal"
            case .journalToday: return "Today"
            case .journalYesterday: return "Yesterday"
            case .journalSelectPrompt: return "Select a journal from the timeline"
            case .journalTitlePlaceholder: return "Title (optional)"
            case .journalItemsHint: return "A journal can hold multiple items. Each item has one tag, text, and images."
            case .journalAddItem: return "Add Item"
            case .journalDeleteItem: return "Delete Item"
            case .journalItemNumberFormat: return "Item %d"
            case .journalItemCountFormat: return "%d items"
            case .journalItemTag: return "Tag"
            case .journalItemTagPlaceholder: return "Tag for this item"
            case .journalBody: return "Text"
            case .journalBodyPlaceholder: return "Write something…"
            case .journalImages: return "Images"
            case .journalImagesHint: return "Drop images here, or paste from the clipboard."
            case .journalAddImage: return "Add Image"
            case .journalPasteImage: return "Paste Image"
            case .journalPasteImageHelp: return "Paste an image from the clipboard"
            case .journalDelete: return "Delete Journal"
            case .journalDeleteConfirm: return "Delete this journal? All items and images will be removed."
            case .journalAutosaved: return "Autosaved"
            case .journalReminder: return "Journal Reminder"
            case .journalReminderEnabled: return "Daily journal reminder"
            case .journalReminderTime: return "Reminder time"
            case .journalReminderTitle: return "Time to journal"
            case .journalReminderBody: return "Open Wick and write today’s entry."
            case .journalOpenAction: return "Open Journal"
            case .journalSection: return "Journal"
            case .journalItemScopeHint: return "Filtered: only matching items appear — not the full day."
            case .journalFilterEmptyTitle: return "No matching items"
            case .journalFilterEmptySubtitle: return "Try another tag or clear the search."
            case .journalOpenFullDay: return "Open Full Day"
            case .journalUntitledItem: return "Untitled item"
            case .journalItemScopeBadge: return "Item"
            case .journalItemScopeEditorHint: return "Editing this item only. Open the full day to manage siblings."
            case .journalDeleteItemConfirm: return "Delete this item? Its images will be removed too."
            case .journalExport: return "Export Journal…"
            case .journalImport: return "Import Journal…"
            case .journalExportSuccess: return "Journal exported"
            case .journalImportSuccess: return "Journal imported"
            case .journalExportFailed: return "Export failed"
            case .journalImportFailed: return "Import failed"
            case .journalRevealData: return "Reveal Data in Finder"
            case .journalLoadFailureTitle: return "Couldn’t read journal file"
            case .journalLoadFailureBody: return "Writes are blocked so your file won’t be overwritten. Import a backup, or start fresh after confirming."
            case .journalStartFresh: return "Start Fresh"
            case .journalRestoredFromBackup: return "Journal restored from backup"
            case .journalReadOnly: return "Read-only (load failed)"
            case .journalChangeDate: return "Change date"
            case .journalToggleSidebar: return "Toggle Sidebar"

            case .generalSection: return "General"
            case .menuBarPercentage: return "Show day remaining in menu bar"
            case .weekStartsOnMonday: return "Week starts on Monday"
            case .launchAtLogin: return "Open at Login"
            case .launchAtLoginNeedsApproval: return "Allow Wick in System Settings → Login Items"
            case .openLoginItems: return "Open Login Items"
            case .notificationDenied: return "Notifications are off — reminders can’t be delivered"
            case .openNotificationSettings: return "Open Notification Settings"
            case .notificationUnavailable: return "Notifications need the packaged Wick.app (not swift run)"
            case .aboutSection: return "About"
            case .versionLabel: return "Version"
            case .checkForUpdates: return "Check for Updates"
            case .checkingForUpdates: return "Checking…"
            case .updateAvailableFormat: return "Update %@ available — click to open downloads"
            case .upToDate: return "You’re up to date"
            case .updateCheckFailed: return "Update check failed"
            case .openReleasePage: return "Open Releases"
            case .checkUpdatesOnLaunch: return "Check for updates on launch"
            case .dataSection: return "Data"
            }
        }
    }
}
