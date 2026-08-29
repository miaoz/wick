# 维护工作清单（2026-08-29 归档）

## 执行状态更新（2026-08-29 晚，含 git status 中未提交的改动）

- **T1 · UI-04** ✅ 完成：`daySection` 拆为独立 `JournalDaySection`（Equatable + `.equatable()`），`JournalItemEditorCard` 同加 Equatable（数据域相等挡住重估），`drafts`/`dirtyEntryIDs` 归属不变；IME 编辑路径未动。
- **T2 · SY-09** ✅ 完成：`JournalLocalSource` 新增单点 `syncEntrySnapshot(entryID:)`（协议 + 桥 + macOS/iOS store + 测试假源），`localEntryMatchesSnapshot` 改单点读，整本拷贝 O(N²)→O(N)，ED-01 新鲜度语义不变（原测试全绿）。
- **T5 · SY-06** ✅ 复核确认已由 `1b3a088`（WP-H）完成：删除传播 / 交易快照已在 `JournalSyncEngine+{DeletionPropagation,TradingSnapshot}.swift`，主文件不再内联。
- **T6 · TR-08/09** ✅ 复核确认已由 `1b3a088`（WP-H）完成：错误统一 `ExchangeClientError`、`milliseconds`/`defaultTransport` 共享；OKX pacing / HL fundingPageCap 按 AGENTS 保留各客户端。
- **待复核池** 已逐项复核：修复 SY-07（删死 `isTransient`）、SY-08（墓碑 GC 后保留 `processedJournalTombstones`，防复活再导入，新增回归测试）、DS-08（删 `deleteItem` 尾死循环）、DS-10（删死别名、UpdateChecker 先通知后标记防永久漏通知、提醒分类随语言重注册）、TR-10（OKX 50102→recvWindow、HL `feeToken` trim，新增测试）、TR-11（`PositionAggregator` 不可达 guard、`preferredTag` 并列字典序确定性，新增测试）、IO-10（删 iOS 死 `refreshInterval`）。复核后无需改动：DS-09（XCTest 嗅探为可靠惯例，显式 override 需动全部测试 setup 且有 flaky 风险）、播种 `try?` 吞错（激活时自愈）、`sumsByOpenDay`（有测试的公共 API）、`rateLimited(retryAfter:)` 载荷、提醒时间 setter 双重调度（幂等）。
- **T3 / T4** 仍阻塞于真实数据 / 真机 / 外部 API，需人工验证，非无人值守。

## 批次二实测进展（追加）

- **T3 · TR-07 ✅ 已用真实数据核实，无需改代码**：用本地 Keychain 凭证直连 `fapi.binance.com/fapi/v1/income`（`scripts/fetch_binance_income.py`）拉取「手工交易」账户全部资金费历史（2026-02-26~08-29，120 条，总额 -14.99807875 USDT），`scripts/funding_dedup_check.py` 检测 **0 个 `symbol#time` 碰撞**；App 缓存 funding（57 条 / -8.7113665）与抓取时刻 API 可见数据**逐条一致**。结论：该账户实际使用中 `symbol#time` 去重键无误删，不启用对冲双 lane 场景则无需改键（若未来启用对冲且同 symbol 同毫秒出现两条，再按 `symbol#time#金额`/`tranId` 改）。另注意 `desiredWindowStart` = 最早日记条目日期，App 只拉该窗口起的数据（非固定 180 天）。
- **T4-3 · HL funding ✅ 已用真实 API 核实**：用「形态策略」本绑定的 0x 地址（公开，无需密钥）直连 `api.hyperliquid.xyz/info userFunding`，App 缓存 funding（136 条 / +6.008619）与真实 API **逐条一致**（0 差异）；本次窗口 <500 条未触发 500/页翻页，翻页逻辑仍需大窗口样本。
- **T4-2（OKX，用户暂未交易）、T4-1（Dropbox 双端）、T4-4（iPhone 真机）** 待用户实测；T4-5 大库数据层已测（见 checklist），另发现并调查一处现存 bug（见下）。

## 日记窗口打开即 ~25–32% CPU（已修复，2026-08-29）

**现象**：打包版 v1.10.31 与源码 dev 构建均复现——日记窗口打开即持续 ~25–32% CPU（仅菜单栏 = 0%），任意本、任意天、是否含今天烛焰都一样。

**机制**（`sample` 定位）：主线程每 display cycle 跑 `NSHostingView.layout → ViewGraphRootValueUpdater.render → beginNextUpdate → AG::Graph::value_set → graphInvalidation → requestUpdate → setNeedsUpdate` 的**布局反馈环**（SwiftUI 每帧写回一个值→又失效）。

