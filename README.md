# Wick

[![Build and Release](https://github.com/miaoz/wick/actions/workflows/release.yml/badge.svg)](https://github.com/miaoz/wick/actions/workflows/release.yml)
[![Latest Release](https://img.shields.io/github/v/release/miaoz/wick)](https://github.com/miaoz/wick/releases/latest)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-black)](https://github.com/miaoz/wick)
[![Swift](https://img.shields.io/badge/Swift-6.1%2B-F05138)](https://www.swift.org)

**Wick** 是一款原生 macOS 菜单栏应用：在状态栏显示蜡烛图标，点击后弹出面板，展示**日 / 周 / 月 / 年**还剩多少时间；并内置**日记**，用标签与图片按条目记录与回顾。

<p align="center">
  <img src="assets/AppIcon-master.png" alt="Wick icon" width="128" height="128">
</p>

## 功能

- **菜单栏常驻**：基于 `MenuBarExtra` 的原生体验，不占用 Dock；可选显示今日剩余百分比
- **时间进度**：日、周、月、年的剩余百分比、剩余时长与结束时间，每秒刷新；可设周从周一开始
- **日记**：双栏原生窗口；一天一篇日记，篇内多条目（标签 + 正文 + 图片）；标签/搜索以条目为粒度；可选每日提醒
- **数据安全**：退出/关窗强制落盘、`journal.json.bak` 与滚动备份、加载失败只读保护、导出/导入 zip
- **登录启动**：可选「登录时启动」（`SMAppService`）
- **烛光 / 极夜主题**：亮色与暗色自动切换面板配色
- **设置**：语言、外观、提醒、菜单栏百分比、数据目录、版本与检查更新（GitHub Releases）
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
4. 在设置中可切换语言与外观、配置日记提醒，或退出应用

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
| 布局 | 左侧时间轴 + 右侧编辑区；工具栏可在双栏 / 单栏间切换 |
| 无筛选 | 时间轴按「整天日记」列出；右侧编辑当天全部条目，可添加 / 删除条目 |
| 标签筛选 | 只列出**匹配该标签的条目**；编辑区只显示这一条，不带出同日其他条目 |
| 全文搜索 | 与标签筛选相同，按条目匹配标题 / 标签 / 正文 |
| 查看整天 | 在条目视图中可「查看当天全部」，退出筛选并打开完整日日记 |
| 图片 | 在条目内拖入、选择文件，或从剪贴板粘贴 |
| 自动保存 | 编辑后短延迟写入本地，无需手动保存 |
| 提醒 | 设置中开启「每日提醒写日记」并选择时间（默认 21:00）；点击通知打开日记 |
| 存储 | `~/Library/Application Support/Wick/Journal/`（`journal.json`、`.bak`、滚动备份、`images/`） |
| 导入导出 | 设置 → 数据：导出 zip / 导入 zip 或 `journal.json`；可在 Finder 中显示数据目录 |
| 快捷键 | 日记窗口 `⌘N` 打开/创建今日日记 |

> **说明：** 本地通知依赖正式 `.app` 包（含 Bundle ID）。`swift run` 开发运行时会跳过提醒调度，打包后的 `Wick.app` 可正常使用。

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
VERSION=1.3 BUILD=4 ./scripts/package_zip.sh
# → dist/Wick-macOS-1.3.zip
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
├── Package.swift                 # Swift Package 清单（WickCore + Wick + 测试）
├── Sources/WickCore/             # 应用逻辑与 UI
│   ├── WickApp.swift             # MenuBarExtra、AppDelegate
│   ├── ProgressPanelView.swift   # 进度面板与设置 UI
│   ├── TimeProgress.swift        # 日/周/月/年计算
│   ├── JournalModels.swift       # 日记数据模型
│   ├── JournalStore.swift        # 本地持久化、备份、导入导出
│   ├── JournalViews.swift        # 日记双栏 UI
│   ├── JournalReminderScheduler.swift  # 每日提醒
│   ├── AppSettings.swift         # 语言、外观、提醒、登录项等
│   ├── L10n.swift                # 文案
│   └── MenuBarIcon.swift         # 菜单栏模板图标
├── Sources/Wick/main.swift       # 可执行入口
├── Tests/WickTests/              # 单元测试
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
