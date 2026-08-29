# Wick for Linux 开发方案（Omarchy）

状态：可执行草案 · 2026-08-30（修订：Omarchy UI 改为 Quickshell `bar-widget` + KeyboardPanel；JSON 斜杠不转义 `\/`；视觉合同 `linux.html` v0.2；原则为三端一致）
仓库：https://github.com/miaoz/wick
目标机：Omarchy 4（Arch + Hyprland 0.56 + Quickshell）
UI 栈：Qt 6 + QML（不做 Tauri / GPUI）
设计合同：`designs/wick-design-language/linux.html`（已确认）。token 源 `tokens-v2.css`。不另起 design system。

本文是给「会写 Swift、不熟 Linux」的执行清单。完成标准写在每阶段末尾，未勾上就不进入下一阶段。

---

## 0. 一句话

Linux 版是**新壳，旧格式**。界面用 Qt/QML 重写；日记 JSON、图片规则、catalog、Dropbox 远端协议、仓位快照必须与 macOS 的 `WickSync` / `WickTrading` 兼容。Mac 是格式真源；Linux 只实现，不发明新字段。

**原则：三端一致。** 除贴桌物理撕页黄历外，macOS / iOS 上已有的功能 Linux 能移植就移植。窗口铬跟 Hyprland；纸面、数据、同步、仓位、检查器跟秉烛。少做一个功能要先问，默认是做。

**产品目标（Linux 1.0）**：对标现有 Wick.app / Wick iOS，只排除 `WickCalendarKit` 那条贴桌撕页彩蛋。栏内检查器（今日事件 + 盈亏月历）在 1.0。Dropbox 与交易所仓位同步是 1.0 的一部分，不是可选项。阶段顺序只是施工顺序，不是砍功能。

---

## 1. 目标与非目标

### Linux 1.0 必须有（对标现有 Wick.app）

- **Omarchy 蜡烛（1.0）**：Quickshell `bar-widget` `linux/omarchy/wick.progress`；点击打开系统 `KeyboardPanel` 下拉（与时钟 / 网络同一套），结构对齐 Mac `ProgressSlipContent`（hero 大百分比 + 今日大烛痕条 + 周/月/年细条 + 页脚格言）。用户已否决浮动 Qt 进度窗。Qt SNI 托盘只作为非 Omarchy 发行版的后备，不是 Omarchy UI。
- **日记**：四栏可磁贴（导航 / 日期列表 / 账册页 / 检查器）；多日记本、一天多条目、标签 + 正文 + 图片、条目检索、复盘（✓/✗ 方章）、导入/导出 zip 或 `journal.json`
- **检查器**：今日事件（宜忌 + 宏观/财报）+ 盈亏月历。黄历不撕页，但入栏。栏位可关；半屏先收检查器再收导航
- **数据安全**：退出/关窗强制落盘、`journal.json.bak` 与滚动备份、加载失败只读
- **中文 IME**：正文用 Qt `TextArea`，禁止 WebView / 自绘输入框
- **Dropbox 同步**：本地为真源；按天对账；日记本改名；墓碑删除；冲突保留双方；OAuth PKCE
- **交易所仓位**：每本日记可绑一个账号（Binance USDⓈ-M / OKX 永续 / Hyperliquid）；只读凭据进 libsecret；按「开仓日 + 标签」挂条目；缺标签自动补条目；不改已有正文/标签/图片
- **仓位快照同步**（可选开关，默认关）：连上 Dropbox 后把成交/资金费/聚合仓位按最新拉取时间整份同步，供他端只读；API Key / Secret / Passphrase / 完整 HL 地址不上云
- **设置**：语言（中/英，`L10n` 同一套文案）、外观（亮/暗/跟随系统 + 秉烛四相位）、字体（系统已装字体）、每日提醒、数据目录、检查更新（GitHub Releases）
- **登录启动**：用户级 `systemd --user` 服务
- **安装**：`.desktop` + Arch 包

### 1.0 明确不做

- **贴桌物理撕页黄历**（`WickCalendarKit`：撕页物理、桌面透明贴窗、程序合成撕纸音）。宏观/财报与宜忌走日记检查器，不另开贴桌窗。这是唯一对现有功能的裁剪。
- **浮动 Qt 进度窗**（layer-shell / 托盘弹出纸签）。Omarchy 上用户已否决；蜡烛走栏内 `bar-widget` + `KeyboardPanel`。
- macOS 壳层细节：`MenuBarExtra` 几何 hack、`SMAppService`、钥匙串弹窗、`LSUIElement`
- GPUI / Tauri / Electron / GTK

### 视觉方向（跟设计语言，不跟 Mac 窗口壳）

Linux 是第三平台，不是把 Mac 窗口贴到 Hyprland 上。视觉以已确认的 `linux.html` 为准。

