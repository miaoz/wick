# AGENTS.md

> 面向 AI 编码代理：Wick 的架构、构建、测试与约定。本文只保留「看代码不易发现」的约束与坑；改动代码前先核对相关源文件。

## 项目概览

- **Wick**：原生 macOS 菜单栏应用（`LSUIElement`，无 Dock 图标）。蜡烛图标弹出面板，实时展示 日/周/月/年 剩余百分比与结束时间（每秒刷新）。
- **日记**：一天一篇、篇内多条目（标签+正文+图片），条目级检索、每日本地通知提醒、zip 导入导出。
- **Dropbox 同步**（可选）：本地为唯一真源，`WickSync` 引擎按日记 UUID 双向对账（日期只是可编辑字段，OAuth PKCE，客户端无 App secret）；删除靠墓碑传播、冲突按条目并集合并并保留败者、远端文件意外消失自动回传。另有默认关闭的仓位快照同步：`trading/snapshot.json` 整文件按 `fetchedAt` 新者胜，凭据不上传，显式删除以 `trading/deleted.json` 墓碑阻止旧设备回传。
- **交易所仓位**（可选，一本日记一个账号）：Binance USDⓈ-M / OKX SWAP / Hyperliquid 永续。凭据按日记本存（打包 `.app` 走 Keychain 一条 JSON；`swift run` 走 `Application Support/Wick/dev-secrets.json` 以免每次重编译弹密码）。`WickTrading` 直连各所 REST 拉成交，归一成 `TradingFill`；窗口下界为该本最早日记日（无日记时仅从当日开始；OKX 所侧约 3 个月、HL 约最近 1 万笔）。快照 `Wick/Trading/<journalID>.json` 增量刷新；开启仓位快照同步后上传成交/资金费/聚合仓位供其他设备只读展示，CEX 凭据永不上传、HL 地址只上传首尾掩码；`PositionAggregator` 聚合成开平仓会话（对冲双 lane、加仓 VWAP、翻仓拆两段、**净值 epsilon 吸附归零**、缺失开仓历史时明确的孤立平仓不得伪造仓位）；按「开仓日 + 宽松标签」挂进卡片（`BTC` 匹配 `BTCUSDT` 与 HL 的 `BTC`）；`PositionEntryPlanner` 持续补齐缺失的开仓日日记或匹配标签（**从不改写已有标签或内容**）。HL 只填 0x 地址、不收私钥。
- **交易日历**：himekuri「黄历」撕页日历（无边框透明穿透窗、撕纸物理与程序合成音效），内容由 `WickCalendarKit` 直连华尔街见闻（宏观 + 财报，keyless REST，非 WebSocket、不打包 Python）。
- **字体**：可从设备已安装字体里任选一套，全局换用（日记、设置、日历、编辑器输入），不内置任何字体文件；不选即默认 Songti/系统外观。见 `AppFont`/`FontPickerView`。
- 其他：登录启动（`SMAppService`）、亮/暗/跟随系统外观（「一日弧光」主题引擎）、中英双语、菜单栏百分比、GitHub Releases 检查更新。
- macOS 13+ / Universal；Swift 6.1+、SwiftUI + AppKit、SwiftPM，**无第三方依赖**。Bundle ID `com.miaoz.wick`；版本默认值见 `scripts/package_app.sh`。

## 模块划分

SwiftPM target（package 声明 macOS 13+ / iOS 16+，macOS 专属 target 不参与 iOS 构建）：

| Target | 职责 |
| --- | --- |
| `WickSync` | 纯 Foundation：日记模型 + 同步引擎 + Dropbox 后端 + `L10n`/`AppLanguage`/`JournalDayKey`。**禁止 `import AppKit`/`UIKit`**；iOS 工程本地包引用指回仓库根 |
| `WickCalendarKit` | 跨平台交易日历：数据 + verlet 撕纸物理 + SwiftUI/SpriteKit 渲染 + 合成音效；一切度量按 `PaperLayout` 参数化（桌面 300×400 部件 / iPhone 页即屏幕满屏），`#if os(macOS)` 只隔离窗口呈现/光标/触觉等平台 API；依赖 `WickSync`。iOS 编译校验：`swift build --target WickCalendarKit --triple arm64-apple-ios16.0 --sdk <iphoneos-sdk>` |
| `WickTrading` | 纯 Foundation + CryptoKit：`ExchangeTradeClient`（Binance USD-M / OKX SWAP / Hyperliquid info）+ 成交→仓位聚合 + 宽松标签匹配 + `DailyRealizedPnl` |
| `WickCore` | macOS 其余几乎全部代码（测试 `@testable import`）；依赖上述三者，`Exports.swift` 同时 `@_exported` 三者 |
| `Wick` | 可执行入口（3 行，调 `WickApp.main()`） |

测试 target 与之一一对应：`WickTests` / `WickSyncTests` / `WickCalendarKitTests` / `WickTradingTests`。

### `Sources/WickCore/`

