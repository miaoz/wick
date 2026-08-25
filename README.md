# Wick（秉烛日记）

[![Build and Release](https://github.com/miaoz/wick/actions/workflows/release.yml/badge.svg)](https://github.com/miaoz/wick/actions/workflows/release.yml)
[![Latest Release](https://img.shields.io/github/v/release/miaoz/wick)](https://github.com/miaoz/wick/releases/latest)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B%20%7C%20iOS%2016%2B-black)](https://github.com/miaoz/wick)
[![Swift](https://img.shields.io/badge/Swift-6.1%2B-F05138)](https://www.swift.org)

**Wick**（中文名「**秉烛日记**」，英文名「**Wick**」）是一款专为交易者与记录者打造的原生应用（macOS / iOS）：
- **macOS 菜单栏**：在状态栏显示蜡烛图标，点击后弹出面板，实时展示**日 / 周 / 月 / 年**还剩多少时间；
- **日记（一天一页纸）**：一天一篇日记、篇内多条目（标签 + 正文 + 图片），条目级检索、复盘白文方章与全套字体自适应排版，可把**交易所仓位**挂到对应日记条目上；
- **交易日历（彩蛋）**：撕页物理「黄历」（全球宏观 + 财报），桌面透明贴窗与手机撕页交互。

<p align="center">
  <img src="assets/AppIcon-master.png" alt="Wick icon" width="128" height="128">
</p>

## 功能

- **菜单栏常驻**：基于 `MenuBarExtra` 的原生体验，不占用 Dock；可选显示今日剩余百分比
- **时间进度**：日、周、月、年的剩余百分比、剩余时长与结束时间，每秒刷新；可设周从周一开始
- **日记**：一天一篇日记、篇内多条目（标签 + 正文 + 图片），条目级检索、可选每日提醒；秉烛主窗 = 全宽顶栏 + 手动三栏（导航 / 日期列表 / 编辑页）+ 可选检查器
- **多日记本**：在栏一（导航）的「日记本」节中切换（点行）、新建（节头右侧 + 钮）、重命名 / 删除（日记本行右键菜单，删除仅限非最后一本）；旧版单日记数据首次启动自动迁移
- **数据安全**：退出/关窗强制落盘、`journal.json.bak` 与滚动备份、加载失败只读保护、导出/导入 zip
- **Dropbox 同步（可选）**：本地存储始终是唯一真源，同步引擎按「天」与 Dropbox 双向对账；日记本改名跨设备同步；删除以墓碑传播、冲突保留双方内容、远端文件意外丢失自动回传；可另行开启仓位快照同步供其他设备只读展示；OAuth PKCE 登录，不在客户端内置 App secret
- **交易日历（彩蛋）**：设置 →「交易日历」开启后，日记窗口顶栏的日历按钮召唤撕页「黄历」——每页展示当日全球宏观事件与财报，拖拽撕纸即翻到次日；无边框透明窗口可贴在桌面上（详见 [交易日历](#交易日历)）
- **交易所仓位（可选）**：每个日记本可绑定一个账号（Binance USDⓈ-M / OKX 永续 / Hyperliquid）。只读凭据仅存本机（打包应用走钥匙串，`swift run` 走本地文件以免每次重编译弹密码），仓位按「开仓日期 + 标签」挂到条目上；缺少匹配标签时自动补建条目（详见 [交易所仓位同步](#交易所仓位同步)）
- **登录启动**：可选「登录时启动」（`SMAppService`）
- **秉烛主题**：面板与日记配色随一天的时间流动（晨光 / 白昼 / 暮色 / 夜幕四相位平滑过渡），纸面墨迹的设计语言，亮 / 暗 / 跟随系统外观三档可选
- **字体**：设置里可从设备已安装的字体中任选一套，全局换用（日记、设置、交易日历、编辑器输入）；不选即默认系统外观
- **设置**：语言、外观、字体、提醒、菜单栏百分比、数据目录、版本与检查更新（GitHub Releases）
- **Universal 二进制**：同时支持 Apple Silicon 与 Intel Mac
- **开箱可分发**：本地一键打 zip；推送 tag 后由 GitHub Actions 自动发版

## 系统要求

| 项目 | 要求 |
| --- | --- |
| 系统 | macOS 13 Ventura 或更高 |
| 架构 | Apple Silicon 或 Intel（Universal 包） |
| 开发 | Xcode 16+ / Swift 6.1+（推荐 Xcode 26、Swift 6.3，与 CI 一致） |

## 安装

### 预编译包（推荐）

1. 打开 [Releases](https://github.com/miaoz/wick/releases/latest)
2. 下载 `Wick-macOS-<version>.zip`
3. 解压后将 `Wick.app` 拖到「应用程序」
4. 首次运行若被 Gatekeeper 拦截：在 Finder 中对应用 **右键 → 打开**，或在「系统设置 → 隐私与安全性」中允许

> **说明：** 发布包使用 ad-hoc 签名，**尚未**使用 Apple Developer ID 签名或公证。因此首次打开可能需要手动允许。

### 从源码安装

```bash
git clone https://github.com/miaoz/wick.git
cd wick
./scripts/package_app.sh
open dist/Wick.app
```

## 使用

1. 启动后，菜单栏会出现蜡烛图标（系统会按菜单栏风格着色）
2. 点击图标打开进度面板，查看日 / 周 / 月 / 年剩余时间
3. 点击书本图标（或设置里的「打开日记」）打开日记窗口
4. 在设置中可切换语言与外观、配置日记提醒、连接交易所同步仓位、开启「交易日历」彩蛋，或退出应用

应用为 `LSUIElement` 菜单栏工具，不会在 Dock 中显示图标。

### 日记

日记适合把「某一天」的多段记录写在一起：例如同一天关注多个主题时，用**多条条目**分别记下标签、文字与图片，之后再按标签检索单条内容。

#### 数据模型

```text
日记（某日）
├── 日期
├── 标题（可选）
└── 条目 1..n
    ├── 标签（每条一个）
    ├── 正文
    └── 图片（可多张）
```

#### 界面与能力

| 能力 | 说明 |
| --- | --- |
| 入口 | 菜单栏进度面板的书本按钮；设置页的「打开日记」；每日提醒通知 |
| 布局 | 秉烛主窗：全宽顶栏 + 手动三栏（导航 / 日期列表 / 编辑页）+ 可选检查器；顶栏三态循环钮（⌃⌘S）在 全导航 → 仅列表 → 专注 间折叠栏位；编辑页 = 一天一页纸，页眉大日期点开可改日 |
| 无筛选 | 时间轴按「整天日记」列出；右侧编辑当天全部条目，可添加 / 删除条目 |
| 标签筛选 | 只列出**匹配该标签的条目**；编辑区只显示这一条，不带出同日其他条目 |
| 全文搜索 | 与标签筛选相同，按条目匹配标题 / 标签 / 正文 |
| 查看整天 | 在条目视图中可「查看当天全部」，退出筛选并打开完整日日记 |
| 图片 | 在条目内拖入、选择文件，或从剪贴板粘贴 |
| 自动保存 | 编辑后短延迟写入本地，无需手动保存 |
| 提醒 | 设置中开启「每日提醒写日记」并选择时间（默认 21:00）；点击通知打开日记 |
| 存储 | `~/Library/Application Support/Wick/Journals/`（`catalog.json` + 每本日记独立目录：`journal.json`、`.bak`、滚动备份、`images/`；旧版单日记路径会自动迁移） |
| 导入导出 | 设置 → 数据：导出/导入**当前**日记本的 zip 或 `journal.json`；可在 Finder 中显示数据目录 |
| 快捷键 | 日记窗口 `⌘N` 打开/创建今日日记 |

> **说明：** 本地通知依赖正式 `.app` 包（含 Bundle ID）。`swift run` 开发运行时会跳过提醒调度，打包后的 `Wick.app` 可正常使用。

### 交易日历

「交易日历」是一款 himekuri「黄历」主题的撕页日历（[himekuri](https://github.com/pluk-inc/himekuri)）——秉烛双色印刷（烟墨 × 朱砂）：大号日期、竖排星期填色列、中部农历与干支。它以**彩蛋**形式提供：在设置 →「交易日历」开启后，日记窗口顶栏的日历按钮用来召唤 / 收起；窗口**无边框透明**，日历 pad 之外的区域点击穿透，可以像实体台历一样贴在桌面上。

每一页展示**当天全球宏观事件与财报**：

| 内容 | 说明 |
| --- | --- |
| 事件 | 两栏双 tab：**宏观事件**（经济数据发布、央行讲话、打新 / 发布会等，按重要性降序，数值行常显「今值 / 预期 / 前值」）+ **财报**（盘前 / 盘后标记、代码、公司名、EPS 预期 / 今值） |
| 数据源 | 华尔街见闻公开 REST 接口直连取数（宏观 + 财报两路），无需任何密钥 |
| 翻页 | 拖住页角撕下即翻到次日，碎纸从 pad 飘落到屏幕外并伴程序合成撕纸音效；事件较多的日子自动分页，可用**方向键 / 滚轮**翻动事件页 |
| 无事件日 | 盖一枚红色方印章（周末「休市」/ 工作日「本日无事」） |
| 离线 | 数据有本地缓存，断网也能翻看已缓存的日子；取数失败不会覆盖缓存 |

> iPhone 客户端同样内置交易日历，以**全屏页面**呈现（iOS 16+，见下文「iPhone 客户端」）。

### 交易所仓位同步（可选）

在设置 →「交易所」为**当前日记本**绑定一个账号。支持 **Binance USDⓈ-M**、**OKX 永续（SWAP）**、**Hyperliquid 永续**。一本日记最多一个账号；分所请开第二本日记。

- **凭据**：中心化交易所填只读 API Key（OKX 另需 Passphrase）；Hyperliquid **只填 0x 地址、不收私钥**（成交查询是公开接口）。打包后的 `.app` 把密钥存在本机钥匙串；`swift run` 开发构建写在 `Application Support/Wick/dev-secrets.json`（权限 0600），避免每次重编译都弹钥匙串密码。
- **同步范围**：从该日记本**最早一篇日记**起（没有日记时**仅从当天开始**，不回填更早历史），更早的成交不拉。日常增量刷新（30 分钟 + 打开日记）。OKX / Hyperliquid 所侧另外还有深度上限（大约 3 个月 / 最近 1 万笔）。
- **展示**：按「开仓日期 + 标签」挂到条目上。标签 `BTC` 可匹配 `BTCUSDT` / `BTCUSDC` / Hyperliquid 的 `BTC`。
- **自动补条目**：持续确保每笔仓位的开仓日有可匹配条目；没有日记时创建日记，已有日记但缺少对应标签时只追加该标签。标签沿用你惯用写法，否则用基础币种；不会改写已有标签、正文、图片或复盘。
- **只读不写**：不改已有日记正文和标签。
- **跨设备快照（可选）**：连接 Dropbox 后可在「同步」区开启「同步仓位快照」。成交、资金费与聚合仓位按最新拉取时间整份同步，其他设备无需交易所凭据即可只读展示；开关默认关闭，API Key、Secret、Passphrase 与完整 Hyperliquid 地址不会上传。

> 直连各所 REST，无第三方聚合。凭证不上传。

### iPhone 客户端（开发中）

仓库 `ios/` 附带一个 iPhone 客户端（v0，仅中文 UI，真机调试，尚未上架）。首页是菜单栏进度面板的手机版（日 / 周 / 月 / 年剩余进度，每秒刷新），日记经书本按钮进入；**交易日历**同样内置其中，以**全屏撕页页面**呈现——米白纸页铺满整屏、装订条横跨刘海行、内容避让安全区。真机运行：用 Xcode 打开 `ios/WickPhone.xcodeproj`，Signing 选择 Personal Team 后运行到自己的设备。

## 从源码构建

### 快速开始

```bash
# 开发运行（当前架构）
swift run

# 默认产物：Universal .app → dist/Wick.app
make
# 或
./build.sh

# 导出可分发 zip → dist/Wick-macOS.zip
make package
# 或
./scripts/package_zip.sh
```

### 版本号

打包时可注入版本信息（写入 `Info.plist`，并体现在 zip 文件名中）：

```bash
VERSION=1.3.1 BUILD=6 ./scripts/package_zip.sh
# → dist/Wick-macOS-1.3.1.zip
```

### 构建说明

| 命令 | 说明 |
| --- | --- |
| `swift run` / `swift build` | SwiftPM 宿主架构构建，适合开发调试 |
| `./build.sh` / `make` | 分别编译 `arm64` 与 `x86_64`，经 `lipo` 合并为 Universal `.app` |
| `./scripts/package_app.sh` | 生成 `dist/Wick.app`（含图标与 `Info.plist`） |
| `./scripts/package_zip.sh` | 在 `.app` 基础上打包 zip |
| `./scripts/generate_icon_assets.sh` | 从脚本重新生成 `assets/AppIcon*` |

> `swift build` 默认只产出当前架构；项目把 `./build.sh` / `make` 作为正式打包入口，以确保 Universal 二进制。

### 图标资源

```bash
./scripts/generate_icon_assets.sh
```

输出：

- `assets/AppIcon-master.png`
- `assets/AppIcon.icns`

## 持续集成与发版

仓库使用 [GitHub Actions](.github/workflows/release.yml) 自动打包：

| 触发 | 结果 |
| --- | --- |
| `push` / `pull_request` 到 `main` | 构建 zip，上传为 workflow artifact |
| 推送 tag `v*`（如 `v1.2.0`） | 构建 zip，并创建 [GitHub Release](https://github.com/miaoz/wick/releases) |
| `workflow_dispatch` | 手动触发构建 |

CI 使用 **`macos-26`** runner，优先选用 **Xcode 26.6**（与当前主开发环境对齐；若镜像无 26.6 则回退到最新 Xcode 26.x）。打包路径与本地相同：`./scripts/package_zip.sh`。

### 发布新版本

```bash
git checkout main
git pull
git tag v1.2
git push origin v1.2
```

完成后在 [Releases](https://github.com/miaoz/wick/releases) 下载 `Wick-macOS-<version>.zip`。

## 项目结构

```text
wick/
├── Package.swift                 # Swift Package 清单（WickSync + WickCalendarKit + WickTrading + WickCore + Wick + 测试）
├── Sources/WickSync/             # 平台无关（纯 Foundation）日记模型 + 同步引擎 + Dropbox 后端
│   ├── JournalModels.swift       # 日记数据模型（UUID 身份 + 可编辑日期）
│   ├── JournalSyncEngine.swift   # 按 UUID 对账引擎（推/拉/合并/墓碑/自愈 + 日记名对账）
│   ├── JournalDayMerge.swift     # 同一 UUID 两版本的条目级并集合并
│   ├── DropboxSyncBackend.swift  # Dropbox API v2 + PKCE OAuth
│   ├── L10n.swift / TimeProgress.swift  # 文案与进度计算（iOS 复用）
│   └── …                         # 状态/布局/协议/Keychain 等
├── Sources/WickCalendarKit/      # 跨平台交易日历（macOS + iOS 共用同一份）
│   ├── TradingCalendarRootView.swift  # 撕页日历根视图（黄历页 + 撕纸物理 + 飘落）
│   ├── MacroCalendar*.swift      # 宏观事件数据层（akshare macro_info_ws 直连 + 缓存）
│   ├── PaperSim.swift            # verlet 撕纸物理（SpriteKit 变形）
│   ├── MacroDayPageView.swift    # 「黄历」页（农历 + 宏观事件固定栏目）
│   └── …                         # 主题 / 撕口 / 飘落轨迹 / 程序合成音效 / 平台 shim
├── Sources/WickTrading/          # 交易所集成（纯 Foundation：Binance 客户端 + 仓位聚合 + 标签匹配）
│   ├── BinanceFuturesClient.swift      # 签名 / 分页 / 错误映射的只读客户端
│   ├── PositionAggregator.swift        # 成交 → 开平仓会话聚合
│   ├── PositionEntryPlanner.swift      # 缺少匹配标签的交易条目规划
│   ├── SymbolTagMatcher.swift          # 宽松标签匹配 / 基础币种推导
│   └── TradingPositionModels.swift     # 仓位快照模型
├── Sources/WickCore/             # macOS 应用逻辑与 UI（依赖 WickSync + WickCalendarKit + WickTrading）
│   ├── WickApp.swift             # MenuBarExtra、AppDelegate
│   ├── ProgressPanelView.swift   # 进度面板与设置 UI（含同步设置、交易日历彩蛋开关）
│   ├── JournalStore.swift        # 本地持久化、备份、导入导出（尾部为同步桥接扩展）
│   ├── JournalRootView.swift     # 日记主窗（全宽顶栏 + 手动三栏 + 可选检查器）
│   ├── SyncCoordinator.swift     # 同步生命周期、连接/断开、退出前最终同步
│   ├── ExchangePositionCoordinator.swift / ExchangeSettingsContent.swift / JournalExchangePositions.swift  # 交易所仓位同步（生命周期 / 设置 UI / 条目卡片展示）
│   ├── TradingCalendarWindowController.swift / FallingPageOverlay.swift  # 日历彩蛋窗口与碎纸叠加窗（macOS 专属）
│   ├── JournalReminderScheduler.swift  # 每日提醒
│   ├── AppSettings.swift         # 语言、外观、提醒、登录项、同步开关等
│   └── MenuBarIcon.swift         # 菜单栏模板图标
├── Sources/Wick/main.swift       # 可执行入口
├── ios/                          # iPhone 客户端（v0，仅中文 UI，真机调试；链接 WickSync + WickCalendarKit）
├── Tests/                        # WickTests + WickSyncTests + WickCalendarKitTests + WickTradingTests 单元测试
├── assets/                       # 应用图标
├── scripts/                      # 图标生成与打包
├── build.sh / Makefile           # 默认构建入口
└── .github/workflows/            # CI / Release
```

## 贡献

欢迎 Issue 与 Pull Request。

1. Fork 本仓库并创建分支：`git checkout -b feature/your-change`
2. 本地验证：`swift build` 与（如涉及打包）`./scripts/package_app.sh`
3. 提交清晰的 commit message，并打开 PR 说明动机与改动

若改动影响 UI，请尽量附上截图或简短说明。

## 许可

本仓库尚未添加 `LICENSE` 文件。在声明开源许可证之前，版权归作者所有；使用、修改与再分发请先与维护者确认，或提交 PR 提议采用常见许可证（如 MIT）。

## 致谢

- [SwiftUI](https://developer.apple.com/xcode/swiftui/) · [Swift Package Manager](https://www.swift.org/documentation/package-manager/)
- [GitHub Actions](https://docs.github.com/actions) 用于自动化构建与发布
