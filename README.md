# Wick

`Wick` 是一个原生的 macOS 菜单栏应用：在系统菜单栏显示 `🕯️` 图标，点击后弹出一个下拉面板，展示日、周、月、年剩余时间百分比。

## 功能

- 使用 `MenuBarExtra` 构建原生菜单栏应用。
- 亮色模式自动使用「烛光」主题，暗色模式自动使用「极夜」主题。
- 面板展示每个时间维度的剩余百分比、剩余时长和结束时间。
- 自带一套以温暖烛光为灵感生成的应用图标资源。
- 项目的默认构建入口会产出同时支持 Apple Silicon 和 Intel Mac 的通用 `.app`。
- 支持一键导出可分发的 `.zip` 安装包。

## 默认构建

```bash
cd /Users/miaoz/Library/CloudStorage/Dropbox/dev/workspace/Wick
./build.sh
```

或者直接：

```bash
cd /Users/miaoz/Library/CloudStorage/Dropbox/dev/workspace/Wick
make
```

这两个入口都会调用通用打包流程，分别构建 `arm64` 和 `x86_64`，再用 `lipo` 合并成一个通用 `.app`。

> 说明：`swift build` 本身是 SwiftPM 的宿主架构构建命令，项目侧不能把它的默认行为改成通用二进制。因此这个仓库把 `./build.sh` / `make` 作为默认构建入口。

## 导出 zip 安装包

```bash
cd /Users/miaoz/Library/CloudStorage/Dropbox/dev/workspace/Wick
./scripts/package_zip.sh
```

或者直接：

```bash
cd /Users/miaoz/Library/CloudStorage/Dropbox/dev/workspace/Wick
make package
```

这个流程会先生成通用 `.app`，再打包为 zip。

zip 输出位置：

```bash
/Users/miaoz/Library/CloudStorage/Dropbox/dev/workspace/Wick/dist/Wick-macOS.zip
```

## 开发运行

```bash
cd /Users/miaoz/Library/CloudStorage/Dropbox/dev/workspace/Wick
swift run
```

## 生成图标

```bash
cd /Users/miaoz/Library/CloudStorage/Dropbox/dev/workspace/Wick
./scripts/generate_icon_assets.sh
```

图标输出位置：

```bash
/Users/miaoz/Library/CloudStorage/Dropbox/dev/workspace/Wick/assets/AppIcon-master.png
/Users/miaoz/Library/CloudStorage/Dropbox/dev/workspace/Wick/assets/AppIcon.icns
```

## 打包成通用 `.app`

```bash
cd /Users/miaoz/Library/CloudStorage/Dropbox/dev/workspace/Wick
./scripts/package_app.sh
```

生成的应用位于：

```bash
/Users/miaoz/Library/CloudStorage/Dropbox/dev/workspace/Wick/dist/Wick.app
```
