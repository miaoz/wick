# AGENTS.md

> 面向 AI 编码代理：Wick 的架构、构建、测试与约定。只保留「看代码不易发现、不知道就会踩坑」的内容；改代码前先核对相关源文件。

## 项目概览

- **Wick**：原生 macOS 菜单栏应用（`LSUIElement`）：日/周/月/年时间进度面板 + 日记（一天一篇、多条目、标签/图片/复盘、zip 导入导出）+ Dropbox 同步 + 交易所仓位展示 + 黄历撕页日历。
- **iPhone 客户端**在 `ios/`，与 macOS **同一版本号**（单一真源 `scripts/package_app.sh`，`./scripts/set_version.sh` 或打包/CI 会自动同步进 `ios/WickPhone.xcodeproj`）。
- macOS 13+ / iOS 16+，Swift 6.1+，SwiftUI + AppKit/UIKit，SwiftPM，**无第三方依赖**。Bundle ID `com.miaoz.wick`。

## 模块划分

| Target | 职责 |
| --- | --- |
| `WickSync` | 纯 Foundation：日记模型、同步引擎、Dropbox 后端、`L10n`、**双端共享的日记库核心**（`JournalLibraryCore` = catalog 事务/删除回滚/生命周期；`JournalSyncBridge` = `JournalLocalSource` 实现，经 `JournalSyncStoreHost`/`JournalLibraryHost` 协议驱动宿主）。**禁止 `import AppKit`/`UIKit`** |
| `WickCalendarKit` | 跨平台交易日历：数据（华尔街见闻 keyless REST）+ 撕纸物理 + 渲染 + 音效 + 主题引擎本体（`WickTheme.swift`）；度量按 `PaperLayout` 参数化；依赖 `WickSync` |
| `WickTrading` | 纯 Foundation + CryptoKit：三家所 REST 客户端 + 成交→仓位聚合 + 标签匹配 + `DailyRealizedPnl` |
| `WickCore` | macOS 应用主体（测试 `@testable import`）；`Exports.swift` `@_exported` 上述三者 |
| `Wick` | 可执行入口（3 行） |

- macOS `JournalStore` = 主文件（状态/属性）+ `JournalStore+{Catalog,Content,Media,Persistence,SyncBridge}.swift` 五个 extension；**catalog 事务与同步桥接已下沉 WickSync 共享核心，双端仅此一份，勿在任一平台重写**。iOS `PhoneJournalStore`/`PhoneExchangeCoordinator` 是共享核心的薄宿主。
- 测试 target 一一对应；iOS 回归在 `ios/WickPhoneTests/`（xcodeproj 内，不在 SwiftPM）；落地页/中间件测试在 `test/agent-readiness.test.mjs`（`node --test`）。
- 主题引擎在 `WickCalendarKit/WickTheme.swift`（`WickCore/WickTheme.swift` 只剩 40 行 `WickPrintFont`，双 target 同名文件注意分辨）；`JournalReviewBadge`/`BurnStripView` 也在 CalendarKit。

## 构建与测试

```bash
swift build && swift run   # 开发（仅宿主架构；非 .app 形态下本地通知被跳过）
swift test                 # 单元测试
xcodebuild test -project ios/WickPhone.xcodeproj -scheme WickPhone -destination 'platform=iOS Simulator,id=<device-id>' CODE_SIGNING_ALLOWED=NO  # iOS 回归
make && make package       # Universal 打包 / 分发 zip
node --test                # 落地页中间件回归
```

