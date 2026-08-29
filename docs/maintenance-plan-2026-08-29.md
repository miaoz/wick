# 维护工作清单（2026-08-29 归档）

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