**二分结果**（均以窗口打开 + `ps` 采样验证）：
- 主内容（BISECT-1）→ 编辑器（BISECT-2）→ 时间轴 day sections（Test A）→ **dayBurnStrip（Test D：去掉→0%）**。
- 已排除：今天烛焰（8月1日静态也循环）、dayHeader `ViewThatFits`（Test B）、条目卡（Test C）、`BurnStripView` 内部（Canvas 重写无效）、编辑器 `.onChange(of: store.entries)`（Test F）。
- **未定位到具体每帧触发源**：烛痕条「存在即循环」（几何/内容无关），疑与 LazyVStack 内 day section 的尺寸/偏好反馈有关。

**根因**：`JournalDaySection` 对今天的 `BurnStripView` 传入 `flameAnimates: true`，内部 `FlameDot` 的 `repeatForever` 呼吸动画按 DisplayLink 持续失效整个日记 `NSHostingView`。时间轴初始布局会先挂载今天页；`LazyVStack` 滚到历史日期后仍可能保留或延迟回收该页，因此此前“8 月 1 日静态页也循环”的排除结论实际没有证明火苗已离开 ViewGraph。

**逐层复核**（macOS 26.6.2 / Apple Silicon，源码 debug 构建）：保留原 `GeometryReader`、三个 `.position`、越界光晕/阴影、背景/刻度/污渍/边框/余烬线并逐项加回，进程均为 0.0% CPU；最后仅加回 `FlameDot(isBreathing: true)` 即恢复约 19–20%。将日记调用点固定 `flameAnimates: false` 后，火苗外观保留为静态，5 秒 `sample` 的 4249 个主线程样本全部停在 `mach_msg`，`NSHostingView.layout` / `NSDisplayCycleFlush` / `RepeatAnimation` 均为 0 帧。

**修复**：日记时间轴永不启用火苗呼吸；菜单栏面板仍按真实可见性启用动画。未改窗口 hosting/container 布局，也未改 `BurnStripView` 的共享绘制实现。

---

近期无新功能开发计划，本清单汇总当前全部在案的延后任务，作为下一阶段的工作依据。

- 来源：`docs/code-review-optimization-plan-2026-08-28.md`（WP-A~G 已于 316cc91 完成）、`docs/cpu-optimization.md`（P0 已于 7cdc297 完成）、两轮会话的代码复核
- 状态基准：main @ aeeb8f3（v1.10.31），382 macOS + 12 iOS + 25 node 测试全绿
- **本清单已逐项对照代码复核**——远端 CPU 文档 P1-10 所列 UI-01/02/05 实际已于 316cc91 修复（详见下文校正记录），勿按其编号直接开工

---

## 状态校正（复核结论，防误报）

| 项 | 审查文档描述 | 复核结果 |
|---|---|---|
| UI-01 侧栏统计 | 非活跃本每渲染读盘+聚合 | ✅ 已修：`JournalSidebarView.swift` 走 `journalStats` 失效缓存，非活跃本不读盘 |
| UI-02 Lightbox | 每帧重读全尺寸图 | ✅ 已修：全图按文件名一次加载进 `@State loadedImage`，手势只改变换参数 |
| UI-05 搜索防抖 | 每击键 ≥3 次全库扫描 | ✅ 已修：`JournalTopBarView` 防抖后提交 `store.searchText` |
| UI-06 导出导入 | 主线程跑 `ditto` + 逐张拷贝 | ✅ 已修：归档构建已挪后台任务 |
| AR-01 共享核心下沉 | catalog 事务/桥接下沉 WickSync | ✅ 已修：`JournalLibraryCore` 双端一份（架构加固轮） |
| DS-07 JournalStore 拆分 | 五类职责单文件 | ✅ 已修：主文件 + `JournalStore+{Catalog,Content,Media,Persistence,SyncBridge}` |

---

## 批次 1：下一步直接做（纯本地，有测试护栏，约 1–2 天）

### T1 · UI-04 编辑器击键重估整个 pane

- **位置**：`JournalEditorPane.swift:333`（`daySection` 仍是函数，未拆独立 View；审查时另见 21、262、337）
- **问题**：每击键整棵编辑器树重估——所有日期区块全量重排 + `ViewThatFits` 单行/两行双版测量（`:382`）。大日记本（几十天、长文）打字掉帧
- **修法**：`daySection`（及条目行）拆成 Equatable 子视图，相等输入挡住重估；`drafts`/`dirtyEntryIDs` 状态归属保持不变
- **验收**：Time Profiler 下连续击键只重估当前编辑区块；中文 IME 组合全程无吞字（AGENTS：编辑必须走 `IMESafeTextViews`，勿动）；`swift test` 全绿
- **工作量**：M ｜ **风险**：IME 敏感区，动布局前先读 AGENTS 日记窗条目

