# TokMon

TokMon 是一款 macOS 原生状态栏应用，用于统一查看 Claude Code、Codex、Kimi Code、Qwen Code 与 OpenCode 的 token usage。它以独立的 `.app` 形式交付，主界面是菜单栏 popover 与原生设置窗口。

## 界面预览

<p>
  <img src="docs/images/tokmon-popover-light.png" alt="TokMon macOS status bar popover in light mode" width="320">
  <img src="docs/images/tokmon-popover-dark.png" alt="TokMon macOS status bar popover in dark mode" width="320">
</p>

点击菜单栏图标可查看实时统计、复制面板截图、打开设置窗口或退出应用。

## 功能概览

- **多源统一**：自动扫描 Claude Code、Codex、Kimi Code、Qwen Code、OpenCode 的本地日志/数据库。
- **指标切换**：Total Tokens、Requests、Input Tokens、Output Tokens、Cache Created、Cache Hit、Hit Rate、Est. Cost。
- **时间范围**：Today / This Week / This Month / All / Custom 快捷范围；Custom 可在 popover 中直接选择起止日期。
- **趋势与热力图**：支持趋势图、按来源/模型分布、紧凑活动热力图；命中率等比例类指标会根据数据分布动态调整纵坐标，兼顾变化幅度与区分度。
- **请求与 Session**：请求日志分页、session 明细，均支持按关键字搜索过滤；session 标题优先使用 session 名 / 项目文件夹名和第一句 prompt。
- **Kimi Quota**：多 API Key 管理，展示周额度与 5 小时滚动额度，支持手动或定时刷新；未配置 API Key 时不显示 Quota 卡片/页签。
- **菜单栏显示**：可在设置中选择在菜单栏显示 Total Tokens、Est. Cost、Requests、Cache Hit Rate、Kimi Weekly Quota、Kimi 5-Hour Quota。
- **费用估算**：支持按模型配置价格，或使用全局默认费率估算 Est. Cost。
- **外观适配**：支持浅色与深色模式，主题色、状态栏图标与文字会自动跟随系统外观。
- **截图分享**：点击 popover 右上角相机图标，可将当前面板复制为图片；首次使用会请求屏幕录制权限。
- **自动更新**：内置 Sparkle，可手动或自动检查 GitHub Release 更新。

## 系统要求

- macOS 14 或更高版本

## 安装与下载

