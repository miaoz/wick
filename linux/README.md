# 秉烛 · Linux

## Stage 4B：Dropbox OAuth PKCE + HTTP backend

Settings 「连接 Dropbox」 runs the real Dropbox app (`hm5yscsy9a11g0q`, redirect `db-hm5yscsy9a11g0q://2/token`). `WICK_FAKE_SYNC=1` still uses the in-memory fake backend.

Callback: `wick.desktop` registers `x-scheme-handler/db-hm5yscsy9a11g0q`; the running instance listens on `$XDG_RUNTIME_DIR/wick-dropbox-auth.sock`. A second process `wick --dropbox-callback <url>` forwards the URL and exits. First authorize also runs `xdg-mime default wick.desktop x-scheme-handler/db-hm5yscsy9a11g0q` (best-effort) and writes a user desktop file with the current binary path.

Refresh token: libsecret schema `com.miaoz.wick` (service `com.miaoz.wick.dropbox` / account `refresh-token`). Never QSettings. `WICK_DEV_SECRETS=1` → `~/.local/share/wick/dev-secrets.json` mode 0600.


## Stage 3：设置 + 托盘壳

托盘「设置」打开可磁贴的设置窗（左栏七组：外观与语言 / 通用 / 日记与提醒 / 同步 / 交易所 / 数据 / 关于）。Linux 1.0 **不出现「交易日历」**。关窗只隐藏，不退出。QSettings：`~/.config/wick/秉烛.conf`，键名对齐 Mac `wick.*`。登录启动写用户 systemd 单元 `~/.config/systemd/user/wick.service`。每日提醒走托盘 `showMessage`。

# 秉烛 · Linux

## Stage 2：四栏日记主窗

托盘菜单「日记」打开可磁贴的 Qt 日记窗（导航 / 日期列表 / 账册页 / 检查器）。纸面只在内容里，窗口铬跟 Hyprland。默认 暗 · 子夜。账册正文是 Qt TextArea。

```bash
sudo pacman -S --needed qt6-base qt6-declarative qt6-svg cmake ninja gcc openssl
cd linux
cmake -G Ninja -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --target wick test_journal_core
ctest --test-dir build --output-on-failure
./build/wick
```

数据目录：`~/.local/share/wick/Journals/`（`catalog.json` + `<UUID>/journal.json`）。UUID 目录和大写 `UUID.uuidString` 一致。

## Stage 1：本地日记 JSON 核心

对齐 Mac `WickSync` 的 on-disk 格式（`JournalSyncEncoding` + `JournalStore` persist/load）。

解码用 nlohmann/json（CMake FetchContent v3.11.3，首次配置要联网）。

## Stage 0：Omarchy 蜡烛

Omarchy 上的蜡烛是 Quickshell `bar-widget`（[`omarchy/wick.progress`](omarchy/wick.progress)），点击打开系统 `KeyboardPanel` 下拉，和时钟 / 网络同一套。`wick` 进程仍要跑（日记窗 / 设置 / 同步），但检测到栏里已有 `wick.progress` 时会藏起 Qt 托盘蜡烛，避免两套面板。`WICK_FORCE_TRAY=1` 可强制显示旧托盘。

安装：把 `omarchy/wick.progress` 拷到 `~/.config/omarchy/plugins/`，在 `shell.json` 的 `bar.layout.right` 加上 `{"id": "wick.progress"}`，然后 `omarchy-restart-shell`。

## 后备：Qt 6 SNI 托盘（非 Omarchy）

没有 Quickshell 栏的发行版才用这个。托盘走 StatusNotifierItem。右键「日记」打开主窗；关主窗只是隐藏，不退出。

目标 Qt **6.8**，CMake 下限 6.4。
