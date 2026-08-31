# Wick for Linux 架构与代码质量审查报告

- 审查日期：2026-08-31
- 范围：`linux/src`（68 个文件，约 14.6k 行 C++）、`linux/qml`（12 个 QML，约 6.3k 行）、`linux/omarchy` Quickshell 挂件、构建/测试/打包配置
- 背景：Linux 版为 2026-08-30 ~ 08-31 两天 89 个提交的高密度移植，此前未经专项审查（`docs/cpu-optimization.md`、`docs/code-review-optimization-plan-2026-08-28.md` 均为 macOS 版口径）
- 方法：架构 / 性能 / QML / 构建测试四路并行审查，高危结论全部回源核实
- 本文只做审查与方案，不含代码改动

## 一、总评

架构方向正确，底子扎实：

- **分层清晰**：`core/`（模型 / catalog / 存储 / zip）纯 std + nlohmann_json，编成 Qt-free 的 `wick_core` 静态库，测试直接链接；`sync/` 引擎纯 C++，Qt 依赖收敛在 `DropboxSyncBackend` 一个文件；`app/` 为 Qt/QML 胶层。无逆向依赖。
- **数据安全路径移植质量高**：只读保护、`.bak` 侧车、catalog 事务回滚、图片导入 quarantine、同步三不变量（rev 回声抑制 / 固定点 / 不自冲突）、Dropbox 401 刷新重试、交易数值口径（手续费符号、OKX subType 数字码、HL 500 条分页）逐条核对全部与 macOS 一致。
- **空闲 CPU 底子好**：QML 零无限循环动画、无 busy-wait、定时器对齐分钟边界。macOS 曾烧 33% CPU 的「呼吸动画 + 关窗不释放」坑在 Linux 版不存在。未连 Dropbox 时空闲每分钟仅 1 次廉价唤醒（托盘图标重渲）。
- **核心路径测试可靠**：2379 行测试，同步引擎三不变量 / 墓碑传播均有用例；FakeSyncBackend 不碰网络，Dropbox 测试只走 loopback。

但存在两处**跨端数据一致性高危 bug**、一批性能热点（大日记本下会爆），以及 app 层零测试的结构性风险。

## 二、必须修的高危问题

### P0-1 远端删除日记本在 Linux 永不收敛，且会被主动复活（已核实）

macOS/iOS 删一本日记 → 远端产生墓碑 → Linux 同步时：

- `JournalSyncEngine::remoteJournalDeletions()` 在 app 层**没有任何消费方**（仅 `linux/tests/test_journal_sync.cpp:658` 引用，`linux/src/sync/JournalSyncEngine.h:72`）——本地不会跟着删。
- 更糟的是 `SyncWorker::syncActive()` 的「自愈」段（`linux/src/app/SyncWorker.cpp:247-255`）：对**每个本地存在的日记本** `clearJournalTombstone()` + 删除远端墓碑文件，随后 `pullAllInternal` 把它重新推回远端。`isJournalTombstoned` 涵盖 `unackedRemoteDeletions`（`linux/src/sync/JournalSyncState.cpp:499`），即**对端刚删的本子，Linux 一同步就全端复活**——与「删除日记本 = 全端删除（墓碑传播）」直接冲突。
- 附带缺失：远端删到最后一本时播种纯本地默认本的逻辑（macOS 有）Linux 没有。

**修法**：app 层实现 `applyRemoteJournalDeletions`（本地删除 + ack，失败保留墓碑重试，对齐 `Sources/WickCore/SyncCoordinator.swift:264-289`）；自愈只保留引擎已有的「远端 manifest 健康但墓碑错误」分支（`linux/src/sync/JournalSyncEngine.cpp:1096-1103`），删掉 SyncWorker 里无差别清墓碑的循环。

### P0-2 交易快照删除队列不落盘

`pendingTradingSnapshotDeletions` 编码时硬编码写空数组、解码不读（`linux/src/sync/JournalSyncState.cpp:467`）。重启后删除意图丢失，reconcile 反而把远端快照拉回本地（`linux/src/sync/JournalSyncEngine.cpp:1349-1359`）。Swift 端该字段正常编解码（`JournalSyncState.swift:529-542`）。

