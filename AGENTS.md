# AGENTS.md

> 本文件面向 AI 编码代理，汇总 Wick 项目的架构、构建、测试与约定。信息均来自对仓库的实际阅读，改动代码前请先核对相关源文件。

## 项目概览

- **Wick** 是一款原生 macOS 菜单栏应用（`LSUIElement`，不显示 Dock 图标）。
- 菜单栏显示蜡烛模板图标，点击弹出面板，实时展示**日 / 周 / 月 / 年**的剩余百分比、剩余时长与结束时间（每秒刷新）。
- 内置**日记**功能：一天一篇日记，篇内多条目（标签 + 正文 + 图片），支持按标签/全文以条目粒度检索、每日本地通知提醒、zip 导出/导入。
- 可选 **Dropbox 同步**：本地存储始终是唯一真源，`WickSync` 模块的同步引擎按「天」与 Dropbox App folder 双向对账（OAuth PKCE，客户端不内置 App secret）；删除靠墓碑传播、同日冲突按条目并集合并并保留败者、远端文件意外消失自动回传。模型/引擎为纯 Foundation，为未来 iPhone 客户端设计。
- 其他能力：登录时启动（`SMAppService`）、亮/暗/跟随系统外观（配色由「一日弧光」主题引擎驱动）、中/英文界面、菜单栏百分比显示、基于 GitHub Releases 的检查更新。
- 内置 **交易日历**：进度面板书签按钮左侧的日历按钮打开「交易日历」窗口——himekuri（https://github.com/pluk-inc/himekuri）「黄历」主题的撕页日历（绿墨×米白纸、双线描边、大号日期、竖排星期填色列、装订/纸堆/撕痕），**无边框透明穿透窗口**（贴桌对象，pad 区外点击穿透），撕下时碎页在单独叠加窗里从 pad 飘落到**屏幕外**并伴**程序合成撕纸音效**；每一页显示该日全球宏观事件，由 akshare `macro_info_ws` 背后的（无密钥）华尔街见闻 REST 接口直连取数（Swift `URLSession`，非 WebSocket、不打包 Python）。
- **平台**：macOS 13+，Apple Silicon 与 Intel（正式打包产出 Universal 二进制）。
- **技术栈**：Swift 6.1+（`Package.swift` 声明 `swift-tools-version: 6.1`；主开发环境为 Xcode 26 / Swift 6.3）、SwiftUI + AppKit、Swift Package Manager。**无任何第三方依赖**（无 `Package.resolved`）。
- Bundle ID：`com.miaoz.wick`；当前版本默认 `1.8.0 (30)`（见 `scripts/package_app.sh` 中的 `VERSION`/`BUILD` 默认值）。

## 仓库结构与模块划分

SwiftPM target（`Package.swift`；package 声明 `macOS 13+` 与 `iOS 16+`，macOS 专属 target 不参与 iOS 构建）：

- `WickSync`（库，**纯 Foundation** 的日记模型 + 同步引擎 + Dropbox 后端 + `L10n`/`AppLanguage`/`JournalDayKey`；禁止 `import AppKit`/`UIKit`；iOS 工程**本地包引用**指回仓库根并链接它）
- `WickCalendarKit`（库，**跨平台交易日历**：数据 + verlet 撕纸物理 + SwiftUI/SpriteKit 渲染 + 程序合成音效；依赖 `WickSync`，macOS 与 iOS 共用同一份；`#if os(macOS)` 只隔离窗口呈现、光标、触觉、`Color.blended` 等平台 API；可经 `swift build --target WickCalendarKit --triple arm64-apple-ios16.0 --sdk <iphoneos-sdk>` 验证可编译 iOS）
- `WickCore`（库，macOS 其余几乎全部代码，可被测试 `@testable import`；依赖 `WickSync` + `WickCalendarKit`，`Exports.swift` 同时 `@_exported` 两者）
- `Wick`（可执行，`Sources/Wick/main.swift` 仅 3 行：调用 `WickApp.main()`）
- `WickTests` / `WickSyncTests` / `WickCalendarKitTests`（单元测试，分别依赖 `WickCore` / `WickSync` / `WickCalendarKit`）

`Sources/WickCore/` 各文件职责：