- **纸面身份**只出现在内容里：四相位弧光、墨/烛/朱砂/黛青、方章、交割单。token 源 `tokens-v2.css`。OS 铬用页面里的 `--os-*`（东京夜系示意），不消耗秉烛颜料。
- **窗口铬跟 Hyprland**：2px 系统描边（Omarchy accent）+ 圆角 + 磁贴间隙；无红绿灯、无假 titlebar、无无边框宣纸贴桌。
- **进度面板**：Omarchy 上走 Quickshell `KeyboardPanel` 下拉（不是浮动 Qt 窗），结构对齐 Mac `ProgressSlipContent`，不是四张独立 metric-card。非 Omarchy 后备才用 SNI 托盘弹出。
- **日记四栏**：导航 / 日期列表 / 账册页 / 检查器。磁贴半屏不够宽时自动先收检查器再收导航，落「仅列表 / 专注」。
- **纸不透明**，不用 Hyprland blur。Omarchy 栏内蜡烛走 `wick.progress`；唤起时一点烛火色。非 Omarchy 后备托盘用模板图标。
- **字态**：圆体 → Inter + Noto Sans SC；宋体 → Noto Serif SC；单据等宽 → JetBrains Mono。Qt 走系统字体，不走网页 CDN。
- **四相位原样保留**。Omarchy 默认「暗 · 子夜」。
- **盈亏约定**：默认绿涨红跌。色值两组固定：`pnlUp` = 朱砂、`pnlDown` = 黛青；约定只交换语义绑定。复盘章印泥、列表、单据、月历一律走约定。黄历「宜 / 方印」永远朱砂。设置可切红涨绿跌。
- **复盘章**：白文方章，字形恒为 ✓ / ✗，印泥随盈亏约定，盖下后约 82% 透明浮在条目右下。

### 施工版本（都在 1.0 内，只是先后）

| 阶段 | 进 1.0？ | 内容 |
| --- | --- | --- |
| 0 | 是 | Omarchy Quickshell `bar-widget` + KeyboardPanel（Qt SNI 托盘仅非 Omarchy 后备） |
| 1 | 是 | 本地 JSON 核心 + 备份/只读 |
| 2 | 是 | 日记四栏主窗 + 检查器 + IME + 图片 + 检索 + zip |
| 3 | 是 | 设置、主题、字体、提醒、开机启动、打包骨架 |
| 4 | 是 | Dropbox 同步 |
| 5 | 是 | 交易所仓位 + 快照同步开关 |
| （1.0 发布） | | 日常可当第二台 Wick 用 |
| 6 | 否，1.0 后 | 其余 Quickshell 增强（插件已在 1.0 / 阶段 0，不再是「上插件」） |

没有「把仓位留到 1.3」这一说。阶段 5 没做完，不打 Linux 1.0。

---

## 2. 硬约束（违反即返工）

1. **磁盘布局与 Mac 同构**（只换根目录）
   - Mac：`~/Library/Application Support/Wick/Journals/`
   - Linux：`~/.local/share/wick/Journals/`
   - 其下：`catalog.json` + `catalog.json.bak` + `<uuid>/{journal.json,journal.json.bak,backups/,images/}`
2. **JSON 版本**：`JournalSnapshot.currentVersion = 2`；`JournalCatalogSnapshot.currentVersion = 1`。读到更高版本：只读，不准改写。编码器斜杠策略与 Mac 一致：`/` 原样写出，禁止 `\/`（NSJSONSerialization / Darwin JSONEncoder 默认不转义斜杠；Linux `SwiftWriter::writeString` 必须同样处理，否则带 URL 的 body 哈希会与 Mac 分叉）。
3. **图片文件名**：单层相对名，拒绝 `/` `\\` `.` `..` NUL。解码失败整份拒收（`JournalImageFilename`）。
4. **加载失败**：只读，禁止写盘与导出。
5. **密钥**：libsecret，schema 前缀 `com.miaoz.wick`。开发构建可写 `~/.local/share/wick/dev-secrets.json`（0600），对标 Mac 的 `dev-secrets.json`。
6. **窗口**：Wayland 优先。Omarchy 蜡烛走 Quickshell `bar-widget`，不用浮动 Qt 窗。非 Omarchy 后备托盘走 StatusNotifierItem，不用 XEmbed。
7. **格式变更**：先改 Swift `WickSync` / `WickTrading` + 测试，再改 Linux。
8. **仓位语义与 Mac 一致**：手续费负=已付；`netPnl = realized + commission + funding`；标签宽松匹配；只读不写已有条目；自动补条目规则见 README「交易所仓位同步」。
9. **同步三不变量**（阶段 4 起）：rev 回声抑制；拉取即固定点；绝不和自己冲突。假后端测试不过，不准连真 Dropbox。
10. **三端一致**：Mac / iOS 已有能力默认进 Linux 1.0。唯一例外是物理黄历。想砍功能先改本文，不准在实现里悄悄省略。

日期/UUID 编解码与 `JournalSyncEncoding.swift` 一致。先从 `Tests/WickSyncTests`、`Tests/WickTradingTests` 抽 golden，再写 C++。

---

## 3. 技术栈（冻结）

