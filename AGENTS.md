# Repository Guidelines

## 项目结构与模块组织

AgentMon 是一个 macOS 原生状态栏 App，用于统一查看 Claude Code 与 Codex 的 token usage。面向用户的交付形态是 `.app`；旧 Hono/Node 服务仅保留为开发期迁移参考，不再作为 App 内置 web dashboard。

- 后端（TypeScript / Hono）在 `src/`：`src/index.ts` 负责服务启动、路由挂载和定时扫描；`src/db.ts` 负责 SQLite schema、upsert / delete helpers 和去重清理；`src/runtime-paths.ts` 根据 `AGENTMON_DATA_DIR` 解析数据目录；`src/scanner/` 负责 Claude / Codex 的 sessions、skills、settings 扫描；`src/tokmon/scanner.ts` 负责 token usage 扫描与回填；`src/routes/` 负责 API 和会写入用户真实文件的操作。
- macOS 壳在 `macos-app/`：`Package.swift` + `Sources/AgentMonApp/` 是 SwiftUI 状态栏 App，`Assets/` 存 App icon，`Packaging/Info.plist` 是 bundle metadata，`scripts/build-app.sh` 负责打包 `.app`。
- 文档在根目录和 `docs/`：`README.md` 是项目总览，`macos-app/README.md` 是 App 使用与打包说明，`AGENTS.md` / `CLAUDE.md` 是 agent 协作约定，`docs/images/` 存 README 截图。

## 构建、测试与本地开发命令

- `npm install`：安装运行依赖和 TypeScript 工具链。
- `npm run dev` / `npm start`：启动 Hono 服务，默认端口 `3388`。TypeScript 通过 Node 的 `tsx/esm` loader 直接运行，没有独立 build 步骤。
- `npx tsc --noEmit`：类型检查，提交前必跑。
- `npx tsc --noEmit`：TypeScript 迁移参考代码的类型检查。
- `swift run AgentMon`（在 `macos-app/` 下）：开发模式启动状态栏 App，会自动起内置服务。
- `bash macos-app/scripts/build-app.sh`：打包 `macos-app/release/AgentMon.app`，面向用户的交付入口。

`npm run dev` 只用于调试旧 API / parity 参考，不是用户交付入口。

## 代码风格与命名约定

遵循现有 TypeScript ESM 写法和模块边界。scanner 只做本地文件扫描与索引更新，routes 负责 API 与真实文件修改，`db.ts` 维护数据库结构和持久化 helper。TokMon API 必须保留在 `/api/tokmon/*`，不要占用 `/api/sessions`。优先使用短小直接的函数，不为临时需求增加抽象。

TypeScript 使用两个空格缩进。命名应清晰表达领域含义，例如 `scanClaudeSessions`、`usageSessions`、`selectedSkillName`。

macOS 侧的 Swift 代码按 SwiftPM 约定放在 `Sources/AgentMonApp/`，文件按职责拆分（`AgentMonStatsStore.swift`、`StatusPopoverView.swift`、`TokMonSettingsWindow.swift` 等）；新增文件遵循同样的命名风格。

## 测试指南

提交前至少运行 `cd macos-app && swift test`、`npx tsc --noEmit` 和 `git diff --check`。修改 TokMon 时验证原生 popover、设置窗口、扫描/重建、summary/trend/heatmap/records/sessions 相关路径。涉及独立版 App 的改动需要重新跑 `bash macos-app/scripts/build-app.sh` 并启动 `release/AgentMon.app` 确认。

注意高风险操作：删除 session、清理 broken skill、卸载 skill、保存 MCP/settings 都会修改用户本地真实文件。

## 提交与 Pull Request 规范

使用简短的祈使句提交信息，例如 `Add MCP install feedback` 或 `Fix broken skill cleanup`。

PR 应包含变更摘要、影响范围、手动验证步骤；涉及 UI 的改动应附截图。任何会写入 `~/.claude`、`~/.codex`、session 文件、symlink 或配置文件的变更，都应在说明中明确标出。

## Agent 专用注意事项

较大改动前先阅读 `README.md` 和本文件。保持项目轻量架构。TokMon 用量数据写入 `usage_records`，扫描 offset 写入 `tokmon_scan_state`。

独立版 App 启动时会设置 `AGENTMON_DATA_DIR=~/Library/Application Support/AgentMon`，所有写入仓库外的数据（SQLite 数据库、扫描状态、`agentmon.config.json` / `tokmon.config.json`）都落到该目录；开发期 `npm run dev` 不设置该变量，会写到仓库根目录。改动路径解析或配置加载时务必保留这个差异。
