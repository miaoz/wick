# AGENTS.md

> 本文件面向 AI 编码代理，汇总 Wick 项目的架构、构建、测试与约定。信息均来自对仓库的实际阅读，改动代码前请先核对相关源文件。

## 项目概览

- **Wick** 是一款原生 macOS 菜单栏应用（`LSUIElement`，不显示 Dock 图标）。
- 菜单栏显示蜡烛模板图标，点击弹出面板，实时展示**日 / 周 / 月 / 年**的剩余百分比、剩余时长与结束时间（每秒刷新）。
- 内置**日记**功能：一天一篇日记，篇内多条目（标签 + 正文 + 图片），支持按标签/全文以条目粒度检索、每日本地通知提醒、zip 导出/导入。
- 其他能力：登录时启动（`SMAppService`）、亮/暗/跟随系统外观（配色由「一日弧光」主题引擎驱动）、中/英文界面、菜单栏百分比显示、基于 GitHub Releases 的检查更新。
- **平台**：macOS 13+，Apple Silicon 与 Intel（正式打包产出 Universal 二进制）。
- **技术栈**：Swift 6.1+（`Package.swift` 声明 `swift-tools-version: 6.1`；主开发环境为 Xcode 26 / Swift 6.3）、SwiftUI + AppKit、Swift Package Manager。**无任何第三方依赖**（无 `Package.resolved`）。
- Bundle ID：`com.miaoz.wick`；当前版本默认 `1.4.0 (9)`（见 `scripts/package_app.sh` 中的 `VERSION`/`BUILD` 默认值）。

## 仓库结构与模块划分

SwiftPM 三个 target（`Package.swift`）：

- `WickCore`（库，几乎全部代码，可被测试 `@testable import`）
- `Wick`（可执行，`Sources/Wick/main.swift` 仅 3 行：调用 `WickApp.main()`）
- `WickTests`（单元测试，仅依赖 `WickCore`）

`Sources/WickCore/` 各文件职责：