| 文件 | 职责 |
| --- | --- |
| `WickApp.swift` | `MenuBarExtra` 场景、`AppDelegate`（外观/登录项/提醒/更新检查、退出前落盘）、菜单栏 label（蜡烛 + 可选当日剩余百分比）；DEBUG 启动参数 `-wick-open-journal` 启动即打开日记窗口（UI 检查用） |
| `ProgressPanelView.swift` | 菜单栏纸签与设置页：<br>· 撕边纸签外壳(`TornSlipShape`) + 今日大烛痕条 + 周/月/年细条(`BurnStripView`,刻度 24/7/当月天数/12)<br>· `PanelTheme` 薄结构体委托 `DayArcEngine`<br>· 设置页:秉烛平铺纸面与发丝分隔线(无嵌套卡片壳,宋体分节,烛火选项签条,彩蛋虚线方框);含「字体风格」入口 → `FontPickerView` 搜索弹层选设备字体 |
| `FontPickerView.swift` | 设置→字体风格 的搜索弹层(`FontPickerSettingRow` 触发 `.popover`):首行「默认（系统字体）」+ 每行用该字体自身预览族名 + 搜索按族名/PostScript 名过滤;点选写 `settings.journalFontName` 并关闭,面板/日记/日历即时换字 |
| `WickTheme.swift` | 「秉烛」主题引擎(原一日弧光重构):`WickRGB`、`WickPalette`(宣纸/烟墨/烛火/朱砂/黛青/烛痕/单据纸/烛印方砖)、`DayPhase` 四锚点 × 亮暗插值,**火苗色跨时段恒定**(子夜不再变蓝);`WICK_ARC_TIME=HH:mm`(仅 DEBUG);`\.wickPalette` 环境键;纸面层级映射 `columnPaper`(栏面)/`editorCanvas`(编辑画布)/`pageSurface`(页纸)对应蓝本 paper/paper-hi/desk 混合,`WickPrintFont.songti` 供 AppKit 文本件用纸面字体(委托 `AppFont.paperNSFont`;缓存键必须包含所选 PostScript 名,字体暂不可用时禁止缓存系统回退)。设计蓝本:`designs/wick-design-language/final.html` |
| `AppFont.swift` | **全应用字体单一解析器**：`paper`(纸面中文/Songti) / `ui`(原 `.system(...)`,含 design/monospacedDigit 参数) / `preset`(原 `.caption`/`.headline` 等预设) / `paperNSFont`(AppKit/编辑器);`selectedFontName` 读 `AppSettings.journalFontName`(空 = 默认外观,非空即全局换用该 PostScript 名)。`installedFonts()` 用 `NSFontManager.availableFontFamilies`+`availableMembers(ofFontFamily:)` 枚举设备字体族——**成员数组 = [PostScript名, 样式名, weight, traits],PostScript 名在 index 0**。**所有字体引用必须走这里,勿硬编码 `Songti SC`/`.system(...)`/`.caption`** |
| `JournalStore.swift` | 多日记本存储单例：`catalog.json` + 每本独立目录；`.bak` + 滚动备份、版本门、加载失败只读保护、图片管理、zip 导入导出、旧版一次性迁移；`updateEntry` 对内容未变的草稿必须 no-op（关闭窗口/切本不可伪造 `updatedAt` 同步编辑）；文件尾部为 `JournalLocalSource` 同步桥接（远端文件名防穿越校验、改名撞名去重） |
| `JournalTopBarView.swift` / `JournalRootView.swift` / `JournalSidebarView.swift` / `JournalEditorPane.swift` | 秉烛主窗：<br>· **原生标题栏顶栏**:窗口用空的 `NSToolbar(.unified)` 建立系统标题栏高度，`JournalTopBarView` 作为 `NSTitlebarAccessoryViewController(.top)` 与红绿灯同一行；三态循环钮 ⌃⌘S[全导航→仅列表→专注]、**静态日记名**、选中日小注、搜索、新建、右钮 ⌥⌘0 全部在 accessory 内，**不测量、不移动、不覆盖红绿灯**，红绿灯由 AppKit 完整管理<br>· **手动三栏**:导航 `JournalNavigationSidebar` / 日期列表 `JournalDayListColumn` / 编辑页;**不用 NavigationSplitView**——macOS 26 会把侧栏画成浮动圆角卡片,与平铺纸面冲突;栏间 `JournalColumnDivider` = 1pt 界线 + 7pt 命中区,拖拽调宽、拖到边缘/双击收栏,栏宽落 `wick.journal.navWidth/listWidth`,拖拽上限实时反推编辑页地板(`navWidthCeiling/listWidthCeiling`,拖栏不再把编辑页挤变形);栏一文字左缘固定 x=10,行 pill 留 4pt 外边距;日记本行统一用 `onTapGesture` + accessibility button 语义承载点击，**勿改回 `Button`**——macOS 13/15 的 `NSButton` 会抢走 `onDrag` 鼠标序列导致无法排序;标签签条走 `SidebarChipFlow`(自研 Layout 贪心换行+超长截断,**勿用 LazyVGrid adaptive**——等宽列长签溢出、拖栏时与邻签重叠)<br>· **栏四检查器** `JournalInspectorView`:今日事件 + 盈亏月历,仅彩蛋关时在;**盈亏收合 → 事件栏全量滚动撑满整栏**(事件常有数十项);宏观标题默认最多两行、财报代码 `fixedSize` 单行不折、**条目点击展开全文/再次点击收起**;栏位状态持久化(`journalColumnMode`)<br>· **编辑页 = 一天一页纸**:`pageSurface` 纸页 + 衬线大日期页眉[点开改日] + 星期/农历小注 + 当日已实现盈亏 + 页内细烛痕条(过去的天然燃尽、今日带「已过 N%」小字);条目沿发丝线排列、无卡片壳;编辑栏 440pt 宽度地板(`editorMinWidth`,页眉排不下时走 `ViewThatFits` 两行版[盈亏/保存注挪下行],部件全 fixedSize、绝不逐字竖排;`editorComfortWidth` 640 = 单行页眉舒适宽,仅供首启默认尺寸)<br>· **日期列表按月分节**(「八月 2026」节头),行 = 日期+周几 / 条数·平仓数 / 等宽盈亏+复盘小章,选中 = 页纸高亮 + 左缘 3pt 朱砂界;List 必须 `.scrollContentBackground(.hidden)`(否则侧栏 vibrancy 把纸色变灰);滚动条隐藏走 `.scrollIndicators(.never)`(macOS 上 `.hidden` 接鼠标/系统「始终显示滚动条」仍露条)+ `ScrollBarHider` 探针(macOS 13 的 AppKit List 吃不到该 modifier,且 SwiftUI 会在 layout 里把 `hasVerticalScroller` 拨回 true;探针 KVO 钉死底层 scroller);DEBUG `-wick-journal-detail-only` 专注态启动 |
| `JournalItemEditorCard.swift` / `JournalImagePreviewOverlay.swift` | 条目行(纸面墨迹,无卡片壳)+ 复盘位(未复盘为朱砂「复盘」按钮位、独占一行;已复盘白文方章 `.overlay(bottomTrailing)` 浮于内容上,0.3s 落印动效;复盘选择走系统 popover,批注未判定时先存草稿;批注行 = 朱砂左边线引文;标签/正文输入纸面字体 `WickPrintFont.songti`);图片缩略图双击/右键/悬停打开 `JournalImagePreviewOverlay` 秉烛风格浮层 Lightbox 大图预览(支持缩放/双击切换/键盘左右切换/拷贝/在系统「预览」中打开) |
| `JournalReviewBadge.swift` / `BurnStripView.swift` / `PaperChrome.swift` / `TagChipFlow.swift` / `TableViewSelectionSuppressor.swift` / `JournalPnlCalendarView.swift` / `JournalDatePickerView.swift` | 白文方章(中英文统一 `✓/✗`;`✓`=涨色、`✗`=跌色,跟随 `pnlColorConvention` 红涨绿跌或绿涨红跌;残边+蘸印深浅,`SealBodyShape`);烛痕条(暖渍+烛苗,刻度参数化,**形变只作用剪影层**);纸质外壳件(撕边/胶带/刻印小方钮 `InkIconButton`——常态无框融入纸面,hover 才浮 1pt 烛火线+起光/烛印方砖);标签签条(纸面朱砂方角);NSTableView 高亮抑制;盈亏月历(红盈 `pnlUp`/黛亏 `pnlDown`/有日记无仓位烛痕渍 `stain1`,软填充 ≈14%,**周一开头**、星期头随 App语言,‹ › 翻月、「已实现合计」行、今日烛火描边、点选跳当天);**秉烛风格日期选择器**(`JournalDatePickerView`,无系统蓝框/纸面年月/周一开头/烛火选中与今日描边/返回今日) |
| `TradingCalendarWindowController.swift` | **彩蛋**:贴桌物理黄历(无边框透明、pad 区外点击穿透),默认关闭,设置 →「交易日历」开启(`wick.calendar.physicalEasterEgg`);开启后主窗无检查器、盈亏月历移至导航栏顶部、顶栏右钮变为召唤/收起。撕页物理与键盘/滚轮监听不变 |
| `FallingPageOverlay.swift` | macOS 碎页叠加窗（飘落出屏幕；iOS 由 App 全屏遮罩承载同一 `FallingPageView`） |
| `JournalWindowController.swift` | 手动持有日记 `NSWindow` + 激活策略切换：<br>· **空原生 unified toolbar + top titlebar accessory**:toolbar 只负责建立跨 macOS 13/26 一致的标题栏几何，不放任何 item；`JournalTopBarView` 由 `NSTitlebarAccessoryViewController(.top)` 承载，红绿灯由 AppKit 管理，勿设 `hosting.safeAreaRegions = []`、勿读取或改写 `standardWindowButton` frame。窗口保留 `.fullSizeContentView` 与透明标题栏，在原生 frame view 最底层放一块 `palette.cardTop` 背景，作为红绿灯区和 accessory 区唯一的 Wick 主题底色；该 AppKit 背景必须通过 `viewDidChangeEffectiveAppearance` 跟随系统自动亮暗切换，并按 `window.effectiveAppearance` 取色，不能只监听 UserDefaults。accessory 背景必须透明，勿单独画不透明色、渐变或 `NSVisualEffectView`，否则会出现材质接缝。hosting view 必须包一层普通 `NSView` 容器、不能直接做 window 的 contentView——`NSHostingView.windowDidLayout → updateAnimatedWindowSize` 只对窗口直接 contentView 生效,而编辑区 ScrollView 理想高 = 全时间线展开,会让窗口每次布局长一格直至撑满屏幕可见高(`sizingOptions = []` 拦不住,实测)<br>· **窗口最小宽 = 可见栏位当前宽度之和 + 编辑页地板 440 + 检查器**(`requiredMinWidth`,随栏宽落盘/开关重算;440 地板打在编辑页自身而非「编辑页+检查器」组合上),且 `windowDidResize` 兜底强拉——程序化 setFrame(autosave 恢复、content-size 跟踪)**不吃 minSize**<br>· 首启无 autosave 存档按屏幕可见区给横版默认尺寸(`defaultContentSize`,宽度瞄准编辑页舒适宽 640),有存档恢复位置尺寸并做离屏救援(`isMostlyOnScreen`);DEBUG 裸二进制的 UserDefaults 落在 `Wick` domain(与打包的 com.miaoz.wick 互不相通) |
| `MenuBarExtraPanel.swift` | 启发式关闭 MenuBarExtra 面板；**尺寸护栏**：高 ≤30 / 宽 ≤60 的小窗一律不碰（误关状态栏宿主小窗会让图标永久消失） |
| `MenuBarExtraContentHost.swift` | macOS 13 `MenuBarExtra` `.window` 宿主：离屏量本征尺寸、等面板窗口就绪后再装入自有 `NSHostingView`，避免系统占位 frame 把 Text 原点钉死；高度变化（进设置）必须回写成 SwiftUI `.frame`，`invalidateIntrinsicContentSize` 推不动 MenuBarExtra |
| `IMESafeTextViews.swift` | AppKit 文本输入封装，IME 组字期间不被外部写值吞字；多行编辑 `IMESafeTextEditor` 实现 `sizeThatFits` 按内容行数自适应高度，不写死固定高度；剪贴板含图片时交 `onPasteImage`；默认字体走 `AppFont.paperNSFont` |
| `JournalImageProcessing.swift` / `MenuBarIcon.swift` | 图片导入（≤2048px，无 alpha → JPEG(0.82)）；代码绘制蜡烛模板图标（只创建一次） |
| `AppSettings.swift` | 设置单例：`@Published` + `didSet` 写 `UserDefaults`（`wick.` 前缀），`init` 用 `isLoading` 抑制加载期副作用；`journalFontName` 存所选字体 PostScript 名（空 = 默认），旧 `wick.journal.fontStyle`（default/classicalMing 枚举）init 一次性迁移 |
| `SyncCoordinator.swift` | 同步生命周期单例：防抖/切本/失活触发、连接断开、远端日记本自动导入与**删除传播**（队列存设备级 `device.json`）、导入前必须 `resetSyncState`、退出前一次限时最终同步；设置页冲突对比弹层见 `SyncConflictResolutionView.swift` |
| `ExchangePositionCoordinator.swift` | 交易所仓位单例：按日记本绑定（一本一所）；打包走 Keychain 一条 JSON（`com.miaoz.wick.exchange`），`swift run` 走 `dev-secrets.json`；快照 `Wick/Trading/<journalID>.json`（原始 `fills` 是真源，读取本地/云端缓存时重建派生 `positions`）；为 `JournalLocalSource` 提供无凭据的云端快照桥接与 HL 地址脱敏；切本加载；30 分钟定时；`PositionEntryPlanner` 补齐开仓日缺失的匹配条目；仓位挂载/补条目按 `entry.date` 计算显示日；已实现盈亏按聚合仓位 `openTime` 归入开仓日（不按平仓 fill 日期） |
| `ExchangeSettingsContent.swift` / `JournalExchangePositions.swift` | 设置页「交易所」区块;条目卡片内仓位 = 撕边胶带「交易所单据」(`ReceiptShape` + `TapeStrip`,等宽数字,红盈黛亏为物理纸上的印刷常量;无命中整块隐藏) |
| `DropboxAuthSession.swift` | `ASWebAuthenticationSession` 包装；回调 scheme 只在打包 `.app` 内注册（`swift run` 收不到回调） |
| `LaunchAtLogin.swift` / `UpdateChecker.swift` / `AppInfo.swift` / `AppNotifications.swift` / `Exports.swift` / `JournalReminderScheduler.swift` | 小工具集：登录项 / 检查更新 / 版本比较 / 共享通知名 / `@_exported` / 每日通知（含包形态门控） |

