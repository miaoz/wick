# Wick 架构加固实施计划

> 基线：`main@e386357`  
> 审查日期：2026-08-22  
> 状态：待实施  
> 范围：macOS 主应用、iPhone 客户端、`WickSync`、`WickTrading`、`WickCalendarKit`、打包与 CI

## 1. 目标

本计划把架构审查中确认的问题转化为可以逐项开发、测试和验收的工作包。实施优先级遵循以下顺序：

1. 防止日记数据、目录元数据和用户文件被错误覆盖或删除。
2. 保证同步、编辑草稿和交易任务在切本、断开、删除、退后台时保持一致。
3. 消除首次同步的整库写放大和常驻 UI 的无效刷新。
4. 补齐 iOS、签名和数据恢复的自动化守门。

本轮不调整产品视觉、不更换 Dropbox/交易所协议、不引入第三方依赖，也不改变现有远端目录格式。除非单项设计明确要求，日记和 catalog 的 JSON 版本号保持不变。

## 2. 当前判断

SwiftPM 的模块边界总体健康：

- `WickSync` 和 `WickTrading` 保持平台无关，适合继续承载共享模型与纯逻辑。
- 同步引擎的 rev 回声抑制、固定点基线、冲突三版记录和跨本身份冻结设计完整。
- 交易聚合、同步矩阵和主题计算已有较好的单元测试基础。

主要风险不在模块拆分，而在跨模块事务边界：同步按天应用、存储按整本写盘；交易请求按日记发起、状态却由全局布尔值表达；编辑器持有独立草稿、同步只观察 Store 快照。

## 3. 总体完成标准

全部工作完成时必须同时满足：

- 任意外部来源的图片文件名都不能读写或删除 `images/` 目录之外的文件。
- catalog 或非当前日记损坏、为空、格式过新时，旧客户端不会自动覆盖原文件。
- 远端删除、切换日记、断开交易所和应用退后台后，不存在已确认但未落地的状态。
- 同步应用远端内容时，不会覆盖未提交草稿；成功应用后，编辑器不会保留旧副本。
- 首次拉取 N 天只产生常数次整本持久化，不再排队 N 份完整快照。
- `swift test`、macOS Universal 打包和 iOS generic-device scheme 均进入 CI。
- 打包脚本遇到签名失败必须失败退出，产物必须通过严格签名验证。
- 新增的错误与性能路径都有确定性测试，不依赖真实 Dropbox 或交易所网络。

## 4. 工作包总览

| ID | 优先级 | 工作包 | 主要结果 | 依赖 |
| --- | --- | --- | --- | --- |
| DS-01 | P0 | 图片路径安全边界 | 统一校验所有图片读写删除 | 无 |
| DS-02 | P0 | catalog 恢复与版本门 | 损坏/未来格式不再被覆盖 | 无 |
| DS-03 | P1 | 非当前日记安全 I/O | 交易补建不能覆盖坏文件 | DS-02 |
| SY-01 | P1 | 远端删除事务 | 最后一本也能正确收敛 | DS-02 |
| ED-01 | P1 | 草稿与同步协调 | 未提交编辑不丢、远端应用后不陈旧 | 无 |
| EX-01 | P1 | 交易任务身份与取消 | 旧请求不能写回已解绑/删除日记 | DS-03 |
| PF-01 | P1 | 同步批量提交 | 首次同步消除 O(N²) 写放大 | ED-01 |
| DS-04 | P1 | 一致性导出 | 导出总是包含最新草稿 | ED-01 |
| PF-02 | P2 | 日历渲染休眠 | 静止页面停止 warp 分配 | 无 |
| PF-03 | P2 | iOS 刷新范围 | 每秒只刷新时间相关视图 | 无 |
| CA-01 | P2 | 日历缓存时效 | 当天数据可自动和手动刷新 | 无 |
| CI-01 | P1 | 跨平台与签名守门 | iOS/签名回归阻断发布 | 无 |

## 5. 数据安全

### DS-01：统一图片路径安全边界

#### 涉及代码

- `Sources/WickSync/JournalModels.swift`
- `Sources/WickCore/JournalStore.swift`
- `ios/WickPhone/PhoneJournalStore.swift`
- `Tests/WickSyncTests/JournalSyncModelTests.swift`
- `Tests/WickTests/JournalStoreTests.swift`

#### 实施方案