### P0-3 Omarchy 挂件每分钟抛 ReferenceError（已核实）

`linux/omarchy/wick.progress/Panel.qml:104`：`SystemClock.onDateChanged`（分钟精度）里 `langProcess.running = true`，但全文件**没有声明 `langProcess`**（也无任何 Process 元素）——每分钟刷一次 Quickshell 错误日志。`langFile` 已有 `watchChanges` 自动重载，这行直接删。

### P0-4 版本号硬编码 0.1.0，更新检查失效（已核实）

`linux/src/main.cpp:23` 写死 `"0.1.0"`，CMake 的 `PROJECT_VERSION` 未以编译定义传入二进制，`scripts/set_version.sh` 只改 CMakeLists/PKGBUILD。结果：1.10.33 发行包的「关于」页恒为 0.1.0，检查更新永远认为有新版本。修法：`target_compile_definitions(wick PRIVATE WICK_VERSION="${PROJECT_VERSION}")` 贯通。

### P1-1 `refreshTradingPositions()` 漏发 `daysChanged`（已核实）

`linux/src/app/JournalLibrary.cpp:228-230` 只发 `itemsChanged/journalsChanged/calendarChanged`，而 DayList/DayPage 的仓位收据和盈亏全部来自 `days` 模型。交易所同步完成但没补新条目时（`ExchangeCoordinator.cpp:502-505`），UI 里 PnL 与仓位卡不刷新，要等下一次别的 `daysChanged`。补一行 `emit daysChanged()`。

### P1-2 通知 action 是全局监听

`linux/src/app/ReminderScheduler.cpp:35-42,107-110`：D-Bus `ActionInvoked` 全局连接，`onNotificationAction` 不校验 notification id / app_name，任何应用的通知只要 action 叫 `"default"`/`"open"` 都会打开日记窗。修法：记下 `Notify` 返回的 id 再比对。

## 三、性能热点与优化空间（按收益排序）

### 热点 1（高）：日记时间线全量非虚拟化重建 —— 大日记本的性能悬崖

`linux/qml/journal/DayPage.qml:113-116` 用 **Repeater over `library.days`** 套在 Flickable 里：整本日记所有天的 TextArea、图片、仓位卡全部常驻场景图。QVariantList 模型无 diff，每次 `daysChanged` **全拆全建**。触发源极多：搜索每击键、选日、打标签、加图、同步落地、切语言。

连锁后果：

- **编辑中光标 / IME 丢失**：任意 `daysChanged` 销毁正在输入的 TextArea，中文 IME preedit 直接丢。macOS 为此有 ED-01（apply 前 flush + 只对干净 draft rebase）整套约定，Linux 侧等价机制为零。
- `days()` 一次变更被 **5 个绑定各求值一遍**（`DayList.qml:16,31,35`、`DayPage.qml:102,115`），每次全量排序 + O(条目×仓位) 匹配（`JournalLibrary.cpp:574-700`）。
- `itemImageFilenames()` 每个条目块 2 次全表扫描（`DayPage.qml:507,509` → `JournalLibrary.cpp:375-396`），重建时 O(items²)。
- 搜索无防抖：`JournalWindow.qml:217` 每击键直发 `daysChanged`（`JournalLibrary.cpp:1128-1138`）。
- `DayPage.qml:465` 每敲一键 TextArea 重排 → 整个 timeline Column 重排 O(n)。

**优化方案**（结构性，决定大日记本可用性）：

1. DayPage 的 Repeater 改 **ListView**（delegate 复用），或只渲染选中日 + 相邻天；
2. `days` 改 `QAbstractListModel`（role 级更新），选中态从模型剥离（`currentIndex` / 自维护 selectedId）；
3. C++ 侧缓存 `days()` 结果，`daysChanged` 时只重建一次；图片列表并入 row 数据（`modelData.images`）；
4. 搜索加 200–300ms 防抖 Timer。

### 热点 2（高）：`journals()` 对非活跃本无缓存全量读盘 —— macOS 明令禁止的坑的加重版