- iOS 编译校验走 **scheme**（`xcodebuild -project ios/WickPhone.xcodeproj -scheme WickPhone ... build`），**勿用 `-target`**（App target 无法解析本地包）；`WickCalendarKit` 另有 SwiftPM 直接编译校验：`swift build --target WickCalendarKit --triple arm64-apple-ios16.0 --sdk <iphoneos-sdk>`。
- CI（`.github/workflows/release.yml`）：`swift test` → iOS 模拟器 `WickPhoneTests` → 打包 → tag `v*` 建 Release + 上传 R2（直链 `https://dl.bitfroth.com/wick/Wick.zip`）。`landing.yml`：`landing/**`/`functions/**` 变更推 main，先 `node --test` 再部署 Cloudflare Pages。
- 测试约定：纯计算进可注入 `Date`/`Calendar` 的静态方法；同步分支用 `WickSyncTests` 的假后端（忠实模拟 Dropbox，**不碰网络**）；交易所客户端走注入 transport；存储行为进 `JournalStoreTests`。

## 代码约定

- 面向用户的文档用简体中文；**代码注释、commit message 用英文**。
- 4 空格缩进、`// MARK: -` 分节、一个文件一个主类型；遵循周边既有风格。
- 单用户开发阶段：可从源头重建的派生数据（如交易快照）schema 变化默认硬切重建；日记正文、图片与同步状态仍遵守数据安全约束。
- UI 文案一律走 `L10n`（加 case + 中英双实现）；设置项一律进 `AppSettings`（`wick.` 前缀 UserDefaults 键）；全局单例经 `.environmentObject` 注入。
- 触及 UI/AppKit 的类型标 `@MainActor`；平台能力封装为小工具类型，别把 AppKit 细节散进视图。
- **颜色一律走主题引擎**（`DayArcEngine` / `\.wickPalette`），禁硬编码；改色板后跑 `WickCalendarKitTests/WickThemeTests` 对比度护栏。
- **字体一律走 `AppFont`**（macOS）/ `TradingCalendarTheme.fontStyle`（日历）/ `PhoneFont`（iOS），禁硬编码 `Songti SC`/`.system(...)`——设置里选的设备字体会全局替换，绕过即漏换。

## 注意事项（坑与数据安全）

**日记数据安全（最高优先级）**

- 布局：`Wick/Journals/catalog.json` + `<uuid>/{journal.json,.bak,backups/,images/}`。加载失败进 `isReadOnlyDueToLoadFailure`，**禁止任何写盘与导出**（空快照会覆盖好归档）；catalog 同样有 `.bak` + 版本门，损坏/未来版本/空库进 `isCatalogReadOnly`，禁用一切 catalog 写入。
- 删除/导入是事务（实现在 `JournalLibraryCore`）：目录先移同卷 quarantine，catalog 写失败全回滚；导入图片同样先隔离再拷贝。**改这些路径必须保住回滚语义**。
- 图片引用唯一规则来源 `JournalImageFilename`（解码即拒非法名，不清洗）；Store 的 `imageURL(for:)` 是唯一 URL 构造器（含目录边界校验），所有读写删/同步都经它。
- `createJournal`/`registerRemoteJournal` 在只读时返回 **nil**——勿返回幻影对象，同步自动导入依赖这个诚实信号。
- **UserNotifications 只在正式 `.app` 包内可用**（裸二进制调用会 abort），`JournalReminderScheduler.notificationsAvailable` 门控必须维持。

**同步（sync v2）**

- 引擎三不变量：① rev 回声抑制（远端变更只比 rev，**本地规范哈希绝不与 Dropbox `content_hash` 比**）；② 拉取即固定点（基线 = 下载字节本地重算）；③ 绝不和自己冲突（`pushedHashes` 命中直接重推）。
- 切本隔离：周期开始即冻结 journalID/快照；落盘/改名必须带 journalID，对不上当前活跃本则 no-op。
- 删除日记本 = **全端删除**（墓碑传播）；远端删除最后一本时播种新 UUID 纯本地默认本（不继承绑定/同步状态）；Coordinator 只对 deleted/notFound 确认，ioFailure/refusedReadOnly 保留墓碑重试。
- 远端变更一轮收为 `[JournalSyncMutation]` 一次 `applySyncedChanges`（PF-01）；下发前 `prepareForRemoteApply` 触发编辑器 flush + 新鲜度重读（ED-01）；成功 apply 发 `JournalRemoteApply`，编辑器只对干净 draft rebase；`resolveConflict(.local)` 同样先 flush。
- 远端 manifest v1 会被本设备先升 v2 再重建；旧设备须清数据再装 v2。回调 scheme 只在打包 `.app` 注册（`swift run` 收不到）；App secret 永不入仓库。
- Dropbox 401 已由 `performAuthorized` 处理（作废缓存 token → 刷新重试一次 → 再 401 才 `needsAuth`），勿回退成直接抛错。

