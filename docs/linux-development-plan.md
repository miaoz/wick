# Wick for Linux 开发方案（Omarchy）

状态：可执行草案 · 2026-08-29（修订：1.0 对齐现有功能，仅排除物理黄历；视觉方向冻结）
仓库：https://github.com/miaoz/wick
目标机：Omarchy 4（Arch + Hyprland 0.56 + Quickshell）
UI 栈：Qt 6 + QML（不做 Tauri / GPUI）
设计：Linux 高保真 HTML 另存，不跟本方案一起进仓。语言接到 `designs/wick-design-language/` 秉烛定稿（第三平台），不另起 design system。

本文是给「会写 Swift、不熟 Linux」的执行清单。完成标准写在每阶段末尾，未勾上就不进入下一阶段。

---

## 0. 一句话

Linux 版是**新壳，旧格式**。界面用 Qt/QML 重写；日记 JSON、图片规则、catalog、Dropbox 远端协议、仓位快照必须与 macOS 的 `WickSync` / `WickTrading` 兼容。Mac 是格式真源；Linux 只实现，不发明新字段。

**产品目标（Linux 1.0）**：除物理黄历彩蛋外，现有 macOS 功能都要有。Dropbox 与交易所仓位同步是 1.0 的一部分，不是可选项。阶段顺序只是施工顺序，不是砍功能。

---

## 1. 目标与非目标

### Linux 1.0 必须有（对标现有 Wick.app）

- **托盘蜡烛**：StatusNotifierItem，出现在 `omarchy.tray`；日/周/月/年进度（`TimeProgress`）；可选菜单栏百分比
- **日记**：多日记本、一天多条目、标签 + 正文 + 图片、条目检索、复盘、导入/导出 zip 或 `journal.json`
- **数据安全**：退出/关窗强制落盘、`journal.json.bak` 与滚动备份、加载失败只读
- **中文 IME**：正文用 Qt `TextArea`，禁止 WebView / 自绘输入框
- **Dropbox 同步**：本地为真源；按天对账；日记本改名；墓碑删除；冲突保留双方；OAuth PKCE
- **交易所仓位**：每本日记可绑一个账号（Binance USDⓈ-M / OKX 永续 / Hyperliquid）；只读凭据进 libsecret；按「开仓日 + 标签」挂条目；缺标签自动补条目；不改已有正文/标签/图片
- **仓位快照同步**（可选开关，默认关）：连上 Dropbox 后把成交/资金费/聚合仓位按最新拉取时间整份同步，供他端只读；API Key / Secret / Passphrase / 完整 HL 地址不上云
- **设置**：语言（中/英，`L10n` 同一套文案）、外观（亮/暗/跟随系统 + 秉烛四相位）、字体（系统已装字体）、每日提醒、数据目录、检查更新（GitHub Releases）
- **登录启动**：用户级 `systemd --user` 服务
- **安装**：`.desktop` + Arch 包

### 1.0 明确不做

- **物理黄历整条彩蛋**（`WickCalendarKit`：撕页物理、桌面透明贴窗、宏观/财报黄历页、程序合成撕纸音）。这是唯一对现有功能的裁剪。
- Quickshell `bar-widget`（顶栏内嵌蜡烛）。Mac 对应物是菜单栏托盘，Linux 用 `omarchy.tray` 即算对齐；内嵌顶栏是 1.0 之后的增强。
- macOS 壳层细节：`MenuBarExtra` 几何 hack、`SMAppService`、钥匙串弹窗、`LSUIElement`
- GPUI / Tauri / Electron / GTK
- 普通翻页黄历（若以后要「有日历、无撕纸」，另开版本，不混进 1.0）

### 视觉方向（跟设计语言，不跟 Mac 窗口壳）

Linux 是第三平台，不是把 Mac 窗口贴到 Hyprland 上。

- **纸面身份**只出现在内容里：四相位弧光、墨/烛/松烟/朱砂、方章、交割单。token 以 `designs/wick-design-language/` 秉烛定稿为准。
- **窗口铬跟 Hyprland**：系统边框、磁贴；无红绿灯、无假 titlebar、无无边框宣纸贴桌。
- **进度面板浮动**（layer-shell / 托盘弹出），不是一块磁贴。日记窗可磁贴：宽三栏，窄了折成「专注」。
- **纸不透明**，不用 Hyprland blur。托盘蜡烛用模板图标。
- **字态**：圆体（活数据）→ Inter + Noto Sans SC；宋体（印刷/存档）→ Noto Serif SC。Qt 装系统字体，不走网页 CDN。
- 交割单盈亏色（松烟盈/朱砂亏 vs 定稿 v2 红盈黛亏）实现前在设计语言里对齐一次；未对齐前按 Mac 印刷单：松烟盈、朱砂亏。

### 施工版本（都在 1.0 内，只是先后）

