# Wick

[![Build and Release](https://github.com/miaoz/wick/actions/workflows/release.yml/badge.svg)](https://github.com/miaoz/wick/actions/workflows/release.yml)
[![Latest Release](https://img.shields.io/github/v/release/miaoz/wick)](https://github.com/miaoz/wick/releases/latest)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-black)](https://github.com/miaoz/wick)
[![Swift](https://img.shields.io/badge/Swift-6.1%2B-F05138)](https://www.swift.org)

**Wick** 是一款原生 macOS 菜单栏应用：在状态栏显示蜡烛图标，点击后弹出面板，展示**日 / 周 / 月 / 年**还剩多少时间。

<p align="center">
  <img src="assets/AppIcon-master.png" alt="Wick icon" width="128" height="128">
</p>

## 功能

- **菜单栏常驻**：基于 `MenuBarExtra` 的原生体验，不占用 Dock
- **时间进度**：日、周、月、年的剩余百分比、剩余时长与结束时间，每秒刷新
- **烛光 / 极夜主题**：亮色与暗色自动切换面板配色
- **设置**：语言（中文 / English）、外观（亮色 / 暗色 / 跟随系统）
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
2. 点击图标打开进度面板
3. 在面板中可进入设置：切换语言与外观
4. 在设置中可退出应用

应用为 `LSUIElement` 菜单栏工具，不会在 Dock 中显示图标。

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
VERSION=1.2.3 BUILD=42 ./scripts/package_zip.sh
# → dist/Wick-macOS-1.2.3.zip
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
git tag v1.2.0
git push origin v1.2.0
```

完成后在 [Releases](https://github.com/miaoz/wick/releases) 下载 `Wick-macOS-<version>.zip`。

## 项目结构

```text
wick/
├── Package.swift                 # Swift Package 清单
├── Sources/Wick/                 # 应用源码
│   ├── WickApp.swift             # 入口与 MenuBarExtra
│   ├── ProgressPanelView.swift   # 进度面板与设置 UI
│   ├── TimeProgress.swift        # 日/周/月/年计算
│   ├── AppSettings.swift         # 语言与外观
│   ├── L10n.swift                # 文案
│   └── MenuBarIcon.swift         # 菜单栏模板图标
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