1. 在 `WickSync` 新增 `JournalImageFilename` 校验工具，作为 macOS、iOS 和同步层唯一规则来源。
2. 安全名称必须是非空的单层相对文件名；拒绝 `/`、`\\`、`.`、`..`、NUL、路径组件和规范化后变化的值。
3. `JournalItem` 解码 `imageFilenames` 时验证每个名称。导入快照或远端日条目包含非法名称时，拒绝整个输入，不做部分清洗和静默丢弃。
4. Store 的图片 URL 构造改为可失败接口，例如：

   ```swift
   func imageURL(for filename: String) -> URL?
   ```

   即使上层模型已验证，URL 构造仍检查 `standardizedFileURL` 位于标准化后的 `imagesDirectory` 内，形成第二道边界。
5. 所有读取、缩略图、粘贴、删除、同步下载和同步上传都必须经过同一接口；删除方法不得再接收未经验证的裸字符串。
6. 加载已有本地快照时发现非法名称，进入现有只读保护，不自动重写文件。错误文案说明数据包含不安全的图片引用，并允许用户走显式恢复/导入流程。

#### 测试

- 接受 `UUID.png`、大小写扩展名和合法空格文件名。
- 拒绝 `../x`、`../../catalog.json`、`a/b.png`、`a\\b.png`、`.`、`..`、空字符串和 NUL。
- 构造目录外哨兵文件，执行删除日记、删除条目、删除图片、同步删除后确认哨兵仍存在。
- macOS 与 iOS Store 共享相同的校验用例。
- 远端非法日条目应报告该日同步失败，不修改本地日记和图片。

#### 完成定义

- 仓库中只有安全 URL 构造器可以访问日记图片。
- `rg "appendingPathComponent\(filename"` 不再出现绕过安全构造器的图片路径。
- 所有负向路径测试通过。

### DS-02：catalog 备份、恢复与版本门

#### 涉及代码

- `Sources/WickSync/JournalModels.swift`
- `Sources/WickCore/JournalStore.swift`
- `ios/WickPhone/PhoneJournalStore.swift`
- `Tests/WickTests/JournalStoreTests.swift`

#### 实施方案

1. 将 catalog 加载结果从 Optional 改为显式状态：

   ```swift
   enum CatalogLoadResult {
       case missing
       case loaded(JournalCatalogSnapshot)
       case restoredFromBackup(JournalCatalogSnapshot)
       case corrupt(Error)
       case unsupportedVersion(Int)
   }
   ```

2. 只允许 `.missing` 创建默认日记。`.corrupt`、`.unsupportedVersion` 和内容为空都不得调用 `seedDefaultJournal()`。
3. 加载时强制检查 `catalog.version <= currentVersion`。未来版本进入只读保护，旧客户端不能重写已知字段或丢弃未知字段。
4. 引入 `catalog.json.bak`。每次覆盖有效主文件前先复制到 sidecar backup，再使用原子写替换主文件。
5. 主文件失败时仅尝试有效且受版本门保护的 backup。恢复成功后保留原损坏文件副本，例如 `catalog.corrupt-<timestamp>.json`。
6. 主文件和 backup 都失败时发布 library 级加载错误，禁用新建、重命名、重排、删除和交易绑定写入。不要为旧 catalog 中的 UUID 自动创建目录。
7. macOS 与 iOS 使用共享的 catalog 解码/版本校验逻辑，平台 Store 只负责 UI 状态和文件操作。

#### 测试

- catalog 不存在时创建一个默认本。
- JSON 截断、空 journals、未知必需字段时不覆盖主文件。
- `version = currentVersion + 1` 时不写主文件和 backup。
- 主文件损坏、backup 有效时恢复 catalog，并保留损坏副本。
- 写 catalog 失败时旧主文件和 backup 至少有一个可加载版本。
- 恢复后日记顺序、active ID、名称和 `exchangeBinding` 不变。

#### 完成定义

- 只有明确的 `.missing` 分支可以首次建库。
- catalog 的保护等级不低于 `journal.json`。
- 两个平台对相同 fixture 得到相同加载结论。

### DS-03：非当前日记的类型化安全 I/O

#### 涉及代码

- `Sources/WickCore/JournalStore.swift`
- `Sources/WickCore/ExchangePositionCoordinator.swift`
- `Tests/WickTests/JournalStoreTests.swift`

#### 实施方案

