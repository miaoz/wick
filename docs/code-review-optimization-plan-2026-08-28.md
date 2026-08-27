# Wick 全仓代码审查与优化计划

> 审查日期：2026-08-28
> 基线：`main@aa40d2d`（含工作区最新提交；上一轮架构加固 `e386357` 之后已有 112 个提交）
> 对照文档：[architecture-hardening-plan.md](./architecture-hardening-plan.md)（2026-08-22 轮，已全部验收关闭，本文不重复其条目）
> 方法：6 路并行模块深审（WickSync / WickCore 存储与协调器 / WickCore UI / WickCalendarKit / WickTrading / iOS+周边工程 / 测试与文档一致性），随后对全部 P1 级发现逐条回代码复核；外部 API 事实对照官方文档验证。

## 1. 总体判断

仓库整体质量在同类项目中属于上乘，上一轮加固的成果真实在位：

- 模块边界健康：`WickSync`/`WickTrading` 保持平台无关，同步三条不变量（rev 回声抑制、拉取即固定点、绝不自冲突）在代码与 67 个引擎测试中都有落点。
- 数据安全防线扎实：catalog/journal 双层只读保护、删除事务 quarantine+回滚、批量提交与代际丢弃均有测试钉住。**本轮未发现 P0 级丢数据路径。**
- 测试整体可信：361 个 Swift 测试 + 7 个 iOS 测试，无真实网络依赖（同步走假后端、交易所走注入 transport）。

主要风险集中在四类：

1. **错误路径缺事务化**：只读态导出会覆盖好归档、导入中途失败会删光图片（均 P1）。
2. **「对接第二家交易所/第二个平台」才暴露的假设**：HL 资金费翻页阈值、OKX 张/币单位与返佣符号、iOS 端缺失 macOS 已有的守卫。
3. **渲染路径上的同步 I/O**：侧栏对非活跃本逐次读盘+全量聚合、Lightbox 逐帧读图（均 P1）。
4. **双端漂移**：`PhoneJournalStore` 约 85% 复制 macOS `JournalStore`，加固轮的 EX-01 守卫未移植到 iOS；文档（AGENTS.md/README）已滞后于 WickCalendarKit 重组。

规模与测试密度：

| 模块 | 源行数 | 测试行数 | 测试数 | 测试/源行比 |
| --- | --- | --- | --- | --- |
| WickCore | 14757 | 2832 | 136 | 0.19 |
| WickSync | 4975 | 2470 | 94 | 0.50 |
| WickCalendarKit | 5704 | 930 | 48 | 0.16 |
| WickTrading | 1615 | 1625 | 83 | 1.01 |
| iOS（xcodeproj） | ~7000 | — | 7 | 极低 |

## 2. 发现总表

ID 前缀：TR=WickTrading，SY=WickSync，DS=存储/数据安全，CA=WickCalendarKit，UI=macOS UI，IO=iOS，TE=测试，DOC=文档，WEB=落地页/Functions，AR=结构重构，CI=持续集成。工作量：S<半天，M≈1天，L≥2天。

### P1（正确性/数据风险，建议全部修复）

| ID | 位置 | 问题 | 工作量 |
| --- | --- | --- | --- |
| TR-01 | `HyperliquidInfoClient.swift:72` | 资金费翻页阈值用错上限（500 误用 2000），活跃账户资金费静默截断 | S |
| CA-01 | `TraderAlmanac.swift:100-104` | 「确定性」种子用 `Hasher`（每进程随机），宜忌/印章每次重启都变，测试假绿 | S |
| SY-01 | `DropboxSyncBackend.swift:391-393` | access token 被吊销后 401 → `needsAuth` 死循环，最长卡 ~4 小时 | S |
| DS-01 | `JournalStore.swift:1193` | 加载失败只读态下导出 = 空归档原子覆盖上一次好导出 | S |
| DS-02 | `JournalStore.swift:1311-1325` | 导入先删光 `images/` 再逐张拷贝，中途失败图片永久丢失 | M |
| UI-01 | `JournalSidebarView.swift:98-99` | 侧栏对非活跃本的统计 = 每次渲染同步读盘解码 + 万笔仓位聚合 | M |
| UI-02 | `JournalImagePreviewOverlay.swift:110-111` | Lightbox 在 body 里无缓存读全尺寸图，缩放/拖拽每帧重读盘 | S |
| CA-02 | `TradingCalendarRootView.swift:85-107` | 顶页纹理不随 isLoading/error 刷新：闲日/失败日永久卡「加载中」 | S |
| IO-01 | `PhoneJournalStore.swift:826-833` | `.bak` 轮换在主线程全量读盘+解码整个快照（与自身注释矛盾） | M |
| IO-02 | `WickPhoneApp.swift:74-84` | 退后台 flush 无 `beginBackgroundTask`，主线程 semaphore 阻塞有 watchdog 风险 | S–M |
| IO-03 | `PhoneSyncCoordinator.swift:262` | `ASWebAuthenticationSession.start()` 返回值未检查，授权可永久悬挂 | S |
| IO-04 | `PhoneExchangeCoordinator.swift:175-210` | 交易任务无 generation/取消守卫（EX-01 未移植），解绑后旧请求可写回孤儿快照 | M |
| IO-05 | `DayListView.swift:83-92` | 盈亏月历点无日记的历史日，打开的是「今天」 | M |
| TE-01 | `JournalSyncEngineTests.swift:566,571` | 回归测试 blocker 匹配旧版 `days/` 路径永不命中，AC-P1-05 竞态测试空转 | S |

