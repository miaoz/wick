# 秉烛 · Omarchy bar widget

Omarchy 上的蜡烛不是独立窗口，是 Quickshell `bar-widget`。
点击走 `qs.Ui.KeyboardPanel`（全屏透明 layer-shell overlay，卡片锚在栏图标下），和时钟 / 网络同一套。

## 安装

```bash
cp -a linux/omarchy/wick.progress ~/.config/omarchy/plugins/
```

在 `~/.config/omarchy/shell.json` 的 `bar.layout.right` 最前面加上 `{"id": "wick.progress"}`，然后：

```bash
omarchy-restart-shell
```

Qt 6 托盘程序（`linux/` 下的 CMake 工程）是非 Omarchy / 纯 SNI 环境的后备。Omarchy 上 `wick` 仍作为守护进程运行（日记 / 设置 / Dropbox），但托盘蜡烛会自动隐藏，只留栏里这支。
