# AGENTS.md

> 面向 AI 编码代理：Wick 的架构、构建、测试与约定。本文只保留「看代码不易发现」的约束与坑；改动代码前先核对相关源文件。

## 项目概览

- **Wick**：原生 macOS 菜单栏应用（`LSUIElement`，无 Dock 图标）。蜡烛图标弹出面板，实时展示 日/周/月/年 剩余百分比与结束时间（每秒刷新）。
- **日记**：一天一篇、篇内多条目（标签+正文+图片），条目级检索、每日本地通知提醒、zip 导入导出。
- **Dropbox 同步**（可选）：本地为唯一真源，`WickSync` 引擎按「天」双向对账（OAuth PKCE，客户端无 App secret）；删除靠墓碑传播、冲突按条目并集合并并保留败者、远端文件意外消失自动回传。
- **Binance 仓位**（可选）：凭据只存 Keychain，`WickTrading` 直连 USDⓈ-M 合约 REST 拉 `userTrades`（HMAC 签名、先对时、7 天分块；窗口下界为最早日记日、无日记回退近 180 天），快照存原始成交、增量刷新；`PositionAggregator` 聚合成开平仓会话（对冲双 lane、加仓 VWAP、翻仓拆两段、**净值 epsilon 吸附归零**，防十进制全平后 ~1e-18 残差造成的幽灵仓位）；按「开仓日 + 宽松标签匹配」挂进日记条目卡片；开仓日缺日记时 `PositionEntryPlanner` 自动补建条目（标签沿用用户惯用写法否则用基础币种 baseAsset，**从不改写已有标签**；已处理 ID 持久化，用户删掉的自动日记不复活）。
- **交易日历**：himekuri「黄历」撕页日历（无边框透明穿透窗、撕纸物理与程序合成音效），内容由 `WickCalendarKit` 直连华尔街见闻（宏观 + 财报，keyless REST，非 WebSocket、不打包 Python）。
- 其他：登录启动（`SMAppService`）、亮/暗/跟随系统外观（「一日弧光」主题引擎）、中英双语、菜单栏百分比、GitHub Releases 检查更新。
- macOS 13+ / Universal；Swift 6.1+、SwiftUI + AppKit、SwiftPM，**无第三方依赖**。Bundle ID `com.miaoz.wick`；版本默认值见 `scripts/package_app.sh`。

## 模块划分

SwiftPM target（package 声明 macOS 13+ / iOS 16+，macOS 专属 target 不参与 iOS 构建）：

| Target | 职责 |
| --- | --- |
| `WickSync` | 纯 Foundation：日记模型 + 同步引擎 + Dropbox 后端 + `L10n`/`AppLanguage`/`JournalDayKey`。**禁止 `import AppKit`/`UIKit`**；iOS 工程本地包引用指回仓库根 |
| `WickCalendarKit` | 跨平台交易日历：数据 + verlet 撕纸物理 + SwiftUI/SpriteKit 渲染 + 合成音效；一切度量按 `PaperLayout` 参数化（桌面 300×400 部件 / iPhone 页即屏幕满屏），`#if os(macOS)` 只隔离窗口呈现/光标/触觉等平台 API；依赖 `WickSync`。iOS 编译校验：`swift build --target WickCalendarKit --triple arm64-apple-ios16.0 --sdk <iphoneos-sdk>` |
| `WickTrading` | 纯 Foundation + CryptoKit：Binance 客户端（签名/分块分页/错误映射，transport 可注入）+ 成交→仓位聚合 + 宽松标签匹配 |
| `WickCore` | macOS 其余几乎全部代码（测试 `@testable import`）；依赖上述三者，`Exports.swift` 同时 `@_exported` 三者 |
| `Wick` | 可执行入口（3 行，调 `WickApp.main()`） |

测试 target 与之一一对应：`WickTests` / `WickSyncTests` / `WickCalendarKitTests` / `WickTradingTests`。

### `Sources/WickCore/`

