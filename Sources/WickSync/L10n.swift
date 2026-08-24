import Foundation

/// App display language. Shared with the iPhone client.
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case chinese = "zh-Hans"
    case english = "en"

    public var id: String { rawValue }

    public var locale: Locale {
        switch self {
        case .chinese:
            return Locale(identifier: "zh_CN")
        case .english:
            return Locale(identifier: "en_US")
        }
    }

    public var displayName: String {
        switch self {
        case .chinese:
            return "中文"
        case .english:
            return "English"
        }
    }

    /// Follows the system preferred languages.
    public static var system: AppLanguage {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .chinese : .english
    }
}

public enum L10n {
    public static func string(_ key: Key, language: AppLanguage) -> String {
        switch language {
        case .chinese:
            return key.chinese
        case .english:
            return key.english
        }
    }

    public enum Key {
        case motto
        case panelWordmark
        case panelHeroToday
        case quit
        case settings
        case back
        case cancel
        case ok
        case language
        case appearance
        case pnlColorConvention
        case journalFontStyle
        case fontDefault
        case chooseFont
        case fontSearchPlaceholder
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
        case journalDayStatsFormat
        case journalDayStatsFlatFormat
        case journalDayElapsedFormat
        case sidebarTodayMark
        case inspectorYiLabel
        case inspectorYiText
        case inspectorJiLabel
        case inspectorJiText
        case inspectorMonthTotal
        case journalItemTagPlaceholder
        case journalBodyPlaceholder
        case journalImagesHint
        case journalAddImage
        case journalPreviewImage
        case journalOpenInPreview
        case journalCopyImage
        case journalRevealInFinder
        case journalImagePreviewHint
        case journalImageZoomIn
        case journalImageZoomOut
        case journalImageActualSize
        case journalImageFit
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
        case journalFilterEmptyTitle
        case journalFilterEmptySubtitle
        case journalOpenFullDay
        case journalUntitledItem
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
        case journalNewerVersionRequired
        case journalUnsafeImageReferences
        case journalRecoveryFailedTitle

        // Sync
        case syncSection
        case syncConnect
        case syncConnecting
        case syncDisconnect
        case syncExplanation
        case syncNow
        case syncStatusSyncing
        case syncStatusOffline
        case syncStatusNeedsAuth
        case syncRemoteTooNew
        case syncLastSync
        case syncNeverSynced
        case syncConflictNoticeFormat
        case syncConflictDismiss
        case syncConflictDismissAll
        case syncConflictKindItem
        case syncConflictKindDeleteEdit
        case syncConflictKindResurrect
        case syncConflictLocalVersion
        case syncConflictRemoteVersion
        case syncConflictMergedVersion
        case syncConflictKeepLocal
        case syncConflictKeepRemote
        case syncConflictKeepMerged
        case syncConflictKeepAllLocal
        case syncConflictKeepAllRemote
        case syncConflictEmptyVersion
        case syncConflictMoreItemsFormat
        case syncConflictNoChoiceHint
        case syncDisconnectConfirmTitle
        case syncDisconnectConfirmBody
        case syncRemoteJournalFormat
        case syncImportJournal
        case syncTradingSnapshots
        case syncTradingSnapshotsHint
        case journalRestoredFromBackup
        case journalReadOnly
        case journalChangeDate
        case journalToggleSidebar
        case journalReview
        case journalReviewCorrect
        case journalReviewWrong
        case journalReviewNotePlaceholder
        case journalReviewClear
        case journalReviewHelp
        case journalLibraryMenu
        case journalLibraryDefaultName
        case journalLibraryNew
        case journalLibraryNewTitle
        case journalLibraryNamePlaceholder
        case journalLibraryRename
        case journalLibraryRenameTitle
        case journalLibraryDelete
        case journalLibraryDeleteConfirm
        case journalLibraryCreate
        case journalLibrarySaveName

