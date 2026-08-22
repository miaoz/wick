# Wick 架构加固验收报告

> 本文件为上一轮验收记录；最新复验结论见 [architecture-hardening-reacceptance-report-2026-08-22.md](./architecture-hardening-reacceptance-report-2026-08-22.md)。

> 验收基线：`main@e386357` 及当前工作区未提交加固改动  
> 验收日期：2026-08-22  
> 对照文档：`docs/architecture-hardening-plan.md`  
> 验收结论：**不通过，暂不建议合并**

## 1. 结论摘要

本轮加固已经覆盖大部分计划项，并通过现有单元测试、iOS 构建、Universal 打包和签名验证。图片路径边界、非当前日记安全 I/O、同步批量持久化、编辑器草稿 rebase、交易任务 token、日历缓存 single-flight、iOS 首页刷新隔离和 CI 守门均有实质改进。

但当前实现仍存在以下未关闭问题：

- P0：1 项，iOS 全新安装无法创建首个日记本。
- P1：7 个工作项，涉及 catalog 恢复、远端删除事务、同步 freshness、交易任务交错状态和导出原子替换。
- P2：2 项，涉及日历 reset 后重绘和 iOS 主线程持久化。

P0 会直接阻断 iPhone 客户端首次使用；P1 中包含可能覆盖新编辑、错误确认远端删除以及丢失旧导出备份的数据安全问题。因此不能仅凭当前 266 个测试全部通过判定可合并。

## 2. 验收范围

本次检查覆盖当前工作区中的 26 个已修改 tracked 文件、2 个新增测试文件及相关文档，约 2244 行新增、336 行删除，重点核对：

1. `DS-01` 至 `DS-04` 数据安全与导出一致性。
2. `SY-01`、`ED-01`、`PF-01` 同步、草稿和批量提交。
3. `EX-01` 交易任务身份、取消和跨日记隔离。
4. `PF-02`、`PF-03`、`CA-01` 常驻性能与缓存。
5. `CI-01` iOS、Universal、签名和 zip 产物守门。

验收以静态代码审查、确定性自动化测试和本地构建为主；未连接真实 Dropbox 或交易所，也未执行 iPhone 真机和 Instruments 测量。

## 3. 阻断问题

### AC-P0-01：iOS 首次启动错误进入 catalog 只读

**严重度：P0**  
**位置：** `ios/WickPhone/PhoneJournalStore.swift:67`

#### 现象

`loadOrCreateCatalog()` 使用同一个 `catch` 处理 `Data(contentsOf:)` 和 catalog 解码的所有错误。全新安装时 `catalog.json` 尚不存在，读取抛出的“文件不存在”错误也会进入该分支：

- `isCatalogReadOnly = true`
- `journals = []`
- `activeJournalID = nil`

后续默认日记创建要求 `!isCatalogReadOnly`，因此永远不会执行。用户首次打开 iPhone App 时没有可用日记本，也没有 App 内恢复入口。

#### 修复要求

1. 在读取前显式区分 catalog 是否存在，或只将 `CocoaError.fileNoSuchFile` 映射为 `.missing`。
2. 只有“主文件和 backup 都不存在”才能创建默认日记本。
3. 损坏、空库和未来版本必须继续进入只读，不能退化为首次建库。
4. 为 `PhoneJournalStore` 增加可注入根目录的初始化入口，使首次启动和损坏 fixture 能进入自动化测试。

#### 必须新增的测试

- 空目录初始化后恰好有一个默认日记本，且 `catalog.json` 已写入。
- 主 catalog 截断、空 journals、未来版本时不创建默认本且原字节不变。
- 主文件和 backup 均不存在，与“主文件不存在但 backup 存在”得到不同结论。

### AC-P1-01：macOS catalog 只读后的恢复操作无效

**严重度：P1**  
**位置：**

- `Sources/WickCore/JournalStore.swift:1192`
- `Sources/WickCore/JournalStore.swift:1317`
- `Sources/WickCore/JournalStore.swift:1783`
- `Sources/WickCore/JournalRootView.swift:229`