`linux/src/app/JournalLibrary.cpp:483-542`：每次调用对每个非活跃本 `entryCountOnDisk()`（**完整读 + 解析 journal.json 只为数条目数**，`JournalStore.cpp:80-94`）再解析 trading.json（`:490-513`）。且 `refreshTradingPositions()` 末尾发 `journalsChanged` 触发 NavColumn Repeater 重建 → 再调一遍 `journals()`。`ExchangeCoordinator` 的 `venue()/accountLabel()/isConfigured()` 每次也全量调 `journals()`（`ExchangeCoordinator.cpp:209-254`），一次 `refreshStatus` = 3 次全量读盘。macOS 至少有失效缓存，这里连缓存都没有。

**方案**：entryCount / positionsCount 加按 mtime 失效的缓存；`ExchangeCoordinator` 状态查询走缓存结果。

### 热点 3（中）：同步周期每 60s 固定全量工作

即使远端 cursor 无变化，每轮仍：

- 全部本地条目算 canonical hash（`JournalSyncEngine.cpp:136-139`）；
- sync state 无条件原子写盘（`JournalSyncEngine.cpp:129,991-995` → `JournalSyncState.cpp:533-542`）；
- 每本非活跃日记从磁盘全量加载（`SyncWorker.cpp:277-295`），且经 `BlockingQueuedConnection` 弹回 **GUI 线程**执行（`SyncWorker.cpp:163-176`）——磁盘 I/O 实际发生在主线程。

**方案**：周期拉长到 5 分钟或空闲退避（连续 N 轮无变更降频，编辑后 15s 防抖恢复）；state 仅脏时落盘；非活跃本加载留在 worker 线程（LocalSource 实现直接读 `JournalFileStore`，不 marshal 回 GUI）。

### 热点 4（中）：persist 与编辑路径

- 每次 persist 恒复制 journal.json → .bak（`JournalStore.cpp:168-190`），400ms 防抖后每次停顿双文件 I/O。方案：.bak 节流（距上次 >N 秒才复制）。
- `setItemBody` 逐键全量 QString→std::string 拷贝 + 防抖后 persist 在 GUI 线程同步序列化整本 JSON（`JournalLibrary.cpp:1704-1717,252-266`），数 MB 日记本会掉帧。方案：序列化挪 worker 线程。
- 托盘图标每分钟无条件重渲 SVG + D-Bus `setIcon`（`TrayController.cpp:206-218`）。方案：缓存上次渲染的百分比文本，未变跳过。
- `setItemReviewNote` 逐键发 `itemsChanged` 但 QML 无消费方（`JournalLibrary.cpp:1758-1773`），纯浪费且连带重启同步防抖。

### 热点 5（中低）：内存与杂项

- 72px 缩略图无 `sourceSize`，12MP 照片全分辨率解码进显存（`DayPage.qml:516-521`）。方案：`sourceSize: Qt.size(144,144)`（2x DPR）；Lightbox 限到窗口×dpr（`DayPage.qml:1023-1032`）。
- 交易所 transport 每请求新建 `QNetworkAccessManager`（`ExchangeClients.cpp:110`）无连接复用；Binance 每次 fetchFills/fetchFunding 各先打一次 `/fapi/v1/time`（`:140,196`）。方案：worker 级共享 NAM + server time 偏移本次同步内缓存。
- `importArchive` 的 journal.json 提交不在事务里：persist 失败只记 `lastPersistError` 仍返回成功，内存态与磁盘脱节（`JournalStore.cpp:493-502`；另 `:493-499` 只读标志连续写两遍是复制粘贴残留）。
- `ExchangeCoordinator::onWorkerFinished` 写 trading.json 用裸 `std::ofstream`（`ExchangeCoordinator.cpp:434-437`），全库唯一非原子落盘。
- 同步每周期全量拷贝 entries（`JournalLibrary.cpp:1839-1847`），随周期拉长自然缓解。
- 关窗只 hide 不释放：三个 QQuickView = 三个 QQmlEngine 常驻。无 CPU 代价（无存活动画 / 定时器），仅内存常驻——可接受取舍；Inspector/NavColumn 可用 Loader 延迟创建（`JournalWindow.qml:294-348`，Inspector 一建成就发网络请求 `Inspector.qml:21-22`）。

### 空闲唤醒源清单（现状）