        // Exchange positions
        case exchangeSection
        case exchangeExplanation
        case exchangeBindJournalFormat
        case exchangeJournal
        case exchangeVenue
        case exchangeVenueBinance
        case exchangeVenueOKX
        case exchangeVenueHyperliquid
        case exchangeApiKey
        case exchangeSecretKey
        case exchangePassphrase
        case exchangeWalletAddress
        case exchangeSaveAndSync
        case exchangeSyncNow
        case exchangeDisconnect
        case exchangeDisconnectConfirmTitle
        case exchangeDisconnectConfirmBody
        case exchangeDisconnectLocalOnly
        case exchangeDisconnectDeleteCloud
        case exchangeReadonlyHint
        case exchangeWindowHint
        case exchangeOKXHint
        case exchangeHyperliquidHint
        case exchangeSyncing
        case exchangeLastSync
        case exchangeNeverSynced
        case exchangeErrorInvalidKey
        case exchangeErrorRateLimited
        case exchangeErrorNetwork
        case exchangeErrorOther
        case exchangeErrorEmptyWindow
        case exchangePositionsTitle
        case exchangePositionVwap
        case exchangePositionSize
        case exchangePositionRealizedPnl
        case exchangePositionCommission
        case exchangePositionFunding
        case exchangePositionNetPnl
        case exchangePositionLong
        case exchangePositionShort
        case exchangePositionOpen
        case exchangePositionClosed
        case copyErrorHint
        case copied

        // Trading calendar
        case tradingCalendar
        case macroEventsSection
        case macroLoading
        case macroLoadFailed
        case macroNoEvents
        case macroActual
        case macroForecast
        case macroPrevious
        case macroImportance
        case macroLunar
        case macroMoreEventsFormat
        case calendarIdleWeekday
        case calendarIdleWeekend
        case inspectorMonthlyOverview
        case inspectorJournalsSection
        case inspectorTagsSection
        case journalLibraryManage
        case journalCycleColumns
        case inspectorToggle
        case inspectorEntriesSection
        case calendarEasterEggTitle
        case calendarEasterEggNote
        case macroEventsFirstPage
        case macroEventsFlipHint
        case earningsSection
        case earningsBeforeOpen
        case earningsAfterClose
        case earningsTimeTbd
        case macroEventsFlipHintTouch

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

        // iOS mobile specific
        case upcomingEventsTitle
        case todayTradingTitle
        case todayRecordsTitle
        case noUpcomingEvents
        case allEventsPublished
        case noClosedTrades
        case viewTradingDetails
        case recordsCountFormat
        case unreviewedCountBadgeFormat
        case emptyTodayJournalHint
        case quickNotePlaceholder
        case stampReview
        case reviewNoteLabel
        case dailyReviewReminderSubtitle
        case settingsAppearanceTheme
        case exchangeBind
        case exchangeUnbind
        case exchangeAccountLabel
        case exchangeConnected
        case exchangeNotConnected
        case tabHome
        case tabJournal
        case tabCalendar
        case tabSettings