| 文件 | 职责 |
| --- | --- |
| `WickApp.swift` | `MenuBarExtra` 场景、`AppDelegate`（外观/登录项/提醒/更新检查启动、退出前落盘）、菜单栏 label（蜡烛图标 + 可选当日剩余百分比） |
| `ProgressPanelView.swift` | 菜单栏弹出的进度面板与设置页 UI（`TimelineView` 每秒刷新；`PanelTheme` 为薄结构体，全部色值委托给 `DayArcEngine`） |
| `WickTheme.swift` | 「一日弧光」主题引擎：`WickRGB`（可插值/可做 WCAG 对比度计算的 sRGB 值类型）、`WickPalette`（全部色角色，含复盘判定色 `reviewCorrect`/`reviewWrong`）、`DayPhase`（晨光/白昼/暮色/夜幕四锚点）、`DayArcEngine`（按时刻在 4 相位 × 亮/暗 2 套锚点色板间插值；`MetricTheme` 色相族恒定、仅辉光随相位缩放；`WICK_ARC_TIME=HH:mm` 环境变量可伪造"当前时刻"用于调试/截图）；`\.wickPalette` 环境键 |
| `JournalStore.swift` | 多日记本存储（`@MainActor ObservableObject` 单例）：`catalog.json` + 每本独立目录；落盘、`.bak` 与滚动备份、加载失败只读保护、图片管理、zip 导入导出；启动时一次性把旧版 `Wick/Journal` 迁到多日记布局；**一天一篇**由 `createEntry`/`updateEntry` 的按日合并保证；`load()`/`loadSnapshot()`/导入均带 `JournalSnapshot.version` 版本门（遇到更新格式只读拒写）；文件尾部为 `JournalLocalSource` 同步桥接扩展（`syncDaySnapshots`/`applySyncedEntry`/`removeSyncedDay`/`applySyncedJournalName`/图片读写，远端文件名做防穿越校验，远端改名与其他本地日记本撞名时去重后返回实际应用名） |
| `JournalRootView.swift` | 日记窗口根视图（`JournalRootView`，`NavigationSplitView` 双栏；macOS 14+ 用系统工具栏，macOS 13 用 `JournalWindowController` 安装的 AppKit `NSToolbar`，判定见 `journalNeedsInViewTopBar`；色值取自 `\.wickPalette`，根视图 300s `TimelineView` 刷新；加载失败/恢复横幅、隐藏快捷键按钮） |
| `JournalSidebarView.swift` | 日记侧栏：搜索框 + 标签芯片过滤（超宽折叠为「更多 N」，展开换行/再点收起）、按日/按条目两种列表、空态；选中高亮为自绘 `listRowBackground`（`sidebarBackground` 打底 + `accentSoft`，替代系统蓝/灰药丸以保证跨 macOS 版本一致），两个 `List` 均挂 `TableViewSelectionSuppressor` 关掉底层 `NSTableView` 的系统高亮（否则点击瞬间会闪一帧系统蓝色）；标签打包逻辑在 `TagChipFlow.swift` |
| `TableViewSelectionSuppressor.swift` | `NSViewRepresentable`：子树搜索找到 SwiftUI `List` 背后的列表视图（新系统为 `SwiftUIOutlineListView`，`NSTableView` 子类；注意它是兄弟子树而非祖先）并设 `selectionHighlightStyle = .none`，配合自绘选中背景消除按住/点击时的系统蓝高亮 |
| `JournalEditorPane.swift` | 日记编辑区：编辑器顶部为 `DayArcStrip` 24h 弧光渐变条（组件在 `DayArcStrip.swift`），今日条目带"此刻"圆点；头部日期按应用语言格式化、零填充，点击弹出图形日历；草稿防抖落盘（IME 组字期间不提交）、图片粘贴/拖拽 |
| `JournalItemEditorCard.swift` | 条目卡片（单层平面：无内部盒子，标签为琥珀色纯文本、正文无框、图片区为缩略图网格，卡片描边弱化、填充 65% 不透明；顶栏为 条目N/添加图片/删除，整卡为图片拖放区）+ 图片缩略图组件；早于今天的条目右下角为「复盘」位——未复盘是「复盘」按钮、已复盘是放大的 `JournalReviewBadge` 印章（56pt，非当前判定贴纸在气泡内淡显），复盘选择（对/错贴纸即选项）在系统 `popover` 中进行——点外部任意处自动关闭（放弃选择不留痕迹），批注输入框始终在场（未判定时先存草稿、选定时并入复盘），已复盘条目的批注显示为铅笔图标批注行（不用斜体：CJK 无斜体字形）|
| `JournalReviewBadge.swift` | 复盘判定贴纸：`JournalReviewBadge`（`.seal` 双环印章微旋转、`size` 可调（编辑器卡片 56pt、气泡选项 34pt）；`.mini` 纯色字形，侧栏条目行用），verdict→字形/颜色映射也在此（correct=reviewCorrect、wrong=reviewWrong） |
| `DayArcStrip.swift` | 弧光条组件本体 |
| `MacroCalendarModels.swift` | 交易日历数据：`MacroCalendarEvent`（time/country/title/importance/actual/forecast/previous/link，`public` Codable）+ `MacroCalendarPayloadDecoder`（解析华尔街见闻 `data.items`，镜像 akshare：`revised` 回填 `previous` 后丢弃、空/非数值→`nil`；数据方会用不同 ticker 重复收录同一发布，按 时间+国家+标题 去重保留首条；`calendar_key` 可能为空字符串，id 回退顺序为 非空 calendar_key → 数字 id → 时间-标题——空 id 会被 SwiftUI 当重复身份重复渲染）；`MacroCalendarError` |
| `MacroCalendarClient.swift` | Swift 直连 akshare `macro_info_ws` 背后的公开 REST 端点（`api-one-wscn.awtmt.com/apiv1/finance/macrodatas?start=&end=`，keyless GET，非 WebSocket）；端点 `end` 为包含式、会漏入次日零点事件（相邻两天页面重复显示），解码后按 `[start, end)` 过滤；`dayUnixRange` 纯计算（本地某日零点起 86400s）可测。见闻日历历史上另有 财报/新股/活动 三类（`finance/report/list`、`finance/ipodatas`、`finance/meetings`），**现已在后端下线或清空（404/恒空），不要再尝试接入**；其内容实质已并入 `macrodatas`——响应按 `calendar_type` 混排 `FD`（数据发布：有 ticker、今值/预期/前值）与 `FE`（事件：打新/发布会/讲话/财报电话会，无 ticker、`calendar_key` 为空、数值全空） |
| `TradingCalendarWindowController.swift` | 交易日历窗口为 **无边框透明、可穿透** 的贴桌对象（仿 himekuri `PaperWindow`/`PassThroughHostingView`：pad 区接收点击、其余穿透到下层）；打开转 `.regular`、关闭回 `.accessory`（仅当日记窗口也未开）、dismiss 菜单栏面板、`closeCalendar()`；建窗时以 `TradingCalendarRootView(language:onClose:onPageTorn:)` 接入 kit（`onPageTorn` → `FallingPageOverlay.spawn`）；建窗时安装**方向键/滚轮本地事件监听**（handler 按 `event.window` 判定作用域——按键要求本窗为 key、滚轮要求指针在 pad 上；`NSEvent` 非 Sendable 故 handler 保持非隔离、经 kit 的 `.wickCalendarFlipEventsPage` Notification 直发翻页，滚轮带累积阈值 + 冷却防触控板惯性连翻） |
| `FallingPageOverlay.swift` | **macOS 专属**的碎页呈现：撕下的碎片放进一个**横跨 pad 到屏幕底部、透明可穿透的叠加窗**，飘落到屏幕外（iOS 端由 App 用全屏 SwiftUI 遮罩承载同一份 `FallingPageView`） |
| `JournalReminderScheduler.swift` | 每日本地通知（`UNUserNotificationCenter`） |
| `JournalWindowController.swift` | 手动持有日记 `NSWindow`（因 `MenuBarExtra` 场景里 SwiftUI `openWindow` 不可用）；日记打开时把激活策略切为 `.regular`（Dock 显示图标、可 Cmd+Tab 切换），关闭时回 `.accessory`；macOS 13 下安装 AppKit `NSToolbar` |
| `LegacyJournalToolbar.swift` | macOS 13 工具栏代理（`LegacyJournalToolbarDelegate`：折叠钮最左（红绿灯行、前导位，双栏单栏均在）、日记本控件其次、新建钮最右；折叠走响应链 `toggleSidebar:`；日记本控件为**无边框 `NSPopUpButton`（pullsDown）**，菜单第 0 项即按钮标题（书本图标+当前日记本名，不出现在下拉里），随 `wickActiveJournalDidChange` 重建；菜单动作经 Notification 异步交给 SwiftUI 弹窗——同步派发会被 macOS 13 的菜单跟踪吞掉） |
| `MenuBarExtraPanel.swift` | 用启发式（类名/styleMask/NSPanel）关闭 `MenuBarExtra` 面板窗口；**带尺寸护栏**：高度 ≤30 或宽度 ≤60 的小窗一律不碰——macOS 13 的 `NSApp.windows` 里混有状态栏图标的宿主小窗，误关会让图标永久消失 |
| `IMESafeTextViews.swift` | AppKit 包装的单行/多行文本输入，避免中文/日文/韩文 IME 组字（marked text）期间被外部写值吞字；多行编辑器为 `IMETextView` 子类（手动装配 scrollView，**不要用 `NSTextView.scrollableTextView()`**），并由 coordinator 监听 clip view bounds 同步文本视图宽度（macOS 13 不向 document view 传播缩小，不修则长行不换行溢出）；keyDown 里显式路由 ⌘V；单行框经 `control(_:textView:doCommandBy:)` 拦截粘贴命令；两者都在剪贴板含图片时交给 `onPasteImage`（图片进条目），否则走默认文本粘贴（注意 ⌘V 也可能以 `noop:` 形式到达，需按 `NSApp.currentEvent` 二次判定） |
| `JournalImageProcessing.swift` | 图片导入处理：最长边 2048px，无 alpha 转 JPEG(0.82)，有 alpha 存 PNG |
| `MenuBarIcon.swift` | 代码绘制的蜡烛模板 `NSImage`（1x/2x，`isTemplate = true`，只创建一次不再变更） |
| `AppSettings.swift` | 设置单例（`AppSettings.shared`）：语言/外观/提醒/菜单栏百分比/周一起始/登录项/更新检查，全部持久化到 `UserDefaults`（键前缀 `wick.`） |
| `Exports.swift` | 两行 `@_exported import WickSync` + `@_exported import WickCalendarKit`——让 WickCore 全部文件免逐文件 import 即可用共享类型 |
| `AppInfo.swift` | 版本读取与语义化比较（`isVersion(_:newerThan:)`） |
| `UpdateChecker.swift` | 查询 GitHub Releases latest API（`miaoz/wick`），15s 超时，自定义 UA |
| `LaunchAtLogin.swift` | `SMAppService.mainApp` 封装（macOS 13+） |
| `AppNotifications.swift` | 自定义 `Notification.Name`（退出/关窗前冲刷草稿、存储恢复、日记本切换/工具栏弹窗；日历事件区翻页通知已移入 kit） |
| `SyncCoordinator.swift` | 同步生命周期单例：持有 `DropboxSyncBackend` + `JournalSyncEngine`（localSource 为 `JournalStore.shared`）；启动时按 `wick.sync.enabled` 启停；`$entries` 变更 → 15s 防抖同步、切换日记本/失去激活 → 触发同步；连接/断开 Dropbox；**自动导入**远端发现的日记本（`registerRemoteJournal` 不切换活跃本，内容在用户打开时拉取；本地删除过的 UUID 记入 `wick.sync.ignoredRemoteJournals` 不再自动导入，设置页手动导入为逃生口）；导入前必须 `resetSyncState`（否则陈旧基线会把空本地误判为全删、向远端写墓碑）；退出前一次 5s 上限的最终同步（`applicationShouldTerminate` 返回 `.terminateLater`） |
| `DropboxAuthSession.swift` | `ASWebAuthenticationSession` 包装（OAuth 浏览器授权 + 回调 URL）；需窗口 anchor，且回调 scheme 只在打包 `.app` 内注册，`swift run` 收不到回调 |