| 源 | 周期 | 隐藏时停止？ | 证据 |
|---|---|---|---|
| `TimeProgress` 分钟计时器 | 对齐分钟边界，单次循环 | 否（常驻合理） | `TimeProgress.cpp:103-108` |
| 托盘图标重渲 | 随上面每分钟 | — | `TrayController.cpp:109-111,206-218` |
| `JournalSyncCoordinator::m_periodic` | 60s（仅已连接） | 不适用 | `JournalSyncCoordinator.cpp:36-37` |
| 同步补拉防抖 | 编辑后 15s | 仅编辑后 | `JournalSyncCoordinator.cpp:32-34` |
| `JournalLibrary::m_saveTimer` | 400ms 防抖 | 仅编辑时 | `JournalLibrary.cpp:72-74` |
| omarchy 主题 watcher | inotify 事件 + 80ms 防抖 | 事件驱动 | `AppSettings.cpp:142-177` |
| 交易所 / 宏观日历 | 无周期定时器，手动 / 开窗才拉 | — | `ExchangeCoordinator.cpp`、`MacroCalendarStore.cpp:71-81` |

macOS 坑对照验证：无限呼吸动画（不存在）、关窗不释放视图树（存在但无 CPU 后果）、定时器 .now 漂移（不存在）、启动即拉交易所（不存在，手动触发）、侧栏非活跃本读盘（**存在且更重**）、编辑每键重估（不存在）、搜索无防抖（**存在**）。

## 四、代码质量清单（按严重度）

### 中

1. **冲突解决 UI 完全未接线**：`pendingConflicts()/resolveConflict()/dismissConflict()` 只有测试调用，冲突记录永久堆积在 `state_.pendingConflicts`，用户永远看不到 delete-vs-edit / item-content-conflict。
2. **`JournalLibrary` 是上帝类**（2175 行，`JournalLibrary.h:27` 一身四任：约 30 个 Q_PROPERTY 的 QML 属性面 / catalog 事务 / `JournalLocalSource` 同步桥 / 仓位+农历+导入导出）。`JournalLibraryZip.cpp` 已是正确拆法，应继续拆出 `+QmlSurface`（days/itemsForEntry/calendarDays 三个展示聚合约 500 行）与 `+SyncBridge`（1500–2175 行段）。
3. **trading 层被腰斩在两个构建目标**：`TradingModels/PositionAggregator` 等在 `wick_core`（`CMakeLists.txt:64-68`），`ExchangeClients` 因 `ExchangeHttpRequest` 内嵌 `QUrl/QByteArray`（`ExchangeClients.h:29-40`）只能编进 `wick` 可执行文件——三所响应解析（fillFromBinance、OKX subType 映射、HL 分页）**零测试覆盖**，恰是跨端口径最易漂移处。方案：transport 边界类型去 Qt 化，下沉 wick_core。
4. **无 L10n 层**：`isChinese() ? 中 : 英` 三元散落十余处（JournalLibrary / SyncWorker / ExchangeCoordinator / MacroCalendarStore / TrayController / Inspector.qml），违反「UI 文案一律走 L10n」；且导致 worker 线程跨线程读 `AppSettings::m_language`（QString 非原子，真实 UB，`SyncWorker.cpp:238`、`ExchangeCoordinator.cpp:129`）。现成的 `appSettings.t()`（`AppSettings.cpp:572`）没人用，QML 侧 `t()` 重复了 5 份。
5. **硬编码色至少 5 处在亮色主题下不可见**：`ProgressPanel.qml:46,58`、`NavColumn.qml:117`、`DayList.qml:161`、`JournalWindow.qml:95,112`；窗口底色 `JournalWindow.cpp:19`、`ProgressWindow.cpp:19` 固定暗色 `0x241C10`（SettingsWindow 反而随主题，`:42-50`，三窗不一致）；`MacroCalendarStore::copyAlmanacCard` 整段硬编码色板与字体名（`MacroCalendarStore.cpp:311-425`）。建议加 CI 级「禁硬编码色」grep 护栏。
6. **`journalDialog` 模态遮罩无 MouseArea 阻断、Esc 不关**（`JournalWindow.qml:352-429`）；纸条窗无失焦自动隐藏、无 Esc（`ProgressWindow.cpp:18`，`Qt::Tool | WindowStaysOnTopHint` 点了别处也常驻）。
7. **`SettingsWindow.qml:1397-1427`** 导出/导入 zip 在 FileDialog onAccepted 里 GUI 线程同步执行，大库冻结数秒。进 worker 或至少 busy 指示。
8. **关闭路径稳定走到 `terminate()`**：`~JournalSyncCoordinator`（`JournalSyncCoordinator.cpp:97-107`）`wait(1500)` 时若 worker 正阻塞在 `BlockingQueuedConnection` 等 GUI，而 GUI 在析构里等 worker——必然超时。所幸落盘全部走 `atomicWriteFile`，中止最坏留 `.tmp` 残渣。