1. 前往 [GitHub Releases](https://github.com/xiehuacheng/TokMon/releases) 下载最新的 `TokMon-X.Y.Z.dmg`。
2. 打开 DMG，将 `TokMon.app` 拖入 **Applications**。
3. 首次启动时，macOS 可能提示 Gatekeeper。当前版本使用本地 ad-hoc 签名，未经过 Apple 公证，按系统提示处理即可。
4. 启动后点击菜单栏的 TokMon 图标开始使用。

更详细的使用说明、打包与开发流程请见 [`macos-app/README.md`](macos-app/README.md)。

## 快速开始

**开发运行**（需要 Xcode / Swift 6.0 工具链）：

```bash
cd macos-app
swift run TokMon
```

**打包独立版 `.app`**：

```bash
bash macos-app/scripts/build-app.sh
open macos-app/release/TokMon.app
```

打包产物位于 `macos-app/release/`，已被 `.gitignore` 忽略，不会进入 Git。

## 界面说明

### 状态栏 Popover

Popover 分为四个页签：

- **Tokens**：核心指标卡片、趋势图、活动热力图、按来源/模型分布。
- **Requests**：请求日志分页，展示每次请求的 tokens、模型、session、时间等明细；支持搜索过滤。
- **Sessions**：按 session 聚合的统计列表；支持搜索过滤。
- **Quota**：Kimi API Key 的额度面板，支持添加、删除、重命名和切换 key；未配置 key 时隐藏。

右上角工具栏按钮依次为：刷新、复制截图、打开设置、检查更新、退出应用。

### 设置窗口

设置窗口分为以下几个区块：

- **General**：设置是否开机自启（Launch at Login）。
- **Sources**：多选要在 popover 中展示的数据来源（Select All + 各来源独立开关），并配置各 agent 本地数据路径。
- **Menu Bar**：选择在菜单栏显示的指标项。
- **Model Pricing**：按模型配置输入/输出/缓存创建/缓存读取单价，用于费用估算。
- **Kimi Quota**：设置 Kimi 额度面板的自动刷新间隔（默认 5 分钟，可选 Manual / 1 / 5 / 15 / 60 分钟）。
- **Maintenance**：手动触发 **Rebuild Database**；即时刷新按钮位于 popover 工具栏。

## 支持的数据源

TokMon 默认读取以下路径，所有路径均可在设置窗口的 **Sources** 区块修改。

| 数据来源 | 默认路径 | 说明 |
| --- | --- | --- |
| Claude Code | `~/.claude/projects` | 扫描本地 session 日志 |
| Codex | `~/.codex` | 递归扫描 `sessions/`、`archived_sessions/` 下的 `.jsonl` 与 `.jsonl.zst` 文件 |
| Kimi Code | `~/.kimi-code` | 递归查找包含 `agents` 目录的 `wire.jsonl` 日志 |
| Qwen Code | `~/.qwen/projects` | 扫描本地项目日志 |
| OpenCode | `~/.local/share/opencode` | 读取该目录下的 `opencode.db` SQLite 数据库 |

## 配置与数据

TokMon 可以零配置运行。通过 `.app` 启动时，SQLite 数据库、扫描状态和本地配置写入：

```text
~/Library/Application Support/TokMon
```

该目录下常见文件：

- `tokmon.db`：SQLite 数据库
- `tokmon.config.json`：来源路径等应用配置
- `tokmon-ui-state.json`：UI 状态（范围、指标、菜单栏显示项、模型价格等）
- `tokmon-kimi-keys.json`：Kimi API Key 列表
- `tokmon-kimi-quota-<id>.json`：各 key 的额度缓存

### 从 AgentMon 迁移

首次启动时，如果 `~/Library/Application Support/TokMon` 不存在，且旧版 `~/Library/Application Support/AgentMon` 存在，TokMon 会自动迁移数据目录，并将 `agentmon.db*` 重命名为 `tokmon.db*`。如果 TokMon 目录已存在，则不会覆盖。

### 扫描版本与数据库重建

`TokMonScanner.scannerVersion` 当前为 `5`。当扫描或合并语义发生变化时，该版本号会递增。App 启动时若检测到本地存储的版本低于当前版本，会自动重建数据库并重新全量扫描。

### 数据一致性

- 用量记录写入 `usage_records` 表，增量扫描 offset 写入 `tokmon_scan_state` 表。
- Claude Code 的 assistant 记录包含 `message_id`，用于同一 `message.id` 的多个 streaming chunk 去重：保留 `createdAt` 最新的一条；时间相同时保留 total tokens 更大的那条。
- 缓存命中率（Hit Rate）的分母/分子仅统计 `cacheHitSupported` 为真的记录；当前所有内置来源默认支持，未来新增不支持该语义的数据源时不会稀释命中率。

## 项目结构

```text
macos-app/
  Package.swift          # SwiftPM manifest（macOS 14+，依赖 Sparkle）
  Sources/TokMonApp/     # SwiftUI / AppKit 状态栏 App 源码
  Tests/TokMonAppTests/  # Swift 测试
  Assets/                # App icon
  Packaging/Info.plist   # .app bundle metadata
  scripts/build-app.sh   # 独立版 .app 打包脚本
  scripts/build-dmg.sh   # 签名 DMG 与 Sparkle appcast.xml 生成脚本
  README.md              # App 使用、打包与开发说明
docs/
  images/                # README 截图
```

根目录还包括：`AGENTS.md`（通用 agent 协作约定）、`CLAUDE.md`（Claude Code 协作约定）、`LICENSE`。

## 文档入口

- [`README.md`](README.md)（本文件）：项目总览、功能介绍、安装与快速开始。
- [`macos-app/README.md`](macos-app/README.md)：独立版 App 的详细使用、开发、打包与发布流程。
- [`AGENTS.md`](AGENTS.md)：通用 agent 协作约定，适用于所有进入本仓库的 AI agent。
- [`CLAUDE.md`](CLAUDE.md)：Claude Code 专用使用说明。

## License

[MIT](LICENSE)