**交易数值口径（易错）**

- 手续费统一**负=已付、正=返佣**（HL/Binance 正数在入口取负，OKX 原生负值），`netPnl = realized + commission + funding`。
- OKX `fillSz` 单位是**张**（未做 `ctVal` 换算，展示量级注意）；OKX `subType` 是数字码（5/6/100/101/104/105/112/113/125/126 = 平仓侧），不是文本。
- HL `userFunding` 时间范围响应上限 **500 条/页**（fills 2000，翻页阈值 `fundingPageCap` 勿混用）；OKX 私有接口限流 ~10 req/2s（客户端 `minPageInterval` 已 pacing）。

**macOS 平台坑（都踩过，勿回退）**

- `MenuBarExtra` label 禁止放 `TimelineView`/Combine Timer 等高频或宿主外存活的失效源（CPU 死循环 / macOS 26 崩溃）；当前用随视图取消的 30s `.task`。
- macOS 13 的 `MenuBarExtra .window` 首版布局拿错误几何 → 走 `MenuBarExtraContentHost` 离屏量尺寸再装自有 `NSHostingView`；高度变化回写 SwiftUI `.frame`。面板根部禁止隐式 `.animation(value:)`。
- 日记窗：空 `NSToolbar(.unified)` 只建立标题栏几何，**不放 item**（macOS 26 会套玻璃胶囊）；控件全在 `JournalTopBarView` 的 titlebar accessory，**不测量/不移动红绿灯**。不用 NavigationSplitView（26 画成浮动卡片）。日记本行用 `onTapGesture` 勿改回 `Button`（抢 `onDrag`）。侧栏标签用 `SidebarChipFlow` 勿用 `LazyVGrid adaptive`。
- 窗口 hosting view 必须包一层普通 `NSView` 容器（否则窗口每次布局自生长）；`minSize` 不吃程序化 setFrame，`windowDidResize` 兜底强拉。侧栏 body 里**禁止对非活跃本读盘/聚合**（统计走失效缓存）；Lightbox 全图按文件名加载一次进 `@State`。
- 日记编辑必须用 `IMESafeTextViews`（原生 `TextField` 中文 IME 吞字）。

**其他**

- 交易日历纹理快照必须随 `isLoading`/错误态重刷（否则闲日永卡「加载中」）；`TraderAlmanac` 种子是纯整数 `year*10000+month*100+day`，**勿改回 `Hasher`**（每进程随机）。iOS 长按分享只有页面上半部有效（撕页区手势吃长按）。
- 物理黄历（彩蛋）的撕到页是**粘滞**的：`TearOffState`（`wick.calendar.tornToDate`）固定当前页，跨启动/跨午夜不自动回今天也不自动前进（**勿恢复 `NSCalendarDayChanged` 重置或开窗时的 `.wickCalendarResetToToday`**）；唯一重置是双端设置里彩蛋关→开（macOS `AppSettings.physicalCalendarEnabled` didSet / iOS `SettingsView` onChange）。
- landing 改文案后必须跑 `scripts/subset_landing_font.sh` 重新子集化字体（源已 pin 到 google/fonts commit，勿改回 `main`）；iOS 无预装中文宋体，不自带字体必混字。
- 网络面：`api.github.com`、两台 `*-wscn.awtmt.com`、`fapi.binance.com`/`www.okx.com`/`api.hyperliquid.xyz`，全部只读 15–20s 超时；无遥测、无账号体系。
- 许可：仓库暂无 `LICENSE`，保留版权，新增第三方代码前需与维护者确认。