### P2（正确性/性能/可维护性，建议分批修）

| ID | 位置 | 问题 | 工作量 |
| --- | --- | --- | --- |
| SY-02 | `JournalSyncEngine.swift:1173-1185` | 结算 marker 只查第一个命中者，陈旧 marker 永久屏蔽新 marker | S |
| SY-03 | `JournalSyncEngine.swift:1017-1031` | 冲突记录/归档在上传成功前写入，网络抖动期每周期重复记录 | S |
| SY-04 | `JournalSyncEngine.swift:1673-1705` + `ProgressPanelView.swift:825-828` | 同步错误文案绕过 L10n，UI 靠 `contains("remote format")` 字符串匹配补救 | M |
| SY-05 | `JournalSyncEngine.swift:199-200` | `resolveConflict(.local)` 直接落盘不 flush 编辑器草稿，用户选择可被旧草稿覆盖 | S |
| DS-03 | `JournalStore.swift:840-852` | 非活跃本 `persistEntries` 走主线程同步写、绕过 persistQueue，且 `.bak` 先删后拷失败即永久丢失 | M |
| DS-04 | `ExchangePositionCoordinator.swift:896-905` | 缓存加载路径在主线程跑全量仓位聚合（与 sync 路径 detached 设计自相矛盾） | M |
| DS-05 | `JournalStore.swift:1948-1956` | 滚动备份时间戳在写盘前推进，写失败后 30 分钟内不再补建备份 | S |
| DS-06 | `JournalImageProcessing.swift:226-230` | `invalidate(filename:)` 实为清空全部 200 条缩略图缓存 | S |
| UI-03 | `JournalRootView.swift:267-272` | ⌘F 聚焦搜索实际已坏（注释与实现不符，焦点被交给 contentView） | S |
| UI-04 | `JournalEditorPane.swift:21,262,337` | 编辑器每次击键重估整个 pane（含全量重排与 ViewThatFits 双版测量） | M |
| UI-05 | `JournalTopBarView.swift:130` + `JournalStore.swift:589-629` | 搜索无防抖，每击键 ≥3 次全库文本扫描 | S–M |
| UI-06 | `ProgressPanelView.swift:753-783` | 导出/导入在主线程同步跑 `ditto` 子进程与逐张图片拷贝 | M |
| TR-02 | `OKXSwapClient.swift:238` | OKX `fillSz` 单位是「张」，`peakSize` 展示量级错误（BTC 放大 100 倍） | S（声明）/L（换算） |
| TR-03 | `TradingPositionModels.swift:222-227` | OKX 手续费返佣（fee>0）被 `abs()` 反转，返佣账户净盈亏少计 2×返佣 | S |
| TR-04 | `BinanceFuturesClient.swift:99,113` | 分块边界闭区间重复成交；public `fetchPositions` 无去庙会双计 | S |
| TR-05 | `OKXSwapClient.swift:49-62,75-87` | OKX 无客户端限速（10 req/2s），大窗口回填易整轮失败 | M |
| TR-06 | `TradingPositionModels.swift:104` + `OKXSwapClient.swift:208-219` | 单向模式保本平仓（pnl=0）生成幻影仓位；OKX `subType` 未解码可消除歧义 | S–M |
| TR-07 | `ExchangePositionCoordinator.swift:480` | funding 去重键 `symbol#time`：币安对冲双 lane 同毫秒资金费会误删一条（需真实数据核实） | S |
| CA-03 | `MacroDayPageView.swift:53` vs `MacroCalendarStore.swift:224-226` | 时区口径分裂：页头/宜忌用本地历，事件与缓存键用中国历 | S |
| CA-04 | `MacroDayPageView.swift:807-824` | FibreGrain 每帧随机重绘：碎页飘落全程颗粒闪烁 | S |
| CA-05 | `TradingCalendarRootView.swift:450-456` | 英文模式下事件栏 tab 命中区按中文宽度硬编码而错位 | S |
| CA-06 | `MacroCalendarModels.swift:84-101` | 宏观解码整天全有或全无（一条坏记录毁全天），与财报行级容错不一致 | S–M |
| CA-07 | `TradingCalendarRootView.swift:517-525` | 纹理主线程同步渲染、两路数据各渲一次、固定 2x（3x iPhone 发虚） | S |
| CA-08 | `CalendarPaperScene.swift:51-68` | PF-02 只停了 warp，SpriteKit 休眠后仍 60fps 空转 | S |
| IO-06 | `EditorView.swift:421-422` | iOS 条目缩略图全尺寸解码、无缓存（macOS 有降采样管线） | M |
| IO-07 | `SwipeBackEnabler.swift:4-20` | 全局污染所有导航控制器 + 手势恒并发，横滑图片可误触发返回 | S–M |
| IO-08 | `SettingsView.swift:603-621` | iOS 导入 journal.json 无确认即覆盖当前活跃本 | S |
| IO-09 | `EditorView.swift:303-313` | iOS 删含图条目不清图片文件，孤儿永驻 `images/` | M |
| WEB-01 | `functions/api/wishlist.js:43-83` | 读改写竞态丢票、无防伪刷（CORS `*`+无 rate limit）、500 回显内部错误、记录 IP 无告知 | M |
| CI-01 | `.github/workflows/release.yml` | 加固轮新建的 `WickPhoneTests` 与 `test/agent-readiness.test.mjs` 不进任何 CI，会腐坏 | S |