`Sources/WickCalendarKit/`（**跨平台交易日历**，macOS 13 + iOS 16；依赖 `WickSync`；`#if os(macOS)` 只隔离窗口呈现/光标/触觉/`Color.blended`）各文件职责：

| 文件 | 职责 |
| --- | --- |
| `MacroCalendarModels.swift` | 交易日历数据：`MacroCalendarEvent`（`public` Codable）+ `MacroCalendarPayloadDecoder`（解析华尔街见闻 `data.items`，镜像 akshare：`revised` 回填 `previous` 后丢弃、空/非数值→`nil`）+ `MacroCalendarError` |
| `MacroCalendarClient.swift` | Swift 直连 akshare `macro_info_ws` 背后的公开 REST 端点（keyless GET，非 WebSocket）；`dayUnixRange` 纯计算可测 |
| `MacroCalendarStore.swift` | `@MainActor` 数据单例：按本地日取数/加载态/错误态，内存 + 磁盘 JSON 缓存（离线可读，失败不覆盖，读缓存重建旧版空 id）；`MacroCalendarFormat` 事件时间（Asia/Shanghai） |
| `LunarDate.swift` | 公历→农历转换（`LunarCalendar`，1900–2100 月长表，纯可测）+ 干支年/生肖（甲子锚定 `mod(year-4,…)`）、农历月名/日名 |
| `PaperSim.swift` | himekuri `PaperSim` 移植：verlet 布料网格（11×14，row0 钉装订、row1 撕线按 `fiberIntact` 逐列钉/断）、结构/剪切/弯曲约束、重力、grab(z lift)、`setSeam` 累计断纤、sleep；纯 Foundation 可测 |
| `CalendarPaperScene.swift` | `SKScene`：把当日页纹理经 `SKWarpGeometryGrid` 每帧按 sim 网格变形（仅顶层页）；`warpPositions` y 翻转映射；iOS 同款 |
| `SeededRandom.swift` | 确定性 xorshift RNG（撕口/纸粒/纸声可复现）+ `tearSeed(for:)` |
| `PaperTear.swift` | 撕口几何：`tearEdgePoints`/`TornPieceShape`/`StubShape`/`TearEdgeLine`；约 1/3「完美撕开」 |
| `FallPlan.swift` | 飘落轨迹纯数值（`FallState`/`FallTrack`/`FallPlan.make`）：下坠/上扬、侧向 carry、bank 旋转、planing 倾斜 |
| `TradingCalendarTheme.swift` | himekuri「黄历」配色/字体助手/`TradingCalendarGeometry`；`Color.blended` 用 `#if os`（`NSColor`/`UIColor`） |
| `MacroDayPageView.swift` | 「黄历」页本体（被快照成纹理供撕纸变形）：双线描边、报头（撕线之下首行可见）、大号日期、竖排星期填色列、中部农历行、宏观事件**固定栏目**（栏高撑满、翻页不串版、按 `MacroEventPaging` 每版 4 行分页、按重要性降序、无事件日红色方印章、页脚 chip）；日期/农历/干支纯计算 |
| `TradingCalendarRootView.swift` | 撕页日历根视图（SwiftUI `ZStack` + SpriteView 顶层页 + 裂纹模型 + 撕痕/残根/装订/手势层 + 事件翻页）；**平台无关**：`init(language:onClose:onPageTorn:)`，撕页经 `onPageTorn` 交给宿主呈现，光标/悬停/Esc/拖窗走 `#if os(macOS)` 与 shim；`CalendarSnapshot`（ImageRenderer） |
| `FallingPage.swift` | `FallingPage`（结构）+ `FallingPageView`（碎纸飞行，`FallPlan` 手工 Catmull-Rom 插值，阴影/3D 倾斜/摆荡）——**不含** macOS 叠加窗（见 WickCore `FallingPageOverlay`） |
| `TearSound.swift` | **纯程序合成纸声**（无音频资源，`AVAudioEngine`）：`playRip`/`playRustle`/`playCrackle` |
| `Haptics.swift` | 触觉 shim（`@MainActor`）：macOS `NSHapticFeedbackManager` / iOS `UIImpactFeedbackGenerator`（`tick`/`rip`） |
| `CalendarCursor.swift` | 光标 shim（`openHand`/`arrow`/`closedHand` + `.calendarCursorOnHover()`）：iOS no-op |
| `CalendarNotifications.swift` | kit 内 `.wickCalendarFlipEventsPage` 翻页通知（kit 监听、WickCore 发） |
| `WindowDrag.swift` | 装订条拖拽移窗（`#if os(macOS)` AppKit overlay `performDrag`；iOS no-op） |

