# CLAUDE.md

本文件给 Claude Code（`claude-code` CLI / IDE 扩展）在本仓库工作时使用。与 `AGENTS.md` 的内容互补，优先读 `AGENTS.md` 了解仓库约定，本文件补充 Claude Code 特有的注意事项。

## 项目速览

AgentMon 是一个 macOS 状态栏 App，用于统一管理 Claude Code 与 Codex 的 token usage、sessions、skills、MCP servers 和配置。技术栈：

- 后端：Hono + `@hono/node-server`，TypeScript 通过 `tsx/esm` 直接运行
- 存储：`better-sqlite3`（`agentmon.db`）
- 前端：原生 HTML / CSS / JS，无框架
- 壳：SwiftUI 状态栏 App（`macos-app/`）

面向用户的交付物是 `.app`；`npm run dev` 仅用于后端 / 前端的本地调试。

## 常用命令

- `npm install`：安装依赖。
- `npm run dev`：启动 Hono 服务，默认端口 `3388`。
- `npx tsc --noEmit`：类型检查，改后端前端共享逻辑后必跑。
- `node --check public/app.js` / `node --check public/tokmon-module.js`：前端原生 JS 的语法检查（没有 bundler，手动跑）。
- `git diff --check`：检查空白和补丁格式问题，提交前必跑。
- `swift run AgentMon`（在 `macos-app/` 下）：以开发模式跑状态栏 App。
- `swift build`（在 `macos-app/` 下）：只验证 Swift 编译。
- `bash macos-app/scripts/build-app.sh`：打包 `macos-app/release/AgentMon.app`。

## 目录与模块边界

- `src/routes/*`：API；涉及改用户真实文件（`~/.claude`、`~/.codex`、session 文件、symlink、`settings.json`、`config.toml`）的逻辑集中在这里。
- `src/scanner/*`：只做本地文件扫描和 SQLite 索引更新，不修改用户文件。
- `src/tokmon/scanner.ts`：token usage 扫描，结果写 `usage_records`，增量 offset 写 `tokmon_scan_state`。
- `src/db.ts`：SQLite schema、upsert/delete helpers、去重清理。新增表或字段时在这里集中管理。
- `src/runtime-paths.ts`：根据 `AGENTMON_DATA_DIR` 决定数据落盘位置。开发期默认写仓库根目录；独立版 App 启动时设置为 `~/Library/Application Support/AgentMon`。
- `public/app.js`：AgentMon 前端（sessions / skills / MCP / settings）。
- `public/tokmon-module.js`：TokMon 首页模块，和 `app.js` 同页挂载。
- `public/vendor/echarts.min.js`：vendored ECharts，让独立 App 离线可用。
- `docs/images/`：README 展示图，包括 Web dashboard 和 macOS 状态栏 popover 截图。
- `macos-app/Sources/AgentMonApp/`：SwiftUI App，状态栏图标、popover、Node 进程管理。

TokMon API 固定在 `/api/tokmon/*`，不要占用 `/api/sessions`。skills / MCP 在 DB 里按 `source:name` 存，UI 按 `name` 聚合。

## Claude Code 使用本仓库时的特别注意

1. **Claude Code 自己就是被监控对象**。AgentMon 会扫描 `~/.claude/projects/`、`~/.claude/sessions/`、`~/.claude/skills/`、`~/.claude/settings.json`。在本仓库工作时尽量不要往这些位置写“测试数据”或临时 session 文件，否则会污染 TokMon 用量与 sessions 列表。需要造数据时用一次性目录，完事清干净。

2. **高风险文件操作要谨慎确认**。`src/routes/sessions.ts`、`src/routes/skills.ts`、`src/routes/mcp.ts`、`src/routes/settings.ts` 都会改用户家目录下的真实文件 / symlink。改这些路径前读完当前实现再动。执行删除、卸载类操作前和用户确认。

3. **数据库操作优先走 `db.ts` 的 helper**，不要在 routes 里临时拼 SQL。新增 schema 时同步更新 `rebuildRuntimeDatabase`，否则“重建数据库”会遗漏新表。

4. **前端不引入框架 / 构建工具**。两个前端文件（`app.js` 约 1500 行，`tokmon-module.js` 约 1400 行）刻意保持原生 JS，改动时延续现有状态管理方式；不要顺手做无关重构。

5. **环境变量**：
   - `AGENTMON_DATA_DIR`：数据与配置落盘目录（独立 App 自动设置，开发期默认仓库根）。
   - `AGENTMON_PROJECT_ROOT`：Swift App 从其他目录启动时的仓库路径（见 `macos-app/Sources/AgentMonApp/ProjectLocator.swift`）。
   - `AGENTMON_NODE_RUNTIME`：`build-app.sh` 手动指定要内嵌的 Node 可执行文件。

6. **打包脚本依赖 `better-sqlite3` 原生模块能被选中的 Node 加载**。改 `build-app.sh` 或升 Node/`better-sqlite3` 时，打包完跑一次 `open macos-app/release/AgentMon.app` 验证菜单栏图标出现且数据能加载，再提交。

7. **验证与提交**：改完至少跑 `node --check public/app.js && node --check public/tokmon-module.js`、`npx tsc --noEmit` 和 `git diff --check`，再在浏览器里点到受影响的页面验证一次。涉及独立 App 的改动要跑 `swift build`，并重新打包启动 `.app`。UI 改动的 PR 附截图。

8. **不要自己 `git commit` / `git push`**，除非用户明确要求。本仓库的提交风格是简短祈使句，例如 `Add MCP install feedback`、`Fix broken skill cleanup`。

## 何时参考哪份文档

- `README.md`：面向用户的整体介绍与运行方式。
- `macos-app/README.md`：独立版 App 的使用、打包、数据目录。
- `AGENTS.md`：仓库通用 agent 协作约定（结构、命名、测试、提交规范）。
- `CLAUDE.md`（本文件）：Claude Code 特有的注意事项，内容与 `AGENTS.md` 不重复的部分优先看这里。
