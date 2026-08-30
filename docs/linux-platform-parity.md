# Wick Linux 与 macOS 平台对齐与差异设计文档

> 本文档记录 Wick Linux 原生客户端（Qt6 / QML / C++20）与 macOS 原生客户端（SwiftUI / AppKit / Swift 6）之间的**特性对齐矩阵**与**系统平台级差异设计决策**。

---

## 1. 架构与数据核心对齐

Wick Linux 端严格复刻并保证了与 Apple 端（macOS / iOS）完全一致的数据模型与底层不变量：

| 模块 | macOS / iOS 实现 | Linux 实现 | 兼容性与一致性保证 |
| --- | --- | --- | --- |
| **存储规范** | `WickSync` (`catalog.json` + `<uuid>/journal.json` + `images/` + `.bak`) | `wick_core` (`JournalCatalog`, `JournalStore`, `JournalPaths`) | 100% 格式兼容，支持跨端无缝直接读取与挂载 |
| **同步协议** | `JournalSyncEngine` (Sync v2 规范) | `JournalSyncEngine.cpp` + `DropboxSyncBackend` | 严格遵守 Sync v2 三不变量：rev 回声抑制、拉取即固定点、绝不自我冲突 |
| **归档导入导出** | `JournalArchive` (zip 压缩包导入导出) | `JournalArchive.cpp` + `miniz` | 双端 zip 结构完全一致（含 catalog 隔离校验与图片校验） |
| **交易所与仓位** | `WickTrading` (Binance / OKX / Hyperliquid + `PositionAggregator`) | `ExchangeClients.cpp` + `PositionAggregator.cpp` | 数值口径统一（手续费负数、时间戳对齐、OKX张数处理、Hyperliquid Funding 分页） |
| **安全凭据存储** | Apple Keychain | `libsecret` (Freedesktop Secret Service API) / 0600 dev fallback | 跨平台原生保全 Dropbox Token 与 API Key 凭据 |

---

## 2. 功能与交互对齐矩阵

| 功能维度 | macOS 功能表现 | Linux 功能表现 | 对齐状态 |
| --- | --- | --- | --- |
| **四栏式布局** | 导航 / 列表 / 编辑纸张 / 检查器 | 导航 / 列表 / 编辑纸张 / 检查器（自适应平铺） |  完全对齐 |
| **栏位三态切换** | `Ctrl+Shift+S` 全导航 → 仅列表 → 专注模式 | `Ctrl+Shift+S` 全导航 → 仅列表 → 专注模式 |  完全对齐 |
| **日记本拖拽重排** | 侧栏日记本行可拖拽调整 catalog 顺序 | 侧栏日记本行长按拖拽重排，自动持久化 catalog |  完全对齐 |
| **时间燃烧条** | 当日日历 24h 时间燃烧渐变进度 | 当日日历 24h 渐变进度与实时时间线 |  完全对齐 |
| **多条目编辑** | 独立标签、时间序号、纯文本正文、空条目清理 | 独立标签、时间序号、多行正文、空条目清理 |  完全对齐 |
| **交易所仓位单据** | 合约仓位卡片展示（方向/杠杆/开平仓均价/盈亏/手续费） | 合约仓位卡片展示（与 macOS 视觉统一） |  完全对齐 |
| **复盘判决与笔记** | ✓ 正确 / ✗ 失误 印章与多行复盘笔记编辑 | ✓ 正确 / ✗ 失误 印章浮层与实时多行笔记编辑 |  完全对齐 |
| **剪贴板图片粘贴** | 聚焦条目 `Cmd+V` 直接粘贴图片文件 | 聚焦条目 `Ctrl+V` 直接编码 PNG 保存并插入 |  完全对齐 |
| **图片拖拽与预览** | 拖拽插入、缩略图列表、全屏 Lightbox 大图预览 | 拖拽插入、缩略图列表、全屏 Lightbox 大图预览 |  完全对齐 |
| **宏观与黄历检查器** | 华尔街见闻宏观事件/财报日历 + 交易黄历（宜/忌/吉神/煞方） | 华尔街见闻宏观事件/财报日历 + 交易黄历 |  完全对齐 |
| **宏观日历卡片分享** | 复制日历分享图 / 系统 ShareSheet | 一键渲染高清交易日历卡片并复制到剪贴板 |  完全对齐 |
| **快捷键体系** | `Cmd+N` / `Cmd+F` / `Cmd+0` / `Cmd+1..9` / `Cmd+,` | `Ctrl+N` / `Ctrl+F` / `Ctrl+0` / `Ctrl+1..9` / `Ctrl+,` |  完全对齐 |
| **定时日记提醒** | `UserNotifications` 本地系统通知 | `org.freedesktop.Notifications` D-Bus 桌面通知 |  完全对齐 |