`Sources/WickSync/`（纯 Foundation，iOS 可复用）各文件职责：

| 文件 | 职责 |
| --- | --- |
| `JournalModels.swift` | 日记模型（`JournalEntry`/`JournalItem`/`JournalReview`/`JournalSnapshot`/`JournalInfo`/catalog，全部 `public` Codable）；`JournalEntry.dayKey` 为同步层按天稳定主键——创建或移日时生成后冻结，解码旧数据时从 `date` 推导一次 |
| `JournalDayKey.swift` | `yyyy-MM-dd`（本地时区、公历）日键生成 |
| `L10n.swift` | 文案目录 + `AppLanguage`（`L10n.string(.key, language:)`，中/英双语；从 WickCore 迁入并公开化，iOS 复用） |
| `TimeProgress.swift` | `TimeProgressCalculator`：日/周/月/年剩余比例的纯计算（可注入 `Date`/`Calendar`，便于测试；从 WickCore 迁入，iOS 首页复用） |
| `JournalSyncEncoding.swift` | 规范 JSON 编码器（sortedKeys，与落盘格式一致）+ SHA-256 内容哈希（≤4MB 时与 Dropbox `content_hash` 逐字节一致，哈希可直接比对远端元数据） |
| `JournalLocalSource.swift` | 引擎↔本地存储协议（按天快照/应用/删除 + 日记名应用 + 图片读写），未来 iOS 存储实现同一协议 |
| `JournalSyncBackend.swift` | 后端协议（listChanges 游标增量/download/upload rev 条件写/delete）+ `RemoteFileMeta` + `SyncBackendError` |
| `DropboxSyncBackend.swift` | Dropbox API v2 实现：PKCE OAuth（`token_access_type=offline`，refresh token 存 Keychain，access token 单飞刷新）、`list_folder(+continue)`、`files/download|upload|delete_v2`；409 冲突/cursor 失效/429/401 分类 |
| `PKCE.swift`、`KeychainTokenStore.swift` | PKCE 工具（无 App secret 的公共客户端）；Keychain 读写（无 access group——ad-hoc 重编译可能丢 token，表现为需重新授权） |
| `JournalDayMerge.swift` | 同一天两版本合并：条目按 UUID 并集、同条目不同内容新 `updatedAt` 方胜（败者入 `losingItems` 保留）、标题同理、身份收敛到 `createdAt` 更早者 |
| `JournalSyncState.swift` | 远端布局 `/journals/<uuid>/{manifest.json,days/,images/,tombstones/,conflicts/}`；manifest/墓碑/冲突载荷 Codable；每设备同步状态（cursor、远端文件视图、按天哈希/rev、pendingConflicts、日记名基线 `manifestName`）与本地持久化（`~/Library/Application Support/Wick/SyncState/<uuid>.json`，**不参与同步**） |
| `JournalSyncEngine.swift` | 对账引擎（`@MainActor ObservableObject`）：cursor 增量 → manifest `formatVersion` 版本门 + 日记名对账（本地改名→rev 条件写推送；远端 manifest 被改写→`applySyncedJournalName` 本地采用；双改→后推者胜、败方下轮采用；旧状态文件无 `manifestName` 基线则一次性播种——远端未动时本地未推送的改名补推、远端已动则信任远端）→ 发现其他日记本 manifest（`discoveredJournals`，供自动/手动导入，消失即剪除）→ 按天矩阵（本地变→条件上传；远端变→下载应用；双变→条目并集合并，败者存档 `conflicts/` 并出 `pendingConflicts`；本地删→先写墓碑再删远端；远端墓碑→本地删（本地有改动则改动方胜并清墓碑）；远端文件无墓碑消失→视为事故自动回传，绝不镜像删除）→ 图片按引用差集上传/下载 → 墓碑 30 天 GC；60s 周期 + 15s 防抖 + `syncOnce()`（退出用）+ `resetSyncState()`（重导入前调） |

