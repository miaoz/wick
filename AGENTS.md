# AGENTS.md

> 面向 AI 编码代理：Wick 的架构、构建、测试与约定。本文只保留「看代码不易发现」的约束与坑；改动代码前先核对相关源文件。

## 项目概览

- **Wick**：原生 macOS 菜单栏应用（`LSUIElement`，无 Dock 图标）。蜡烛图标弹出面板，实时展示 日/周/月/年 剩余百分比与结束时间（每秒刷新）。
- **日记**：一天一篇、篇内多条目（标签+正文+图片），条目级检索、每日本地通知提醒、zip 导入导出。
- **Dropbox 同步**（可选）：本地为唯一真源，`WickSync` 引擎按「天」双向对账（OAuth PKCE，客户端无 App secret）；删除靠墓碑传播、冲突按条目并集合并并保留败者、远端文件意外消失自动回传。
- **交易所仓位**（可选，一本日记一个账号）：Binance USDⓈ-M / OKX SWAP / Hyperliquid 永续。凭据按日记本存（打包 `.app` 走 Keychain 一条 JSON；`swift run` 走 `Application Support/Wick/dev-secrets.json` 以免每次重编译弹密码）。`WickTrading` 直连各所 REST 拉成交，归一成 `TradingFill`；窗口下界为该本最早日记日（无日记回退近 180 天；OKX 所侧约 3 个月、HL 约最近 1 万笔）。快照 `Wick/Trading/<journalID>.json` 增量刷新；`PositionAggregator` 聚合成开平仓会话（对冲双 lane、加仓 VWAP、翻仓拆两段、**净值 epsilon 吸附归零**）；按「开仓日 + 宽松标签」挂进卡片（`BTC` 匹配 `BTCUSDT` 与 HL 的 `BTC`）；缺日记时 `PositionEntryPlanner` 补建（**从不改写已有标签**；已处理 ID 随 snapshot，删掉的自动日记不复活）。HL 只填 0x 地址、不收私钥。
- **交易日历**：himekuri「黄历」撕页日历（无边框透明穿透窗、撕纸物理与程序合成音效），内容由 `WickCalendarKit` 直连华尔街见闻（宏观 + 财报，keyless REST，非 WebSocket、不打包 Python）。
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
| `ProgressPanelView.swift` | 菜单栏纸签与设置页:撕边纸签外壳(`TornSlipShape`)+ 今日大烛痕条 + 周/月/年细条(`BurnStripView`,刻度 24/7/当月天数/12);`PanelTheme` 薄结构体委托 `DayArcEngine`;设置页含「交易日历」区(彩蛋开关) |
| `WickTheme.swift` | 「秉烛」主题引擎(原一日弧光重构):`WickRGB`、`WickPalette`(宣纸/烟墨/烛火/朱砂/黛青/烛痕/单据纸/烛印方砖)、`DayPhase` 四锚点 × 亮暗插值,**火苗色跨时段恒定**(子夜不再变蓝);`WICK_ARC_TIME=HH:mm`(仅 DEBUG);`\.wickPalette` 环境键;纸面层级映射 `columnPaper`(栏面)/`editorCanvas`(编辑画布)/`pageSurface`(页纸)对应蓝本 paper/paper-hi/desk 混合,`WickPrintFont.songti` 供 AppKit 文本件用宋体。设计蓝本:`designs/wick-design-language/final.html` |
| `JournalStore.swift` | 多日记本存储单例：`catalog.json` + 每本独立目录；`.bak` + 滚动备份、版本门、加载失败只读保护、图片管理、zip 导入导出、旧版一次性迁移；文件尾部为 `JournalLocalSource` 同步桥接（远端文件名防穿越校验、改名撞名去重） |
| `JournalRootView.swift` / `JournalSidebarView.swift` / `JournalEditorPane.swift` | 秉烛主窗:**全宽顶栏**(红绿灯让位、三态循环钮 ⌃⌘S[全导航→仅列表→专注]、**静态日记名**(顶栏不挂日记本操作;切换 = 栏一点行,新建 = 栏一「日记本」节头右侧 + 钮,重命名/删除 = 日记本行右键菜单,删除仅限非最后一本,**日记本列表支持拖拽重排持久化**)+ 选中日小注、搜索、新建、右钮 ⌥⌘0;**顶栏高度由 `JournalRootView.topBarHeight` (48pt) 统一度量**,按钮/文字/搜索框在栏内垂直居中,红绿灯由 `JournalWindow` 对齐居中)+ **手动三栏**(导航 `JournalNavigationSidebar` / 日期列表 `JournalDayListColumn` / 编辑页;**不用 NavigationSplitView**——macOS 26 会把侧栏画成浮动圆角卡片,与平铺纸面冲突;栏间 `JournalColumnDivider` = 1pt 界线 + 7pt 命中区,拖拽调宽、拖到边缘/双击收栏,栏宽落 `wick.journal.navWidth/listWidth`,**拖拽上限实时反推编辑页地板**(`navWidthCeiling/listWidthCeiling`,拖栏不再把编辑页挤变形);**栏一文字左缘固定 x=10,与首颗红绿灯左缘(x≈9)对齐**(v4 同此关系,行 pill 留 4pt 外边距);标签签条走 `SidebarChipFlow`(自研 Layout 贪心换行+超长截断,**勿用 LazyVGrid adaptive**——等宽列会让长签溢出、拖栏时与邻签重叠))+ 栏四检查器 `JournalInspectorView`(今日事件 + 盈亏月历,仅彩蛋关时在;**盈亏收合 → 事件栏全量滚动撑满整栏**,事件常有数十项;宏观标题默认最多两行、财报代码 `fixedSize` 单行不折、**条目点击展开全文/再次点击收起**);栏位状态持久化(`journalColumnMode`);**编辑页 = 一天一页纸**(`pageSurface` 纸页 + 衬线大日期页眉[点开改日]+ 星期/农历小注 + 当日已实现盈亏 + 页内细烛痕条——过去的天然燃尽、今日带「已过 N%」小字),条目沿发丝线排列、无卡片壳,编辑栏有 440pt 宽度地板(`editorMinWidth`,页眉排不下时走 `ViewThatFits` 两行版[盈亏/保存注挪下行],部件全 fixedSize、绝不逐字竖排;`editorComfortWidth` 640 = 单行页眉舒适宽,仅供首启默认尺寸);**日期列表按月分节**(「八月 2026」节头),行 = 日期+周几 / 条数·平仓数 / 等宽盈亏+复盘小章,选中 = 页纸高亮 + 左缘 3pt 朱砂界,List 必须 `.scrollContentBackground(.hidden)` 否则侧栏 vibrancy 把纸色变灰;滚动条隐藏走 `.scrollIndicators(.never)`(macOS 上 `.hidden` 接鼠标/系统「始终显示滚动条」仍会露条)+ `ScrollBarHider` 探针(macOS 13 的 AppKit List 根本吃不到该 modifier,且 SwiftUI 会在 layout 里把 `hasVerticalScroller` 拨回 true;探针 KVO 钉死底层 scroller,滚动功能不受影响);DEBUG `-wick-journal-detail-only` 专注态启动 |
| `JournalItemEditorCard.swift` | 条目行(纸面墨迹,无卡片壳)+ 复盘位(未复盘为朱砂虚线章位、独占一行;已复盘白文方章 `.overlay(bottomTrailing)` 浮于内容上,0.3s 落印动效;复盘选择走系统 popover,批注未判定时先存草稿;批注行 = 朱砂左边线引文;标签/正文输入宋体 `WickPrintFont.songti`) |
| `JournalReviewBadge.swift` / `BurnStripView.swift` / `PaperChrome.swift` / `TagChipFlow.swift` / `TableViewSelectionSuppressor.swift` / `JournalPnlCalendarView.swift` | 朱砂白文方章(对/错同色靠字表意,残边+蘸印深浅,`SealBodyShape`);烛痕条(暖渍+烛苗,刻度参数化,**形变只作用剪影层**);纸质外壳件(撕边/胶带/刻印小方钮 `InkIconButton`——常态无框融入纸面,hover 才浮 1pt 烛火线+起光/烛印方砖);标签签条(宋体朱砂方角);NSTableView 高亮抑制;盈亏月历(红盈 `pnlUp`/黛亏 `pnlDown`/有日记无仓位烛痕渍 `stain1`,软填充 ≈14%,**周一开头**、星期头随 App语言,‹ › 翻月、「已实现合计」行、今日烛火描边、点选跳当天) |
| `TradingCalendarWindowController.swift` | **彩蛋**:贴桌物理黄历(无边框透明、pad 区外点击穿透),默认关闭,设置 →「交易日历」开启(`wick.calendar.physicalEasterEgg`);开启后主窗无检查器、盈亏月历移至导航栏顶部、顶栏右钮变为召唤/收起。撕页物理与键盘/滚轮监听不变 |
| `FallingPageOverlay.swift` | macOS 碎页叠加窗（飘落出屏幕；iOS 由 App 全屏遮罩承载同一 `FallingPageView`） |
| `JournalWindowController.swift` | 手动持有日记 `NSWindow`(`JournalWindow` 自定义窗口类,布局时将原生红绿灯与 `JournalRootView.topBarHeight` 垂直居中对齐) + 激活策略切换；**全版本无 toolbar**(KVO 钉住 `window.toolbar` = nil)——窗口控件全部在全宽顶栏(`JournalRootView.topBar`),栏位折叠走三态循环(`journalColumnMode`);`hosting.safeAreaRegions = []`(13.3+)让顶栏与红绿灯同一行,否则 SwiftUI 安全区会把顶栏挤到红绿灯下面;**hosting view 必须包一层普通 `NSView` 容器、不能直接做 window 的 contentView**——`NSHostingView.windowDidLayout → updateAnimatedWindowSize` 只对窗口直接 contentView 生效,而编辑区 ScrollView 理想高 = 全时间线展开,会让窗口每次布局长一格直至撑满屏幕可见高(`sizingOptions = []` 拦不住,实测);**窗口最小宽 = 可见栏位当前宽度之和 + 编辑页地板 440 + 检查器**(`requiredMinWidth`,随栏宽落盘/开关重算;440 地板打在编辑页自身而非「编辑页+检查器」组合上),且 `windowDidResize` 兜底强拉——程序化 setFrame(autosave 恢复、content-size 跟踪)**不吃 minSize**;首启无 autosave 存档按屏幕可见区给横版默认尺寸(`defaultContentSize`,宽度瞄准编辑页舒适宽 640),有存档恢复位置尺寸并做离屏救援(`isMostlyOnScreen`);DEBUG 裸二进制的 UserDefaults 落在 `Wick` domain(与打包的 com.miaoz.wick 互不相通) |
| `MenuBarExtraPanel.swift` | 启发式关闭 MenuBarExtra 面板；**尺寸护栏**：高 ≤30 / 宽 ≤60 的小窗一律不碰（误关状态栏宿主小窗会让图标永久消失） |
| `MenuBarExtraContentHost.swift` | macOS 13 `MenuBarExtra` `.window` 宿主：离屏量本征尺寸、等面板窗口就绪后再装入自有 `NSHostingView`，避免系统占位 frame 把 Text 原点钉死；高度变化（进设置）必须回写成 SwiftUI `.frame`，`invalidateIntrinsicContentSize` 推不动 MenuBarExtra |
| `IMESafeTextViews.swift` | AppKit 文本输入封装，IME 组字期间不被外部写值吞字；剪贴板含图片时交 `onPasteImage` |
| `JournalImageProcessing.swift` / `MenuBarIcon.swift` | 图片导入（≤2048px，无 alpha → JPEG(0.82)）；代码绘制蜡烛模板图标（只创建一次） |
| `AppSettings.swift` | 设置单例：`@Published` + `didSet` 写 `UserDefaults`（`wick.` 前缀），`init` 用 `isLoading` 抑制加载期副作用 |
| `SyncCoordinator.swift` | 同步生命周期单例：防抖/切本/失活触发、连接断开、远端日记本自动导入与**删除传播**（队列存设备级 `device.json`）、导入前必须 `resetSyncState`、退出前一次限时最终同步；设置页冲突对比弹层见 `SyncConflictResolutionView.swift` |
| `ExchangePositionCoordinator.swift` | 交易所仓位单例：按日记本绑定（一本一所）；打包走 Keychain 一条 JSON（`com.miaoz.wick.exchange`），`swift run` 走 `dev-secrets.json`；快照 `Wick/Trading/<journalID>.json`；切本加载；30 分钟定时；`PositionEntryPlanner` 补建开仓日条目 |
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
| `TradingCalendarTheme.swift` | 配色(**秉烛:烟墨 #2B2118 + 朱砂 #C03A22 双色印刷**,不再临摹 himekuri 绿墨)/ 字体 + `TradingCalendarGeometry` + `PaperLayout`(桌面/iPhone 满屏参数化) |
| `PaperSim.swift` / `CalendarPaperScene.swift` / `PaperTear.swift` / `SeededRandom.swift` / `FallPlan.swift` | verlet 布料物理 / SKScene warp 变形 / 撕口几何 / 确定性 RNG / 飘落轨迹数值 |
| `FallingPage.swift` | 碎页结构与飞行动画视图（`FallPlan` 手工 Catmull-Rom）；macOS 叠加窗在 WickCore `FallingPageOverlay` |
| `LunarDate.swift` / `TearSound.swift` / `Haptics.swift` / `CalendarCursor.swift` / `WindowDrag.swift` / `CalendarNotifications.swift` | 农历+干支生肖（1900–2100 月长表）/ 合成纸声（AVAudioEngine）/ 触觉 / 光标 / 拖窗 shim（iOS no-op）/ 翻页与切栏通知 |

### `Sources/WickSync/`

| 文件 | 职责 |
| --- | --- |
| `JournalModels.swift` / `JournalDayKey.swift` | 日记模型（`dayKey` 为按天稳定主键，创建后冻结、旧数据解码推导）；`yyyy-MM-dd` 日键 |
| `L10n.swift` / `TimeProgress.swift` | 双语文案目录（`L10n.string(.key, language:)`）；日/周/月/年剩余比例纯计算 |
| `JournalSyncEncoding.swift` | 规范 JSON（sortedKeys）+ SHA-256。**本地规范哈希绝不与 Dropbox `content_hash` 比较**（4MB 分块再哈希，两算法永不相等）；远端变更一律只比 rev |
| `JournalLocalSource.swift` / `JournalSyncBackend.swift` | 引擎↔本地存储协议；后端协议（listChanges/download/upload rev 条件写/delete） |
| `DropboxSyncBackend.swift` + `PKCE.swift` + `KeychainTokenStore.swift` | Dropbox API v2（PKCE offline、单飞刷新、409/429/401 分类）；Keychain 读写 service+account 参数化（Dropbox 与 Binance 共用；无 access group，签名身份变化可能丢 token——本机打包已用稳定身份 `Wick Local`，`swift build` 的 ad-hoc 二进制仍是另一身份） |
| `JournalDayMerge.swift` | 同日合并：条目按 UUID 并集、同条目新 `updatedAt` 胜（败者入 `losingItems`）、身份收敛到 `createdAt` 更早者 |
| `JournalSyncState.swift` | 远端布局 `/journals/<uuid>/{manifest,days,images,tombstones,conflicts,settlements}` + `/journal-tombstones/<uuid>.json`（日记本墓碑在文件夹外）；每设备状态（cursor、远端 rev 视图、`DaySyncState`（`pushedHashes` 自合并保护、`DaySettlement` 待决）、冲突清理队列、`manifestName` 基线；**自定义解码全字段带默认值**）；设备级 `device.json` 承载删除队列（日记本删除时其自身状态文件即被清除） |
| `JournalSyncEngine.swift` | 对账引擎（`@MainActor`）。三条不变量：**①rev 回声抑制**（只比 rev）；**②拉取即固定点**（基线 = 下载字节本地重算哈希）；**③绝不和自己冲突**（`pushedHashes` 命中直接重推，不归档不弹冲突）。另有新鲜度守卫（快照后又编辑的天本轮跳过）、**切本隔离**（周期开始即冻结 journalID/名字/天快照；落盘/改名必须带 journalID，对不上当前活跃本则 no-op，否则一本的远端日子会灌进刚打开的另一本）、日记本删除传播（周期最先 flush 墓碑 + 清文件夹、同伴墓碑确认重发、30 天 GC）、冲突三版记录 + 结算标记跨端自动收敛、远端文件无墓碑消失自动回传（绝不镜像删除）；60s 周期 + 15s 防抖 + `syncOnce()` + `resetSyncState()` |

其他目录：`assets/`（图标，iconset 为中间产物）、`ios/`（iPhone 客户端 v0，仅中文 UI：手写 xcodeproj 用文件系统同步组、`Info.plist` 在 `ios/` 根而非同步组内；链接 `WickSync`+`WickCalendarKit`；`CalendarView` 满屏承载 kit 根视图并构造 `PaperLayout.fullScreen`；DEBUG 启动参数 `-wick-open-calendar` 直接弹日历便于截图；CLI 校验 `xcodebuild -project ios/WickPhone.xcodeproj -target WickPhone build CODE_SIGNING_ALLOWED=NO`）、`scripts/`（`package_app.sh`/`package_zip.sh`/图标生成）、`.github/workflows/release.yml`（唯一 CI）、`dist/`（产物，已 gitignore）。

## 构建与测试

```bash
swift build && swift run   # 开发（仅宿主架构；非 .app 形态下本地通知被跳过）
swift test                 # 单元测试（CI 打包前执行）
make                       # 正式打包：arm64+x86_64 lipo 成 Universal → dist/Wick.app
make package               # 可分发 zip → dist/Wick-macOS[-<VERSION>].zip
VERSION=1.3.1 BUILD=6 ./scripts/package_zip.sh   # 注入版本号
make icon                  # 代码重绘图标
make clean                 # rm -rf .build dist
```

- 发布一律走 `make`（`swift build` 只产当前架构）；Info.plist 由脚本 heredoc 生成（`LSUIElement=true`）；`.app` **未公证**：本机存在 `Wick Local` 自签名身份时用它签（稳定身份，Keychain ACL 跨构建不失效），否则回退 ad-hoc（CI 即如此）；文档/脚本不得暗示已公证。
- CI（release.yml）：macos-26 + Xcode 26.6 → `swift test` → 打包 → 仅 tag `v*` 建 GitHub Release（**只留最新 3 个**，不删 git tag）。
- 测试落点：纯计算进可注入 `Date`/`Calendar` 的静态方法（`TimeProgressCalculator`/`DayArcEngine`/`PaperSim` 等）；存储行为进 `JournalStoreTests`；同步分支一律用 `WickSyncTests` 的假后端复现（假后端忠实模拟 Dropbox：分块哈希、增量回声——**不碰网络**）；UI 层无测试。

## 代码约定

- 面向用户的文档（README 等）用简体中文；**代码注释、commit message 用英文**。
- 4 空格缩进、`// MARK: -` 分节、一个文件一个主类型；无 SwiftLint/格式化配置，遵循周边既有风格。
- UI 文案一律走 `L10n`（加 case + 中英双实现，不硬编码）；设置项一律进 `AppSettings`（`wick.` 前缀键）；全局单例经 `.environmentObject` 注入。
- 触及 UI/AppKit 的类型标 `@MainActor`（Swift 6 严格并发检查）；平台能力封装为小工具类型（`LaunchAtLogin`、`UpdateChecker` 等），别把 AppKit 细节散进视图。
- **颜色一律走主题引擎**（`DayArcEngine` / `\.wickPalette`），禁硬编码；改锚点色板后必须跑 `WickThemeTests` 的对比度护栏。

## 注意事项（安全与数据保护）

- **日记数据安全是核心约束**：多日记布局 `Wick/Journals/catalog.json` + `<uuid>/{journal.json,.bak,backups/,images/}`；加载失败进 `isReadOnlyDueToLoadFailure` 且**禁止任何写盘**（坏文件移存 `journal.corrupt-<ts>.json`）；覆盖前先写 `.bak`（滚动备份 ≤5 份、间隔 ≥30 分钟）；退出/关日记窗/切换日记本前发 `wickWillFlushJournalDrafts` 并 `flushPendingWrites()`。
- **UserNotifications 只在正式 `.app` 包内可用**（`swift run`/裸二进制下调用会 abort）；`JournalReminderScheduler.notificationsAvailable` 的包形态门控必须维持。
- **Dropbox 同步**：回调 scheme `db-hm5yscsy9a11g0q` 只在打包 `.app` 内注册；**App secret 永不入仓库/二进制**（PKCE 公共客户端只需 App key）；同步仅针对当前活跃日记本；只读/版本门命中时引擎一律只读拒写。**删除日记本 = 全端删除**（本地删除上传墓碑 + 清远端文件夹，所有设备同步删除；无「仅本机移除」选项）。
- **`MenuBarExtra` 的 label 禁止放 `TimelineView` 等高频失效源**（会触发 `requestUpdate`→`setImage` 死循环占满 CPU；当前 label 用 30s `Timer` 且仅文本变化时更新）。
- **macOS 13（Ventura）下 `MenuBarExtra` `.window` 内容首版布局会拿到错误几何**：系统 `NSHostingView` 先对着占位 frame 排 SwiftUI，面板再按 fitting size 收缩，`Text` 原点留在第一次的错位上（曾表现为每秒漂移；`.id` 翻转能修好但用户会看到一跳）。13.x 因此走 `MenuBarExtraContentHost`：先离屏量出本征尺寸让面板以正确大小出现，再把真正的 SwiftUI 树装进**我们自己的** `NSHostingView`（不是 window 的直接 contentView），文字的第一次布局就是对的。高度变化（进度→设置）不能靠 `invalidateIntrinsicContentSize`（MenuBarExtra 不听），要按无约束 `sizeThatFits` 回写 SwiftUI `.frame`。macOS 14+ 仍直接放 `ProgressPanelView`。**面板根部禁止挂隐式 `.animation(value:)`**（根部每秒随 TimelineView 重渲染，Ventura 会把这些事务卷进动画），动画一律在状态变更点显式 `withAnimation`。
- 日记编辑必须用 `IMESafeTextViews`，原生 SwiftUI `TextField` 在中文 IME 下吞字。
- macOS 13 下手动 `NSWindow` + 隐藏标题栏不会安装任何工具栏——日记窗全版本不装 toolbar（见下条），栏位折叠走 `JournalRootView` 顶栏的三态循环(⌃⌘S);勿用自研 binding 桥或 `sidebarTrackingSeparator`。
- **macOS 26 会给工具栏里的一切 item(Menu/Button/NSViewRepresentable)强制套玻璃胶囊、且 `titleVisibility = .hidden` 不再隐藏窗口标题**——日记窗因此**全版本无 toolbar**(`JournalWindowController` 用 KVO 把 `window.toolbar` 钉住为 `nil`,SwiftUI 会在布局时重装上),全部窗口控件(三态循环钮/日记本菜单/搜索/新建/检查器)做成全宽内建顶栏(`JournalRootView.topBar`,左缘 78pt 避让红绿灯、垫 `windowDragBackground()` 供拖窗);勿把自定义控件搬回工具栏。
- 网络面很小：`api.github.com`（更新，15s）、`api-one-wscn.awtmt.com` + `api-ddc-wscn.awtmt.com`（日历，keyless，15s，失败走缓存/空态）、`fapi.binance.com` / `www.okx.com` / `api.hyperliquid.xyz`（仓位只读，20s）；无遥测、无账号体系。
- 许可：仓库暂无 `LICENSE`，README 声明保留版权，新增第三方代码前需与维护者确认。