#### 现象

catalog 加载失败后，Store 清空 `journals` 和 `activeJournalID`，活动路径仍是初始化阶段的 `_pending` 占位目录。UI 随后显示“导入”和“清空并重新开始”，但两个路径都只清除日记内容级 `isReadOnlyDueToLoadFailure`：

- `abandonCorruptDatabaseAndStartFresh()` 不清除 `isCatalogReadOnly`，也不重建 catalog。
- `breakReadOnlyIfImporting()` 不清除 `isCatalogReadOnly`。
- 导入或重新开始会面向 `_pending/journal.json` 工作，catalog 仍不可写，App 仍无活动日记本。
- 导入在校验输入前就清除内容只读；导入失败时还可能让错误 banner 消失，但 library 仍未恢复。

#### 修复要求

1. 将“日记内容恢复”和“catalog/library 恢复”拆成明确 API，禁止共用 `_pending` 路径。
2. library 重新开始时先隔离损坏 catalog，再创建新 UUID、绑定真实目录、写入 catalog，全部成功后才退出只读。
3. library 导入时先完整校验输入，再创建或选择真实日记本；任一步失败都保持原只读状态和原文件。
4. 恢复 API 必须返回错误，UI 不得使用 `try?` 静默丢弃失败。

#### 必须新增的测试

- 损坏 catalog 后执行“重新开始”，重新加载 Store 后存在一个真实可写日记本。
- 损坏 catalog 后导入有效 zip，重新加载后内容可读且不产生 `_pending` 数据库。
- 导入无效文件后仍保持 catalog 只读，原 catalog 字节不变。

### AC-P1-02：主 catalog 缺失时不会恢复有效 backup

**严重度：P1**  
**位置：** `Sources/WickCore/JournalStore.swift:1358`

#### 现象

`loadCatalog()` 只在主文件存在但损坏时尝试 `catalog.json.bak`。主文件不存在时直接返回 `.missing` 并播种新 catalog。若 backup 仍有效，原有日记顺序、名称、active ID 和交易所绑定会被新默认库取代。

#### 修复要求

加载判定应遵循以下矩阵：

| 主文件 | backup | 结论 |
| --- | --- | --- |
| 不存在 | 不存在 | `.missing`，允许首次建库 |
| 不存在 | 有效 | `.restoredFromBackup` |
| 不存在 | 损坏 | `.corrupt`，进入只读 |
| 不存在 | 未来版本 | `.unsupportedVersion` |

恢复主文件时不需要创建“损坏主文件”隔离副本，但必须保留有效 backup，直到新主文件写入成功。

### AC-P1-03：iOS catalog 保护与恢复链路未完成

**严重度：P1**  
**位置：**

- `ios/WickPhone/PhoneJournalStore.swift:94`
- `ios/WickPhone/SettingsView.swift:63`

#### 现象

iOS 虽然使用共享 `JournalCatalogCodec`，但 `persistCatalog()` 仍然：

- 不创建 `catalog.json.bak`。
- 用 `try?` 吞掉目录创建和原子写错误。
- 不向调用方返回持久化是否成功。
- catalog 损坏或未来版本后只有提示，没有导入、恢复 backup 或显式重新开始入口。

这与计划中“catalog 保护等级不低于 journal.json”和“两平台对相同 fixture 得到相同结论”的完成定义不符。

#### 修复要求

优先提取共享的 catalog repository/state reducer；平台 Store 只处理 UI 状态。若暂不提取，iOS 至少必须实现与 macOS 相同的 backup、版本门、缺失矩阵、错误返回和恢复测试。

### AC-P1-04：远端删除在 catalog 提交失败时仍被确认

**严重度：P1**  
**位置：**

- `Sources/WickCore/JournalStore.swift:324`
- `Sources/WickCore/JournalStore.swift:1413`
- `ios/WickPhone/PhoneJournalStore.swift:226`
- `ios/WickPhone/PhoneJournalStore.swift:94`