其他目录：

- `assets/`：`AppIcon-master.png`、`AppIcon.icns`（`AppIcon.iconset/` 是生成中间产物，已 gitignore）
- `ios/`：iPhone 客户端（v0，**仅中文 UI**，真机调试，未上架）。手写 `WickPhone.xcodeproj`（文件系统同步组——往里加源码文件不用改 pbxproj；`Info.plist` 放在 `ios/` 根而非同步文件夹内，否则会被当资源重复打包），本地包引用指回仓库根、链接 `WickSync` + `WickCalendarKit`。`WickPhone/` 下：`HomeView`（首页 = macOS 菜单栏面板的手机版：日/周/月/年剩余进度 + 相位 + 每秒刷新，日记经书本按钮进入、交易日历经「交易日历」按钮 `fullScreenCover` 进入）、`CalendarView`（**全屏承载 `WickCalendarKit.TradingCalendarRootView`**：按屏幕尺寸缩放 pad、`onPageTorn` 触发全屏 `FallingPageView` 遮罩滑出屏幕底部、墙色渐变背景）、`PhoneJournalStore`（实现 `JournalLocalSource` 的精简存储：同磁盘布局、`.bak`、版本门、只读保护，无滚动备份/迁移；`entries` 保持新→旧有序——`DayListView` 按数组顺序渲染）、`PhoneSyncCoordinator`（同 macOS 协调器职责 + iOS `ASWebAuthenticationSession` 包装，回调闭包走 `nonisolated` 工厂——同 macOS 的崩溃教训）、`DayListView`/`EditorView`/`SettingsView`（列表 + 编辑器 + 同步设置；条目图片只展示，**暂不支持添加图片、复盘、多语言**）、`Assets.xcassets`（`AppIcon` 用 `assets/AppIcon-master.png` 单尺寸 1024）。真机运行：Xcode 打开工程选自己设备，Signing 选 Personal Team。CLI 校验：`xcodebuild -project ios/WickPhone.xcodeproj -target WickPhone build CODE_SIGNING_ALLOWED=NO OBJROOT=/tmp/x SYMROOT=/tmp/y`（本机无模拟器运行时，带 `-destination` 会报「platform not installed」；本沙盒无 iOS 模拟器运行时，actool 会报 `No available simulator runtimes`——Swift 代码可用 `swiftc -typecheck -target arm64-apple-ios16.0 -sdk <iphoneos-sdk> -I .build/arm64-apple-ios/debug/Modules ios/WickPhone/*.swift` 校验）
- `scripts/`：`package_app.sh`（打 `.app`，含生成 `InfoPlist.strings` 中英双语通知用途文案）、`package_zip.sh`（打 zip）、`generate_icon_assets.sh` + `generate_icon.swift`（代码绘制图标）
- `.github/workflows/release.yml`：唯一的 CI 工作流
- `dist/`：打包产物（已 gitignore）

