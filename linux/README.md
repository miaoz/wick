# 秉烛 · Linux

## Stage 1：本地日记 JSON 核心

对齐 Mac `WickSync` 的 on-disk 格式（`JournalSyncEncoding` + `JournalStore` persist/load）。不画日记窗口。

数据目录：`~/.local/share/wick/Journals/`（`catalog.json` + `<UUID>/journal.json`）。UUID 目录和大写 `UUID.uuidString` 一致。

```bash
sudo pacman -S --needed qt6-base qt6-declarative qt6-svg cmake ninja gcc openssl
cd linux
cmake -G Ninja -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --target test_journal_core
ctest --test-dir build --output-on-failure
```

Debian 对照：上面 Qt 包之外再加 `libssl-dev`。解码用 nlohmann/json（CMake FetchContent v3.11.3，首次配置要联网）。

## Stage 0：Omarchy 蜡烛

Omarchy 上的蜡烛是 Quickshell `bar-widget`（[`omarchy/wick.progress`](omarchy/wick.progress)），点击打开系统 `KeyboardPanel` 下拉，和时钟 / 网络同一套。不要跑下面的 Qt 托盘当 Omarchy UI。

安装：把 `omarchy/wick.progress` 拷到 `~/.config/omarchy/plugins/`，在 `shell.json` 的 `bar.layout.right` 加上 `{"id": "wick.progress"}`，然后 `omarchy-restart-shell`。

## 后备：Qt 6 SNI 托盘（非 Omarchy）

没有 Quickshell 栏的发行版才用这个。托盘走 StatusNotifierItem。

```bash
cmake --build build
./build/wick
```

目标 Qt **6.8**，CMake 下限 6.4。