---

## 3. 因系统平台差异产生的故意设计区别

为完美契合 Linux（特别是 Wayland / Hyprland / Omarchy 等现代平铺桌面环境）的设计范式与生态标准，以下特性采取了符合 Linux 平台特性的差异化设计：

### 3.1 窗口形态与装饰（Window Chrome）
- **macOS 端**：依赖 AppKit 的统一标题栏（`NSToolbar.unified`）、左上角红绿灯（Traffic Lights）以及 Titlebar Accessory 挂载控件。
- **Linux 端**：采用**无标题栏原生矩形画布**，所有功能控件内聚于 QML 内容层。在 Hyprland 等平铺窗口管理器中能够自动成为原生 Tile，边框、外阴影与圆角均交由 Compositor 统一渲染，不侵入系统主题与全局平铺规则。

### 3.2 顶部栏与时间进度面板（Panel & System Tray）
- **macOS 端**：作为 `LSUIElement` 常驻于 macOS 顶部 MenuBar，点击状态栏图标弹出 `MenuBarExtra` 浮动时间进度卡片。
- **Linux 端**：
  1. 在 **Omarchy / Hyprland** 环境下，原生提供 Quickshell Layer-Shell 插件（`wick.progress`），与桌面 TopBar 深度融合，支持点击滑出 Layer-Shell 悬浮面板。
  2. 在 **通用 Linux 桌面**（GNOME / KDE / Sway / Waybar 等）环境下，通过 FreeDesktop `StatusNotifierItem` (SNI) 系统托盘提供微型蜡烛进度图标与菜单。

### 3.3 物理黄历撕纸彩蛋（Physical Tear-off Paper Calendar）
- **macOS 端**：内置了基于 AppKit / Metal 精细物理碰撞与纹理剥离的物理黄历撕纸动效彩蛋。
- **Linux 端**：**确定在 Linux 1.0 不引入物理撕纸模拟器**。
  - *原因*：Linux 端聚焦于简洁克制的高性能交易复盘工作流，避免复杂的跨平台 3D 物理引擎依赖与非必要的 GPU 开销。
  - *替代体验*：保留了完整的华尔街见闻宏观日历、交易黄历宜忌算法，并增加了「一键导出/复制日历长图卡片」能力，满足日常复盘与社群分享需求。

### 3.4 字体栈（Typography & Font Matching）
- **macOS 端**：优先加载系统预装的 `Songti SC`（宋体）与 `SF Pro` / `SF Mono`。
- **Linux 端**：采用 FreeDesktop Fontconfig 标准，推荐并内置 fallback 至开源 CJK 字体栈：
  - 印刷与印章字体：`Noto Serif CJK SC`, `Source Han Serif SC`, `Songti SC`, `serif`
  - 界面与正文字体：`Noto Sans CJK SC`, `Source Han Sans SC`, `Inter`, `sans-serif`
  - 等宽与数值字体：`JetBrains Mono`, `Noto Sans Mono`, `monospace`

### 3.5 桌面通知通道（Desktop Notifications）
- **macOS 端**：使用 Apple `UserNotifications.framework`，受 App Bundle 与通知权限门控。
- **Linux 端**：直接基于 D-Bus `org.freedesktop.Notifications` 协议向系统通知守护进程（如 `mako`, `dunst`, `swaync`, `fnott`, `kded`）发送标准桌面通知，并注册 `ActionInvoked` 回调以支持点击通知一键呼出日记窗口；托盘 `QSystemTrayIcon::showMessage` 作为备用通道。

---

## 4. 总结

通过上述对齐工作，Wick Linux 端已完全具备与 macOS 端相当的专业交易日记与复盘能力，并无缝融入 Linux 桌面生态。
