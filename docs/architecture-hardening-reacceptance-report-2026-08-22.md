# Wick 架构加固复验报告

> 复验日期：2026-08-22  
> 验收基线：`main@e386357` + 当前工作区未提交加固改动  
> 对照文档：[architecture-hardening-plan.md](./architecture-hardening-plan.md)  
> 上一版报告：[architecture-hardening-acceptance-report.md](./architecture-hardening-acceptance-report.md)

## 1. 验收结论

**通过，建议进入合并流程。**

本轮复验确认上一版提出的 4 项 P1 数据一致性/恢复问题均已关闭，并有对应实现、macOS/通用回归测试和 iOS 编译证据：iOS writer 冻结日记本目标并等待最终 generation；macOS/iOS 删除采用隔离目录与 catalog 提交的可回滚事务；iOS catalog 支持 backup 恢复、JSON 导入和可见错误反馈。此前的 catalog、同步、交易、物理模拟、导出、日历缓存和打包门禁仍保持通过。

## 2. P1 问题复验

### AC-RE-P1-01：iOS writer 快照身份与最终 flush

**状态：已关闭。**

**位置：** [`ios/WickPhone/PhoneJournalStore.swift:695`](/Users/miaoz/workspace/wick/ios/WickPhone/PhoneJournalStore.swift:695)、[`ios/WickPhoneTests/PhoneJournalStoreTests.swift:1`](/Users/miaoz/workspace/wick/ios/WickPhoneTests/PhoneJournalStoreTests.swift:1)

`PendingSnapshot` 现在冻结 `journalID`、`databaseURL` 和 `generation`；写入回调按 generation 对账，不再使用切本后的可变路径。`flushPendingWrites()` 直接等待在途写入，并继续 drain 最新待写 generation，返回成功状态；编码和原子写入失败会进入 `lastPersistError`。

**修复验收条件：**

- 待写 snapshot 携带冻结的 `journalID`、数据库 URL 和 generation。
- `flushPendingWrites()` 等待“当前写入 + 所有最新待写”完成，并可报告编码/写盘错误。
- iOS scheme 已重新编译 `PhoneJournalStore`；SwiftPM 测试 target 不包含 iOS writer，因此切本竞态仍需真机/模拟器运行验证。

### AC-RE-P1-02：远端删除失败回滚完整 Store session

**状态：已关闭。**

**位置：**

  - [`Sources/WickCore/JournalStore.swift:389`](/Users/miaoz/workspace/wick/Sources/WickCore/JournalStore.swift:389)
  - [`ios/WickPhone/PhoneJournalStore.swift:476`](/Users/miaoz/workspace/wick/ios/WickPhone/PhoneJournalStore.swift:476)

两端均在删除前捕获完整 session（路径、条目、选择/搜索、备份与只读状态），目录先移动到同卷隔离路径；catalog 提交失败时恢复 session、目录和 active ID，并清理失败期间创建的新默认目录。新增回归测试覆盖路径、条目、重载和临时目录清理。

**修复验收条件：**

- 删除前冻结完整 Store session（路径、entries、selection、读写状态和新建目录）。
- 任何失败都通过 `bindPaths(for: originalActiveID)` 重新绑定并恢复原内容。
- 清理失败期间新建的默认目录和临时隔离目录。
- macOS 回归测试已覆盖；新增 `WickPhoneTests` XCTest target，已在 iOS Simulator 执行 writer、删除事务和 catalog 恢复回归。

### AC-RE-P1-03：普通用户删除事务

**状态：已关闭。**

**位置：**

  - [`Sources/WickCore/JournalStore.swift:309`](/Users/miaoz/workspace/wick/Sources/WickCore/JournalStore.swift:309)
  - [`ios/WickPhone/PhoneJournalStore.swift:406`](/Users/miaoz/workspace/wick/ios/WickPhone/PhoneJournalStore.swift:406)

普通 `deleteJournal(id:)` 现在复用隔离目录、catalog 提交和失败回滚流程；目录移动失败或 catalog 写入失败均返回 `false`，不发布成功状态。新增 catalog 写失败回归测试，目录失败路径也有远端删除测试覆盖。

**修复验收条件：**

- 普通删除复用远端删除的可回滚事务，或返回明确的 `Result`/错误。
- 目录删除失败、catalog 写失败时都不发布成功状态、不确认同步删除。
- macOS 与 iOS Simulator 测试均覆盖 catalog 写失败回滚；真实设备上的文件系统故障注入仍属于发布前补验项。

### AC-RE-P1-04：iOS catalog 非破坏性恢复/导入

**状态：已关闭。**

**位置：**

  - [`ios/WickPhone/PhoneJournalStore.swift:148`](/Users/miaoz/workspace/wick/ios/WickPhone/PhoneJournalStore.swift:148)
  - [`ios/WickPhone/SettingsView.swift:81`](/Users/miaoz/workspace/wick/ios/WickPhone/SettingsView.swift:81)

新增 `restoreCatalogFromBackup()` 和 `importJournalJSON(from:)`，恢复会保留有效 catalog 元数据；catalog 恢复失败及无效导入失败保持原 catalog 字节和只读状态。设置页将“清空并重新开始”标为破坏性末选项，并以 alert 显示错误。

**修复验收条件：**