#### 现象

两个平台的远端删除流程都先删除日记目录，再修改内存 catalog，最后调用不会返回结果的 `persistCatalog()`。即使 catalog 写盘失败，方法仍返回 `.deleted`，Coordinator 随后确认远端墓碑。

可能结果：

1. 本地日记目录已经删除。
2. 磁盘 catalog 仍引用旧 UUID。
3. 远端墓碑已被 acknowledge。
4. 重启时 App 可能创建空目录或无法继续可靠处理删除。

现有 `testRemoteDeleteDirectoryFailureIsIOFailure` 仅覆盖目录删除失败，没有覆盖 catalog 写失败。

#### 修复要求

1. `persistCatalog()` 改为 `throws` 或返回明确 `Result`。
2. 删除目录前先移动到同卷临时隔离位置；catalog 提交失败时回滚目录和内存状态。
3. 只有 catalog、新默认本和活动切换全部提交成功后才返回 `.deleted`。
4. Coordinator 继续只对 `.deleted/.notFound` acknowledge。
5. macOS 和 iOS 使用同一状态转换测试表，并注入可确定失败的文件系统 seam。

### AC-P1-05：mutation 入队后仍可被新编辑穿透 freshness guard

**严重度：P1**  
**位置：**

- `Sources/WickSync/JournalSyncEngine.swift:489`
- `Sources/WickSync/JournalSyncEngine.swift:509`
- `Sources/WickSync/JournalSyncEngine.swift:845`

#### 现象

`pullDay()` 或 `mergeDay()` 在单日 freshness 检查通过后，只把 mutation 放入数组。引擎继续处理其他日期时会执行网络 `await`，用户可以在此期间编辑已经入队的日期。整轮结束调用 `applySyncedChanges()` 前没有再次校验该日 hash。

Store 的批量 apply 会再次 flush 编辑器，但 flush 后立即用已排队的旧 mutation 覆盖该日，因此无法弥补这个时间窗。merge 分支还可能已经把基于旧本地快照的结果上传到远端。

#### 修复要求

1. mutation 携带其决策时对应的 expected local hash。
2. 最终提交前对所有 mutation 再执行一次 draft flush 和 freshness 校验。
3. Store 只提交仍匹配的 mutation，并返回实际提交的 day key。
4. 引擎仅对实际提交的 mutation更新本地基线；被跳过的日期不能保留“已经拉取”的 state。
5. merge 在远端写入前和本地最终提交前都要有一致的身份/新鲜度策略。

#### 必须新增的测试

用可阻塞 fake backend 构造至少两个远端日期：第一个日期 mutation 入队后，在第二个日期下载等待期间修改第一个日期。断言本轮不覆盖新编辑，且下一轮正常合并或推送。

### AC-P1-06：交易任务的 per-journal 状态与清理存在交错错误

**严重度：P1**  
**位置：**

- `Sources/WickCore/ExchangePositionCoordinator.swift:461`
- `Sources/WickCore/ExchangePositionCoordinator.swift:610`
- `Sources/WickCore/ExchangePositionCoordinator.swift:627`

#### 问题 A：切本后 UI 状态未重新派生

`activeJournalDidChange()` 加载新 snapshot 和凭据，但没有调用 `refreshPublishedState()`。从正在同步的 A 切换到空闲的 B 后，`isSyncing` 和 `lastError` 可能继续显示 A 的状态；`refreshIfStale()` 还会因为旧 `isSyncing == true` 跳过 B 的自动刷新。

现有并行测试在切本后手动调用 `refreshPublishedState()`，因此没有覆盖生产路径。

#### 问题 B：旧任务结束会无条件清除新任务

`finishSync()` 的 `defer` 无条件执行 `runningJobs[token.journalID] = nil`。旧任务被取消后，如果用户立即保存新凭据并启动新任务，旧任务稍后结束会清空新任务的 run ID；新任务最终也会因为身份不匹配而丢弃结果。

