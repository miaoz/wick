# 秉烛 · Linux stage 0

Omarchy 上的蜡烛是 Quickshell `bar-widget`（[`omarchy/wick.progress`](omarchy/wick.progress)），点击打开系统 `KeyboardPanel` 下拉，和时钟 / 网络同一套。不要跑下面的 Qt 托盘当 Omarchy UI。

安装：把 `omarchy/wick.progress` 拷到 `~/.config/omarchy/plugins/`，在 `shell.json` 的 `bar.layout.right` 加上 `{"id": "wick.progress"}`，然后 `omarchy-restart-shell`。

## 后备：Qt 6 SNI 托盘（非 Omarchy）

没有 Quickshell 栏的发行版才用这个。托盘走 StatusNotifierItem。

```bash
sudo pacman -S --needed qt6-base qt6-declarative qt6-svg cmake ninja gcc
cd linux
cmake -G Ninja -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
./build/wick
```

Debian 对照：`qt6-base-dev qt6-declarative-dev qt6-svg-dev qml6-module-qtquick qml6-module-qtquick-layouts cmake ninja-build g++`。目标 Qt **6.8**，CMake 下限 6.4。
