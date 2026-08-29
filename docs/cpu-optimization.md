# Wick CPU / 热管理优化说明

- 对象：本机安装的 **Wick 1.10.30 (build 69)**，`com.miaoz.wick`
- 源码：本仓库 `main`（验证时 HEAD `f3dde9e`，与安装包同版本号）
- 采样机：2017 iMac 27" 5K（`iMac18,3`），Radeon Pro 580，macOS 15.7.9
- 采样日：2026-08-29
- 相关：`docs/code-review-optimization-plan-2026-08-28.md`（CA-04 / CA-08 / UI-01 / UI-04 等，本文只覆盖**已实测**的常驻 CPU 路径）

## 现象

同一进程、开/关日记对照（2026-08-29，本机 5K）：

| 状态 | Wick CPU | WindowServer | GPU（本机 580） |
|---|---|---|---|
| 日记关掉，可见窗口 0 | 32–35% 主线程 | ~18% | 合成下来 |
| 「手工交易」1500×940 再打开 | **33%** 主线程 | **~18%** | ~48–54W / 58°C |

**Wick 进程那 ~33% 和日记窗是否打开无关。** 开着、关着都是同一条 DisplayLink → `layoutIfNeeded` 热路径（关窗 3s sample：2271 主线程样本里约 748 条；开窗 2s sample：1499 里约 494 条，比例同为约三分之一）。栈里有 `_NSViewLayoutFeedbackLoopDebugger`。这是每帧 layout，不是 60 秒一次的 TimelineView。

日记窗真正多出来的是 **5K 上这块大窗的 GPU 合成**（本机大约 50W），不是 Wick 再多吃一截 CPU。关窗只停合成；进程 CPU 不降，是因为动画和视图树还在未释放的 window 里转。

RSS 开/关都约 221 MB，也符合关窗未拆 hosting。

同时 `coreaudiod` 持有 Wick 的 `audio-out` sleep assertion（采样时已连续数小时）。

---

## 源码对照：已经做过的，不要当新问题

1.10.30 **已经**把整页 `TimelineView(.periodic(from: .now, by: 1))` 拆掉了（`e80d6f4`）。当前是：

- 进度内容：`TimelineView(.periodic(from: .now, by: 60))`，且意图上随面板隐藏卸载
- 菜单栏 label：**禁止** TimelineView，改 30s `task`（`WickApp.swift` 46–75 行注释写明 100% CPU 的 `requestUpdate` 死循环）
- `WindowVisibilityProbe`：KVO `NSWindow.isVisible`，想在 MenuBarExtra `.window` 收起后把 TimelineView 卸掉（注释写明「停掉 minute tick **和 flame loop**」）

这些改动方向对，但 **在本机 Sequoia 上开日记、关日记都未能把 Wick CPU 打到 1% 以下**。下面是对照源码后仍成立的原因。

---

## P0：关窗 / 收起面板后，动画必须停

这是开/关日记都常驻 ~33% 的根因。DisplayLink 热路径和 `FlameDot` 的 `repeatForever` 对得上。

### 1. `FlameDot` 无限呼吸动画

`Sources/WickCalendarKit/BurnStripView.swift` 171–174 行：

```swift
.onAppear {
    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
        breathing = true
    }
}
```

`showsFlame: true` 的调用点：

| 位置 | 何时挂着 |
|---|---|
| `ProgressPanelView.swift` 1034–1037（今日 hero 烛痕） | 菜单栏面板视图图还在就转 |
| `JournalEditorPane.swift` 514（`isToday`） | 日记窗关了但未释放就转 |

`repeatForever` 会按 DisplayLink 驱动 opacity，从而整页 SwiftUI layout。关窗如果只是 `orderOut` / 隐藏，`onAppear` 过的视图 **不会** `onDisappear`，动画继续。

改法：

- 用显式 `isAnimating`（窗口 key / 面板可见）关掉 animation，不要 `repeatForever` 无条件开着
- 或改成 `TimelineView` 低频 tick，且必须随可见性卸载
- 隐藏时把 `showsFlame` 设为 false，让 `FlameDot` 出树

### 2. `WindowVisibilityProbe` 在 Sequoia 上没把火焰卸掉

`ProgressPanelView.swift` 15–17、44–54、1123–1173 行。

意图：`isPanelVisible == false` 时卸掉内容区 TimelineView，从而卸掉 hero `BurnStripView` 的火焰。

漏洞（与采样一致）：

- `@State private var isPanelVisible = true`：probe 没报到 false 之前，火焰默认在转
- **表头第二处 TimelineView（145 行）不受 `isPanelVisible` 保护**
- probe 只 KVO `window.isVisible`。MenuBarExtra `.window` 在 Sequoia 上收起后，NSPanel 仍可能 `isVisible == true`（辅助功能窗口列表是 0，但 AppKit 仍每帧 `layoutIfNeeded`——与采样吻合）
- probe 放在 `.background { ... .frame(width: 0, height: 0) }`，不一定能挂上真正的 panel 窗

改法：

- 用 `MenuBarExtraPanel` 已有的「这是不是 MenuBarExtra 窗」启发式，在 dismiss 时显式 `isPanelVisible = false`
- 表头 TimelineView 与 `CandleTileView` 一并纳入同一可见性开关
- 验收：收起蜡烛面板后 `sample` 不再出现 `NSDisplayCycleFlush` 占三成

### 3. 关窗不释放视图树

三处都是 `isReleasedWhenClosed = false`，关窗只藏不拆：