#### 其他缺口

`pruneDeletedJournals()` 只遍历已有 cache 文件来寻找被删除日记。首次同步尚未生成 cache 时，删除日记不会主动取消对应网络任务，虽然最终提交守卫通常能阻止写回，但不满足“删除即取消”的完成标准。

#### 修复要求

1. `activeJournalDidChange()` 必须立即重新派生当前日记的 busy/error。
2. 清理任务时仅在 `runningJobs[journalID] == token.runID` 时移除该映射。
3. 删除日记时按 `runningJobs.keys - liveJournalIDs` 取消任务，不依赖 cache 文件存在。
4. 测试不得手动调用生产路径本应自动触发的刷新方法。

#### 必须新增的测试

- A 正在同步时直接切到 B，不手动 refresh，B 显示空闲并能启动刷新。
- 取消 run 1 后立即启动 run 2，再释放 run 1；run 2 的身份仍存在且结果成功提交。
- 无历史 cache 的日记在请求中被删除，客户端收到 cancellation。

### AC-P1-07：导出目标替换不是原子操作

**严重度：P1**  
**位置：** `Sources/WickCore/JournalStore.swift:1091`

#### 现象

实现先删除已有目标 zip，再将系统临时目录中的新 zip 移到目标位置。删除成功但移动失败时，用户原有备份已经丢失。这也不满足代码注释和计划中“失败时目标旧文件仍可用”的定义。

当前只读目录测试让删除步骤本身失败，因此无法覆盖删除后、移动前的失败窗口。

#### 修复要求

1. 在目标目录中创建同卷临时文件。
2. 完整生成并校验临时 zip 后，使用 `replaceItemAt` 或等价原子替换。
3. 替换失败时保留旧目标，并清理临时文件。
4. 注入 FileManager/替换 seam，确定性模拟“临时产物成功、最终替换失败”。

## 4. 非阻断但应补齐的问题

### AC-P2-01：`PaperSim.reset()` 没有触发几何 revision

**位置：**

- `Sources/WickCalendarKit/PaperSim.swift:66`
- `Sources/WickCalendarKit/CalendarPaperScene.swift:59`
- `Sources/WickCalendarKit/TradingCalendarRootView.swift:465`

`reset()` 修改了 `pos`、`home` 和 fiber，但没有递增 `geometryRevision`。Scene 只在 revision 变化或显式 `markDirty()` 时重建 warp。换页纹理通常会间接 mark dirty，但 solver 的“reset 后必须绘制新几何”不变量并未成立，纹理生成失败或调用顺序变化时可能保留旧变形。

建议让 `reset()` 递增 revision，或让调用方同时 `paperScene.markDirty()`；新增“动态页面 -> reset -> 下一帧 warp 重建且恢复静止几何”测试。

### AC-P2-02：iOS 全量 JSON 持久化仍在 MainActor

**位置：** `ios/WickPhone/PhoneJournalStore.swift:420`

iOS 的 `persist()` 在主线程解码旧主文件、复制 backup、编码完整 snapshot 并原子写盘。mutation batch 已把首次同步从 N 次整本写降为一次，但大日记本的单次编码与 I/O 仍会阻塞界面，未达到计划中的串行后台 writer 目标。

建议采用“正在写 generation + 最新待写 generation”的串行 writer；`flushPendingWrites()` 必须等待最终 generation，且 backup 语义与 macOS 一致。

## 5. 工作包验收矩阵