| 文件 | 职责 |
| --- | --- |
| `WickApp.swift` | `MenuBarExtra` 场景、`AppDelegate`（外观/登录项/提醒/更新检查启动、退出前落盘）、菜单栏 label（蜡烛图标 + 可选当日剩余百分比） |
| `ProgressPanelView.swift` | 菜单栏弹出的进度面板与设置页 UI（`TimelineView` 每秒刷新；`PanelTheme` 为薄结构体，全部色值委托给 `DayArcEngine`） |
| `WickTheme.swift` | 「一日弧光」主题引擎：`WickRGB`（可插值/可做 WCAG 对比度计算的 sRGB 值类型）、`WickPalette`（全部色角色）、`DayPhase`（晨光/白昼/暮色/夜幕四锚点）、`DayArcEngine`（按时刻在 4 相位 × 亮/暗 2 套锚点色板间插值；`MetricTheme` 色相族恒定、仅辉光随相位缩放；`WICK_ARC_TIME=HH:mm` 环境变量可伪造"当前时刻"用于调试/截图）；`\.wickPalette` 环境键 |
| `TimeProgress.swift` | `TimeProgressCalculator`：日/周/月/年剩余比例的纯计算（可注入 `Date`/`Calendar`，便于测试） |
| `JournalModels.swift` | 日记模型：`JournalEntry`（某日，1..n 个 `JournalItem`：标签/正文/图片文件名）、`JournalSnapshot`（Codable，`currentVersion = 1`） |
| `JournalStore.swift` | 日记存储（`@MainActor ObservableObject` 单例）：落盘、`.bak` 与滚动备份、加载失败只读保护、图片管理、zip 导入导出；**一天一篇**由 `createEntry`/`updateEntry` 的按日合并保证 |
| `JournalViews.swift` | 日记窗口 UI（`JournalRootView`，`NavigationSplitView` 双栏 + 系统侧栏折叠；色值取自 `\.wickPalette`，根视图 300s `TimelineView` 刷新；编辑器顶部为 `DayArcStrip` 24h 弧光渐变条，今日条目带"此刻"圆点；头部日期按应用语言格式化、零填充，点击弹出图形日历） |
| `JournalReminderScheduler.swift` | 每日本地通知（`UNUserNotificationCenter`）；**同文件内还有 `JournalWindowController`**——手动持有日记 `NSWindow`，因为 `MenuBarExtra` 场景里 SwiftUI `openWindow` 不可用 |
| `MenuBarExtraPanel.swift` | 用启发式（类名/styleMask）关闭 `MenuBarExtra` 面板窗口 |
| `IMESafeTextViews.swift` | AppKit 包装的单行/多行文本输入，避免中文/日文/韩文 IME 组字（marked text）期间被外部写值吞字 |
| `JournalImageProcessing.swift` | 图片导入处理：最长边 2048px，无 alpha 转 JPEG(0.82)，有 alpha 存 PNG |
| `MenuBarIcon.swift` | 代码绘制的蜡烛模板 `NSImage`（1x/2x，`isTemplate = true`，只创建一次不再变更） |
| `AppSettings.swift` | 设置单例（`AppSettings.shared`）：语言/外观/提醒/菜单栏百分比/周一起始/登录项/更新检查，全部持久化到 `UserDefaults`（键前缀 `wick.`） |
| `L10n.swift` | 文案目录：`L10n.string(.key, language:)`，中/英双语 |
| `AppInfo.swift` | 版本读取与语义化比较（`isVersion(_:newerThan:)`） |
| `UpdateChecker.swift` | 查询 GitHub Releases latest API（`miaoz/wick`），15s 超时，自定义 UA |
| `LaunchAtLogin.swift` | `SMAppService.mainApp` 封装（macOS 13+） |
| `AppNotifications.swift` | 自定义 `Notification.Name`（退出/关窗前冲刷草稿、存储恢复通知） |

其他目录：

- `assets/`：`AppIcon-master.png`、`AppIcon.icns`（`AppIcon.iconset/` 是生成中间产物，已 gitignore）
- `scripts/`：`package_app.sh`（打 `.app`）、`package_zip.sh`（打 zip）、`generate_icon_assets.sh` + `generate_icon.swift`（代码绘制图标）
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

- 测试位于 `Tests/WickTests/`，XCTest + `@testable import WickCore`，CI 在打包前执行 `swift test`。
- 现有四个测试文件：
  - `TimeProgressTests.swift`：剩余比例边界（0/1 钳制、起止时刻）、四类进度齐全、周一起始。
  - `JournalStoreTests.swift`：用 `JournalStore(rootDirectory:)`（临时目录的测试专用初始化器）覆盖一天一篇、标签按条目过滤、删除条目清理图片、持久化重载、主文件损坏时从 `.bak` 恢复、无备份时进入只读且**不覆盖磁盘坏文件**。
  - `AppInfoTests.swift`：版本号比较。
  - `WickThemeTests.swift`：主题引擎——相位归属（锚点切换、跨午夜回绕）、插值中点、全天每 15 分钟 × 亮/暗的对比度护栏（textPrimary ≥4.5、accentText ≥4.0 等）、指标色相族稳定性。
- 新增可测逻辑时的落点：纯计算放 `TimeProgressCalculator` / `DayArcEngine` 这类可注入 `Date`/`Calendar` 的静态方法；存储行为扩展 `JournalStoreTests`。UI 层无测试。

## CI 与发版

`.github/workflows/release.yml`（name: Build and Release）：