### T2 · SY-09 同步决策 O(N²) 快照拷贝

- **位置**：`JournalSyncEngine.swift:990`（`localEntryMatchesSnapshot`；调用点 585 / 852 / 926；审查时行号 1085）
- **问题**：每次调用执行 `localSource.syncEntrySnapshots()` 全量拷贝整本条目快照，一轮同步 N 个决策 × O(N) = O(N²)
- **修法**：按审查建议加**单点查询**（按 entryID 取单条 + 单点哈希），不做轮级缓存——语义上每次调用必须读到**新鲜**落盘状态（ED-01 flush 后新鲜度重读），缓存会破坏同步三不变量
- **验收**：大库（万条）同步轮快照拷贝次数从 O(N²) 降为 O(N)；`WickSyncTests` 假后端全部原样通过，无行为变化
- **工作量**：S–M ｜ **风险**：同步引擎是数据安全最高优先级区，改前重读 AGENTS「同步（sync v2）」节

---

## 批次 2：发版前人工验证（约半天–1 天 + TR-07 视数据）

### T3 · TR-07 funding 去重键核实（在案两轮，阻塞于真实数据）

- **位置**：`ExchangePositionCoordinator.swift:480`（审查时行号）
- **问题**：去重键 `symbol#time` 在币安对冲双 lane 同毫秒两条资金费时误删一条
- **动作**：用真实币安账户（需对冲模式）拉 funding 历史，核对是否存在同 symbol 同毫秒多条；若存在，去重键改 `symbol#time#金额`（或 tid）
- **验收**：真实数据下 funding 总额与交易所账单一致

### T4 · 外部世界验证组（发布前人工项，一直在案）

| 子项 | 内容 | 通过标准 |
|---|---|---|
| Dropbox 真实回归 | 双设备 sync v2 全链路：拉/推/冲突/删除传播/墓碑 GC | 三不变量成立：无自冲突、拉取即定点、rev 回声抑制 |
| OKX funding 真实 API | 私有接口翻页 + `fundingBackfilled` 全量回填（限速 ~10 req/2s） | 与 OKX 账单一致；之前从未对真实 API 验证过 |
| HL funding 真实 API | `userFunding` 500 条/页 cap 翻页 | 与 Hyperliquid 账单一致 |
| iPhone 真机 | 后台 flush（IO-02 watchdog 观察）、撕页、长按分享、图片预览 | 后台切换无崩溃、无数据丢失 |
| Instruments 大库实测 | 万条级日记本：侧栏切换、搜索、打字、同步轮 | 无读盘于渲染路径；同步轮内存峰值平稳 |

---

## 批次 3：结构项（功能空窗期做，约 2–3 天）

### T5 · SY-06 同步引擎拆分

- **位置**：`JournalSyncEngine.swift`（1729 行上帝类）
- **修法**：`reconcileTradingSnapshot`（~150 行）与删除传播（~130 行）先抽 extension；不合并进共享核心（那要等批次 2 验证通过后按 AR-01 的路径走）
- **验收**：纯搬移行为不变，全部测试原样通过

### T6 · TR-08/09 交易客户端去重

- **位置**：`BinanceFuturesClient.swift:6-26` vs `ExchangeTradeClient.swift:4-16`（错误类型完全平行重复 + 18 行映射）；三家客户端的分页循环 / transport 闭包 / `milliseconds()` 三份重复
- **修法**：错误类型归并到 `ExchangeClientError`；分页等抽共享实现
- **验收**：三家客户端测试原样通过；注意 OKX 限速 pacing 与 HL 翻页 cap 参数勿在归并中混淆（AGENTS 交易数值口径节）

---

## 明确不做

- **P1-9 残留**（隐藏面板随 `@Published` 重估）：每次击键一次、非每帧，量级可忽略；动它要加环境注入复杂度，不值得。

## 待复核池（审查文档 P2/P3，未逐项复核现状，开工前先花 5 分钟对照行号）

SY-07（死代码 `isTransient`/`rateLimited`）、SY-08（墓碑 GC 后复活→自动再导入窗口）、DS-08（`deleteItem` 尾部死代码、播种吞错）、DS-09（`NSClassFromString("XCTestCase")` 测试嗅探进生产）、DS-10（设置死代码/双重调度/漏通知）、TR-10（OKX 50102/50011 未分类、HL `feeToken` trim）、TR-11（tag 并列字典序）、IO-10（iOS 死代码与双轨解析）。

---

## 建议执行顺序

```
T1 (UI-04) → T2 (SY-09)          批次 1，本地可做
T4 验证组 + T3 (TR-07)           绑下一次发版
T5 (SY-06) → T6 (TR-08/09)       空窗期；若期间修了双端共有 bug，先按 AGENTS 下沉共享核心再重构
```