| 控制器 | 关闭时 | 残留 |
|---|---|---|
| `JournalWindowController.swift` 116、380–385 | `windowWillClose` 只改 accessory policy | `NSHostingController` + 今日 `FlameDot` 仍在 |
| `TradingCalendarWindowController.swift` 163、113–127 | `orderOut` + `isPresented = false` | SpriteKit scene 仍 `update` |
| `FallingPageOverlay.swift` 42 | 3.4s 后 `contentView = nil`（这条是好的） | — |

日记关了 GPU 合成停、进程 CPU 不降：大窗不再画到 5K，但 **今日烛苗还在关着的 window 里呼吸**。

改法：`windowWillClose` / `orderOut` 时

- `hostingController = nil` 或换成空视图
- 日历：`SKView.isPaused = true`，最好 `presentScene(nil)`
- 下次打开再重建 hosting

---

## P1：其它会把循环喂饱的点

### 4. `TearSound` 引擎只开不停

`Sources/WickCalendarKit/TearSound.swift`：单例 `init` 里 `engine.prepare()`，`ensureRunning()` 里 `engine.start()`，**没有 `stop()`**。

撕过一页之后 `AVAudioEngine` 常驻，对应采样里数小时的 `audio-out` Prevent Sleep。

改法：播放结束（或日历窗关闭）后 `engine.stop()`；不要在 `init` 里 `prepare()` 到进程退出。

### 5. 日历 SpriteKit 休眠后仍 60fps

已记在审查文档 **CA-08**。`CalendarPaperScene.update`（51–55 行）每帧 `sim.step`，只是跳过 warp 重建。窗 `orderOut` 后 scene 还在，SKView 默认继续跑。

改法：不可见时 `isPaused = true`；几何冻结时不要每帧 step。

### 6. `FallingPageView` 的 `TimelineView(.animation)`

`FallingPage.swift` 100–103 行：整段坠落 60fps。Overlay 3.4s 后会拆 `contentView`，主路径还好。若坠落视图被嵌进未释放的日历/日记树，会变成第二条 DisplayLink。

### 7. `FibreGrain` 每帧随机（CA-04）

`MacroDayPageView.swift` 807–824 行：`Canvas` 里 `CGFloat.random`。父视图每帧 invalidation（火焰、SKView、FallingPage）就会整页重掷颗粒。改成按日期 seed 的静态纹理。

### 8. `from: .now` 仍写在 body 里

仍出现在：

- `ProgressPanelView.swift` 45、145
- `JournalRootView.swift` 74
- `JournalTopBarView.swift` 33
- iOS `HomeView.swift` / `EditorView.swift` 仍是 `by: 1`

60/300 秒间隔本身不是 30% CPU 的原因，但 `from: .now` 在 body 重算时会重置 schedule。改 `.distantPast`。iOS 首页 `by: 1` 应改为 60 或按可见性卸载。

### 9. 启动即拉交易 / 同步

`WickApp.swift` 168–170：启动就 `SyncCoordinator.shared` + `ExchangePositionCoordinator.shared.start()`。

- 同步周期 60s（`JournalSyncEngine.periodicInterval`）
- 交易刷新 30 分钟（`ExchangePositionCoordinator.refreshInterval`）

这两条 **不是** DisplayLink 热路径，但关日记后 timer 仍在。关窗不必停 30min 刷新；不要让 `@Published snapshot` 去 invalidation 隐藏的菜单栏整页。`WickApp` 上挂了 `@ObservedObject JournalStore.shared`，store 一发布，隐藏的 `MenuBarExtra` 内容也会重绘。

### 10. 日记开着时的交互路径（空闲开窗未测到额外 CPU）

空闲打开 1500×940 日记窗，Wick 进程 CPU 与关窗相同（仍 ~33%）。审查文档里的开窗成本是 **编辑/搜索/侧栏刷新** 时才会叠加上去，不是这块常驻 33%：

- **UI-01** 侧栏非活跃本同步读盘 + 仓位聚合
- **UI-02** Lightbox 每帧读全图
- **UI-04** 编辑器每次击键重估整个 pane
- **UI-05** 搜索无防抖

先修 P0 把空闲打到 < 1%，再处理上述交互路径。日记窗在 5K 上的空闲增量目前是 GPU 合成（本机约 50W），随关窗消失。

---

## 建议改动顺序

1. `FlameDot`：可见性绑定，禁止无条件 `repeatForever`
2. 日记 / 日历关窗时拆 hosting 或暂停 SKView；今日烛苗必须出树
3. `WindowVisibilityProbe` 改为 dismiss 显式置位，表头 TimelineView 同一开关
4. `TearSound.engine.stop()`
5. CA-08 / CA-04
6. `from: .now` → `.distantPast`；iOS `by: 1` → 60
7. 再处理编辑/搜索时的 UI-01/04/05

## 验收

空闲：不点蜡烛，日记和日历都关掉，等 30 秒。

- Wick CPU **< 1%**
- `sample Wick 3`：主线程几乎全是 `mach_msg`；`NSDisplayCycleFlush` / `propagate_dirty` 不应再占三成
- 无 `_NSViewLayoutFeedbackLoopDebugger`
- `pmset -g assertions` 无 Wick `audio-out`

交互：点开菜单栏允许短暂升高；**收起后 1–2 秒回到 < 1%**。打开再关闭日记 / 日历，同样回到基线。

本机在出包前可先 `killall Wick`。不要把未修版本设为登录项常挂。