### P3（卫生项，随其他改动顺手做）

| ID | 位置 | 问题 |
| --- | --- | --- |
| SY-06 | `JournalSyncEngine.swift` | 1729 行上帝类：`reconcileTradingSnapshot`（~150 行）与删除传播（~130 行）可抽离（M） |
| SY-07 | `JournalSyncBackend.swift:35-42`、`DropboxSyncBackend.swift:395-396` | 死代码：`isTransient` 零调用；`rateLimited(retryAfter:)` 载荷无人消费 |
| SY-08 | `JournalSyncEngine.swift:1652-1662` | 墓碑 GC 注释与代码矛盾；GC 后 `processedJournalTombstones` 移除条目存在复活→自动再导入窗口（建议永久保留） |
| SY-09 | `JournalSyncEngine.swift:1085` + `JournalStore.swift:2213` | `localEntryMatchesSnapshot` 每个决策全量拷贝整本快照（O(N²)）；加单点哈希查询 |
| SY-10 | `KeychainTokenStore.swift:132-141`、`PKCE.swift:9-11` | DevSecretFile 先写后 chmod 有权限窗口；PKCE verifier 吞 `SecRandomCopyBytes` 失败 |
| SY-11 | `L10n.swift:384-386,688-690`、`DropboxSyncBackend.swift:259` | 死 key `progressLow/Burning/Plenty`；`path_display` 回退未小写 |
| DS-07 | `JournalStore.swift:2439`（全文件） | 五类职责单文件，按 catalog/持久化/图片/导入导出/同步桥拆 extension（M） |
| DS-08 | `JournalStore.swift:961-966`、`251-256`、`268` | `deleteItem` 尾部死循环；播种 `try?` 吞错；缩略图缓存失效策略不一致 |
| DS-09 | `JournalStore.swift:1940` | `NSClassFromString("XCTestCase")` 测试嗅探进生产路径，改显式 override |
| DS-10 | `AppSettings.swift:133-136,208-218`、`UpdateChecker.swift:131-147`、`JournalReminderScheduler.swift:126-131` | `checkForUpdatesOnLaunch` 死代码；提醒时间 setter 双重调度；更新版本标记先写后通知（未授权则永久漏通知）；提醒分类注册不随语言切换 |
| UI-07 | `ProgressPanelView.swift:378` | `Text("彩蛋")` 硬编码中文，违反 L10n 约定 |
| UI-08 | `JournalInspectorView.swift:149-162`、`TagChipFlow.swift`、`TraderAlmanac.swift:805-879` | 死代码：`yijiChip` 零调用；`TagChipFlow` 只剩测试引用；`TraderYiJiRow` 生产零调用 |
| UI-09 | `JournalSidebarView.swift:651` 等 4 处 | 同一两位小数 `NumberFormatter` + `format(pnl:)` 重复 4 份，提共享 `PnlFormat` |
| UI-10 | `ScrollBarHider.swift:95-131`、`JournalItemEditorCard.swift:121-125` | KVO 探针无 deinit 兜底；复盘 popover 订阅未过滤的窗口关闭通知 |
| UI-11 | `ProgressPanelView.swift:25,978-983`、`FontPickerView.swift:72`、`JournalRootView.swift:56-57` | 面板主题不随 tick 漂移；body 内新建 DateFormatter；字体枚举首开卡顿；栏宽下限不一致 |
| UI-12 | `JournalEditorPane.swift:337,587` | `?? JournalEntry()` 幻影兜底会渲染不存在的今天 |
| CA-09 | `LunarDate.swift:73,47,81-87` | `cal.timeZone = calendar.timeZone` 自赋值；2100 年后农历表越界（理论） |
| CA-10 | `TraderAlmanac.swift:112-114`、`MacroDayPageView.swift:705` | 注释「3-star」实为 `>=2`；闲日印章英文小字硬编码 |
| TR-08 | `BinanceFuturesClient.swift:6-26` vs `ExchangeTradeClient.swift:4-16` | `BinanceError` 与 `ExchangeClientError` 完全平行重复 + 18 行映射 |
| TR-09 | 三客户端 | 分页循环/transport 闭包/`milliseconds()` 三份重复，可抽共享实现（M） |
| TR-10 | `OKXSwapClient.swift:301,304`、`HyperliquidInfoClient.swift:133,141` | OKX 50102/50011 未分类；HL `feeToken` 未 trim、`tid` 回退碰撞风险 |
| TR-11 | `PositionAggregator.swift:50`、`DailyRealizedPnl.swift:12-22`、`SymbolTagMatcher.swift:117-130` | 不可达 guard；`sumsByOpenDay` 仅测试调用；tag 并列时结果依赖字典序 |
| IO-10 | `PhoneExchangeCoordinator.swift:23` 等 | `refreshInterval` 死代码（iOS 无定时刷新）；缺 `PositionEntryPlanner`；`PhoneTheme` 双轨解析 |
| IO-11 | iOS 杂项 | `PhoneReminderScheduler` 文案硬编码中文；月烛痕刻度硬编码 31；`JournalReviewBadge` 漏传 language；隔离目录名缺 `.` 前缀；Debug/Release 共用 dev bundle id |
| WEB-02 | `functions/_middleware.js`、`scripts/subset_landing_font.sh:18` | 无安全头（nosniff/CSP/frame-ancestors）；字体子集引用可变 main 分支无 pin/校验 |