| 阶段 | 进 1.0？ | 内容 |
| --- | --- | --- |
| 0 | 是 | 托盘 + 进度窗口 |
| 1 | 是 | 本地 JSON 核心 + 备份/只读 |
| 2 | 是 | 日记主窗 + IME + 图片 + 检索 + zip |
| 3 | 是 | 设置、主题、字体、提醒、开机启动、打包骨架 |
| 4 | 是 | Dropbox 同步 |
| 5 | 是 | 交易所仓位 + 快照同步开关 |
| （1.0 发布） | | 日常可当第二台 Wick 用 |
| 6 | 否，1.0 后 | Quickshell 顶栏插件 |

没有「把仓位留到 1.3」这一说。阶段 5 没做完，不打 Linux 1.0。

---

## 2. 硬约束（违反即返工）

1. **磁盘布局与 Mac 同构**（只换根目录）
   - Mac：`~/Library/Application Support/Wick/Journals/`
   - Linux：`~/.local/share/wick/Journals/`
   - 其下：`catalog.json` + `catalog.json.bak` + `<uuid>/{journal.json,journal.json.bak,backups/,images/}`
2. **JSON 版本**：`JournalSnapshot.currentVersion = 2`；`JournalCatalogSnapshot.currentVersion = 1`。读到更高版本：只读，不准改写。
3. **图片文件名**：单层相对名，拒绝 `/` `\\` `.` `..` NUL。解码失败整份拒收（`JournalImageFilename`）。
4. **加载失败**：只读，禁止写盘与导出。
5. **密钥**：libsecret，schema 前缀 `com.miaoz.wick`。开发构建可写 `~/.local/share/wick/dev-secrets.json`（0600），对标 Mac 的 `dev-secrets.json`。
6. **窗口**：Wayland 优先。托盘走 StatusNotifierItem，不用 XEmbed。
7. **格式变更**：先改 Swift `WickSync` / `WickTrading` + 测试，再改 Linux。
8. **仓位语义与 Mac 一致**：手续费负=已付；`netPnl = realized + commission + funding`；标签宽松匹配；只读不写已有条目；自动补条目规则见 README「交易所仓位同步」。
9. **同步三不变量**（阶段 4 起）：rev 回声抑制；拉取即固定点；绝不和自己冲突。假后端测试不过，不准连真 Dropbox。

日期/UUID 编解码与 `JournalSyncEncoding.swift` 一致。先从 `Tests/WickSyncTests`、`Tests/WickTradingTests` 抽 golden，再写 C++。

---

## 3. 技术栈（冻结）

| 层 | 选择 | 原因 |
| --- | --- | --- |
| UI | Qt 6.8+ Quick / QML，Controls 2 | 近 SwiftUI；Omarchy 已带 Qt |
| 应用胶 | C++20 | 第一期不要 cxx-qt |
| 构建 | CMake 3.22 + Ninja | Arch 默认 |
| 托盘 | `Qt.labs.platform` `SystemTrayIcon` | 进 `omarchy.tray` |
| 通知 | freedesktop Notifications | Quickshell 收 |
| 密钥 | libsecret | 对标钥匙串 |
| HTTP / HMAC | Qt Network + OpenSSL（交易所签名） | 对标 `WickTrading` |
| i18n | 从 `L10n.swift` 导出同一张表 | 文案不两套 |
| 测试 | CTest + Swift golden JSON | 格式兼容是验收 |
| 打包 | `PKGBUILD` + `wick.desktop` | pacman |

仍不在 1.0 引入 Rust/Python。若阶段 4 同步引擎在 C++ 里失控，再抽 Rust，QML 不动。

```bash
sudo pacman -S --needed \
  qt6-base qt6-declarative qt6-wayland \
  cmake ninja gcc pkgconf \
  libsecret libnotify openssl
```

---

## 4. 仓库怎么放

```
wick/
├── Sources/WickSync/            # 日记 + 同步格式真源
├── Sources/WickTrading/         # 仓位语义真源
├── Tests/WickSyncTests/
├── Tests/WickTradingTests/
├── linux/
│   ├── CMakeLists.txt
│   ├── README.md
│   ├── src/
│   │   ├── main.cpp             # QApplication
│   │   ├── app/                 # 托盘、主窗、设置
│   │   ├── core/                # catalog / snapshot / 备份 / 图片
│   │   ├── progress/            # TimeProgress
│   │   ├── sync/                # 阶段 4：引擎 + Dropbox + PKCE
│   │   └── trading/             # 阶段 5：三所客户端 + 聚合 + 挂条目
│   ├── qml/
│   │   ├── Main.qml
│   │   ├── TrayProgress.qml
│   │   ├── journal/
│   │   ├── settings/            # 含交易所、同步开关
│   │   └── positions/           # 条目上的仓位卡片
│   ├── tests/
│   ├── resources/wick.desktop
│   └── packaging/PKGBUILD
└── docs/linux-development-plan.md
```

---

## 5. 阶段（施工顺序，全部通向 1.0）

### 阶段 0 — 托盘能点（2–3 天）