1. 将 `loadEntriesFromDisk(journalID:) -> [JournalEntry]` 改为带错误语义的结果，至少区分 missing、loaded、corrupt 和 unsupportedVersion。
2. `entries(for:)` 不再用空数组表达加载失败。调用方必须显式处理错误。
3. 非当前日记写入前必须确认：journal ID 仍在 catalog、原文件成功加载或明确不存在、catalog 未处于只读状态。
4. `persistEntries` 使用与当前日记一致的 `.bak`、原子写和错误报告；写入失败不能被 `try?` 吞掉。
5. 交易自动补建只在 loaded 或合法的新空本上执行。corrupt/unsupported 时跳过该本并显示非破坏性错误。

#### 测试与完成定义

- 对损坏、新版本和已删除日记运行自动补建，原文件字节完全不变。
- 对正常非当前日记补建成功，并产生可恢复 backup。
- 已从 catalog 删除的 UUID 不会被重新创建目录。

## 6. 同步与编辑一致性

### SY-01：远端日记删除事务

#### 涉及代码

- `Sources/WickCore/SyncCoordinator.swift`
- `Sources/WickCore/JournalStore.swift`
- `ios/WickPhone/PhoneSyncCoordinator.swift`
- `ios/WickPhone/PhoneJournalStore.swift`

#### 实施方案

1. Store 新增专用的远端删除 API，不复用“用户删除且至少保留一本”的 UI API。
2. 删除最后一本时，事务顺序为：flush 草稿和写盘、删除目标目录、更新 catalog、创建一个新 UUID 的纯本地默认本、切换 active journal、持久化 catalog。
3. 新默认本不能继承被删除本的 Dropbox 状态或交易所绑定。
4. 删除 API 返回明确结果：deleted、notFound、refusedReadOnly、ioFailure。
5. Coordinator 只对 deleted/notFound 调用 `acknowledgeRemoteJournalDeletion`；失败时保留待处理 tombstone，下一轮重试并显示错误。
6. 保持 `remotelyDeletedJournalIDs` 更新与 catalog 事务一致，避免 Store 发布变化时把远端删除重新排队为本地删除。

#### 测试

- 两本删除非当前本、两本删除当前本、最后一本被远端删除。
- 删除目录失败、catalog 写失败和只读保护下均不 acknowledge。
- 新默认本下一轮同步不会复活已删除 UUID。
- macOS 与 iOS 使用同一状态转换测试表。

### ED-01：草稿 session、同步 freshness 与后台 flush

#### 问题约束

同步引擎当前在远端下载后先检查 Store 快照，再进入 `applySyncedEntry` 通知编辑器 flush。未提交 draft 因此不在 freshness guard 的观察范围内；同 ID 远端应用后，编辑器缓存又不会自动重建。

#### 实施方案

1. 在 `JournalLocalSource` 增加远端应用前置步骤，例如：

   ```swift
   func prepareForRemoteApply(dayKey: String)
   ```

   引擎在 freshness guard 之前调用。macOS 实现同步通知对应编辑 session 立即提交；iOS 实现提交当前打开页面的 draft。
2. flush 后重新读取该日规范哈希，再和周期开始时的 expected snapshot 比较。只要 draft 导致内容变化，本轮跳过远端应用，让下一轮进入正常合并。
3. 成功应用后发布带 `journalID/dayKey/entryID` 的 typed event。编辑器只在同日且无本地 dirty 状态时用 Store 新值替换 draft。
4. `JournalEditorPane` 的 draft 记录增加 dirty/revision，而不是用 `saveTasks.keys` 近似 dirty 集合。干净 draft 可安全 rebase，脏 draft 必须先提交或合并。
5. iOS `EditorView` 改为由 dayKey 驱动的 editor session，不再仅依赖 `State(initialValue:)`。session 观察 Store revision，并实现相同的 clean rebase 规则。
6. iOS 页面直接观察 `scenePhase`；进入 inactive/background 时同步 `saveNow()`，然后 Store flush。应用级 flush 不能代替 View draft 提交。

#### 测试

- 网络等待期间编辑同一天：远端本轮不覆盖，下一轮产生合并或本地胜出。
- 远端更新同 ID 的干净页面：UI 和 Store 同时显示新内容。
- 远端更新后第一次键入不会恢复旧 title/body/tag/review。
- iOS 输入后立即 background，重建 Store 后内容仍在。
- IME composition 活跃时不强制截断组字；完成组字后再提交。

#### 完成定义