## 3. P1 详情与修法

### TR-01 Hyperliquid 资金费翻页阈值错误（已复核）

`Sources/WickTrading/HyperliquidInfoClient.swift:72`：`fetchFills` 与 `fetchFunding` 共用续页条件 `guard page.count >= min(pageLimit, 2000)`。HL 官方文档「Pagination」节明确：带时间范围的响应**最多返回 500 条**（[Info API](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint)），只有 `userFillsByTime` 单独声明 2000。资金费满页 500 < 2000 → 只取第一页即停。活跃账户（资金费每小时每币一次，3 个月窗口可达数千条）`fundingPnl`/`netPnl` 失真。另 `:68` 页数上限 8 页按 2000 条/页设定，修阈值后需同步放宽（500×8 仅覆盖 4000 条）。

- 修法：funding 独立常量 `fundingPageCap = 500` 作续页阈值，页数上限提至 ~64。
- 测试：假 transport 首页返回满 500 条，断言发出第二请求且结果合并（`HyperliquidInfoClientTests`）。

### CA-01 TraderAlmanac 种子跨进程不确定（已复核）

`Sources/WickCalendarKit/TraderAlmanac.swift:100-104`：`Hasher` 默认带每进程随机种子（SE-0206，仓库未设 `SWIFT_DETERMINISTIC_HASHING`），与第 99 行注释 "Deterministic integer seed" 直接矛盾。同一天每次重启 App 宜忌/印章都不同，双端也不同。`Tests/WickCalendarKitTests/TraderAlmanacTests.swift:14` 在单进程内调两次，**永远测不出**（假绿）。