1. `linux/` 最小工程：进度小窗 + 托盘蜡烛（先用 `assets/`）。
2. 左键开关进度；右键：日记 / 设置 / 退出。
3. `TimeProgress` 每秒刷新；可设周起始。
4. `wick.desktop`。

完成标准：Omarchy 上编译运行；托盘可见可点；杀进程无残留。

### 阶段 1 — 本地库核心（1–2 周）

`JournalItem` / `JournalEntry` / `JournalSnapshot` / `JournalCatalogSnapshot` / `JournalImageFilename` / catalog 五种加载结局 / atomic write / 只读门闩。

完成标准：Swift golden 往返一致；截断主文件后只读且不覆盖 `.bak`；非法图片名拒收。

这一阶段仍不准画三栏。格式错了，同步和仓位都会写坏 Mac。

### 阶段 2 — 日记主窗（约 2 周）

三栏布局、多日记本、条目/标签/图片/`TextArea`、检索、自动保存、**导入导出 zip 与 journal.json**、顶栏折叠后做。

完成标准：中文 IME 不丢字；Linux 写的 `Journals/` 拷到 Mac 能开；Mac 的日记在 Linux 能开能改。

### 阶段 3 — 设置与壳（约 1 周）

语言、亮暗 + 秉烛四相位、系统字体选择、每日提醒、数据目录、登录启动、`PKGBUILD` 骨架。

完成标准：设置项与 Mac 对应（无黄历开关）；`makepkg -si` 能装；卸载不删数据。

此处**还不能**当 1.0 发布。

### 阶段 4 — Dropbox 同步（2–3 周）

移植 `JournalSyncEngine`：假后端先绿，再 PKCE 真账号。覆盖改名、墓碑、冲突保留双方。Coordinator 退出前最终同步。

完成标准：`WickSyncTests` 对应用例在 CTest 绿；Mac + Omarchy 同一 Dropbox 手测改名/删除/冲突。

### 阶段 5 — 交易所仓位（约 2 周）**1.0 关门条件**

移植 `WickTrading`：

- 设置里为本日记绑定 Binance / OKX / HL（一本一账号）
- 凭据只读、进 libsecret（开发态 0600 文件）
- 从该本最早一篇日记起拉成交（无日记则只从当天、不回填）
- 聚合、标签匹配、手续费/资金费口径与 Mac 测试一致
- 条目卡片展示；缺标签只追加、不改已有内容
- 「同步仓位快照」开关：依赖阶段 4 已可用的 Dropbox；默认关；密钥不上云

完成标准：

- [ ] `WickTradingTests` 对应 golden：聚合与匹配一致
- [ ] 绑定测试网或只读 key：开仓日出现可匹配条目，已有正文不被改
- [ ] 第二台 Mac 打开快照同步后的日记本，只读看到仓位、看不到密钥
- [ ] 断开交易所后日记仍在

**阶段 5 完成 = Linux 1.0。** 可以当 Omarchy 上的第二台 Wick 用，和 Mac 共用 Dropbox。

### 阶段 6 — Quickshell 插件（1.0 之后）

`linux/omarchy-plugin/`：顶栏内嵌蜡烛。不算现有功能缺口。

---

## 6. 阶段 0 当天命令

在 **Omarchy 本机**验收托盘（云上无图形会话不算）：

```bash
sudo pacman -S --needed qt6-base qt6-declarative qt6-wayland cmake ninja gcc openssl libsecret

git clone https://github.com/miaoz/wick.git
cd wick
# 按 linux/CMakeLists.txt 落地后：
cmake -G Ninja -B linux/build -S linux
ninja -C linux/build
./linux/build/wick
```

---

## 7. 工作方式

- 每阶段一个 PR，标题 `linux:`。不动格式时不准改 `Sources/`。
- 动 JSON / 仓位语义：同一 PR 含 Swift 源 + 对应 Tests + `linux/tests`。
- 日记 UI 用真实中文 IME 打一段再提交。
- 仓位、同步的手测在 Omarchy 真机；不要只在无显示器的 CI 上宣布完成。
- 提交信息英文，用户文档中文。

---

## 8. 风险

| 风险 | 处理 |
| --- | --- |
| 日期 JSON 与 Swift `Date` 不一致 | 先对 golden |
| 同步或仓位先做、本地格式未绿 | 禁止；会写坏 Mac 日记 |
| 交易所限流 / OKX 张单位 | 照 `AGENTS.md` 交易口径，测试锁死 |
| Hyprland 磁贴日记窗 | 进度面板浮动；主窗可磁贴 |
| 托盘要用 `QApplication` | 不准改成 `QGuiApplication` |
| 秉烛主题耗时 | 阶段 3 必须有四相位，但可先做能用的过渡，再抠动画 |

---

## 9. 现在立刻做的下一件事

本文件进仓之后，下一提交是阶段 0（最小托盘），不是同步，也不是仓位。Linux 设计稿 HTML 仍不进仓，等视觉评审后再说。

1. 本文件（本次已进仓）
2. `linux/` 最小 CMake + 托盘 + `TimeProgress`（在 Omarchy 真机验收）
