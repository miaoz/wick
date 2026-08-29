# 秉烛 · Linux stage 0

Omarchy（Arch + Hyprland + Quickshell）上的原生 Qt 6 / QML 托盘蜡烛。左键弹出浮动进度纸签，右键菜单：日记 / 设置 / 退出。

**必须在 Omarchy 会话里跑**——托盘走 StatusNotifierItem，没有 Quickshell（或其它 SNI host）时蜡烛不会出现。

## 依赖

```bash
sudo pacman -S --needed qt6-base qt6-declarative qt6-svg cmake ninja gcc
```

Debian / 本仓库开发机对照：`qt6-base-dev qt6-declarative-dev qt6-svg-dev qml6-module-qtquick qml6-module-qtquick-layouts cmake ninja-build g++`。目标是 Qt **6.8**；CMake 下限 6.4。

可选字体（纸签字态）：`ttf-inter ttf-jetbrains-mono noto-fonts-cjk`。缺字会落到系统无衬线 / 宋体。

## 编译

在 `linux/` 目录：

```bash
cmake -G Ninja -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

产物：`build/wick`。

## 运行

```bash
./build/wick
```

- 左键托盘蜡烛：开关浮动纸签（`Qt::Tool` + 无边框 + 置顶，不进任务栏）。Wayland 上托盘几何常常是空的，纸签会落到当前屏右上。
- 右键：日记、设置（stage 0 只打日志）、退出（干净 quit，不留进程）。
- Hyprland 若把纸签磁贴进 tiling，加一条：

  ```
  windowrulev2 = float, class:^(wick)$
  windowrulev2 = noborder, class:^(wick)$
  ```

layer-shell 锚定托盘下方是后续阶段；stage 0 先用普通浮动窗。

## 桌面文件

`resources/wick.desktop`（`Name=秉烛`，`Exec=wick`，`Icon=wick`）。装到系统时把 `resources/candle.svg` 作为 `wick` 图标一并安装。