| 层 | 选择 | 原因 |
| --- | --- | --- |
| UI | Qt 6.8+ Quick / QML，Controls 2 | 近 SwiftUI；Omarchy 已带 Qt |
| 应用胶 | C++20 | 第一期不要 cxx-qt |
| 构建 | CMake 3.22 + Ninja | Arch 默认 |
| Omarchy 蜡烛 | Quickshell `linux/omarchy/wick.progress` + `KeyboardPanel` | 1.0 栏内 UI；用户否决浮动 Qt 窗 |
| 托盘（后备） | `Qt.labs.platform` `SystemTrayIcon` | 非 Omarchy 发行版 SNI，不是 Omarchy UI |
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
│   ├── omarchy/
│   │   └── wick.progress       # 阶段 0/1.0：Omarchy bar-widget
│   ├── tests/
│   ├── resources/wick.desktop
│   └── packaging/PKGBUILD
└── docs/linux-development-plan.md
```

---

## 5. 阶段（施工顺序，全部通向 1.0）

### 阶段 0 — Omarchy 栏内蜡烛（2–3 天）

Omarchy UI 是 Quickshell `linux/omarchy/wick.progress` `bar-widget` + 系统 `KeyboardPanel`。用户已否决浮动 Qt 进度窗。Qt SNI 托盘只作为非 Omarchy 后备，不要拿它当 Omarchy UI。

1. `linux/omarchy/wick.progress`：顶栏蜡烛；点击打开 `KeyboardPanel` 下拉。
2. 面板结构对齐 `ProgressSlipContent`：hero 大百分比、今日大烛痕条（00:00→24:00）、周/月/年细条、页脚格言。
3. 安装：拷到 `~/.config/omarchy/plugins/`，在 `shell.json` 的 `bar.layout.right` 加上 `{"id": "wick.progress"}`，然后 `omarchy-restart-shell`。
4. `wick.desktop`（日记主窗仍是 Qt）。非 Omarchy：才启用 SNI 托盘。

完成标准：Omarchy 栏内蜡烛可见可点，下拉是 KeyboardPanel；不弹出浮动 Qt 窗。

### 阶段 1 — 本地库核心（1–2 周）

`JournalItem` / `JournalEntry` / `JournalSnapshot` / `JournalCatalogSnapshot` / `JournalImageFilename` / catalog 五种加载结局 / atomic write / 只读门门。

完成标准：Swift golden 往返一致；截断主文件后只读且不覆盖 `.bak`；非法图片名拒收。

这一阶段仍不准画主窗。格式错了，同步和仓位都会写坏 Mac。

### 阶段 2 — 日记主窗（约 2 周）

四栏布局（导航 / 日期列表 / 账册页 / 检查器）、多日记本、条目/标签/图片/`TextArea`、检索、自动保存、**导入导出 zip 与 journal.json**、栏位折叠（检查器 → 导航 → 专注）。账册页按 `JournalDaySection`：无卡片壳、发丝线分隔、页眉含大日期 / 农历 / 净盈亏 / 保存态。检查器含今日事件与盈亏月历。

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

### 阶段 6 — 其余 Quickshell 增强（1.0 之后）

顶栏蜡烛插件已在阶段 0 / Linux 1.0（`linux/omarchy/wick.progress` + KeyboardPanel）。本阶段只做插件之上的增强，不再是「上插件」。

---

## 6. 阶段 0 当天命令

在 **Omarchy 本机**验收栏内蜡烛（云上无图形会话不算）。Qt 二进制仍要编（日记主窗），但 Omarchy UI 走插件：

```bash
sudo pacman -S --needed qt6-base qt6-declarative qt6-wayland cmake ninja gcc openssl libsecret

# 栏内蜡烛（1.0）：
cp linux/omarchy/wick.progress ~/.config/omarchy/plugins/
# 在 ~/.config/omarchy/shell.json 的 bar.layout.right 加上 {"id": "wick.progress"}
omarchy-restart-shell

# 日记主窗（Qt，非浮动进度窗）：
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
- 三端一致：Mac / iOS 已有能力默认做进 Linux。想砍先改本文。

---

## 8. 风险

| 风险 | 处理 |
| --- | --- |
| 日期 JSON 与 Swift `Date` 不一致 | 先对 golden |
| 同步或仓位先做、本地格式未绿 | 禁止；会写坏 Mac 日记 |
| 交易所限流 / OKX 张单位 | 照 `AGENTS.md` 交易口径，测试锁死 |
| Hyprland 磁贴日记窗 | Omarchy 进度走 KeyboardPanel；主窗可磁贴 |
| 托盘要用 `QApplication` | 不准改成 `QGuiApplication` |
| 秉烛主题耗时 | 阶段 3 必须有四相位，但可先做能用的过渡，再拔动画 |

---

## 9. 现在立刻做的下一件事

本文件进仓之后，下一提交是阶段 0（Omarchy `wick.progress` bar-widget + KeyboardPanel），不是同步，也不是仓位。不要做浮动 Qt 进度窗。视觉以 `designs/wick-design-language/linux.html` 为准。

1. 本文件（本次 PR）
2. `linux/omarchy/wick.progress` 栏内蜡烛 + KeyboardPanel（在 Omarchy 真机验收）；Qt SNI 仅非 Omarchy 后备
