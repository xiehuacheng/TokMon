# TokMon macOS App

本目录是 TokMon 的 macOS 原生状态栏 App。它用 SwiftUI 构建菜单栏图标、popover 与设置窗口，所有扫描、查询、配置均走 Swift 原生路径。项目总览与入口请见仓库根目录的 [README.md](../README.md)。

## 目录

- [功能简介](#功能简介)
- [安装与启动](#安装与启动)
- [界面说明](#界面说明)
- [设置窗口](#设置窗口)
- [支持的数据源与默认路径](#支持的数据源与默认路径)
- [数据目录与迁移](#数据目录与迁移)
- [开发指南](#开发指南)
- [打包与发布](#打包与发布)
- [注意事项](#注意事项)

## 功能简介

- macOS 菜单栏原生 App，点击图标弹出统计面板。
- 统一聚合 Claude Code、Codex、Kimi Code、Qwen Code、OpenCode 的 token usage。
- Popover 分为四个页面：Tokens（概览）、Requests（请求明细）、Sessions（会话统计）、Quota（Kimi 额度）。
- Tokens 页面支持切换 Total Tokens、Requests、Input、Output、Cache Created、Cache Hit、Cache Hit Rate、Est. Cost 等指标。
- 支持 Today、This Week、This Month、All、Custom 时间范围，Custom 可在 popover 中直接选择起止日期。
- 支持趋势图、活动热力图、按来源/模型分布；命中率等比例类指标会根据数据分布动态调整纵坐标，兼顾变化幅度与区分度。
- Requests / Sessions 页面支持按关键字搜索过滤。
- 菜单栏可显示 Total Tokens、Est. Cost、Requests、Cache Hit Rate、Kimi Weekly Quota、Kimi 5-Hour Quota。
- 未配置 Kimi API Key 时，Quota 页面与首页 Quota 卡片自动隐藏。
- 点击 popover 右上角相机图标可将当前面板截图复制到剪贴板。
- 支持浅色/深色模式，主题色随系统外观自动调整。
- 内置 Sparkle 更新检查。

## 安装与启动

### 普通用户：下载 DMG

1. 前往 [GitHub Releases](https://github.com/xiehuacheng/TokMon/releases) 下载最新版 `TokMon-X.Y.Z.dmg`。
2. 打开 DMG，将 `TokMon.app` 拖到 `Applications`。

### 首次启动安全提示

首次启动若出现 Gatekeeper 提示，是因为当前 `.app` 仅做本地 ad-hoc 签名、未经过 Apple 公证；系统会弹出安全性检查，请前往「系统设置 → 隐私与安全性 → 安全性」，点击「仍要打开」完成通过处理。

### 开发者：源码运行

在 `macos-app/` 目录执行：

```bash
cd macos-app
swift run TokMon
```

如果从其他目录启动 SwiftPM 目标，可显式指定仓库根目录：

```bash
TOKMON_PROJECT_ROOT=/path/to/TokMon swift run TokMon
```

## 界面说明

### 状态栏图标

- App 启动后在菜单栏显示 TokMon 图标。
- 图标与文字会跟随系统深浅色自动调整。
- 点击图标打开 popover。

### Popover 页面

| 页面 | 说明 |
|------|------|
| Tokens | 总览卡片、趋势图、活动热力图、按来源/模型分布 |
| Requests | 请求日志分页，支持加载更多 |
| Sessions | 会话列表及单会话明细 |
| Quota | Kimi Code API Key 管理，展示周额度与 5 小时滚动额度 |

### Popover 右上角工具栏

- **刷新**：立即重新扫描并刷新数据。
- **截图**：将当前面板复制为图片到剪贴板；首次使用会请求屏幕录制权限。
- **设置**：打开 TokMon 设置窗口。
- **检查更新**：手动触发 Sparkle 更新检查。
- **退出**：退出 App。

## 设置窗口

设置窗口可通过 popover 右上角齿轮图标打开，包含以下区块：

### General

- **Launch at Login**：设置 TokMon 是否随用户登录自动启动。

### Sources

- **Show**：选择要在 popover 中展示的数据来源，提供全选（Select All）和各来源独立开关；未选择任何来源时等同于展示全部来源。
- **各来源路径**：复选框位于来源名称左侧，右侧为路径输入框，分别配置 Claude Code、Codex、Kimi Code、OpenCode、Qwen Code 的本地数据路径。

### Menu Bar

选择需要在菜单栏显示的指标：

- Total Tokens
- Est. Cost
- Requests
- Cache Hit Rate
- Kimi Weekly Quota
- Kimi 5-Hour Quota

### Model Pricing

- 为具体模型配置 Input / Output / Cache Write / Cache Read 单价（每百万 token）。
- 用于 Est. Cost 估算。
- 模型列表来自已扫描到的模型；可手动添加、删除。

### Kimi Quota

- **Refresh Interval**：Kimi 额度自动刷新间隔，可选 Manual（手动）、1 min、5 min、15 min、60 min，默认 5 min。

### Maintenance

- **Rebuild Database**：清空数据库并重新全量扫描；常用于数据异常或 scanner 版本升级后需要重建的场景。即时刷新请使用 popover 工具栏的刷新按钮。

## 支持的数据源与默认路径

| 来源 | 默认路径 | 扫描说明 |
|------|----------|----------|
| Claude Code | `~/.claude/projects/` | 扫描 `.jsonl` 日志；assistant 记录按 `message_id` 去重 |
| Codex | `~/.codex` | 自动扫描 `sessions/` 与 `archived_sessions/` 子目录；也支持直接指向 `~/.codex/sessions` |
| Kimi Code | `~/.kimi-code/` | 递归查找包含 `agents` 目录的 `wire.jsonl` 日志 |
| Qwen Code | `~/.qwen/projects/` | 扫描 `.jsonl` 日志 |
| OpenCode | `~/.local/share/opencode/` | 读取该目录下的 `opencode.db` SQLite 数据库 |

自定义路径可在设置窗口的 Sources 区块修改。

## 数据目录与迁移

App 的 SQLite 数据库、扫描状态、本地配置写入：

```text
~/Library/Application Support/TokMon
```

该目录下的主要文件：

- `tokmon.db`：SQLite 数据库（含 `usage_records`、`tokmon_scan_state`、`tokmon_session_metadata`、`tokmon_usage_rollups` 等表）。
- `tokmon.config.json`：来源路径等配置。
- `tokmon-ui-state.json`：UI 状态（当前范围、菜单栏显示项、模型价格、Kimi 额度刷新间隔等）。
- `tokmon-kimi-keys.json`：Kimi API Key 本地存储。
- `tokmon-kimi-quota-<keyID>.json`：各 Kimi Key 的额度缓存。

### 从 AgentMon 迁移

首次启动时，如果 `~/Library/Application Support/TokMon` 不存在且旧版 `~/Library/Application Support/AgentMon` 存在，会自动迁移整个数据目录；若 TokMon 目录已存在，则不会覆盖。

### 数据一致性与 scanner 版本

- Claude Code assistant 记录含 `message_id`，同一 `message.id` 的多个 streaming chunk 会按最近优先合并：保留 `createdAt` 最新的一条；时间相同时保留 total tokens 更大的那条。
- `TokMonScanner.scannerVersion` 当前为 `5`；扫描或合并语义变化时递增。
- App 启动时若检测到存储版本低于当前版本，会自动重建数据库并重新全量扫描。
- 缓存命中率只统计支持缓存命中语义的数据来源，避免不支持的来源拉低命中率。

## 开发指南

### 常用命令

```bash
# 开发模式启动状态栏 App
cd macos-app
swift run TokMon

# 验证编译
swift build

# 运行测试
swift test

# 提交前检查空白与补丁格式
cd ..
git diff --check
```

### 环境变量

- `TOKMON_PROJECT_ROOT`：当 Swift App 从非仓库目录启动时，指定仓库根路径。实现见 `Sources/TokMonApp/TokMonProjectLocator.swift`。

### 验证独立版 App

修改 Swift 代码后，如需验证打包后的 `.app`，必须重新运行打包脚本并重启：

```bash
bash macos-app/scripts/build-app.sh
open macos-app/release/TokMon.app
```

## 打包与发布

### 打包为 `.app`

在仓库根目录执行：

```bash
bash macos-app/scripts/build-app.sh
```

生成结果位于 `macos-app/release/TokMon.app`，该目录已被 `.gitignore` 忽略。

### 打包 DMG 与 appcast

```bash
bash macos-app/scripts/build-dmg.sh
```

生成结果包括：

- `macos-app/release/TokMon.app`
- `macos-app/release/TokMon-<version>.dmg`
- `macos-app/release/appcast.xml`

`build-dmg.sh` 会输出 DMG 的 SHA-256，发布时需要记录。

### 发布流程

发布新版本时按以下步骤执行，确保 DMG 与 `appcast.xml` 同时上传：

1. **完成所有改动并通过验证**：
   - `cd macos-app && swift test`
   - `cd /项目根目录 && git diff --check`
   - `bash macos-app/scripts/build-app.sh`
   - `bash macos-app/scripts/build-dmg.sh`
2. **更新版本号**：修改 `macos-app/Packaging/Info.plist`：
   - `CFBundleShortVersionString`：语义版本号，例如 `0.2.14`
   - `CFBundleVersion`：整数构建号，例如 `17`
3. **重新打包**（版本号变更后必须重新执行）：
   - `bash macos-app/scripts/build-app.sh`
   - `bash macos-app/scripts/build-dmg.sh`
4. **清理旧版 DMG**（避免 `macos-app/release/` 出现重复安装包）。
5. **提交并打 tag**：
   - `git add -A`
   - `git commit -m "Release TokMon X.Y.Z"`
   - `git tag -a vX.Y.Z -m "TokMon vX.Y.Z"`
6. **推送**：
   - `git push origin main`
   - `git push origin vX.Y.Z`
7. **创建 GitHub Release**：
   - Release title：`TokMon vX.Y.Z`
   - Tag：`vX.Y.Z`
   - 发布说明使用中文撰写。
   - 发布说明按以下板块组织（无相关项时可留空或省略）：
     - **新增功能**
     - **优化**
     - **修复**
     - **其他**
   - **安装指引**：说明用户如何下载 `TokMon-X.Y.Z.dmg` 并安装到 `/Applications`。
   - **Release 文件说明**：简要说明本次 Release 中各文件的作用，例如：
     - `TokMon-X.Y.Z.dmg`：可直接下载安装的磁盘映像。
     - `appcast.xml`：Sparkle 自动更新使用的订阅源，普通用户无需手动下载。
     - `release-notes.html`：供 Sparkle 弹窗内嵌展示的更新日志网页。
   - 基于上一个版本的 tag 差异撰写，覆盖完整变更。
   - **必须上传两个资源**：`TokMon-X.Y.Z.dmg` 和 `appcast.xml`。
   - 在发布说明中写明 DMG 的 SHA-256。

## 注意事项

- **截图权限**：截图功能使用 ScreenCaptureKit，首次点击相机图标时会请求屏幕录制权限；权限说明文本位于 `Packaging/Info.plist` 的 `NSScreenCaptureUsageDescription`。
- **签名与 Gatekeeper**：独立版 `.app` 仅做了本地 ad-hoc 签名，未经过 Apple 公证，首次分发给其他机器时可能需要处理 macOS Gatekeeper 提示。
- **刷新机制**：状态栏统计在数据变化或 popover 打开时事件驱动刷新，不依赖固定轮询间隔。
- **多显示器验证**：涉及 popover 位置或窗口层级的改动，请在主显示器和副显示器上都进行验证。
- **数据目录差异**：独立版 App 的数据写入 `~/Library/Application Support/TokMon`，开发模式（`swift run`）也使用同一目录；源码目录不会被写入。