- freshness guard 覆盖 Store 和编辑 session 中尚未落盘的内容。
- draft 的 dirty 状态由数据表示，不由 Task 是否存在间接表示。
- 关闭窗口、切本、同步应用、导出、退后台复用同一 flush 协议。

### EX-01：交易同步任务身份、取消和隔离

#### 涉及代码

- `Sources/WickCore/ExchangePositionCoordinator.swift`
- `Sources/WickTrading/ExchangeTradeClient.swift`
- 新增 Coordinator 生命周期测试

#### 实施方案

1. 每次请求生成不可复用的 run ID，并冻结 journal ID、venue、绑定指纹和凭据 generation。
2. 用 `[UUID: Task<Void, Never>]` 或等价的 per-journal job registry 替代全局 `isSyncing` 门。UI 的忙碌/错误状态从当前 active journal 的状态派生。
3. journal 切换不必取消旧本任务，但 disconnect、删除日记和修改绑定必须取消对应任务并递增 generation。
4. `finishSync` 写入前再次验证：run ID 仍是最新、journal 仍在 catalog、绑定指纹未变、任务未取消。
5. 校验失败时只丢弃结果，不保存 cache、不自动补建、不更新全局错误。
6. 将 fills 排序、聚合和大 JSON 编解码移出 MainActor；完成后仅在 MainActor 提交验证过的结果。
7. 为客户端工厂、时钟、cache repository 和 JournalStore facade 提供可注入接口，避免生命周期测试访问 Keychain 或网络。

#### 测试

- 请求中途 disconnect、删除日记、改 API key、切换交易所。
- A 正在同步时 B 可以独立同步；A 的错误不出现在 B 的设置页。
- 删除 A 后旧请求完成，不重建 `Journals/A` 或 `Trading/A.json`。
- 取消任务后客户端收到 cancellation，完成回调不修改状态。

## 7. 持久化与性能

### PF-01：同步批量应用和常数次提交

#### 目标设计

同步引擎保留逐日网络对账，但把本地变更收集为 mutation batch。建议在 `WickSync` 定义：

```swift
public enum JournalSyncMutation: Sendable {
    case upsert(JournalEntry)
    case remove(dayKey: String)
}

public protocol JournalLocalSource: AnyObject {
    func applySyncedChanges(_ changes: [JournalSyncMutation], journalID: UUID)
}
```

#### 实施方案

1. `reconcileDay` 不立即整本持久化，而是记录 mutation；需要计算基线时继续使用已经确定的规范数据。
2. 日期阶段完成后一次性应用 batch，再进行图片对账，使图片集合能够看到最新日条目。
3. Store 在内存中完成全部 upsert/remove、统一排序、一次 selection reconcile、一次 `persist()`、一次 catalog metadata 更新和一次 UI 发布。
4. 任意日失败不阻止其他成功 mutation 落地，但错误日不进入 batch；保留现有 first-error 报告语义。
5. iOS Store 同样批量提交，并把编码、backup 和原子写移到串行 writer；MainActor 只更新发布状态。
6. 可选第二阶段：持久化队列只保留“正在写 + 最新待写”两代快照，避免快速编辑时积压中间代。实施前必须验证 `.bak` 与退出 flush 语义不变。

#### 性能测试

- Fake local source 导入 1、100、1000 天，记录 batch 次数和 persist 次数；每轮均不超过 1 次日记提交和 1 次 catalog 提交。
- 同步中部分日期失败，其余日期仍正确应用且失败日下轮可重试。
- 退出前 `flushPendingWrites()` 等待 writer 的最终 generation 完成。
- 使用 Instruments 对 1000 天 fixture 检查峰值内存、主线程占用和磁盘写入；记录优化前后基线，不把机器相关耗时写成脆弱单测阈值。

### DS-04：一致性导出

#### 实施方案

1. 导出入口先走统一 editor flush，再调用同步等待的 Store flush。
2. 不从可能陈旧的 `databaseURL` 复制主文件；直接从 flush 后的冻结内存快照编码到临时导出目录。
3. 冻结 active journal ID 和图片目录，导出期间切本不得混入另一本数据。
4. 导出失败不修改日记、catalog 或目标位置中的旧 zip；最后一步才原子替换目标文件。

#### 测试与完成定义

- 修改正文后立即导出，解压后的内容是最新值。
- persist queue 中存在旧 generation 时，导出仍使用最终 generation。
- 导出期间切本，zip 的 JSON 与图片始终来自同一本。
- 失败时目标旧文件仍可用，临时目录被清理。