### 低

9. `WickIcon.qml:24-458` 每个图标实例创建全部 22 个 Shape（约 50+ 对象）靠 visible 选名，场景图节点放大 ~22 倍；`SettingsWindow.qml:354` 引用了不存在的 `sparkles` 图标（渲染空白）。
10. Inspector 硬编码中文四处不走 `insp.t()`（`Inspector.qml:345,373,468,495`）；`EventsContent` 实例化两份不可见那份照样全建（`:707-799`）；`★`/`🕒` emoji 当图标（`:197`）。
11. DayPage 今日 burn 进度无分钟 tick 会停滞到下一次 daysChanged（`DayPage.qml:283,307`）；`"% 已过"` 硬编码（`:307`）；删除按钮 ToolTip 恒为 "Delete Today's Journal"（`:233`）。
12. ReviewSeal 每次 daysChanged 重建重播盖章动画（`DayPage.qml:761-778`）；缺口采样 seed 固定 9，所有章轮廓一样（`ReviewSeal.qml:72`）。
13. 挂件周起点写死周一，与 C++ `weekStartsOnMonday`/locale 口径不一致（`Panel.qml:72-74` vs `TimeProgress.cpp:63-68`）；长期建议挂件读 C++ 算好的状态文件消灭双实现。`Panel.qml:38-39` `onFileChanged: reload()` 与 `watchChanges` 重复双读。
14. 死代码：`JournalLibrary` 约 15 个 QML 不用的 Q_PROPERTY（`pageDateLabel` 等，`JournalLibrary.h:48-59,82`）+ `copyAlmanacCard/deleteEmptyItem/lunarLineFor` 无调用方；`AppSettings::stubExport/stubImport`（`AppSettings.cpp:589-599`）。
15. `sync.deviceID` 键没按 `wick.*` 前缀约定（`JournalSyncCoordinator.cpp:124`）；旧式 SIGNAL/SLOT 宏 2 处（`JournalWindow.cpp:35`、`ReminderScheduler.cpp:41`）。
16. `qtExchangeTransport` 的 `QNetworkReply` 从不 `deleteLater`（`ExchangeClients.cpp:116-128`），靠隐式 parent 清理；金额符号 U+2212 与 ASCII `-` 混用（`JournalLibrary.cpp:803,1097` vs `:676,976`，PositionReceipt.qml 又是第三套）；分页页数全是无名魔法数字。
17. `JournalLibrary.cpp:591` 用 `std::unordered_map` 但只 include `<unordered_set>`（靠传递包含编译过）；`qs()/ss()` helper 在 JournalLibrary 与 JournalLibraryZip 重复定义。
18. 启动阻塞：`main.cpp:58` 无条件 `ensureMimeDefault()`，每次启动两次 `QProcess::waitForFinished(3000)` 且重写用户 desktop 文件；`ExchangeCoordinator.cpp:386` 在 GUI 线程做 libsecret 同步 D-Bus 调用。
19. `SyncGuard` 析构里递归调用 `performSyncCycle`（`JournalSyncEngine.cpp:74-83`），cursorExpired 路径无退避，病态循环下递归无界。
20. `DropboxSyncBackend::perform` 在 worker 线程跑嵌套事件循环（`DropboxSyncBackend.cpp:462`），排队槽可在同步中途重入（`signOut` 无 `isSyncing_` 兜底）。

## 五、构建与工程化

**缺**：