## 构建与测试命令

```bash
# 开发（仅宿主架构）
swift build
swift run          # 注意：非 .app 形态下本地通知会被跳过（见下「注意事项」）

# 单元测试（XCTest）
swift test

# 正式打包：分别编译 arm64 / x86_64 并 lipo 成 Universal → dist/Wick.app
make               # = ./build.sh = scripts/package_app.sh

# 打可分发 zip → dist/Wick-macOS[-<VERSION>].zip
make package       # = scripts/package_zip.sh（内部先调 package_app.sh）

# 注入版本号（写入 Info.plist 与 zip 文件名）
VERSION=1.3.1 BUILD=6 ./scripts/package_zip.sh

# 重新生成图标、清理
make icon          # scripts/generate_icon_assets.sh（swift 绘主图 + sips + iconutil）
make clean         # rm -rf .build dist
```

要点：

- `swift build` 只产出当前架构；**发布一律走 `make` / `scripts/package_app.sh`** 以保证 Universal。
- 打包脚本用 `plutil -lint` 校验 Info.plist、`lipo -info` 打印架构；`.app` 为 **ad-hoc 签名**（`codesign --sign -`），未公证，README 已说明首次打开需用户手动允许。
- 生成 `Info.plist` 是脚本内 heredoc（`LSUIElement=true`、含 `NSUserNotificationsUsageDescription`），不在仓库里维护单独的 plist 文件。

## 测试说明