### PF-02：SpriteKit 静止休眠

#### 实施方案

1. `PaperSim.step(_:)` 返回本帧是否改变网格，或暴露单调递增的 geometry revision。
2. `CalendarPaperScene.update` 仅在 revision 改变时创建目标数组和 `SKWarpGeometryGrid`。
3. 进入 sleeping 后可暂停 Scene；grab、tear、纹理替换和 layout 变化必须显式唤醒并标记 dirty。
4. 不改变现有 verlet 数值、撕口几何和确定性随机结果。

#### 测试与完成定义

- sleeping 连续 120 帧时 geometry revision 不变，warp 构建次数为 0。
- grab/tear 后首帧立即恢复更新。
- 现有 `PaperSimTests` 全部保持通过；桌面和 iPhone 撕页手感无可见回归。

### PF-03：iOS 首页刷新隔离

#### 实施方案

1. 将时间标题和四条进度提取为小型 `TimelineView` 子视图。
2. `NavigationStack`、List 导航入口、toolbar、sheet 和 calendar cover 移出每秒 closure。
3. 日期格式改用缓存的 formatter 或 `FormatStyle`；语言变化时明确失效。
4. `JournalDayKey` 的 formatter 优化只在 profiling 证明为热点后实施，避免引入共享 formatter 的并发风险。

#### 完成定义

- 每秒 tick 不重建日记导航和弹层声明。
- 打开设置、编辑器或日历时，首页 tick 不触发其无关状态变化。

### CA-01：交易日历缓存时效

#### 实施方案

1. `DayState` 记录 macro 和 earnings 各自的 `fetchedAt`，两路独立判断时效。
2. 当天使用短 TTL，历史日期使用长 TTL；失败时继续展示磁盘缓存并保留可重试状态。
3. `loadIfNeeded` 在过期时后台刷新而不是永久返回，并新增 `reload(for:)` 供显式刷新。
4. 同一日期同一路 feed 保持 single-flight，避免翻页和多窗口重复请求。

#### 测试

- 未过期不请求、过期请求、并发调用只请求一次。
- macro 成功/earnings 失败时仅更新成功一路的时间戳和缓存。
- 失败不覆盖已有磁盘缓存。

## 8. 架构收敛

大型文件本身不是缺陷，但实施上述工作时应按真实职责提取组件，避免继续扩张单例：

- 从 `JournalStore.swift` 提取 `JournalCatalogRepository`、`JournalSnapshotWriter`、`JournalImageStore` 和 `JournalArchiveService`。`JournalStore` 继续作为 `@MainActor` facade 和 UI 状态源。
- 从 `ExchangePositionCoordinator` 提取 client factory、per-journal job state 和 trading cache repository。
- `JournalSyncEngine` 暂不整体重写；先引入 mutation batch。后续可把单日对账矩阵提取为纯 reducer，但必须保持现有测试矩阵和远端格式。
- 新组件优先使用协议注入文件系统、时钟和客户端，生产单例只负责组装，不让测试依赖 `Application Support`、Keychain 或真实网络。

拆分应跟随对应工作包提交，不做独立的大规模文件搬迁，以便每个 commit 都能验证行为没有变化。

## 9. CI 与发布

### CI-01：iOS、签名和恢复测试守门

#### 实施方案

1. 在 CI 增加 iOS 构建：

   ```bash
   xcodebuild \
     -project ios/WickPhone.xcodeproj \
     -scheme WickPhone \
     -destination 'generic/platform=iOS' \
     build CODE_SIGNING_ALLOWED=NO
   ```

2. 将 `AGENTS.md` 中失败的 `-target WickPhone` 校验命令替换为上述 scheme 命令。
3. 保留 `WickCalendarKit` 的 iOS triple 编译检查，作为共享 target 的快速守门；App scheme 构建负责发现工程链接和资源问题。
4. 移除打包脚本中 `codesign ... || true`。找不到 `Wick Local` 可以按现有规则回退 ad-hoc，但实际签名失败必须退出非零。
5. 打包后执行：

   ```bash
   codesign --verify --deep --strict --verbose=2 dist/Wick.app
   ```

6. zip 生成后解压到临时目录，再对解压出的 `.app` 重复签名验证和 Universal 架构检查。
7. CI 增加 catalog 恢复、非法图片路径、批量同步提交和交易任务取消测试。

#### 完成定义