- 修法：换纯整数种子，如 `seed = year * 10000 + month * 100 + day`。
- 测试：断言同一日期与硬编码基准索引一致（锁定跨进程确定性）；补周五 `seed % 3` 门控路由测试。

### SY-01 401 后永不刷新 token（已复核）

`Sources/WickSync/DropboxSyncBackend.swift:391-393` 对任何 401 直接抛 `.needsAuth`；而 `validAccessToken()`（`:164-193`）在本地未过期时反复返回**同一个刚被拒的** access token。Dropbox access token 可被独立吊销（refresh token 仍有效），此时 `isAuthorized` 仍为 true → 同一坏 token → 再 401，循环至本地 expiry（4h−5min）到期才自愈，期间 UI 误导用户重新授权。

- 修法：401 时清空 `accessToken`/`accessTokenExpiry` 并用 refresh token 重试一次，仍 401 才抛 `needsAuth`。
- 测试：该文件目前**零测试**；补基于 URLProtocol mock 的「401→刷新重试→成功/再 401→needsAuth」两路径。

### DS-01 只读态导出覆盖好归档（已复核）

`Sources/WickCore/JournalStore.swift:1193`：加载失败进 `isReadOnlyDueToLoadFailure` 时 `load()` 已清空 `entries`（`:1907`），导出只跳过 flush，随后照样编码空快照并原子替换目标 zip。「禁止写盘」保护了 journal.json，却没保护导出产物。

- 修法：导出开头 `guard !isReadOnlyDueToLoadFailure else { throw … }`。
- 测试：构造损坏 journal.json 的 store，断言导出抛错且既有目标文件字节不变。

### DS-02 导入中途失败删光图片（已复核）

`Sources/WickCore/JournalStore.swift:1311-1325`：先 `removeItem(at: imagesDirectory)` 删光现有图片，再逐张 `try copyItem`；任一拷贝抛错即退出，内存 entries 未替换但**原图片目录已物理删除**（`.bak` 只含 journal.json，不含图片）。

- 修法：现有 images 先移到同卷 quarantine 目录，全部成功后删 quarantine、失败移回（复用 deleteJournal 同事务模式）。
- 测试：failpoint 让第 N 张拷贝失败，断言原图片目录字节不变。

### UI-01 侧栏非活跃本统计 = 每渲染读盘+聚合（已复核）

`Sources/WickCore/JournalSidebarView.swift:98-99`：body 中对每本调 `store.entryCount(for:)`（非活跃本 → `loadEntriesFromDisk` 读盘+整本解码，`JournalStore.swift:721-731`）与 `positionsCount(for:)`（→ `loadSnapshot` + `PositionAggregator.aggregate` 全量重跑，`ExchangePositionCoordinator.swift:211-217`）。侧栏 `@EnvironmentObject store` 任何 `@Published` 变化（搜索每击键）都重估。

- 修法：每本条数/仓位数做成目录加载时算好、变更失效的内存缓存（或入 `JournalInfo` 派生快照）。
- 验证：两本以上、其一绑交易所，搜索连续输入，Time Profiler 看主线程。

### UI-02 Lightbox 逐帧读图（已复核）

`Sources/WickCore/JournalImagePreviewOverlay.swift:110-111`：`GeometryReader` 闭包内 `store.loadNSImage(filename:)` = 无缓存 `NSImage(contentsOf:)`（`JournalStore.swift:1058-1061`）；`scale`/`offset` 为视图 `@State`，手势每帧改 state → 每帧重读盘。

- 修法：按文件名 `.task(id:)` 加载一次进 `@State`（或加小型 LRU），手势只改变换参数。
- 验证：手动双击放大/拖拽观察掉帧；Instruments 看 `NSImage(contentsOf:)` 频次。

### CA-02 顶页纹理不随加载态刷新