- 测试位于 `Tests/`，XCTest：`WickTests` 用 `@testable import WickCore`，`WickSyncTests` 用 `@testable import WickSync`；CI 在打包前执行 `swift test`。
- 现有测试文件：
  - `TimeProgressTests.swift`：剩余比例边界（0/1 钳制、起止时刻）、四类进度齐全、周一起始。
  - `JournalStoreTests.swift`：用 `JournalStore(rootDirectory:)`（临时多日记根目录）覆盖默认日记本、新建/切换/删除日记本、旧版单日记迁移、一天一篇、标签按条目过滤、删除条目清理图片、持久化重载、主文件损坏时从 `.bak` 恢复、无备份时进入只读且**不覆盖磁盘坏文件**。
  - `JournalStoreSyncTests.swift`：同步桥接——快照版本门（v99 只读且磁盘原样、新版 `.bak` 不恢复）、`applySyncedEntry` 按 dayKey 插替/保 remote updatedAt/选中跟随身份变更/只读下拒绝、`removeSyncedDay` 清图片、图片读写与路径穿越防护、`applySyncedJournalName` 改名/撞名去重/同名幂等。
  - `AppInfoTests.swift`：版本号比较。
  - `WickThemeTests.swift`：主题引擎——相位归属（锚点切换、跨午夜回绕）、插值中点、全天每 15 分钟 × 亮/暗的对比度护栏（textPrimary ≥4.5、accentText ≥4.0 等）、指标色相族稳定性。
  - `TagChipFlowTests.swift`：标签芯片换行打包（贪心换行、超宽独占一行）与折叠行裁剪（为「更多 N」腾出空间、全部裁掉的边界）。
  - `WickCalendarKitTests/MacroCalendarTests.swift`：`dayUnixRange` 本地日跨度/零点边界；华尔街见闻载荷解析字段映射与 `revised→previous` 回填；空 items/畸形载荷报错/无 release_time 跳过；重复收录条目去重；空 `calendar_key` 的 id 回退；事件分页计数；数值强转（`%` 容忍、空/非数值→nil）。
  - `WickCalendarKitTests/PaperSimTests.swift`：rest 网格几何（row0 顶边、row1 撕线、末行页底）；静止步进有限值稳定；`setSeam` 按列断纤；全撕后重力下垂。
  - `WickCalendarKitTests/LunarDateTests.swift`：公历→农历已知日期（春节正月初一、年中某日）；干支/生肖（甲子锚定）、农历月名（正月/冬月/腊月）、日名（初一…三十）。
  - `WickSyncTests/JournalSyncModelTests.swift`：dayKey 生成/解码推导/往返、规范编码 decode→encode 字节稳定、SHA-256 已知向量。
  - `WickSyncTests/JournalDayMergeTests.swift`：并集、同条目冲突新者胜+败者记录、标题规则、占位空条目剔除、时间戳 min/max、身份按 createdAt 收敛（与参数顺序无关）。
  - `WickSyncTests/JournalSyncEngineTests.swift`：内存假后端 + 假本地源模拟**双设备**——首同步上传、二次空转、拉取、推送、不同条目并集合并、同条目冲突存档、删除墓碑传播、删除 vs 编辑两方向、远端文件消失自愈回传、图片双向、新版 manifest 阻断、cursor 失效恢复、状态跨实例恢复、切换日记本不串数据、日记名改名双向传播/收敛无回波/双改后推者胜/导入采用远端名/旧状态基线播种两方向。
- 新增可测逻辑时的落点：纯计算放 `TimeProgressCalculator` / `DayArcEngine` 这类可注入 `Date`/`Calendar` 的静态方法；存储行为扩展 `JournalStoreTests`；同步行为扩展 `WickSyncTests`（引擎一切分支都应能用假后端复现，不碰网络）。UI 层无测试。

## CI 与发版

`.github/workflows/release.yml`（name: Build and Release）：

- 触发：push/PR 到 `main`、推送 tag `v*`、`workflow_dispatch`。
- 环境：`macos-26` runner，优先 `xcode-select` **Xcode 26.6**（没有则回退最新 26.x）；步骤含工具链打印、`swift test`、版本解析（tag 去掉 `v` 前缀；非 tag 用 `0.0.0-<short-sha>`，BUILD 为 run number）、`./scripts/package_zip.sh`、校验二进制、上传 artifact（30 天）。
- 仅当 tag 以 `v` 开头时用 `softprops/action-gh-release` 创建 GitHub Release 并附上 zip；随后执行 `Prune old releases` 步骤，**只保留最新 3 个 Release**（`gh release delete`，不删 git tag，旧版本仍可从 tag 出码重建）。
- 发版流程：`git tag v1.2.3 && git push origin v1.2.3`（tag 版本号会成为 zip/Release 版本）。

## 代码风格与约定

- **文档语言**：README 等面向用户的文档用简体中文；**代码注释、commit message 用英文**（保持一致，新增注释也用英文）。
- 无 SwiftLint/格式化配置；遵循现有风格：4 空格缩进、`// MARK: -` 分节、类型职责单一（一个文件一个主类型）。
- UI 文案**必须走 `L10n`**：`L10n.Key` 枚举加 case，并同时提供中/英文实现，不要硬编码字符串到视图里。
- 设置项一律加在 `AppSettings` 单例：`@Published` + `didSet` 写 `UserDefaults`（键名 `wick.` 前缀，集中在私有 `Keys` 枚举）；`init` 里用 `isLoading` 抑制加载期的副作用（如提醒重调度）。
- 全局单例：`AppSettings.shared`、`JournalStore.shared`、`JournalReminderScheduler.shared`、`JournalWindowController.shared`；依赖通过 `.environmentObject` 注入 SwiftUI。
- 触及 UI / AppKit 的类型标 `@MainActor`（Swift 6 并发严格检查，CI 曾因并发问题修过构建）。
- 平台能力封装为小工具枚举/类（`LaunchAtLogin`、`UpdateChecker`、`MenuBarExtraPanel`、`JournalImageProcessing`），保持这一模式而不是把 AppKit 细节散进视图。
- **颜色一律走主题引擎**：新增 UI 不得硬编码色值，从 `DayArcEngine` / `\.wickPalette` 取色；正文级文字用 `textPrimary/Secondary/Tertiary` 或 `accentText`（`accent` 仅作图形 tint）。改锚点色板后必须跑 `WickThemeTests` 的对比度护栏。调试某个时刻的配色用 `WICK_ARC_TIME=HH:mm swift run`（仅 DEBUG 构建生效，正式包不带调试开关）。