- 触发：push/PR 到 `main`、推送 tag `v*`、`workflow_dispatch`。
- 环境：`macos-26` runner，优先 `xcode-select` **Xcode 26.6**（没有则回退最新 26.x）；步骤含工具链打印、`swift test`、版本解析（tag 去掉 `v` 前缀；非 tag 用 `0.0.0-<short-sha>`，BUILD 为 run number）、`./scripts/package_zip.sh`、校验二进制、上传 artifact（30 天）。
- 仅当 tag 以 `v` 开头时用 `softprops/action-gh-release` 创建 GitHub Release 并附上 zip。
- 发版流程：`git tag v1.2.3 && git push origin v1.2.3`（tag 版本号会成为 zip/Release 版本）。

## 代码风格与约定

- **文档语言**：README 等面向用户的文档用简体中文；**代码注释、commit message 用英文**（保持一致，新增注释也用英文）。
- 无 SwiftLint/格式化配置；遵循现有风格：4 空格缩进、`// MARK: -` 分节、类型职责单一（一个文件一个主类型）。
- UI 文案**必须走 `L10n`**：`L10n.Key` 枚举加 case，并同时提供中/英文实现，不要硬编码字符串到视图里。
- 设置项一律加在 `AppSettings` 单例：`@Published` + `didSet` 写 `UserDefaults`（键名 `wick.` 前缀，集中在私有 `Keys` 枚举）；`init` 里用 `isLoading` 抑制加载期的副作用（如提醒重调度）。
- 全局单例：`AppSettings.shared`、`JournalStore.shared`、`JournalReminderScheduler.shared`、`JournalWindowController.shared`；依赖通过 `.environmentObject` 注入 SwiftUI。
- 触及 UI / AppKit 的类型标 `@MainActor`（Swift 6 并发严格检查，CI 曾因并发问题修过构建）。
- 平台能力封装为小工具枚举/类（`LaunchAtLogin`、`UpdateChecker`、`MenuBarExtraPanel`、`JournalImageProcessing`），保持这一模式而不是把 AppKit 细节散进视图。
- **颜色一律走主题引擎**：新增 UI 不得硬编码色值，从 `DayArcEngine` / `\.wickPalette` 取色；正文级文字用 `textPrimary/Secondary/Tertiary` 或 `accentText`（`accent` 仅作图形 tint）。改锚点色板后必须跑 `WickThemeTests` 的对比度护栏。调试某个时刻的配色用 `WICK_ARC_TIME=HH:mm swift run`。

## 注意事项（安全与数据保护）

- **日记数据安全是核心约束**，改动 `JournalStore` 时必须保持：
  - 加载失败进入 `isReadOnlyDueToLoadFailure`，**禁止任何写盘**（防止空数据覆盖损坏文件）；损坏文件移存为 `journal.corrupt-<ts>.json` 隔离。
  - 覆盖前先复制 sidecar `journal.json.bak`；滚动备份最多 5 份、间隔 ≥30 分钟。
  - 退出（`applicationShouldTerminate`）与关日记窗前发 `wickWillFlushJournalDrafts` 并 `flushPendingWrites()`。
- **UserNotifications 只能在正式 `.app` 包内使用**：`swift run`/裸二进制下调用会 abort，因此 `JournalReminderScheduler.notificationsAvailable` 做了包形态门控，新增通知相关代码必须维持该门控。
- **`MenuBarExtra` 的 label 里禁止放 `TimelineView` 等高频失效源**：会触发 `requestUpdate` → `setImage` 死循环占满 CPU（`WickApp.swift` 有注释；当前 label 用 30s `Timer` 且仅在文本变化时更新状态）。
- IME 组字：日记编辑用 `IMESafeTextViews` 里的封装，不要用原生 SwiftUI `TextField` 直接替换，否则中文输入会吞字（有专门修复提交）。
- 网络面很小：仅检查更新访问 `api.github.com`（15s 超时）；无遥测、无账号体系。
- 发布包 ad-hoc 签名、未公证——不要在文档/脚本中暗示已签名公证。
- 许可：仓库暂无 `LICENSE`，README 声明保留版权，新增第三方代码前需与维护者确认。