`Sources/WickCalendarKit/TradingCalendarRootView.swift:85-107`：纹理刷新只挂 `currentDate/events/earnings/page/tab/sortOrder` 的 onChange。空结果成功（值相等不触发）或失败（只写 `state.error`）时不重渲；`onAppear` 先取数后渲染的时序使首版纹理恒含 `isLoading=true` → 闲日永久卡「加载中」（「休市/本日无事」印章上不了顶页）、失败日错误态不可达；撕走一页才「自愈」。

- 修法：补 `.onChange(of: store.isLoading(for: currentDate))` 与 errorText（含财报路）→ `refreshPageTexture()`。
- 测试：DEBUG fetch seam 返回 `[]`/抛错，断言纹理重渲计数增加。

### IO-01 iOS `.bak` 轮换主线程全量解码

`ios/WickPhone/PhoneJournalStore.swift:826-833`：`persist()` 里为轮换 `.bak` 先 `loadSnapshot(from: databaseURL)`（同步读盘+完整解码），每次编辑保存都执行，与类头注释「never run on the main thread」矛盾；macOS 对应实现明确不重解码且在后台队列。

- 修法：轮换移入 persistQueue 写入闭包，存在性判断用 `fileExists`。
- 测试：大日记 fixture 下断言主线程无解码耗时；回归 `WickPhoneTests`。

### IO-02 退后台 flush 无后台任务保护

`ios/WickPhone/WickPhoneApp.swift:74-84` + `PhoneJournalStore.swift:885-907`：`.background` 时在主线程 semaphore 等写盘队列 drain，无 `UIApplication.beginBackgroundTask`。系统可在 handler 返回后随时挂起（丢 pending generation，靠原子写不损坏、下次启动恢复）；慢盘则主线程阻塞触发 0x8badf00d。上一轮复验清单 §6 本就要求真机验证此路径。

- 修法：flush 用 background task 包裹，expiration handler 结束任务。
- 验证：真机「编辑→立即锁屏→杀进程重开」内容仍在；Console 无 watchdog。

### IO-03 ASWebAuthenticationSession 永久悬挂

`ios/WickPhone/PhoneSyncCoordinator.swift:262`：`session.start()` 返回 `false` 时 completion 永不回调 → `withCheckedThrowingContinuation` 永不 resume → 「连接中」状态不复位。

- 修法：`guard session.start() else { continuation.resume(throwing: …) }`。
- 验证：断网/无窗口场景手动验证连接按钮可重试。

### IO-04 iOS 交易任务无身份守卫（EX-01 未移植）

`ios/WickPhone/PhoneExchangeCoordinator.swift:175-210`：`syncNow` 完成后直接写回快照，不校验 binding 是否仍存在/journal 是否在 catalog/任务是否被取代。macOS 有完整守卫（`ExchangePositionCoordinator.swift:114-119,553-561`）。fetch 在途时解绑/删除 → 旧请求写回孤儿快照，开启云同步还会经 `cloudSnapshotDocument` 上传。

- 修法：移植 generation/cancel 守卫（参照 macOS 实现）。
- 测试：`WickPhoneTests` 注入慢客户端，解绑后断言快照文件不存在。

### IO-05 盈亏月历点击语义错误

`ios/WickPhone/DayListView.swift:83-92`：点无日记的历史日走 `store.openOrCreateToday()`，打开的是今天而非该日；且 `PhoneJournalStore` 缺 macOS `createEntry(on:)` 的按日创建入口。

- 修法：Store 增 `createEntry(on:)`（含同日去重），回调按选中 dayKey 建/开。
- 测试：点上月某日 → 编辑器页眉显示该日；重复点击不重复建。

### TE-01 失效的同步回归测试（已复核）

`Tests/WickSyncTests/JournalSyncEngineTests.swift:566,571`：`downloadBlocker` 匹配 `hasSuffix("days/2026-08-02.json")`，但 sync v2 远端路径是 `entries/<uuid>.json`（`JournalSyncState.swift:32`），blocker 永不命中、300×10ms 轮询恒超时，AC-P1-05「下载在途时本地编辑」竞态从未发生，断言平凡通过。

- 修法：改为按 entryID 对应的真实远端路径匹配（从 state/fixture 取 entries 路径）。
- 验证：临时在引擎里打印/断言 blocker 真的拦截到一次下载（测试应能在无本地编辑时走到下载点）。

## 4. P2 修法要点（按批次）

