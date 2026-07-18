[中文](../README.md) | **English** | [日本語](./README.ja.md)

# TokMon

> A macOS menu bar token usage tracker

![GitHub top language](https://img.shields.io/github/languages/top/xiehuacheng/tokmon) ![GitHub Repo stars](https://img.shields.io/github/stars/xiehuacheng/tokmon?style=social) ![GitHub forks](https://img.shields.io/github/forks/xiehuacheng/tokmon?style=social) ![GitHub License](https://img.shields.io/github/license/xiehuacheng/tokmon) ![GitHub Issues](https://img.shields.io/github/issues/xiehuacheng/tokmon) ![GitHub last commit](https://img.shields.io/github/last-commit/xiehuacheng/tokmon)

## Table of Contents

- [UI Preview](#ui-preview)
- [Feature Overview](#feature-overview)
- [System Requirements](#system-requirements)
- [Download & Installation](#download--installation)
- [Quick Start](#quick-start)
- [UI Guide](#ui-guide)
- [Supported Data Sources](#supported-data-sources)
- [Configuration & Data](#configuration--data)
- [Project Structure](#project-structure)
- [Documentation](#documentation)
- [License](#license)

## UI Preview

<p>
  <img src="docs/images/tokmon-popover-light.png" alt="TokMon macOS status bar popover in light mode" width="320">
  <img src="docs/images/tokmon-popover-dark.png" alt="TokMon macOS status bar popover in dark mode" width="320">
</p>

Click the menu bar icon to view real-time statistics, copy the panel screenshot, open the settings window, or quit the app.

## Feature Overview

- **Multi-source aggregation**: Automatically scans local logs/databases for Claude Code, Codex, Kimi Code, Qwen Code, and OpenCode.
- **Metric switching**: Total Tokens, Requests, Input Tokens, Output Tokens, Cache Created, Cache Hit, Hit Rate, Est. Cost.
- **Time range**: Quick ranges for Today / This Week / This Month / All / Custom; Custom lets you choose start and end dates directly in the popover.
- **Trends & heatmap**: Supports trend charts, source/model breakdowns, and a compact activity heatmap; proportional metrics such as Hit Rate dynamically adjust their vertical axis based on data distribution to balance change magnitude and readability.
- **Requests & Sessions**: Paginated request logs and session details, both supporting keyword search/filtering; session titles prioritize the session name / project folder name and the first prompt.
- **Kimi Quota**: Multi-API-key management showing weekly quota and rolling 5-hour quota, with manual or scheduled refresh; the Quota card/tab is hidden when no API key is configured.
- **Menu bar display**: Choose in settings which metric to show in the menu bar: Total Tokens, Est. Cost, Requests, Cache Hit Rate, Kimi Weekly Quota, or Kimi 5-Hour Quota.
- **Cost estimation**: Supports per-model pricing or estimating Est. Cost using global default rates.
- **Appearance adaptation**: Supports light and dark modes; accent color, status bar icon, and text automatically follow the system appearance.
- **Screenshot sharing**: Click the camera icon in the top-right corner of the popover to copy the current panel as an image; screen recording permission is requested on first use.
- **Auto updates**: Built-in Sparkle for manual or automatic checks for GitHub Release updates.

## System Requirements

- macOS 14 or later

## Download & Installation

1. Go to [GitHub Releases](https://github.com/xiehuacheng/TokMon/releases) to download the latest `TokMon-X.Y.Z.dmg`.
2. Open the DMG and drag `TokMon.app` into **Applications**.
3. On first launch, macOS may show a Gatekeeper warning. The current release is locally ad-hoc signed and not notarized by Apple; follow the system prompts to proceed.
4. After launching, click the TokMon icon in the menu bar to start using it.

For more detailed usage, packaging, and development instructions, see [`macos-app/README.md`](macos-app/README.md).

## Quick Start

**Development run** (requires Xcode / Swift 6.0 toolchain):

```bash
cd macos-app
swift run TokMon
```

**Package a standalone `.app`**:

```bash
bash macos-app/scripts/build-app.sh
open macos-app/release/TokMon.app
```

Build artifacts are placed in `macos-app/release/`, which is ignored by `.gitignore` and not committed to Git.

## UI Guide

### Status Bar Popover

The popover has four tabs:

- **Tokens**: Core metric cards, trend chart, activity heatmap, and source/model breakdown.
- **Requests**: Paginated request logs showing details such as tokens, model, session, and time for each request; supports search filtering.
- **Sessions**: Statistics list aggregated by session; supports search filtering.
- **Quota**: Quota panel for Kimi API keys, supporting adding, deleting, renaming, and switching keys; hidden when no key is configured.

The toolbar buttons in the top-right corner are, from left to right: Refresh, Copy Screenshot, Open Settings, Check for Updates, and Quit App.

### Settings Window

The settings window is divided into the following sections:

- **General**: Enable or disable Launch at Login.
- **Sources**: Select which data sources to display in the popover (Select All + individual toggles), and configure each agent's local data path.
- **Menu Bar**: Choose the metrics to display in the menu bar.
- **Model Pricing**: Configure per-model input/output/cache-creation/cache-read pricing for cost estimation.
- **Kimi Quota**: Set the auto-refresh interval for the Kimi Quota panel (default 5 minutes; options: Manual / 1 / 5 / 15 / 60 minutes).
- **Maintenance**: Manually trigger **Rebuild Database**; the immediate refresh button is located in the popover toolbar.

## Supported Data Sources

TokMon reads from the following default paths, all of which can be changed in the **Sources** section of the settings window.

| Data Source | Default Path | Description |
| --- | --- | --- |
| Claude Code | `~/.claude/projects` | Scan local session logs |
| Codex | `~/.codex` | Recursively scan `.jsonl` and `.jsonl.zst` files under `sessions/` and `archived_sessions/` |
| Kimi Code | `~/.kimi-code` | Recursively find `wire.jsonl` logs in directories containing an `agents` folder |
| Qwen Code | `~/.qwen/projects` | Scan local project logs |
| OpenCode | `~/.local/share/opencode` | Read the `opencode.db` SQLite database in this directory |

## Configuration & Data

TokMon works out of the box. When launched via the `.app`, the SQLite database, scan state, and local configuration are written to:

```text
~/Library/Application Support/TokMon
```

Common files in this directory:

- `tokmon.db`: SQLite database
- `tokmon.config.json`: App configuration such as source paths
- `tokmon-ui-state.json`: UI state (range, metrics, menu bar display items, model prices, etc.)
- `tokmon-kimi-keys.json`: List of Kimi API keys
- `tokmon-kimi-quota-<id>.json`: Quota cache for each key

### Migrating from AgentMon

On first launch, if `~/Library/Application Support/TokMon` does not exist and the legacy `~/Library/Application Support/AgentMon` directory exists, TokMon will automatically migrate the data directory and rename `agentmon.db*` to `tokmon.db*`. If the TokMon directory already exists, it will not be overwritten.

### Scanner Version & Database Rebuild

`TokMonScanner.scannerVersion` is currently `5`. This version number is incremented when scanning or merge semantics change. If the app detects a locally stored version lower than the current version on launch, it will automatically rebuild the database and perform a full rescan.

### Data Consistency

- Usage records are written to the `usage_records` table, and incremental scan offsets are written to the `tokmon_scan_state` table.
- Claude Code assistant records contain a `message_id` used to deduplicate multiple streaming chunks for the same `message.id`: the latest `createdAt` is kept; if the times are identical, the record with the larger total tokens is kept.
- The numerator and denominator of the Cache Hit Rate only count records whose `cacheHitSupported` is true; all built-in sources currently support this by default, so future sources that do not support this semantics will not dilute the rate.

## Project Structure

```text
macos-app/
  Package.swift          # SwiftPM manifest (macOS 14+, depends on Sparkle)
  Sources/TokMonApp/     # SwiftUI / AppKit status bar app source
  Tests/TokMonAppTests/  # Swift tests
  Assets/                # App icon
  Packaging/Info.plist   # .app bundle metadata
  scripts/build-app.sh   # Standalone .app packaging script
  scripts/build-dmg.sh   # Signed DMG and Sparkle appcast.xml generation script
  README.md              # App usage, packaging, and development instructions
docs/
  images/                # README screenshots
```

The root directory also includes: `AGENTS.md` (general agent collaboration conventions), `CLAUDE.md` (Claude Code collaboration conventions), and `LICENSE`.

## Documentation

- [`README.md`](README.md) (this file): Project overview, feature introduction, installation, and quick start.
- [`macos-app/README.md`](macos-app/README.md): Detailed usage, development, packaging, and release workflow for the standalone app.
- [`AGENTS.md`](AGENTS.md): General agent collaboration conventions applicable to all AI agents entering this repository.
- [`CLAUDE.md`](CLAUDE.md): Usage instructions dedicated to Claude Code.

## License

[MIT](LICENSE)

> This is a translated version. For the authoritative content, please refer to README.md.