        public var chinese: String {
            switch self {
            case .motto: return "一寸光阴一寸金。"
            case .panelWordmark: return "秉烛"
            case .panelHeroToday: return "今日剩余"
            case .quit: return "退出"
            case .settings: return "设置"
            case .back: return "返回"
            case .cancel: return "取消"
            case .ok: return "好"
            case .language: return "语言"
            case .appearance: return "外观"
            case .pnlColorConvention: return "涨跌配色"
            case .journalFontStyle: return "字体风格"
            case .fontDefault: return "默认（系统字体）"
            case .chooseFont: return "选择字体…"
            case .fontSearchPlaceholder: return "搜索字体"
            case .dayTitle: return "日"
            case .daySubtitle: return "今天"
            case .weekTitle: return "周"
            case .weekSubtitle: return "本周"
            case .monthTitle: return "月"
            case .monthSubtitle: return "本月"
            case .yearTitle: return "年"
            case .yearSubtitle: return "今年"
            case .remainingLessThanOneMinute: return "不到 1 分钟"
            case .remainingPrefix: return "剩 "
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
            case .journalDayStatsFormat: return "%d 条 · %d 笔已平仓"
            case .journalDayStatsFlatFormat: return "%d 条 · 无持仓"
            case .journalDayElapsedFormat: return "今日已过 %d%%"
            case .sidebarTodayMark: return "今"
            case .inspectorYiLabel: return "宜"
            case .inspectorYiText: return "止盈 · 复盘"
            case .inspectorJiLabel: return "忌"
            case .inspectorJiText: return "追单 · 扛单"
            case .inspectorMonthTotal: return "已实现合计"
            case .journalItemTagPlaceholder: return "为此条目添加标签"
            case .journalBodyPlaceholder: return "写点什么…"
            case .journalImagesHint: return "拖入图片，或从剪贴板粘贴。"
            case .journalAddImage: return "添加图片"
            case .journalPreviewImage: return "预览图片"
            case .journalOpenInPreview: return "在「预览」中打开"
            case .journalCopyImage: return "拷贝图片"
            case .journalRevealInFinder: return "在访达中显示"
            case .journalImagePreviewHint: return "双击放大预览图片"
            case .journalImageZoomIn: return "放大"
            case .journalImageZoomOut: return "缩小"
            case .journalImageActualSize: return "实际大小"
            case .journalImageFit: return "适应窗口"
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
            case .journalFilterEmptyTitle: return "没有匹配的条目"
            case .journalFilterEmptySubtitle: return "试试其他标签或清空搜索。"
            case .journalOpenFullDay: return "查看当天全部"
            case .journalUntitledItem: return "未命名条目"
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
            case .journalNewerVersionRequired: return "日记数据由更新版本的 Wick 写入，请升级 App 后再编辑"
            case .journalUnsafeImageReferences: return "日记数据包含不安全的图片引用，已阻止编辑以防文件被误删；请导入备份恢复"
            case .journalRecoveryFailedTitle: return "恢复失败"

            case .syncSection: return "同步"
            case .syncConnect: return "连接 Dropbox"
            case .syncConnecting: return "正在连接…"
            case .syncDisconnect: return "断开 Dropbox"
            case .syncExplanation: return "通过 Dropbox 在多台设备间同步日记。本地始终是主副本，同步中断不影响使用。"
            case .syncNow: return "立即同步"
            case .syncStatusSyncing: return "正在同步…"
            case .syncStatusOffline: return "当前离线，将自动重试"
            case .syncStatusNeedsAuth: return "需要重新连接 Dropbox"
            case .syncRemoteTooNew: return "远端数据由更新版本的 Wick 写入，请升级 App"
            case .syncLastSync: return "最后同步"
            case .syncNeverSynced: return "尚未同步"
            case .syncConflictNoticeFormat: return "发现 %lld 个同步冲突，双方内容均已保留"
            case .syncConflictDismiss: return "知道了"
            case .syncConflictDismissAll: return "全部保留合并结果"
            case .syncConflictKindItem: return "双方都修改了这一天"
            case .syncConflictKindDeleteEdit: return "远端删除与本机编辑冲突，已保留编辑"
            case .syncConflictKindResurrect: return "本机删除被远端编辑覆盖，已恢复"
            case .syncConflictLocalVersion: return "本机版本"
            case .syncConflictRemoteVersion: return "远端版本"
            case .syncConflictMergedVersion: return "合并结果（当前）"
            case .syncConflictKeepLocal: return "保留本机"
            case .syncConflictKeepRemote: return "保留远端"
            case .syncConflictKeepMerged: return "保留合并"
            case .syncConflictKeepAllLocal: return "全部保留本机"
            case .syncConflictKeepAllRemote: return "全部保留远端"
            case .syncConflictEmptyVersion: return "（空）"
            case .syncConflictMoreItemsFormat: return "还有 %d 条…"
            case .syncConflictNoChoiceHint: return "此冲突已自动处理，无需选择。"
            case .syncDisconnectConfirmTitle: return "断开 Dropbox？"
            case .syncDisconnectConfirmBody: return "将停止同步。本机与 Dropbox 中已有的数据都会保留。"
            case .syncRemoteJournalFormat: return "在 Dropbox 上发现日记本「%@」，可导入本机"
            case .syncImportJournal: return "导入"
            case .syncTradingSnapshots: return "同步仓位快照"
            case .syncTradingSnapshotsHint: return "可选。上传成交、资金费与仓位供其他设备只读展示；API Key、Secret 与 Passphrase 永不上传。"
            case .journalRestoredFromBackup: return "已从备份恢复日记"
            case .journalReadOnly: return "只读（加载失败）"
            case .journalChangeDate: return "修改日期"
            case .journalToggleSidebar: return "切换侧栏"
            case .journalReview: return "复盘"
            case .journalReviewCorrect: return "对"
            case .journalReviewWrong: return "错"
            case .journalReviewNotePlaceholder: return "补一句复盘…"
            case .journalReviewClear: return "清除复盘"
            case .journalReviewHelp: return "复盘此条目"
            case .journalLibraryMenu: return "切换日记本"
            case .journalLibraryDefaultName: return "日记"
            case .journalLibraryNew: return "新建日记本…"
            case .journalLibraryNewTitle: return "新建日记本"
            case .journalLibraryNamePlaceholder: return "名称"
            case .journalLibraryRename: return "重命名…"
            case .journalLibraryRenameTitle: return "重命名日记本"
            case .journalLibraryDelete: return "删除日记本…"
            case .journalLibraryDeleteConfirm: return "确定删除这个日记本？其中的全部日记、条目与图片都会被永久删除。"
            case .journalLibraryCreate: return "创建"
            case .journalLibrarySaveName: return "保存"

            case .exchangeSection: return "交易所"
            case .exchangeExplanation: return "先在上方选择日记本，再绑定一个交易所账号。仓位按「开仓日期 + 标签」挂到该日记条目上（标签 BTC 匹配 BTCUSDT 或 Hyperliquid 的 BTC）；没有日记的开仓日会自动创建条目。"
            case .exchangeBindJournalFormat: return "绑定到日记本「%@」"
            case .exchangeJournal: return "日记本"
            case .exchangeVenue: return "交易所"
            case .exchangeVenueBinance: return "Binance"
            case .exchangeVenueOKX: return "OKX"
            case .exchangeVenueHyperliquid: return "Hyperliquid"
            case .exchangeApiKey: return "API Key"
            case .exchangeSecretKey: return "Secret"
            case .exchangePassphrase: return "Passphrase"
            case .exchangeWalletAddress: return "钱包地址"
            case .exchangeSaveAndSync: return "保存并同步"
            case .exchangeSyncNow: return "立即刷新"
            case .exchangeDisconnect: return "断开交易所"
            case .exchangeDisconnectConfirmTitle: return "断开交易所？"
            case .exchangeDisconnectConfirmBody: return "本机保存的交易所凭据将被删除。日记内容不受影响。"
            case .exchangeDisconnectLocalOnly: return "仅断开本机"
            case .exchangeDisconnectDeleteCloud: return "断开并删除云端仓位"
            case .exchangeReadonlyHint: return "中心化交易所请用只读 API Key。打包后的应用把密钥存在本机钥匙串；用 swift run 开发时写在 Application Support 的本地文件里，避免每次重编译都弹钥匙串密码。"
            case .exchangeWindowHint: return "同步范围从本日记最早一天起。Binance 为 USDⓈ-M 合约；开仓日没有日记时会自动创建条目，删除后不会自动重建。"
            case .exchangeOKXHint: return "OKX 永续（SWAP），只读 API Key。同步从本日记第一天起，更早的成交不拉；所侧大约最多只能提供近 3 个月。"
            case .exchangeHyperliquidHint: return "只需填写 0x 地址，无需私钥（成交查询公开）。同步从本日记第一天起，更早的成交不拉；所侧大约最多保留最近 1 万笔。"
            case .exchangeSyncing: return "正在同步…"
            case .exchangeLastSync: return "上次同步"
            case .exchangeNeverSynced: return "尚未同步"
            case .exchangeErrorInvalidKey: return "API Key 无效、权限不足，或地址格式不对"
            case .exchangeErrorRateLimited: return "请求过于频繁，请稍后再试"
            case .exchangeErrorNetwork: return "网络错误，稍后自动重试"
            case .exchangeErrorOther: return "同步失败"
            case .exchangeErrorEmptyWindow: return "该账号在同步窗口内没有成交"
            case .exchangePositionsTitle: return "交易所仓位"
            case .exchangePositionVwap: return "开仓 → 平仓 VWAP"
            case .exchangePositionSize: return "数量 · 峰值"
            case .exchangePositionRealizedPnl: return "已实现盈亏"
            case .exchangePositionCommission: return "手续费"
            case .exchangePositionFunding: return "资金费"
            case .exchangePositionNetPnl: return "净盈亏"
            case .exchangePositionLong: return "多"
            case .exchangePositionShort: return "空"
            case .exchangePositionOpen: return "持仓中"
            case .exchangePositionClosed: return "已平仓"
            case .copyErrorHint: return "点击复制错误信息"
            case .copied: return "已复制"

            case .tradingCalendar: return "交易日历"
            case .macroEventsSection: return "宏观"
            case .macroLoading: return "加载中…"
            case .macroLoadFailed: return "加载失败"
            case .macroNoEvents: return "今日暂无宏观事件"
            case .macroActual: return "今值"
            case .macroForecast: return "预期"
            case .macroPrevious: return "前值"
            case .macroImportance: return "重要性"
            case .macroLunar: return "农历"
            case .macroMoreEventsFormat: return "另有 %d 项"
            case .calendarIdleWeekday: return "本日无事"
            case .calendarIdleWeekend: return "休市"
            case .inspectorMonthlyOverview: return "月度总览"
            case .inspectorJournalsSection: return "日记本"
            case .inspectorTagsSection: return "标签"
            case .journalLibraryManage: return "管理"
            case .journalCycleColumns: return "切换栏位(⌃⌘S)"
            case .inspectorToggle: return "检查器(⌥⌘0)"
            case .inspectorEntriesSection: return "条目"
            case .calendarEasterEggTitle: return "贴桌物理黄历"
            case .calendarEasterEggNote: return "彩蛋,默认关闭。开启后黄历以无边框贴桌窗呈现(撕页物理完整保留),主窗检查器随之关闭,盈亏月历移至导航栏顶部。"
            case .macroEventsFirstPage: return "回到首页"
            case .macroEventsFlipHint: return "轻点 / 滚轮 / ↑↓ 翻页 · ←→ 切换栏目"
            case .earningsSection: return "财报"
            case .earningsBeforeOpen: return "盘前"
            case .earningsAfterClose: return "盘后"
            case .earningsTimeTbd: return "未定"
            case .macroEventsFlipHintTouch: return "轻点翻页 · 点栏目切换"

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

            // iOS mobile specific
            case .upcomingEventsTitle: return "即将发布事件"
            case .todayTradingTitle: return "今日交易"
            case .todayRecordsTitle: return "今日记录"
            case .noUpcomingEvents: return "今日暂无宏观数据发布"
            case .allEventsPublished: return "今日已公布完毕"
            case .noClosedTrades: return "暂无平仓成交"
            case .viewTradingDetails: return "查看实盘 ›"
            case .recordsCountFormat: return "共 %d 条"
            case .unreviewedCountBadgeFormat: return "%d 待复盘"
            case .emptyTodayJournalHint: return "今天还没有记录，在下方快速写下一笔吧…"
            case .quickNotePlaceholder: return "写下此刻的交易想法或盘感…"
            case .stampReview: return "落印"
            case .reviewNoteLabel: return "批注"
            case .dailyReviewReminderSubtitle: return "每晚定时推送复盘提醒通知"
            case .settingsAppearanceTheme: return "外观与主题"
            case .exchangeBind: return "绑定交易所"
            case .exchangeUnbind: return "解绑"
            case .exchangeAccountLabel: return "账户备注"
            case .exchangeConnected: return "已连接"
            case .exchangeNotConnected: return "未配置交易所"
            case .tabHome: return "今日"
            case .tabJournal: return "日记"
            case .tabCalendar: return "日历"
            case .tabSettings: return "设置"
            }
        }