| 文件 | 职责 |
| --- | --- |
| `WickApp.swift` | `MenuBarExtra` 场景、`AppDelegate`（外观/登录项/提醒/更新检查、退出前落盘）、菜单栏 label（蜡烛 + 可选当日剩余百分比） |
| `ProgressPanelView.swift` | 菜单栏面板与设置页 UI（`TimelineView` 每秒刷新；`PanelTheme` 为薄结构体，色值全部委托 `DayArcEngine`） |
| `WickTheme.swift` | 「一日弧光」主题引擎：`WickRGB`（可插值/对比度计算）、`WickPalette`、`DayPhase` 四锚点 × 亮暗两套插值；`WICK_ARC_TIME=HH:mm` 伪造当前时刻（仅 DEBUG）；`\.wickPalette` 环境键 |
| `JournalStore.swift` | 多日记本存储单例：`catalog.json` + 每本独立目录；`.bak` + 滚动备份、版本门、加载失败只读保护、图片管理、zip 导入导出、旧版一次性迁移；文件尾部为 `JournalLocalSource` 同步桥接（远端文件名防穿越校验、改名撞名去重） |
| `JournalRootView.swift` / `JournalSidebarView.swift` / `JournalEditorPane.swift` | 日记窗口三区块：双栏 SplitView（macOS 13 工具栏走 AppKit）；侧栏搜索 + 标签芯片（自绘选中背景 + `TableViewSelectionSuppressor` 关系统高亮）；编辑器顶部 `DayArcStrip`、草稿防抖落盘、图片粘贴/拖拽 |
| `JournalItemEditorCard.swift` | 条目卡片 + 复盘位（未复盘按钮永远独占一行；已复盘印章 `.overlay(bottomTrailing)` 浮于内容上；复盘选择走系统 popover，批注未判定时先存草稿） |
| `JournalReviewBadge.swift` / `DayArcStrip.swift` / `TagChipFlow.swift` / `TableViewSelectionSuppressor.swift` | 复盘印章（`.seal`/`.mini`）；弧光条；标签芯片换行打包；NSTableView 高亮抑制 |
| `TradingCalendarWindowController.swift` | 交易日历窗口（无边框透明、pad 区外点击穿透的贴桌对象）；建窗接入 kit 的 `TradingCalendarRootView(language:onClose:onPageTorn:)`；方向键/滚轮本地监听（按 `event.window` 判定作用域——按键需本窗为 key、滚轮需指针在 pad 上；`NSEvent` 非 Sendable 故 handler 非隔离、经 kit 的 `.wickCalendarFlipEventsPage` 通知直发）：**↑↓/滚轮翻页、←→ 切换宏观/财报**，滚轮带累积阈值 + 冷却 |
| `FallingPageOverlay.swift` | macOS 碎页叠加窗（飘落出屏幕；iOS 由 App 全屏遮罩承载同一 `FallingPageView`） |
| `JournalWindowController.swift` / `LegacyJournalToolbar.swift` | 手动持有日记 `NSWindow` + 激活策略切换；macOS 13 的 AppKit `NSToolbar`（折叠走响应链 `toggleSidebar:`，菜单动作经 Notification 异步交给 SwiftUI） |
| `MenuBarExtraPanel.swift` | 启发式关闭 MenuBarExtra 面板；**尺寸护栏**：高 ≤30 / 宽 ≤60 的小窗一律不碰（误关状态栏宿主小窗会让图标永久消失） |
| `IMESafeTextViews.swift` | AppKit 文本输入封装，IME 组字期间不被外部写值吞字；剪贴板含图片时交 `onPasteImage` |
| `JournalImageProcessing.swift` / `MenuBarIcon.swift` | 图片导入（≤2048px，无 alpha → JPEG(0.82)）；代码绘制蜡烛模板图标（只创建一次） |
| `AppSettings.swift` | 设置单例：`@Published` + `didSet` 写 `UserDefaults`（`wick.` 前缀），`init` 用 `isLoading` 抑制加载期副作用 |
| `SyncCoordinator.swift` | 同步生命周期单例：防抖/切本/失活触发、连接断开、远端日记本自动导入与**删除传播**（队列存设备级 `device.json`）、导入前必须 `resetSyncState`、退出前一次限时最终同步；设置页冲突对比弹层见 `SyncConflictResolutionView.swift` |
| `ExchangePositionCoordinator.swift` | 交易所仓位单例：Keychain 凭据（service `com.miaoz.wick.binance`）、快照存原始成交增量刷新、30 分钟定时、`PositionEntryPlanner` 补建开仓日条目（静默不抢选中，上限 5000） |
| `ExchangeSettingsContent.swift` / `JournalExchangePositions.swift` | 设置页「交易所」区块；条目卡片内仓位区块（无命中整块隐藏） |
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
| `TradingCalendarTheme.swift` | 配色/字体 + `TradingCalendarGeometry`（桌面静态度量）+ `PaperLayout`（`.desktop` 原样复刻；`.fullScreen(size:safeTop:safeBottom:)` iPhone 满屏：字级随宽缩放、避让刘海/Home 指示条、按窗高推每页行数、钳制 0 尺寸布局提案） |
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
| `DropboxSyncBackend.swift` + `PKCE.swift` + `KeychainTokenStore.swift` | Dropbox API v2（PKCE offline、单飞刷新、409/429/401 分类）；Keychain 读写 service+account 参数化（Dropbox 与 Binance 共用；无 access group，ad-hoc 重编译可能丢 token） |
| `JournalDayMerge.swift` | 同日合并：条目按 UUID 并集、同条目新 `updatedAt` 胜（败者入 `losingItems`）、身份收敛到 `createdAt` 更早者 |
| `JournalSyncState.swift` | 远端布局 `/journals/<uuid>/{manifest,days,images,tombstones,conflicts,settlements}` + `/journal-tombstones/<uuid>.json`（日记本墓碑在文件夹外）；每设备状态（cursor、远端 rev 视图、`DaySyncState`（`pushedHashes` 自合并保护、`DaySettlement` 待决）、冲突清理队列、`manifestName` 基线；**自定义解码全字段带默认值**）；设备级 `device.json` 承载删除队列（日记本删除时其自身状态文件即被清除） |
| `JournalSyncEngine.swift` | 对账引擎（`@MainActor`）。三条不变量：**①rev 回声抑制**（只比 rev）；**②拉取即固定点**（基线 = 下载字节本地重算哈希）；**③绝不和自己冲突**（`pushedHashes` 命中直接重推，不归档不弹冲突）。另有新鲜度守卫（快照后又编辑的天本轮跳过）、日记本删除传播（周期最先 flush 墓碑 + 清文件夹、同伴墓碑确认重发、30 天 GC）、冲突三版记录 + 结算标记跨端自动收敛、远端文件无墓碑消失自动回传（绝不镜像删除）；60s 周期 + 15s 防抖 + `syncOnce()` + `resetSyncState()` |

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

- 发布一律走 `make`（`swift build` 只产当前架构）；Info.plist 由脚本 heredoc 生成（`LSUIElement=true`）；`.app` 为 **ad-hoc 签名、未公证**（文档/脚本不得暗示已公证）。
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
- 日记编辑必须用 `IMESafeTextViews`，原生 SwiftUI `TextField` 在中文 IME 下吞字。
- macOS 13 下手动 `NSWindow` + 隐藏标题栏不会安装任何工具栏——折叠/新建走 `LegacyJournalToolbar`（真 AppKit `NSToolbar`），勿用自研 binding 桥或 `sidebarTrackingSeparator`。
- 网络面很小：`api.github.com`（更新，15s）、`api-one-wscn.awtmt.com` + `api-ddc-wscn.awtmt.com`（日历，keyless，15s，失败走缓存/空态）、`fapi.binance.com`（仓位，HMAC 签名只读，20s）；无遥测、无账号体系。
- 许可：仓库暂无 `LICENSE`，README 声明保留版权，新增第三方代码前需与维护者确认。
