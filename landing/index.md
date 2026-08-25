# Wick · 秉烛日记 (A Trader's Almanac & Review Journal)

> macOS 菜单栏应用：日 / 周 / 月 / 年剩余进度 · 一天一页复盘日记 · 撕页黄历 · 只读仓位单据。本地存储，无账号，无遥测。
> A native macOS menu bar app for traders: real-time time progress, daily trading review journal, macroeconomic tear-off calendar, and read-only crypto exchange position receipts.

- **Website**: [https://wick.bitfroth.com](https://wick.bitfroth.com)
- **Download**: [Download for macOS (Universal)](https://dl.bitfroth.com/wick/Wick.zip)
- **System Requirements**: macOS 13 Ventura or later (Apple Silicon & Intel)
- **License**: Open Source / Free
- **GitHub**: [https://github.com/miaoz/wick](https://github.com/miaoz/wick)
- **Agent Instructions**: [https://wick.bitfroth.com/llms.txt](https://wick.bitfroth.com/llms.txt)

---

## What Wick Does (Core Features)

### 1. Time, Marked (时间刻度)
- Ambient real-time progress indicators in the macOS menu bar.
- Tracks remaining percentage, elapsed time, and countdowns for the **Day, Week, Month, and Year** (updated every second).
- "秉烛" (Holding a Candle) dynamic theme reflecting the ambient daylight phase (Dawn, Day, Dusk, Night).

### 2. A Page a Day (纸上日记)
- One page per day, structured with multiple tagged entries, images, and review seals (`✓` / `✗`).
- Full-text search and tag-filtered views.
- Offline-first local storage in `~/Library/Application Support/Wick/Journals/`.
- Automatic backup (`journal.json.bak` and rolling snapshots) and zip import/export.
- Optional multi-device synchronization via Dropbox (OAuth PKCE, local-first conflict resolution).

### 3. Tear-Off Almanac (撕页黄历)
- Integrated macroeconomic releases and corporate earnings calendar for US, HK, and CN markets.
- Optional realistic tear-off calendar easter egg with 2D verlet paper physics and synthesized paper tearing sound effects.

### 4. Exchange Receipts (仓位单据)
- Direct, read-only REST connection to crypto exchanges:
  - **Binance** (USDⓈ-M Futures)
  - **OKX** (SWAP Perpetuals)
  - **Hyperliquid** (Perpetuals Info API, public 0x address only)
- Automatically aggregates individual execution fills into trading sessions and positions (VWAP calculations, hedging lane separation, realized P&L).
- Automatically matches and mounts position receipts onto the corresponding day's journal entry by timestamp and symbol.
- **Privacy & Security Guarantee**: All API credentials reside strictly in the local macOS Keychain. No trading or withdrawal permissions required. No credentials or telemetry data are ever uploaded to any server.

---

## Screenshots & Media
- [Main Journal Window (Light)](https://wick.bitfroth.com/assets/screenshot-journal.png)
- [Main Journal Window (Dark)](https://wick.bitfroth.com/assets/screenshot-journal-dark.png)
- [Menu Bar Progress Panel](https://wick.bitfroth.com/assets/screenshot-panel.png)
- [iOS Companion (Light)](https://wick.bitfroth.com/assets/screenshot-ios-home.png)

---

## Machine-Readable Resources
- [Agent Index & Guidance (llms.txt)](https://wick.bitfroth.com/llms.txt)
- [Full LLM Context (llms-full.txt)](https://wick.bitfroth.com/llms-full.txt)
- [XML Sitemap](https://wick.bitfroth.com/sitemap.xml)
- [GitHub Releases](https://github.com/miaoz/wick/releases)