- **同步批**（SY-02~05）：marker 遍历改为「任一匹配即清除」；`recordConflict` 挪到上传成功后或按 `(entryID, summary)` 去重；`Status.error` 改类型化 enum、视图层走 L10n；`resolveConflict(.local)` 补 `prepareForRemoteApply`。各配假后端测试。
- **存储批**（DS-03~06）：统一非活跃本写盘走 persistQueue、`.bak` 失败至少记 `lastPersistError`；缓存加载路径聚合挪 detached 或物化进缓存；滚动备份时间戳改在写成功回调推进 + 旧代际失败 NSLog；缩略图缓存改按 key 删除。
- **UI 批**（UI-03~06）：⌘F 真发通知聚焦顶栏搜索框；`daySection` 拆独立 View 让相等性挡重估；`searchText` 加 200–300ms 防抖提交；导出/导入挪 `Task` 后台 + 进行中状态。
- **交易批**（TR-02~07）：OKX 短期至少在注释/文档声明「张」单位（长期拉 instruments `ctVal` 换算）；归一化入口统一手续费符号约定（OKX 取负），去掉 `abs()`；Binance 下一块起点 `chunkEnd + 1ms`；OKX 页间 ≥220ms 或 50011/429 指数退避；解码 OKX `subType` 填 `effect`；TR-07 先用真实对冲账户数据核实再决定是否给键加 lane 维度。
- **日历批**（CA-03~08）：页头/宜忌统一中国历（或同一来源）；FibreGrain 改 `SeededRandom`（顺带修分享图一致性）；tab 边界按当前语言实测文案宽度；宏观改逐条容错解码；纹理刷新去抖合并 + 满屏用 `displayScale`；休眠时 `scene.isPaused = true`。
- **iOS 批**（IO-06~09）：缩略图走 ImageIO 降采样 + NSCache；SwipeBackEnabler 限定自有栈；导入前确认弹窗（显示将替换条数）；删条目经 `imageURL(for:)` 删文件。
- **Web/CI 批**（WEB-01、CI-01）：wishlist 的 votes/emails 拆 key 或上原子计数、加 Origin 白名单与长度上限、500 改固定文案；release.yml 加 iOS Simulator `xcodebuild test` 步骤、landing.yml 加 `node --test test/`。

## 5. 专项

### 5.1 双端重复（最大可维护性债）

`ios/WickPhone/PhoneJournalStore.swift`（1144 行）约 **85% 是 `JournalStore`（2439 行）的复制或改写**，近乎逐行重复 25 组（删除事务回滚、catalog 持久化、同步桥接 `applySyncedEntry`/`mergeSyncedDateCollision`/`localEntryStillMatches` 等）。漂移已实证：日期碰撞合并的 `updatedAt`/selection 处理两端已不同；EX-01 守卫 iOS 缺失（IO-04）；iOS 多出主线程解码回归（IO-01）。其他平行对：`PhoneSyncCoordinator↔SyncCoordinator`、`PhoneExchangeCoordinator↔ExchangePositionCoordinator`、`PhoneFont↔AppFont`、复盘/预览/盈亏月历视图，合计约占 iOS 代码 55–60%。`ReceiptShape` 双端**同名不同实现**（锯齿 vs 噪声撕边），最易误导。

- 建议（AR-01，L）：把 catalog 事务、删除/回滚、合并、`JournalLocalSource` 桥接下沉为 `WickSync` 平台无关层（可消 ~900 行重复）；UI 层重复在 iOS v0 阶段可接受。非本轮必须，但每修一个双端共有 bug 都在付两遍成本。

### 5.2 测试缺口

- **失效/伪测试（优先）**：TE-01；`JournalDatePickerTests.swift:49-73` 把设置页渲染 PNG 写到硬编码个人路径且零断言（伪测试，删或改真断言）；`TimeProgressTests.swift:73-96` 只断言 0<f<1 不验证周一开头语义。
- **零测试的关键逻辑**：PaperTear 撕口几何、FallPlan Catmull-Rom、JournalReminderScheduler（触发时间计算/包形态门控）、JournalImageProcessing 降采样、PKCE S256、DropboxSyncBackend 错误分类（409/429/401）、MacroCalendarClient 的 `[start,end)` 过滤、滚动备份（5 份上限/30 分钟间隔，JournalStoreTests 40 用例零覆盖——DS-05 无护栏）、MenuBarExtraPanel 尺寸护栏与窗口几何启发式。
- **交易所缺口**：HL funding 翻页（TR-01 正漏在这）、OKX 多页/50102/50011/subType、Binance 分块边界去重、聚合器同毫秒双笔排序、FundingAttributor 边界（事件恰在 closeTime）。
- 脆弱点：`JournalSyncEngineTests.swift:1787,1808` 等 10–20ms 固定 sleep（改条件轮询）。