- PR 同时受 SwiftPM 单测、iOS app build、Universal 打包和签名验证保护。
- 任一签名步骤失败都不会上传 artifact 或创建 GitHub Release。
- 本地文档命令与 CI 使用同一种 iOS scheme 构建方式。

## 10. 分阶段交付

### 阶段 0：回归测试先行

- [ ] 为 DS-01、DS-02、SY-01、ED-01、EX-01 写出当前会失败的最小测试。
- [ ] 为持久化 writer 增加测试计数器，记录当前 100/1000 天同步提交次数。
- [ ] 保存一次日历静止状态的 Instruments 基线。

### 阶段 1：数据安全

- [ ] DS-01 图片路径安全边界。
- [ ] DS-02 catalog 版本门、backup 和 library 只读状态。
- [ ] DS-03 非当前日记类型化 I/O。
- [ ] SY-01 远端删除事务。

阶段门：所有损坏/未来格式 fixture 字节不变；非法图片路径不能访问目录外文件；远端删除最后一本能收敛。

### 阶段 2：任务与草稿一致性

- [ ] ED-01 统一 editor session flush/rebase。
- [ ] EX-01 per-journal 交易任务与 generation。
- [ ] DS-04 一致性导出。

阶段门：切本、删除、断开、后台和远端 apply 的组合测试全部通过，不产生日记复活或旧 draft 回写。

### 阶段 3：性能

- [ ] PF-01 同步 mutation batch。
- [ ] PF-02 SpriteKit dirty/sleep 更新。
- [ ] PF-03 iOS 首页刷新隔离。
- [ ] CA-01 日历缓存 TTL/single-flight。

阶段门：1000 天同步为常数次整本提交；静止日历不重建 warp；主线程和磁盘写入基线显著下降且功能无回归。

### 阶段 4：发布守门与文档收尾

- [ ] CI-01 iOS scheme 与签名验证。
- [ ] 修正 README 中“无日记时近 180 天”与当前“仅从当天开始”的不一致，确认产品规则后统一代码、测试和文档。
- [ ] 更新 `AGENTS.md` 的新安全不变量、事务接口和构建命令。

## 11. 兼容、迁移与回滚

- 图片名称规则不需要快照版本升级。发现非法旧数据时必须只读阻断，不能自动删除引用或文件。
- catalog backup 是新增旁路文件，对旧版本透明；旧客户端仍能读取 `catalog.json`。
- mutation batch 只改变本地应用时机，不改变 Dropbox 文件布局、规范 JSON 或冲突算法。
- editor session 和交易 generation 都是进程内状态，不需要磁盘迁移。
- 每个阶段保持可单独回滚。涉及持久化格式的提交必须先证明旧版本仍可读取，或显式提升版本并提供迁移器。
- 禁止以清空 `Application Support/Wick`、重建 catalog 或丢弃远端状态作为自动恢复策略。

## 12. 观测与人工验证

在不增加遥测的前提下使用本地统一日志记录以下事件，不记录正文、标签、图片内容、API key 或账号地址：

- catalog 主文件失败、backup 恢复、未来版本阻断。
- 同步周期的日数、mutation 数、persist 数和总耗时。
- 交易 run 的 journal ID、run ID、取消原因和结果是否因 generation 失效而丢弃。
- 日历进入/退出 sleeping 的次数和 warp rebuild 次数，仅用于 DEBUG。

每个阶段完成后人工验证：

1. macOS 打包应用的新建、编辑、切本、导入、导出和退出重开。
2. 两个 fake device 的新增、冲突、日删除、本删除和远端文件意外消失。
3. iPhone 真机输入后立即锁屏/切后台、重新进入并同步。
4. 三个交易所至少使用 fixture 完成全量、增量、断开和删除日记流程。
5. 日历桌面与 iPhone 的拖拽、撕页、翻栏、休眠唤醒和声音。

## 13. 基线验证记录

审查基线已完成：

- `swift test`：213 tests，0 failures。
- `xcodebuild -project ios/WickPhone.xcodeproj -scheme WickPhone -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO`：成功。
- `xcodebuild -project ios/WickPhone.xcodeproj -target WickPhone build CODE_SIGNING_ALLOWED=NO`：失败，App target 无法解析 `WickCalendarKit` 和 `WickSync`；该命令不应继续作为文档校验方式。
- 审查未执行真实 Dropbox、交易所网络或真机 Instruments 测量。

