# AgentMon

AgentMon 是一个 macOS 原生状态栏应用，用于查看 Claude Code 与 Codex 的 token usage。当前交付形态是 `.app`，主界面是菜单栏 popover 和原生设置窗口，不再包含浏览器 dashboard。

## 界面预览

<p>
  <img src="docs/images/agentmon-status-popover.png" alt="AgentMon macOS status bar popover showing live token metrics and a trend chart" width="360">
</p>

状态栏看板展示 token 用量卡片、趋势图、活动热力图、请求明细和 session 统计；设置窗口提供路径、默认范围、模型价格、扫描和维护操作。

## 技术栈

- App：SwiftUI / AppKit
- 数据库：SQLite3
- 配置解析：smol-toml
- 迁移辅助：TypeScript + Hono（仅保留为开发期 API / parity 参考）

## 功能概览

### TokMon
- 支持 Total Tokens、Requests、Input、Output、Cache Created、Cache Hit、Est. Cost 指标切换
- 支持趋势图、最近 30 天热力图、年度热力图 popover、按模型 / 来源分布、请求日志分页
- 支持 Yesterday、Today、This Week、This Month、This Year、All 快捷时间范围
- session 标题统一使用项目文件夹名和第一句 prompt
- 支持按模型配置价格，用于费用估算
- API 命名空间为 `/api/tokmon/*`，避免和 AgentMon 的 `/api/sessions` 冲突

### 状态栏看板
- 展示 Total Tokens、Requests、Input、Output、Cache Created、Cache Hit、Cache Hit Rate、Est. Cost 指标
- 内置轻量趋势图，可在状态栏里快速查看近期变化
- 右上角提供原生设置窗口和退出 App
- 原生设置窗口支持 source paths、默认范围、默认指标、刷新间隔、按模型价格、扫描和重建数据库

## 数据来源

### Claude Code
- `~/.claude/projects/`
- `~/.claude/sessions/`
- `~/.claude/skills/`
- `~/.claude/settings.json`
- `~/.claude/plugins/installed_plugins.json`

### Codex
- `~/.codex/sessions/`
- `~/.codex/session_index.jsonl`
- `~/.codex/skills/`
- `~/.codex/config.toml`

## 运行方式

AgentMon 的交付形态是 macOS 状态栏 App。打包独立版 `.app`：

```bash
bash macos-app/scripts/build-app.sh
open macos-app/release/AgentMon.app
```

App 启动后会在菜单栏显示 AgentMon 图标。点击状态栏图标可以查看实时统计、打开设置窗口或退出应用。打包产物位于 `macos-app/release/`，不会提交到 Git。更多细节见 `macos-app/README.md`。

开发时也可以直接运行 Swift App：

```bash
cd macos-app
swift run AgentMon
```

TypeScript 服务仅保留为开发期迁移参考。需要调试旧 API 或 parity 数据时，可以单独启动本地服务：

```bash
npm install
npm run dev
```

默认端口为 `3388`。

## 配置

项目可以零配置运行，默认读取 `~/.claude` 和 `~/.codex`。如需自定义路径，复制示例文件后修改：

```bash
cp agentmon.config.example.json agentmon.config.json
cp tokmon.config.example.json tokmon.config.json
```

`agentmon.config.json` 配置 Claude Code / Codex home 目录。`tokmon.config.json` 配置 token usage 日志扫描目录。真实配置文件、SQLite 数据库和本地扫描状态不会提交到 Git。

当通过 macOS App 启动时，AgentMon 会把数据库、扫描状态和本地配置写入：

```text
~/Library/Application Support/AgentMon
```

## 项目结构

```text
src/
  index.ts               # 服务入口、路由挂载、初始/周期扫描
  db.ts                  # SQLite schema、upsert/delete helpers、去重清理
  runtime-paths.ts       # 根据 AGENTMON_DATA_DIR 解析数据目录
  scanner/
    index.ts             # 配置加载与扫描调度
    claude-*.ts          # Claude Code sessions / skills / settings 扫描
    codex-*.ts           # Codex sessions / skills / settings 扫描
    utils.ts             # 扫描辅助函数
  tokmon/
    scanner.ts           # TokMon token usage 扫描器（含 Claude 回填）
  routes/
    tokmon.ts            # TokMon API（/api/tokmon/*）
    sessions.ts          # sessions API（/api/sessions）
    skills.ts            # skills API（/api/skills）
    mcp.ts               # MCP API（/api/mcp）
    settings.ts          # settings API（/api/settings）
macos-app/
  Package.swift          # SwiftPM manifest
  Sources/AgentMonApp/   # SwiftUI 状态栏 App 源码
  Assets/                # App icon（.icns / .png）
  Packaging/Info.plist   # .app bundle metadata
  scripts/build-app.sh   # 独立版 .app 打包脚本
  README.md              # macOS App 使用与打包说明
docs/
  images/                # README 截图
```

根目录还包括：`package.json`、`tsconfig.json`、`agentmon.config.example.json`、`tokmon.config.example.json`、`AGENTS.md`（Codex 协作约定）、`CLAUDE.md`（Claude Code 协作约定）和 `LICENSE`。

## 重要说明

- AgentMon 使用本地 SQLite 索引 token usage 元数据。
- 原生 App 当前不会提供 session 删除、skill 卸载或 MCP/settings 改写入口。

## 已知实现约定

- TokMon 用量数据写入同一个 `agentmon.db` 的 `usage_records` 表，增量扫描 offset 存在 `tokmon_scan_state`
- TokMon 日志路径来自 `tokmon.config.json`；如果不存在，默认读取 `~/.claude/projects` 和 `~/.codex/sessions`

## License

MIT