- 零警告开关：无 `-Wall -Wextra -Wpedantic`（全 linux/ grep 无命中，唯一警告相关是给 miniz 加 `-w`，`CMakeLists.txt:50`）。
- 无 sanitizer（ASan/UBSan/TSan）/ clang-tidy / clang-format target；无 LTO（`CMAKE_INTERPROCEDURAL_OPTIMIZATION` 未设）。
- QML 走传统 qrc + AUTORCC（`CMakeLists.txt:129-131`），未用 `qt_add_qml_module`——无 qmlcachegen 预编译，启动时全运行时编译。
- 无 `install()` 规则 / CPack，安装全靠 shell 脚本与 PKGBUILD 手铺路径。

**坑**：

- `packaging/wick.service:8` 硬编码 `ExecStart=/usr/bin/wick`，非 root 安装（`~/.local/bin/wick`，`install.sh:11,25`）后 systemd 单元指向不存在的路径。
- `packaging/PKGBUILD:22-23` 的 `build()` 只编 `--target wick` 不跑测试。
- `omarchyPluginOwnsCandle()` 只在启动时探测一次（`TrayController.cpp:40-64`），装/卸挂件要重启生效；`WICK_HEADLESS_TRAY` 命名反直觉。

**好**：依赖仅两个 FetchContent 且 pin 版本 + SHA256（nlohmann_json v3.11.3、miniz 3.0.2）；libsecret 可选降级到 dev-secrets 文件（0600）；`QT_NO_CAST_FROM_ASCII` 等宏已开（仅 app target）；打包三产物（tar.gz/zip/pkg.tar.zst）+ CI 双发行版（Ubuntu/Arch）验证完整。

**测试覆盖矩阵**：

| 模块 | 测试 |
|---|---|
| core/（模型、catalog、存储、编码、zip） | ✅ test_journal_core（658 行）/ test_journal_archive（222 行） |
| sync/（引擎、状态、DayMerge、PKCE、Dropbox backend） | ✅ test_journal_sync（823 行）/ test_dropbox_backend（490 行，loopback 假服务器）/ test_pkce（78 行） |
| trading/ 纯逻辑（Crypto、聚合、标签、规划、快照编解码） | ✅ test_trading（108 行，偏薄） |
| **trading/ExchangeClients（579 行三所解析）** | ❌（构建目标外） |
| **app/ 全部（JournalLibrary 2175 行、ExchangeCoordinator 535 行、SyncWorker、MacroCalendarStore 等）** | ❌ 全军覆没 |
| QML（6338 行）/ Omarchy 挂件 | ❌（无 qmltestrunner） |

## 六、优化方案路线图

| 优先级 | 事项 | 性质 | 预估工作量 |
|---|---|---|---|
| P0 | 远端删除收敛：实现 `applyRemoteJournalDeletions` + 删 SyncWorker 无差别自愈 + 末本播种默认本 | 数据正确性 | 1–2 天（含测试） |
| P0 | `pendingTradingSnapshotDeletions` 编解码补齐 | 数据正确性 | 半天 |
| P0 | 删 `langProcess` 幽灵引用；版本号经 `WICK_VERSION` 编译定义贯通 | 一行/几行修复 | 半小时 |
| P1 | `refreshTradingPositions` 补发 `daysChanged`；通知 action 校验 id | 一行级 bug | 半天 |
| P1 | DayPage 时间线虚拟化（ListView/选中日渲染）+ days 模型化（QAbstractListModel）+ 搜索防抖 | 性能结构 | 2–3 天 |
| P1 | `journals()` / ExchangeCoordinator 读盘加 mtime 失效缓存 | 性能 | 1 天 |
| P2 | 同步退避 + state 脏才落盘 + 非活跃本加载留 worker 线程 | 性能 | 1–2 天 |
| P2 | ExchangeClients 去 Qt 化下沉 wick_core + 补三所解析测试 | 可测性 | 1–2 天 |
| P2 | 冲突解决 UI 接线；importArchive 事务闭环 | 功能缺口 | 1–2 天 |
| P3 | L10n 层收敛、硬编码色 + CI grep 护栏、WickIcon 重构、构建加固（-Wall/sanitizer/qmlcachegen）、关窗 terminate 竞态 | 质量债 | 随改随收 |

## 七、结论

移植完成度和数据安全保真度都很高，空闲 CPU 底子干净。真正的风险集中在三点：

