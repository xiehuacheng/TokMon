# CLAUDE.md

本文件给 Claude Code（`claude-code` CLI / IDE 扩展）在本仓库工作时使用。与 `AGENTS.md` 的内容互补，优先读 `AGENTS.md` 了解仓库约定，本文件补充 Claude Code 特有的注意事项。

## 项目速览

AgentMon 是一个 macOS 原生状态栏 App，用于统一查看 Claude Code 与 Codex 的 token usage。技术栈：

- App：SwiftUI / AppKit
- 存储：SQLite3（`agentmon.db`）
- 壳：SwiftUI 状态栏 App（`macos-app/`）

面向用户的交付物是 `.app`。

## 常用命令

- `swift run AgentMon`（在 `macos-app/` 下）：以开发模式跑状态栏 App。
- `swift build`（在 `macos-app/` 下）：只验证 Swift 编译。
- `swift test`（在 `macos-app/` 下）：运行原生 TokMon 测试。
- `bash macos-app/scripts/build-app.sh`：打包 `macos-app/release/AgentMon.app`。
- `git diff --check`：检查空白和补丁格式问题，提交前必跑。

## 目录与模块边界

- `macos-app/Sources/AgentMonApp/`：SwiftUI App，状态栏图标、popover、设置窗口、原生 TokMon 引擎。
- `TokMonScanner.swift`：token usage 扫描，结果写 `usage_records`，增量 offset 写 `tokmon_scan_state`。
- `TokMonDatabase.swift`：SQLite schema、写入 helper、rollup 维护和重建。
- `TokMonQueryStore.swift`：summary、trend、heatmap、records、sessions 查询。
- `TokMonConfigStore.swift`：TokMon 配置和 UI state 读写。
- `docs/images/`：README 展示图。

## Claude Code 使用本仓库时的特别注意

1. **Claude Code 自己就是被监控对象**。AgentMon 会扫描 `~/.claude/projects/`。在本仓库工作时尽量不要往这些位置写“测试数据”或临时 session 文件，否则会污染 TokMon 用量。需要造数据时用一次性目录，完事清干净。

2. **数据库操作优先走 `TokMonDatabase` 的 helper**。新增 schema 时同步更新重建逻辑和 Swift 测试，否则“重建数据库”会遗漏新表。

3. **环境变量**：
   - `AGENTMON_PROJECT_ROOT`：Swift App 从其他目录启动时的仓库路径（见 `macos-app/Sources/AgentMonApp/ProjectLocator.swift`）。

4. **验证与提交**：改完至少跑 `cd macos-app && swift test` 和 `git diff --check`。涉及独立 App 的改动要重新打包启动 `.app`。UI 改动的 PR 附截图。

5. **不要自己 `git commit` / `git push`**，除非用户明确要求。本仓库的提交风格是简短祈使句，例如 `Clean native runtime`、`Fix token scan state`。

## 文档入口

- `README.md`：面向用户的整体介绍与运行方式。
- `macos-app/README.md`：独立版 App 的使用、打包、数据目录。
- `AGENTS.md`：仓库通用 agent 协作约定（结构、命名、测试、提交规范）。
- `CLAUDE.md`（本文件）：Claude Code 特有的注意事项，内容与 `AGENTS.md` 不重复的部分优先看这里。