| 工作包 | 状态 | 验收判断 |
| --- | --- | --- |
| DS-01 图片路径安全 | 通过 | 共享校验、模型解码拒绝、Store URL 二次边界和负向测试已落地 |
| DS-02 catalog 恢复与版本门 | 未通过 | macOS 主缺失不读 backup、恢复入口失效；iOS 首启和 backup 链路未完成 |
| DS-03 非当前日记安全 I/O | 通过 | typed load result、损坏/未来版本阻断和 backup 测试已落地 |
| SY-01 远端删除事务 | 未通过 | 目录删除失败可重试，但 catalog 写失败仍会返回 deleted 并 acknowledge |
| ED-01 草稿与同步协调 | 部分通过 | flush/rebase 已实现；batch 最终提交前仍有 freshness 时间窗 |
| EX-01 交易任务身份与取消 | 部分通过 | token/generation 已实现；切本状态与旧任务清理存在交错错误 |
| PF-01 同步批量提交 | 部分通过 | 单轮一次 batch/persist 已验证，但需与最终 freshness 提交合并设计 |
| DS-04 一致性导出 | 部分通过 | 最新内存快照和 active journal 冻结已实现；目标替换非原子 |
| PF-02 日历渲染休眠 | 部分通过 | sleeping/texture dirty 测试通过；reset revision 缺失 |
| PF-03 iOS 刷新范围 | 通过 | 每秒 TimelineView 已限制在时间标题和进度区域 |
| CA-01 日历缓存时效 | 通过 | 分 feed TTL、失败保留缓存和 single-flight 测试通过 |
| CI-01 跨平台与签名守门 | 通过 | iOS scheme、SwiftPM iOS target、Universal、签名及 zip 复验已接入 |

## 6. 已执行验证

### 单元测试

```text
swift test
Executed 266 tests, with 0 failures
```

测试输出存在 CoreData `Failed to create NSXPCConnection` 环境日志，但对应测试均通过，未观察到功能失败。

### iOS 构建

```bash
xcodebuild \
  -project ios/WickPhone.xcodeproj \
  -scheme WickPhone \
  -destination 'generic/platform=iOS' \
  build CODE_SIGNING_ALLOWED=NO
```

结果：成功。

```bash
swift build \
  --target WickCalendarKit \
  --triple arm64-apple-ios16.0 \
  --sdk "$(xcrun --sdk iphoneos --show-sdk-path)"
```

结果：成功。

### macOS 正式打包

```bash
make package
```

结果：成功。

- `dist/Wick.app`：x86_64 + arm64 Universal。
- 签名身份：`Wick Local`。
- `.app` 通过 `codesign --verify --deep --strict`。
- `dist/Wick-macOS.zip` 解压后再次通过严格签名和 Universal 架构检查。

### 静态检查

```text
git diff --check
```

结果：通过。

## 7. 复验门槛

修复后必须同时满足以下条件，才可将结论改为“通过”：

1. `AC-P0-01`、全部 `AC-P1-*` 有对应回归测试并通过。
2. iOS 首次启动测试实际创建默认 catalog，不仅验证 scheme 可编译。
3. macOS 与 iOS 对 catalog missing/corrupt/empty/future/backup fixture 使用同一状态矩阵。
4. 远端删除 catalog 写失败时目录和内存状态回滚，Coordinator 不 acknowledge。
5. mutation 入队后发生本地编辑时，本轮不覆盖该编辑，下一轮能够收敛。
6. 交易任务覆盖“旧任务迟到 + 新任务已启动”和“不手动刷新直接切本”。
7. 导出最终替换失败时，旧目标 zip 字节保持不变。
8. 再次通过 `swift test`、iOS generic-device scheme、iOS shared target 和 `make package`。

P2 项可在不影响上述数据安全结论的前提下单独排期，但 `PaperSim.reset()` 建议与本轮 PF-02 一并关闭；iOS writer 至少应记录大 fixture 的主线程基线，避免把性能风险留成无量化债务。

## 8. 验收限制

本次未执行以下外部或人工场景，因此即使修复阻断项，发布前仍需完成：

- 两个真实 Dropbox 设备的本删除、日删除、冲突和断网恢复。
- Binance、OKX、Hyperliquid fixture 之外的真实只读账号验证。
- iPhone 真机输入后立即锁屏/切后台再恢复。
- macOS 13、macOS 26 和 iPhone 的撕页手感与 reset 视觉检查。
- 1000 天日记 fixture 的 Instruments 主线程、内存和磁盘写入对比。