## 注意事项（安全与数据保护）

- **日记数据安全是核心约束**，改动 `JournalStore` 时必须保持：
  - 多日记布局：`~/Library/Application Support/Wick/Journals/catalog.json` + `<uuid>/{journal.json,.bak,backups/,images/}`；不再运行时兼容旧版单日记路径（仅启动时一次性迁移 `Wick/Journal` → `Journals/<uuid>/`）。
  - 加载失败进入 `isReadOnlyDueToLoadFailure`，**禁止任何写盘**（防止空数据覆盖损坏文件）；损坏文件移存为 `journal.corrupt-<ts>.json` 隔离。
  - 覆盖前先复制 sidecar `journal.json.bak`；滚动备份最多 5 份、间隔 ≥30 分钟。
  - 退出（`applicationShouldTerminate`）与关日记窗前发 `wickWillFlushJournalDrafts` 并 `flushPendingWrites()`；切换日记本前同样 `flushPendingWrites()`。
- **UserNotifications 只能在正式 `.app` 包内使用**：`swift run`/裸二进制下调用会 abort，因此 `JournalReminderScheduler.notificationsAvailable` 做了包形态门控，新增通知相关代码必须维持该门控。
- **Dropbox 同步**：OAuth 回调走自定义 scheme `db-hm5yscsy9a11g0q`（`package_app.sh` 生成的 Info.plist 里 `CFBundleURLTypes`，与 `DropboxSyncBackend.callbackScheme` 一致），因此「连接 Dropbox」只能在打包 `.app` 内完成，`swift run` 收不到回调；引擎全部逻辑用 `WickSyncTests` 的内存假后端覆盖，不碰网络。**App secret 永不写入仓库/二进制**（PKCE 公共客户端只需要 App key）。同步只针对当前活跃日记本（切换即重新对账）；`isReadOnlyDueToLoadFailure` 时引擎只读不推；远端 manifest `formatVersion` 与 `JournalSnapshot.version` 双重版本门，遇到更新格式一律只读拒写。
- 同步数据面：Dropbox App folder 内 `/journals/<uuid>/`（manifest + days + images + tombstones + conflicts）；每设备私有状态在本地 `Wick/SyncState/`；设置项 `wick.sync.enabled`/`wick.sync.accountEmail` 在 `AppSettings`，token 只在 Keychain。
- **`MenuBarExtra` 的 label 里禁止放 `TimelineView` 等高频失效源**：会触发 `requestUpdate` → `setImage` 死循环占满 CPU（`WickApp.swift` 有注释；当前 label 用 30s `Timer` 且仅在文本变化时更新状态）。
- IME 组字：日记编辑用 `IMESafeTextViews` 里的封装，不要用原生 SwiftUI `TextField` 直接替换，否则中文输入会吞字（有专门修复提交）。
- **手动 `NSWindow` + `NSHostingController` 且标题栏透明/隐藏标题时，macOS 13 不会安装任何工具栏**（SwiftUI `.toolbar` 项与 `NavigationSplitView` 的侧栏折叠按钮都不出现；视图内 `safeAreaInset`/`ignoresSafeArea` 的条带方案在各版本间落点不一致，已弃用）；因此 macOS 13 由 `JournalWindowController` 安装真正的 **AppKit `NSToolbar`**（`LegacyJournalToolbarDelegate`：折叠钮最左、新建钮最右，系统布局保证与红绿灯同线），折叠动作走响应链 `toggleSidebar:`（与系统按钮同机制，勿用自研 binding 桥）；快捷键 ⌘N/⌃⌘S 以隐藏按钮形式留在视图里（`journalNeedsInViewTopBar` 判定，`WICK_INVIEW_TOPBAR=1` 仅 DEBUG 构建可强制预览）。`sidebarTrackingSeparator` 不要用于本窗口——内容 VC 是 `NSHostingController` 而非 `NSSplitViewController`，关联不合法且实测导致窗口状态异常。
- 网络面很小：检查更新访问 `api.github.com`（15s 超时）；交易日历访问华尔街见闻 `api-one-wscn.awtmt.com`（keyless REST，15s 超时，失败/离线走缓存与空态）；无遥测、无账号体系。
- 发布包 ad-hoc 签名、未公证——不要在文档/脚本中暗示已签名公证。
- 许可：仓库暂无 `LICENSE`，README 声明保留版权，新增第三方代码前需与维护者确认。