### `Sources/WickCalendarKit/`

| 文件 | 职责 |
| --- | --- |
| `MacroCalendarModels.swift` | `MacroCalendarEvent` + 解码器（镜像 akshare：`revised`→`previous`、空/非数值→`nil`、**按 时间+国家+标题 去重**、`calendar_key` 为空时 id 回退到数字 id——空 id 会被 SwiftUI 当重复身份重复渲染）；`EarningsReport` + `EarningsCallTime`（BMO 盘前/AMC 盘后/unspecified）+ 财报列式解码器（`data.fields` 列名 + `data.items` 行数组按列 zip，feed 的 0 → `nil`） |
| `MacroCalendarClient.swift` | 宏观：`api-one-wscn.awtmt.com/apiv1/finance/macrodatas`（`end` 为包含式会漏入次日零点事件 → 解码后按 `[start, end)` 过滤）。财报：**另一台主机** `api-ddc-wscn.awtmt.com`（**无 `/apiv1` 前缀**）`finance/report/list`（`country=US,HK,CN`，每请求硬上限 20 条、分页参数无效）。新股/活动端点（主站 `ipodatas`/`meetings`）**恒空已弃用**——其内容已并入宏观 feed 的 `calendar_type=FE` 条目（打新/发布会/讲话/财报电话会；`FD`=数据发布） |
| `MacroCalendarStore.swift` | 按日取数单例：宏观/财报两路独立取数与错误态（`isLoading` 两路落地才清除）；磁盘缓存 `<dayKey>.json` + `<dayKey>.earnings.json`（离线可读、失败不覆盖、读缓存重建旧版空 id）；`MacroCalendarFormat` 事件时间（Asia/Shanghai） |
| `MacroDayPageView.swift` | 黄历页本体（快照成纹理供撕纸变形）：报头/大日期/竖排星期列/农历行 + **固定栏目双 tab**（宏观事件/财报 chip，激活实心、未激活描边——纹理是静态的，切换靠 pad 级输入）；栏高撑满、翻页不串版、按 `MacroEventPaging` 分页（栏底「另有 N 项 ›」/「‹ 回到首页」，首版附提示小字）；桌面按事件数分档密度、满屏按名义行带反推字号；财报行为盘前盘后标记 + 国家 + 代码 + 公司名 + EPS 预期/今值（无星级）；两栏共用 `pageSlice`/`paneMetrics`/`rowChrome`/`overflowFooter`；闲日红色方印章（周末「休市」/工作日「本日无事」） |
| `TradingCalendarRootView.swift` | 撕页根视图，平台无关（`init(language:onClose:onPageTorn:layout:)`）：裂纹模型、纹理快照随日期/数据/版号/栏目重刷、轻点栏目行切 tab、轻点行区翻页（位移 <8pt）、撕页经 `onPageTorn` 交宿主（碎页携带当日两栏数据 + 版号 + 栏目） |
| `TradingCalendarTheme.swift` | 配色(秉烛:烟墨 #2B2118 + 朱砂 #C03A22 双色印刷,不再临摹 himekuri 绿墨)/ 字体(`fontStyle`:`default` = Hiragino/系统,`.custom(postScriptName:)` = 宿主所选已安装字体,`kanji`/`mincho`/`numeral`/`control` 都走它) + `TradingCalendarGeometry` + `PaperLayout`(桌面/iPhone 满屏参数化) |
| `PaperSim.swift` / `CalendarPaperScene.swift` / `PaperTear.swift` / `SeededRandom.swift` / `FallPlan.swift` | verlet 布料物理 / SKScene warp 变形 / 撕口几何 / 确定性 RNG / 飘落轨迹数值 |
| `FallingPage.swift` | 碎页结构与飞行动画视图（`FallPlan` 手工 Catmull-Rom）；macOS 叠加窗在 WickCore `FallingPageOverlay` |
| `LunarDate.swift` / `TearSound.swift` / `Haptics.swift` / `CalendarCursor.swift` / `WindowDrag.swift` / `CalendarNotifications.swift` | 农历+干支生肖（1900–2100 月长表）/ 合成纸声（AVAudioEngine）/ 触觉 / 光标 / 拖窗 shim（iOS no-op）/ 翻页与切栏通知 |

### `Sources/WickSync/`

| 文件 | 职责 |
| --- | --- |
| `JournalModels.swift` / `JournalDayKey.swift` | 日记模型（`JournalEntry.id` UUID 是唯一稳定身份；`date` 可任意修改并可创建过去日记）；`JournalDayKey` 只把日期格式化为 `yyyy-MM-dd`，用于显示、分组与交易归日，绝不持久化或参与同步身份 |
| `L10n.swift` / `TimeProgress.swift` | 双语文案目录（`L10n.string(.key, language:)`）；日/周/月/年剩余比例纯计算 |
| `JournalSyncEncoding.swift` | 规范 JSON（sortedKeys）+ SHA-256。**本地规范哈希绝不与 Dropbox `content_hash` 比较**（4MB 分块再哈希，两算法永不相等）；远端变更一律只比 rev |
| `JournalLocalSource.swift` / `JournalSyncBackend.swift` | 引擎↔本地存储协议；后端协议（listChanges/download/upload rev 条件写/delete） |
| `DropboxSyncBackend.swift` + `PKCE.swift` + `KeychainTokenStore.swift` | Dropbox API v2（PKCE offline、单飞刷新、409/429/401 分类）；Keychain 读写 service+account 参数化（Dropbox 与 Binance 共用；无 access group，签名身份变化可能丢 token——本机打包已用稳定身份 `Wick Local`，`swift build` 的 ad-hoc 二进制仍是另一身份） |
| `JournalDayMerge.swift` | 同 UUID 合并：条目按 item UUID 并集、同条目新 `updatedAt` 胜（败者入 `losingItems`），较新的版本决定可编辑 `date` |
| `JournalSyncState.swift` | v2 远端布局 `/journals/<journalUUID>/{manifest,entries,images,entry-tombstones,conflicts,settlements}` + `/journal-tombstones-v2/<uuid>.json`；`entries/<entryUUID>.json` 与墓碑均按永久 UUID 命名；每设备状态（cursor、远端 rev 视图、`EntrySyncState`（`pushedHashes` 自合并保护、`EntrySettlement` 待决）、冲突清理队列、`manifestName` 基线）；状态文件为 `<journal>-v2.json` / `device-v2.json`，旧 day-key 状态不读取 |
| `JournalSyncEngine.swift` | 对账引擎（`@MainActor`）。三条不变量：**①rev 回声抑制**（只比 rev）；**②拉取即固定点**（基线 = 下载字节本地重算哈希）；**③绝不和自己冲突**（`pushedHashes` 命中直接重推，不归档不弹冲突）。另有新鲜度守卫（快照后又编辑的天本轮跳过）、**切本隔离**（周期开始即冻结 journalID/名字/天快照；落盘/改名必须带 journalID，对不上当前活跃本则 no-op，否则一本的远端日子会灌进刚打开的另一本）、日记本删除传播（墓碑存在期间持续权威，旧客户端在墓碑旁回传日文件仍会被清掉；真实本地编辑可清墓碑恢复；30 天 GC）、冲突三版记录 + 结算标记跨端自动收敛、远端文件无墓碑消失自动回传（绝不镜像删除）；60s 周期 + 15s 防抖 + `syncOnce()` + `resetSyncState()` |

其他目录：`assets/`（图标，iconset 为中间产物）、`ios/`（iPhone 客户端 v0，仅中文 UI：手写 xcodeproj 用文件系统同步组、`Info.plist` 在 `ios/` 根而非同步组内；链接 `WickSync`+`WickCalendarKit`；`CalendarView` 满屏承载 kit 根视图并构造 `PaperLayout.fullScreen`；DEBUG 启动参数 `-wick-open-calendar` 直接弹日历便于截图；CLI 校验走 **scheme**：`xcodebuild -project ios/WickPhone.xcodeproj -scheme WickPhone -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO`（**勿用** `-target WickPhone`，App target 无法解析 `WickCalendarKit`/`WickSync`）；iOS Store 回归测试 target 为 `WickPhoneTests`，模拟器命令：`xcodebuild test -project ios/WickPhone.xcodeproj -scheme WickPhone -destination 'platform=iOS Simulator,id=<device-id>' CODE_SIGNING_ALLOWED=NO`、`scripts/`（`package_app.sh`/`package_zip.sh`/图标生成）、`landing/`（官网落地页，静态站：`index.html`+`app.js`+`style.css`+`assets/`，中文只存 HTML 一份、`app.js` 的 `I18N_EN` 只放英文、启动时从 DOM 捕获中文；截图素材为模拟器 3x / 虚拟 2x 屏直出；**宋体印刷字 = 自托管子集 `assets/fonts/wick-print.woff2`**（Noto Serif SC 可变字重 200–900、改名 Wick Print、OFL 见同目录 `OFL.txt`，`--f-print` 栈置顶，`index.html` preload）——**iOS 无预装中文宋体**（Songti SC 是按需下载资产），不自带字体必混字（日文明朝缺简体特有字，图/载/烛等会掉回退）；**改落地页文案后必须跑 `scripts/subset_landing_font.sh` 重新子集化**（字符集 = index.html+app.js 全集，缓存在 `.build/landing-font/`）；`_d_meta.json` 是设计工具元数据，`.assetsignore` 拦截不上传；Cloudflare Pages 项目 `wick` → <https://wick-ccc.pages.dev>，根 `wrangler.toml` 的 `pages_build_output_dir` 指向它，本地部署 `npx wrangler pages deploy landing --project-name=wick`，凭据在根 `.env`[已 gitignore]）、`.github/workflows/`（`release.yml` 应用发布、`landing.yml` 落地页部署：`landing/**` 变更推 main 即自动部署，用仓库 secrets `CLOUDFLARE_API_TOKEN`/`CLOUDFLARE_ACCOUNT_ID`）、`dist/`（产物，已 gitignore）。

## 构建与测试

```bash
swift build && swift run   # 开发（仅宿主架构；非 .app 形态下本地通知被跳过）
swift test                 # 单元测试（CI 打包前执行）
xcodebuild test -project ios/WickPhone.xcodeproj -scheme WickPhone -destination 'platform=iOS Simulator,id=<device-id>' CODE_SIGNING_ALLOWED=NO  # iOS Store 回归
make                       # 正式打包：arm64+x86_64 lipo 成 Universal → dist/Wick.app
make package               # 可分发 zip → dist/Wick-macOS[-<VERSION>].zip
VERSION=1.10.16 BUILD=55 ./scripts/package_zip.sh   # 注入版本号
make icon                  # 代码重绘图标
make clean                 # rm -rf .build dist
```

- CI（release.yml）：macos-26 + Xcode 26.6 → `swift test` → 打包 → 仅 tag `v*` 建 GitHub Release（正文由 git log 自动生成：自上一 tag 的改动清单 + 安装说明，**只留最新 10 个**，不删 git tag）+ **自动上传包到 Cloudflare R2 桶 `application-releases/wick/`**（`Wick-macOS-${VERSION}.zip` 与最新别名 `Wick.zip`，公网直链 `https://dl.bitfroth.com/wick/Wick.zip`，由 `landing/` 下载按钮直接引用；本地手动上传可用 `./scripts/upload_r2.sh`）。
- 测试落点：纯计算进可注入 `Date`/`Calendar` 的静态方法（`TimeProgressCalculator`/`DayArcEngine`/`PaperSim` 等）；存储行为进 `JournalStoreTests`；同步分支一律用 `WickSyncTests` 的假后端复现（假后端忠实模拟 Dropbox：分块哈希、增量回声——**不碰网络**）；UI 层无测试。

## 代码约定

- 面向用户的文档（README 等）用简体中文；**代码注释、commit message 用英文**。
- 当前为单用户开发阶段：对交易快照等可从源头重建的派生数据，schema 变化默认硬切并重建，**不保留旧字段、旧路径或一次性迁移分支**；日记正文、图片与 Dropbox 同步状态仍遵守数据安全约束。
- 4 空格缩进、`// MARK: -` 分节、一个文件一个主类型；无 SwiftLint/格式化配置，遵循周边既有风格。
- UI 文案一律走 `L10n`（加 case + 中英双实现，不硬编码）；设置项一律进 `AppSettings`（`wick.` 前缀键）；全局单例经 `.environmentObject` 注入。
- 触及 UI/AppKit 的类型标 `@MainActor`（Swift 6 严格并发检查）；平台能力封装为小工具类型（`LaunchAtLogin`、`UpdateChecker` 等），别把 AppKit 细节散进视图。
- **颜色一律走主题引擎**（`DayArcEngine` / `\.wickPalette`），禁硬编码；改锚点色板后必须跑 `WickThemeTests` 的对比度护栏。
- **字体一律走 `AppFont`**（`paper`/`ui`/`preset`/`paperNSFont`，WickCore）与 `TradingCalendarTheme.fontStyle`（日历）；禁硬编码 `Songti SC` / `.system(...)` / `.caption` 等——设置里的「字体风格」选的设备字体会全局替换，绕过即漏换。

## 注意事项（安全与数据保护）

- **日记数据安全是核心约束**：多日记布局 `Wick/Journals/catalog.json` + `<uuid>/{journal.json,.bak,backups/,images/}`；加载失败进 `isReadOnlyDueToLoadFailure` 且**禁止任何写盘**（坏文件移存 `journal.corrupt-<ts>.json`）；覆盖前先写 `.bak`（滚动备份 ≤5 份、间隔 ≥30 分钟）；退出/关日记窗/切换日记本前发 `wickWillFlushJournalDrafts` 并 `flushPendingWrites()`。**catalog 保护 ≥ journal.json**：`catalog.json` 也有 `catalog.json.bak` 与版本门（`JournalCatalogCodec.decode`，macOS/iOS 共享）；只有显式 `.missing` 才 `seedDefaultJournal()`；损坏/未来版本/空库进 `isCatalogReadOnly`，禁用新建/重命名/重排/删除/绑定写入（`CatalogLoadResult`）。
- **图片路径唯一规则来源 `WickSync.JournalImageFilename`**：`JournalItem` 解码即校验非法引用（含 `/`、`\`、`.`、`..`、NUL、规范化漂移者整体拒绝，不做清洗）；macOS/iOS Store 的 `imageURL(for:)` 是**唯一**图片 URL 构造器（返回可选，再做 `standardizedFileURL` 落在 `imagesDirectory` 内的第二道边界）；所有读/缩略图/删除/同步上传下载都经它。
- **UserNotifications 只在正式 `.app` 包内可用**（`swift run`/裸二进制下调用会 abort）；`JournalReminderScheduler.notificationsAvailable` 的包形态门控必须维持。
- **Dropbox 同步**：回调 scheme `db-hm5yscsy9a11g0q` 只在打包 `.app` 内注册；**App secret 永不入仓库/二进制**（PKCE 公共客户端只需 App key）；同步仅针对当前活跃日记本；只读/版本门命中时引擎一律只读拒写。**删除日记本 = 全端删除**（本地删除上传墓碑 + 清远端文件夹，所有设备同步删除；无「仅本机移除」选项）。远端删除走 Store 专用事务 `deleteJournalFromRemote(id:) -> RemoteJournalDeleteResult`（**最后一本也删除**并播种新 UUID 纯本地默认本，不继承绑定/同步状态）；Coordinator 只对 deleted/notFound 调 `acknowledgeRemoteJournalDeletion`，ioFailure/refusedReadOnly 保留墓碑下轮重试。
- **同步批量提交（PF-01）**：引擎把一轮的远端变更收集为 `[JournalSyncMutation]`，UUID 对账阶段结束后一次 `applySyncedChanges`（一次 persist/catalog touch/selection reconcile/UI publish），再跑图片对账；失败条目不进 batch、保留 first-error 语义。**草稿协调（ED-01）**：引擎在下发前先 `prepareForRemoteApply(entryID:)` 触发编辑器 flush，freshness guard 在 flush 后重读哈希，草稿改动则该轮跳过、下轮正常合并；成功 apply 后发 `JournalRemoteApply` typed event，编辑器仅对**干净** draft 做 rebase（dirty 由数据表示，不用 `saveTasks.keys` 近似）。
- **UUID 硬切（sync v2）**：`JournalSnapshot` v2 启动时把所有 v1 `journal.json` 原子迁移并保留原文件为 `.bak`；旧 `dayKey` 解码后不再编码。发现远端 manifest v1 时，当前设备先将 manifest 升为 v2 以阻止旧客户端写入，再删除旧 `days/tombstones/conflicts/settlements`，并以本机 UUID 条目重建远端。旧设备必须清除应用数据后再安装 v2。
- **`MenuBarExtra` 的 label 禁止放 `TimelineView` 或 Combine `Timer` publisher 等高频/宿主外存活的失效源**（前者会触发 `requestUpdate`→`setImage` 死循环占满 CPU，后者在 macOS 26 label host 释放后继续投递会崩溃）；当前 label 用随视图取消的 30s `.task`，且仅文本变化时更新。
- **macOS 13（Ventura）下 `MenuBarExtra` `.window` 内容首版布局会拿到错误几何**：系统 `NSHostingView` 先对着占位 frame 排 SwiftUI，面板再按 fitting size 收缩，`Text` 原点留在第一次的错位上（曾表现为每秒漂移；`.id` 翻转能修好但用户会看到一跳）。13.x 因此走 `MenuBarExtraContentHost`：先离屏量出本征尺寸让面板以正确大小出现，再把真正的 SwiftUI 树装进**我们自己的** `NSHostingView`（不是 window 的直接 contentView），文字的第一次布局就是对的。高度变化（进度→设置）不能靠 `invalidateIntrinsicContentSize`（MenuBarExtra 不听），要按无约束 `sizeThatFits` 回写 SwiftUI `.frame`。macOS 14+ 仍直接放 `ProgressPanelView`。**面板根部禁止挂隐式 `.animation(value:)`**（根部每秒随 TimelineView 重渲染，Ventura 会把这些事务卷进动画），动画一律在状态变更点显式 `withAnimation`。
- 日记编辑必须用 `IMESafeTextViews`，原生 SwiftUI `TextField` 在中文 IME 下吞字。
- macOS 13 下空 `NSToolbar(.unified)` 仅用于建立系统标题栏几何，不放 SwiftUI item；栏位折叠走 `JournalTopBarView` 的三态循环(⌃⌘S);勿用自研 binding 桥或 `sidebarTrackingSeparator`。
- **macOS 26 会给 toolbar item(Menu/Button/NSViewRepresentable)强制套玻璃胶囊**——日记窗使用空的 unified toolbar，不向 toolbar 放 item；全部窗口控件放入 `JournalTopBarView` 的 native top titlebar accessory，左边距由 AppKit accessory 可见区域管理，勿把自定义控件搬回 toolbar item。
- 网络面很小：`api.github.com`（更新，15s）、`api-one-wscn.awtmt.com` + `api-ddc-wscn.awtmt.com`（日历，keyless，15s，失败走缓存/空态）、`fapi.binance.com` / `www.okx.com` / `api.hyperliquid.xyz`（仓位只读，20s）；无遥测、无账号体系。
- 许可：仓库暂无 `LICENSE`，README 声明保留版权，新增第三方代码前需与维护者确认。