        public var english: String {
            switch self {
            case .motto: return "Time is precious."
            case .panelWordmark: return "Wick"
            case .panelHeroToday: return "Left today"
            case .quit: return "Quit"
            case .settings: return "Settings"
            case .back: return "Back"
            case .cancel: return "Cancel"
            case .ok: return "OK"
            case .language: return "Language"
            case .appearance: return "Appearance"
            case .pnlColorConvention: return "PnL color"
            case .journalFontStyle: return "Typeface"
            case .fontDefault: return "Default (system)"
            case .chooseFont: return "Choose font…"
            case .fontSearchPlaceholder: return "Search fonts"
            case .dayTitle: return "Day"
            case .daySubtitle: return "Today"
            case .weekTitle: return "Week"
            case .weekSubtitle: return "Week"
            case .monthTitle: return "Month"
            case .monthSubtitle: return "Month"
            case .yearTitle: return "Year"
            case .yearSubtitle: return "Year"
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
            case .journalDayStatsFormat: return "%d · %d closed"
            case .journalDayStatsFlatFormat: return "%d · flat"
            case .journalDayElapsedFormat: return "%d%% of today elapsed"
            case .sidebarTodayMark: return "NOW"
            case .inspectorYiLabel: return "DO"
            case .inspectorYiText: return "Take profit · Review"
            case .inspectorJiLabel: return "AVOID"
            case .inspectorJiText: return "Chase · Hold losers"
            case .inspectorMonthTotal: return "Realized total"
            case .journalItemTagPlaceholder: return "Tag for this item"
            case .journalBodyPlaceholder: return "Write something…"
            case .journalImagesHint: return "Drop images here, or paste from the clipboard."
            case .journalAddImage: return "Add Image"
            case .journalPreviewImage: return "Preview Image"
            case .journalOpenInPreview: return "Open in Preview"
            case .journalCopyImage: return "Copy Image"
            case .journalRevealInFinder: return "Reveal in Finder"
            case .journalImagePreviewHint: return "Double-click to preview image"
            case .journalImageZoomIn: return "Zoom In"
            case .journalImageZoomOut: return "Zoom Out"
            case .journalImageActualSize: return "Actual Size"
            case .journalImageFit: return "Fit to Window"
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
            case .journalFilterEmptyTitle: return "No matching items"
            case .journalFilterEmptySubtitle: return "Try another tag or clear the search."
            case .journalOpenFullDay: return "Open Full Day"
            case .journalUntitledItem: return "Untitled item"
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
            case .journalNewerVersionRequired: return "Journal data was written by a newer version of Wick — update the app to edit"
            case .journalUnsafeImageReferences: return "This journal contains unsafe image references. Editing is blocked to protect your files — import a backup to recover."
            case .journalRecoveryFailedTitle: return "Recovery Failed"

            case .syncSection: return "Sync"
            case .syncConnect: return "Connect Dropbox"
            case .syncConnecting: return "Connecting…"
            case .syncDisconnect: return "Disconnect Dropbox"
            case .syncExplanation: return "Sync journals across devices via Dropbox. Local data is always the primary copy — syncing can fail without affecting use."
            case .syncNow: return "Sync Now"
            case .syncStatusSyncing: return "Syncing…"
            case .syncStatusOffline: return "Offline — will retry automatically"
            case .syncStatusNeedsAuth: return "Dropbox sign-in required"
            case .syncRemoteTooNew: return "Remote data was written by a newer Wick — please update"
            case .syncLastSync: return "Last synced"
            case .syncNeverSynced: return "Not synced yet"
            case .syncConflictNoticeFormat: return "%lld sync conflict(s) found — both versions were kept"
            case .syncConflictDismiss: return "Dismiss"
            case .syncConflictDismissAll: return "Keep Merged for All"
            case .syncConflictKindItem: return "Edited on both devices"
            case .syncConflictKindDeleteEdit: return "Remote delete vs. local edit - edit kept"
            case .syncConflictKindResurrect: return "Local delete overridden by remote edit - restored"
            case .syncConflictLocalVersion: return "This Mac"
            case .syncConflictRemoteVersion: return "Dropbox"
            case .syncConflictMergedVersion: return "Merged (current)"
            case .syncConflictKeepLocal: return "Keep This Mac"
            case .syncConflictKeepRemote: return "Keep Dropbox"
            case .syncConflictKeepMerged: return "Keep Merged"
            case .syncConflictKeepAllLocal: return "Keep This Mac for All"
            case .syncConflictKeepAllRemote: return "Keep Dropbox for All"
            case .syncConflictEmptyVersion: return "(empty)"
            case .syncConflictMoreItemsFormat: return "%d more items…"
            case .syncConflictNoChoiceHint: return "Already handled automatically - nothing to choose."
            case .syncDisconnectConfirmTitle: return "Disconnect Dropbox?"
            case .syncDisconnectConfirmBody: return "Syncing will stop. Data already on this Mac and in Dropbox is kept."
            case .syncRemoteJournalFormat: return "Found journal “%@” on Dropbox — it can be imported to this Mac"
            case .syncImportJournal: return "Import"
            case .syncTradingSnapshots: return "Sync position snapshots"
            case .syncTradingSnapshotsHint: return "Optional. Uploads fills, funding, and positions for read-only display on other devices. API keys, secrets, and passphrases are never uploaded."
            case .journalRestoredFromBackup: return "Journal restored from backup"
            case .journalReadOnly: return "Read-only (load failed)"
            case .journalChangeDate: return "Change date"
            case .journalToggleSidebar: return "Toggle Sidebar"
            case .journalReview: return "Review"
            case .journalReviewCorrect: return "Right"
            case .journalReviewWrong: return "Wrong"
            case .journalReviewNotePlaceholder: return "Add a review note…"
            case .journalReviewClear: return "Clear review"
            case .journalReviewHelp: return "Review this item"
            case .journalLibraryMenu: return "Switch Journal"
            case .journalLibraryDefaultName: return "Journal"
            case .journalLibraryNew: return "New Journal…"
            case .journalLibraryNewTitle: return "New Journal"
            case .journalLibraryNamePlaceholder: return "Name"
            case .journalLibraryRename: return "Rename…"
            case .journalLibraryRenameTitle: return "Rename Journal"
            case .journalLibraryDelete: return "Delete Journal…"
            case .journalLibraryDeleteConfirm: return "Delete this journal? All days, items, and images will be permanently removed."
            case .journalLibraryCreate: return "Create"
            case .journalLibrarySaveName: return "Save"

            case .exchangeSection: return "Exchange"
            case .exchangeExplanation: return "Pick a journal above, then bind one exchange account. Positions attach to that journal’s items by open date + tag (tag BTC matches BTCUSDT or Hyperliquid’s BTC); missing position days get an entry created automatically."
            case .exchangeBindJournalFormat: return "Bound to journal “%@”"
            case .exchangeJournal: return "Journal"
            case .exchangeVenue: return "Venue"
            case .exchangeVenueBinance: return "Binance"
            case .exchangeVenueOKX: return "OKX"
            case .exchangeVenueHyperliquid: return "Hyperliquid"
            case .exchangeApiKey: return "API Key"
            case .exchangeSecretKey: return "Secret"
            case .exchangePassphrase: return "Passphrase"
            case .exchangeWalletAddress: return "Wallet address"
            case .exchangeSaveAndSync: return "Save & Sync"
            case .exchangeSyncNow: return "Refresh Now"
            case .exchangeDisconnect: return "Disconnect"
            case .exchangeDisconnectConfirmTitle: return "Disconnect exchange?"
            case .exchangeDisconnectConfirmBody: return "Exchange credentials stored on this Mac will be removed. Journal content is not affected."
            case .exchangeDisconnectLocalOnly: return "Disconnect This Mac Only"
            case .exchangeDisconnectDeleteCloud: return "Disconnect & Delete Cloud Positions"
            case .exchangeReadonlyHint: return "Use a read-only API key on centralized venues. The packaged app stores secrets in Keychain; `swift run` writes a local Application Support file so rebuilds don’t prompt for the login password."
            case .exchangeWindowHint: return "Sync covers from this journal’s earliest day. Binance is USDⓈ-M futures; missing position days get an entry, and deletions are respected."
            case .exchangeOKXHint: return "OKX perpetuals (SWAP), read-only key. Sync starts at this journal’s first day — older fills are not fetched. The venue itself only keeps about three months."
            case .exchangeHyperliquidHint: return "Address only — no private key (fills are public). Sync starts at this journal’s first day — older fills are not fetched. The venue keeps about the latest 10,000 fills."
            case .exchangeSyncing: return "Syncing…"
            case .exchangeLastSync: return "Last synced"
            case .exchangeNeverSynced: return "Not synced yet"
            case .exchangeErrorInvalidKey: return "Invalid API key, missing permission, or bad address"
            case .exchangeErrorRateLimited: return "Rate limited - try again later"
            case .exchangeErrorNetwork: return "Network error - will retry later"
            case .exchangeErrorOther: return "Sync failed"
            case .exchangeErrorEmptyWindow: return "No fills in the sync window for this account"
            case .exchangePositionsTitle: return "Exchange positions"
            case .exchangePositionVwap: return "Open → Close VWAP"
            case .exchangePositionSize: return "Size · Peak"
            case .exchangePositionRealizedPnl: return "Realized PnL"
            case .exchangePositionCommission: return "Commission"
            case .exchangePositionFunding: return "Funding"
            case .exchangePositionNetPnl: return "Net PnL"
            case .exchangePositionLong: return "Long"
            case .exchangePositionShort: return "Short"
            case .exchangePositionOpen: return "Open"
            case .exchangePositionClosed: return "Closed"
            case .copyErrorHint: return "Click to copy error"
            case .copied: return "Copied"

            case .tradingCalendar: return "Trading Calendar"
            case .macroEventsSection: return "Macro Events"
            case .macroLoading: return "Loading…"
            case .macroLoadFailed: return "Failed to load"
            case .macroNoEvents: return "No macro events today"
            case .macroActual: return "Actual"
            case .macroForecast: return "Forecast"
            case .macroPrevious: return "Previous"
            case .macroImportance: return "Importance"
            case .macroLunar: return "Lunar"
            case .macroMoreEventsFormat: return "%d more"
            case .calendarIdleWeekday: return "Quiet day"
            case .calendarIdleWeekend: return "Market closed"
            case .inspectorMonthlyOverview: return "Monthly Overview"
            case .inspectorJournalsSection: return "Journals"
            case .inspectorTagsSection: return "Tags"
            case .journalLibraryManage: return "Manage"
            case .journalCycleColumns: return "Cycle columns (⌃⌘S)"
            case .inspectorToggle: return "Inspector (⌥⌘0)"
            case .inspectorEntriesSection: return "Entries"
            case .calendarEasterEggTitle: return "Physical desk calendar"
            case .calendarEasterEggNote: return "Easter egg, off by default. The almanac becomes a borderless desk window with the full tear physics; the main-window inspector closes and the PnL calendar moves to the sidebar top."
            case .macroEventsFirstPage: return "First page"
            case .macroEventsFlipHint: return "Tap / scroll / ↑↓ to flip · ←→ to switch tab"
            case .earningsSection: return "Earnings"
            case .earningsBeforeOpen: return "BMO"
            case .earningsAfterClose: return "AMC"
            case .earningsTimeTbd: return "TBD"
            case .macroEventsFlipHintTouch: return "Tap to flip · tap a tab to switch"

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

            // iOS mobile specific
            case .upcomingEventsTitle: return "Upcoming Events"
            case .todayTradingTitle: return "Today's Trading"
            case .todayRecordsTitle: return "Today's Records"
            case .noUpcomingEvents: return "No upcoming macro data today"
            case .allEventsPublished: return "All published for today"
            case .noClosedTrades: return "No closed trades"
            case .viewTradingDetails: return "View Trades ›"
            case .recordsCountFormat: return "%d items"
            case .unreviewedCountBadgeFormat: return "%d to review"
            case .emptyTodayJournalHint: return "No entries today. Write a quick note below…"
            case .quickNotePlaceholder: return "Write down your trading thoughts…"
            case .stampReview: return "Stamp"
            case .reviewNoteLabel: return "Note"
            case .dailyReviewReminderSubtitle: return "Send a review reminder notification every night"
            case .settingsAppearanceTheme: return "Appearance & Theme"
            case .exchangeBind: return "Bind Exchange"
            case .exchangeUnbind: return "Unbind"
            case .exchangeAccountLabel: return "Account Label"
            case .exchangeConnected: return "Connected"
            case .exchangeNotConnected: return "Not Configured"
            case .tabHome: return "Today"
            case .tabJournal: return "Journal"
            case .tabCalendar: return "Calendar"
            case .tabSettings: return "Settings"
            }
        }
    }
}