### 5.3 文档漂移（截至今日仍未回填）

- AGENTS.md：`WickTheme.swift`（主题引擎）记在 WickCore（第 37 行），实际已在 `Sources/WickCalendarKit/WickTheme.swift`（WickCore 同名文件只剩 40 行 `WickPrintFont`），双 target 同名文件的 footgun 无记录；`BurnStripView.swift`/`JournalReviewBadge.swift` 同样已迁（第 42 行）；`TraderAlmanac.swift`（936 行新系统）与页面图片分享（ImageShare）全文无一字；`test/`、`functions/` 未记录；「UI 层无测试」已过时（现有视图级测试）；iOS 节未提链接 `WickTrading`；`WickDateFormat.swift` 未记录。另：`WickThemeTests` 仍挂在 `WickTests`，引擎本体已下沉，建议迁往 `WickCalendarKitTests` 保留对比度护栏。
- README.md：WickTrading 章节漏 OKX/HL/DailyRealizedPnl/FundingAttributor；交易日历章节未提宜忌与图片分享。
- docs/ 三份加固文档：抽查 7 项声称已修复的机制全部真实存在（仅行号与测试计数过时），结论可信。

## 6. 工作包与实施顺序

| 包 | 内容 | 预计 | 验收 |
| --- | --- | --- | --- |
| WP-A 快修 | TR-01、CA-01、SY-01、DS-01、TE-01 + 各自测试 | ~1.5 天 | `swift test` 全绿；新增 5 个针对性测试通过 |
| WP-B 数据安全事务化 | DS-02（导入 quarantine 事务） | ~1 天 | failpoint 测试：图片拷贝失败原目录不变 |
| WP-C 渲染路径 I/O | UI-01、UI-02、CA-02 | ~1 天 | Time Profiler 击键无读盘；断网首启日历出错误态而非卡加载 |
| WP-D iOS 正确性 | IO-01~05 | ~2–3 天 | `WickPhoneTests` 增补 ≥4 用例；真机后台 flush 验证 |
| WP-E 同步/交易正确性 | SY-02~05、TR-02~07 | ~2 天 | 假后端/假 transport 锁定各分支；TR-07 需真实数据先核实 |
| WP-F UI 响应性 | UI-03~06 | ~1–2 天 | ⌘F 聚焦恢复；大日记本搜索/打字无卡顿 |
| WP-G CI/文档/网页 | CI-01、WEB-01、WEB-02、WEB-03、文档漂移回填 | ~1 天 | 故意改坏被测断言 CI 变红；AGENTS.md 与文件清单一致 |
| WP-H 结构（可选） | SY-06、DS-07、TR-08/09、AR-01 | ~3–5 天 | 纯重构行为不变，现有全部测试原样通过 |

顺序建议：WP-A → WP-B → WP-C → WP-D → WP-G → WP-E/F → WP-H。WP-A/B/C 全是 S–M 工作量且各自独立；WP-H 只在功能空窗期做，AR-01 之前先完成 WP-D/E 中所有双端共有修复（否则下沉时带着两份不同实现）。

## 7. 验证记录与免责

- 全部 14 条 P1 均已回代码复核（file:line 见上文）；HL「500 条/响应」依据官方文档 Pagination 节；OKX「张」单位、返佣符号、限流值依据 OKX v5 文档。
- 复核中**证伪并剔除**一条初审发现：iOS `entryCount` 解码器策略错误（实际 `PhoneJournalStore.loadSnapshot` 正确使用 `JournalSyncEncoding.decoder`，与 macOS 一致，不成立）。
- P2/P3 条目均有代理报告级的 file:line 证据，其中 UI-01/02、SY-01/02/03/05、CA-01、TR-01、DS-01/02、TE-01、WEB-01 由主审逐一复核；其余 P2/P3 建议实施前花 5 分钟对照行号再确认一次。
- 本轮未做：真实 Dropbox/交易所网络验证、iPhone 真机测试、Instruments 大数据量实测——与上一轮一致，属发布前人工验证项。