1. **跨端删除传播的两处正确性 bug**（P0-1/P0-2，必须立即修）；
2. **大日记本下 Repeater 全量重建的性能 / IME 悬崖**（热点 1，结构性，值得尽快做）；
3. **app 层零测试**（2175 行的 JournalLibrary 是最大的裸奔点）。


---

## 八、复审与修复记录（2026-08-31 第二轮）

### 复审对象

提交 `b47c5f9 fix(linux): resolve review findings across sync, trading, and UI`（23 文件，+1011/-327）。

### 复审结论

报告 P0 全部正确修复：远端删除收敛链路（`SyncWorker::syncActive` 消费 `remoteJournalDeletions()` + `JournalLibrary::deleteJournalFromRemote` 事务化删除/末本播种/ack-retry 语义，对齐 macOS Coordinator）、`pendingTradingSnapshotDeletions` 编解码（键名与 `JournalLocalSource.swift` 逐字段一致，附往返测试）、挂件 `langProcess` 幽灵引用删除、`WICK_VERSION` 编译定义贯通。P1/P2 落地：`refreshTradingPositions` 补发 `daysChanged`、通知 id 跟踪（含 `NotificationClosed` 清理）、`journals()` mtime 失效缓存、`ExchangeCoordinator` 改 `exchangeBindingFor` 直查、搜索 150ms 防抖、图片并入 days 模型、缩略图 `sourceSize`、ExchangeClients 去 Qt 化下沉 `wick_core`（三所解析新增 65 个 CHECK）、`atomicWriteFile`、`-Wall -Wextra`。另顺带修复 `ProgressPanel.qml` 上一提交遗留的多余 `}`（原文件 44 开 45 合，面板无法加载）。

复审验证：增量构建通过，6/6 CTest 通过。

### 复审新发现问题及修复（本轮已修）

| # | 问题 | 修复 |
|---|---|---|
| 1 | **days 缓存失效不完整**：`languageChanged`/`bootstrap`/`selectDay`/`setItemTag`/`setItemReview` 五处发 `daysChanged` 但未失效缓存 → 点选高亮不动、打标签/复盘/切语言后时间线拿旧数据 | 五处各补 `invalidateDaysCache()`（`JournalLibrary.cpp`），现全部 8 个 `daysChanged` 发射点均有失效 |
| 2 | **`pullAllInternal` 对活跃本二次同步且改走磁盘读**：forced 路径读到 ≤400ms 防抖前的旧盘内容，可能把比 baseline 旧的内容判为本地回退推上去 | 循环内跳过活跃本（`SyncWorker.cpp`），活跃本已由 `syncOnce()` 内存态同步 |
| 3 | 非活跃本图片同步仍 marshal 回 GUI 读盘（热点 3 只修了一半） | `syncedImageFilenames`/`syncedImageData`/`hasSyncedImage`/`storeSyncedImage` 四个代理方法补 forced 磁盘直读分支（复用 `JournalImageFilename::isValid` 校验 + `atomicWriteFile`），同步期 GUI 线程不再做磁盘 I/O |
| 4 | `itemImageFilenames` Q_INVOKABLE 死代码（QML 已改用 `modelData.images`） | 删除声明与定义 |
| 5 | `-Wextra` 新暴露 `SecretTokenStore.cpp` 8 条 missing-field-initializers 警告 | 显式补齐 reserved 字段初始化（首字段为 gint 用 0） |

本轮验证：构建零警告，6/6 CTest 通过。

### 有意保留 / 遗留事项

- `setItemReviewNote` 维持零信号：该路径逐击键调用（`DayPage.qml:755`），发 `daysChanged` 会触发 Repeater 全量重建、销毁正在输入的 TextArea（IME 丢失）；下方备注 label 短暂滞后，下次结构性变更自愈。根治依赖时间线虚拟化。
- 未动项（路线图 P2/P3）：DayPage Repeater→ListView 虚拟化与 days 模型化、同步周期退避 + state 脏才落盘、冲突解决 UI 接线、`importArchive` 事务闭环、L10n 层、剩余硬编码色、关窗 `terminate()` 竞态。
- `SyncWorker` 的远端删除集成路径无自动化测试（app 层无测试设施），建议后续补。