- iOS 设置提供 backup 恢复和日记导入；恢复失败保持原 catalog 只读和原字节。
- “清空并重新开始”明确为最后的破坏性操作。
- 恢复 API 返回错误并由 UI 展示；iOS generic-device build 已验证签名和调用链。

## 3. 残余风险与边界

### AC-RE-P2-01：catalog 恢复失败的临时目录清理

**状态：已关闭（macOS 与 iOS Simulator 回归测试）。**

macOS 与 iOS 测试均确认 catalog 写入失败时不会留下新 UUID 目录，并恢复原 catalog、路径和只读状态；iOS `recoverCatalog` 使用 created-ID 清理与 session 恢复逻辑。

### AC-RE-P2-02：iOS 恢复失败的 UI 错误反馈

**状态：已关闭。**

设置页使用 `do/catch` 写入 `recoveryErrorMessage`，通过 alert 呈现底层错误文本；导入器取消、文件读取和版本错误也统一进入同一反馈路径。

## 4. 已验收通过的改动

- 图片引用的单层文件名校验、目录边界校验和非法引用只读保护。
- macOS/iOS 共享 catalog loader 的 missing/corrupt/empty/future/backup 判定；macOS 主 catalog 缺失时可从有效 backup 恢复。
- 同步 mutation 携带 expected local hash，并在 batch 最终提交前再次 freshness 校验；批量 apply 只推进实际提交日期的 baseline。
- 交易任务 per-journal token、旧任务迟到保护、切本状态刷新和无 cache 删除取消。
- `PaperSim.reset()` revision 与 warp 重建测试。
- 导出在目标目录生成临时 zip，最终替换失败时保留旧目标。
- 日历缓存 TTL、失败保留旧缓存和 single-flight；iOS 首页刷新范围隔离。
- Universal 构建、签名失败门禁和 zip 解压后严格签名验证脚本。
- iOS `WickPhoneTests` XCTest target：writer 切本隔离、普通/远端删除事务回滚、catalog future-version backup 恢复。

## 5. 验证记录

本轮实际执行：

```text
swift test
Executed 282 tests, with 0 failures

xcodebuild -project ios/WickPhone.xcodeproj \
  -scheme WickPhone \
  -destination 'generic/platform=iOS' \
  build CODE_SIGNING_ALLOWED=NO
BUILD SUCCEEDED

xcodebuild test -project ios/WickPhone.xcodeproj \
  -scheme WickPhone \
  -destination 'platform=iOS Simulator,id=DE61CD5C-0090-45BE-AB4C-2E77B86F7DAA' \
  CODE_SIGNING_ALLOWED=NO
Executed 4 tests, with 0 failures
TEST SUCCEEDED

swift build --target WickCalendarKit \
  --triple arm64-apple-ios16.0 \
  --sdk "$(xcrun --sdk iphoneos --show-sdk-path)"
Build of target: 'WickCalendarKit' complete

make package
Created dist/Wick.app and dist/Wick-macOS.zip
Universal arm64+x86_64; codesign --verify --deep --strict passed; zip integrity passed

git diff --check
passed
```

本轮 iOS Simulator 回归覆盖 4 项测试，结果为 `Executed 4 tests, with 0 failures`；测试 target 已加入 `WickPhone` scheme 的 TestAction，避免只验证编译而不执行测试。

测试输出中出现 CoreData `Failed to create NSXPCConnection` 和 Simulator AppIntents 环境日志，但相关用例均通过。本轮没有真实 Dropbox/交易所网络、iPhone 真机后台恢复或 Instruments 大数据量测量，因此这些仍属于发布前人工验证项。

此前 `make package` 暴露的 Swift 6 主 actor 隔离 warning（`IMESafeTextViews.swift`、`JournalWindowController.swift`）已清理；当前 macOS 打包不再产生这两处 warning。

另外，`PhoneJournalStore` 位于 iOS Xcode 工程而非 SwiftPM 测试 target；`swift test` 不执行 iOS 代码，但新增的 `WickPhoneTests` 已由 `xcodebuild test` 在 iOS Simulator 实际执行 4 项相关回归。

## 6. 合并前复验清单

1. 已关闭 AC-RE-P1-01 至 AC-RE-P1-04，并完成 macOS 与 iOS Simulator 确定性回归测试。
2. 发布前在 iOS 真机验证“编辑 A → 立即切 B → 退出/重载”不会交叉写入，并验证 flush 错误提示。
3. 发布前在 iOS 真机补做删除目录/catalog 故障注入和 catalog backup/JSON 恢复交互测试。
4. 真实 Dropbox/交易所网络、后台挂起恢复和 Instruments 大数据量性能测量不在本轮自动门禁范围内。

## 7. 真机测试包

版本已统一为 `1.10.13 (52)`：

- macOS Universal App：`dist/Wick.app`
- macOS 分发包：`dist/Wick-macOS.zip`
- iOS Apple Development archive：`dist/WickPhone-1.10.13-52.xcarchive`

iOS archive 已通过签名校验，bundle ID 为 `com.miaoz.wick.phone.dev`，签名团队为 `2QR53496J6`。连接的 iPhone 当前因 Developer Disk Image 未挂载而无法直接执行 device build；解锁设备并启用开发者服务后，可从该 archive 通过 Xcode 安装测试。
