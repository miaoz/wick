# Wick

`Wick` 是一个原生的 macOS 菜单栏应用：在系统菜单栏显示 `🕯️` 图标，点击后弹出一个下拉面板，展示日、周、月、年剩余时间百分比。

## 功能

- 使用 `MenuBarExtra` 构建原生菜单栏应用。
- 亮色模式自动使用「烛光」主题，暗色模式自动使用「极夜」主题。
- 面板展示每个时间维度的剩余百分比、剩余时长和结束时间。
- 内置设置：语言（中文 / 英文，默认中文）与外观（亮色 / 暗色 / 跟随系统）；日期格式随所选语言切换。
- 自带一套以温暖烛光为灵感生成的应用图标资源。
- 项目的默认构建入口会产出同时支持 Apple Silicon 和 Intel Mac 的通用 `.app`。
- 支持一键导出可分发的 `.zip` 安装包。
- 通过 GitHub Actions 自动打包，并在打 tag 时发布到 GitHub Releases。

## 默认构建

```bash
./build.sh
```

或者直接：

```bash
make
```

这两个入口都会调用通用打包流程，分别构建 `arm64` 和 `x86_64`，再用 `lipo` 合并成一个通用 `.app`。

> 说明：`swift build` 本身是 SwiftPM 的宿主架构构建命令，项目侧不能把它的默认行为改成通用二进制。因此这个仓库把 `./build.sh` / `make` 作为默认构建入口。

## 导出 zip 安装包

```bash
./scripts/package_zip.sh
```

或者直接：

```bash
make package
```

这个流程会先生成通用 `.app`，再打包为 zip。

zip 输出位置：

```text
dist/Wick-macOS.zip
```

指定版本号（会写入 `Info.plist`，并体现在 zip 文件名中）：

```bash
VERSION=1.2.3 BUILD=42 ./scripts/package_zip.sh
# → dist/Wick-macOS-1.2.3.zip
```

## GitHub 自动打包与分发

仓库使用 [`.github/workflows/release.yml`](.github/workflows/release.yml)：

| 触发条件 | 行为 |
| --- | --- |
| `push` / `pull_request` 到 `main` | 构建通用 macOS zip，上传为 workflow artifact |
| 推送 tag `v*`（例如 `v1.0.0`） | 同上，并创建 [GitHub Release](https://github.com/miaoz/wick/releases)，附带安装包 |
| `workflow_dispatch` | 手动触发构建 |

CI 跑在 GitHub 的 **`macos-26`** 云端机器上，并优先选用 **Xcode 26.6**（与当前本机开发环境一致；若镜像尚未装 26.6 则回退到最新的 Xcode 26.x）。打包脚本与本地相同（`./scripts/package_zip.sh`）。

### 发布新版本

```bash
# 确认 main 已是要发布的代码
git checkout main
git pull

# 打 tag 并推送（会触发 Release 工作流）
git tag v1.0.0
git push origin v1.0.0
```

发布完成后，在 [Releases](https://github.com/miaoz/wick/releases) 下载 `Wick-macOS-<version>.zip`。

### 安装说明

1. 解压 zip，将 `Wick.app` 拖到「应用程序」。
2. 首次打开若被 Gatekeeper 拦截：在 Finder 中对 `Wick.app` **右键 → 打开**，或在「系统设置 → 隐私与安全性」中允许。

当前 CI 使用 ad-hoc 签名（与本地 `package_app.sh` 一致），**未做 Apple Developer ID 签名 / 公证**。若需要双击即开、无安全提示，需要另行配置证书与 notarization。

## 开发运行

```bash
swift run
```

## 生成图标

```bash
./scripts/generate_icon_assets.sh
```

图标输出位置：

```text
assets/AppIcon-master.png
assets/AppIcon.icns
```

## 打包成通用 `.app`

```bash
./scripts/package_app.sh
```

生成的应用位于：

```text
dist/Wick.app
```
