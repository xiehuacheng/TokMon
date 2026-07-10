# CLAUDE.md

本文件给 Claude Code（`claude-code` CLI / IDE 扩展）在本仓库工作时使用。与 `AGENTS.md` 的内容互补，优先读 `AGENTS.md` 了解仓库约定，本文件补充 Claude Code 特有的注意事项。

## 项目速览

TokMon 是一个 macOS 原生状态栏 App，用于统一查看 Claude Code、Codex、Kimi Code、Qwen Code 与 OpenCode 的 token usage。技术栈：

- App：SwiftUI / AppKit
- 存储：SQLite3（`tokmon.db`）
- 壳：SwiftUI 状态栏 App（`macos-app/`）

面向用户的交付物是 `.app`。

## 常用命令

- `swift run TokMon`（在 `macos-app/` 下）：以开发模式跑状态栏 App。
- `swift build`（在 `macos-app/` 下）：只验证 Swift 编译。
- `swift test`（在 `macos-app/` 下）：运行原生 TokMon 测试。
- `bash macos-app/scripts/build-app.sh`：打包 `macos-app/release/TokMon.app`。
- `git diff --check`：检查空白和补丁格式问题，提交前必跑。

## 目录与模块边界

- `macos-app/Sources/TokMonApp/`：SwiftUI App，状态栏图标、popover、设置窗口、原生 TokMon 引擎。
- `TokMonScanner.swift`：token usage 扫描，结果写 `usage_records`（Claude Code assistant 记录含 `message_id`，用于同一 `message.id` 的 streaming chunk 去重），增量 offset 写 `tokmon_scan_state`。
- `TokMonDatabase.swift`：SQLite schema、写入 helper、rollup 维护和重建。
- `TokMonQueryStore.swift`：summary、trend、heatmap、records、sessions 查询。
- `TokMonConfigStore.swift`：TokMon 配置和 UI state 读写。
- `TokMonGlassStyle.swift`：主题色、玻璃态效果与动态颜色（浅色 / 深色模式）。
- `TokMonKeychain.swift`：Kimi API Key 的 Keychain 存取（按账户隔离）。
- `TokMonKimiQuotaStore.swift`：Kimi `/usages` 与 `/usage` 额度请求、解析与缓存。
- `TokMonQuotaView.swift`：Kimi Quota popover 页面（支持多 key 的添加 / 删除 / 重命名 / 选择）。
- `docs/images/`：README 展示图。

## Claude Code 使用本仓库时的特别注意

1. **Claude Code 自己就是被监控对象**。TokMon 会扫描 `~/.claude/projects/`。在本仓库工作时尽量不要往这些位置写“测试数据”或临时 session 文件，否则会污染 TokMon 用量。需要造数据时用一次性目录，完事清干净。

2. **数据库操作优先走 `TokMonDatabase` 的 helper**。新增 schema 时同步更新重建逻辑和 Swift 测试，否则“重建数据库”会遗漏新表。当扫描/合并语义变化时，记得递增 `TokMonScanner.scannerVersion`；App 启动时发现存储版本低于当前版本会自动重建数据库并重新全量扫描。

3. **环境变量**：
   - `TOKMON_PROJECT_ROOT`：Swift App 从其他目录启动时的仓库路径（见 `macos-app/Sources/TokMonApp/TokMonProjectLocator.swift`）。

4. **验证与提交**：改完至少跑 `cd macos-app && swift test` 和 `git diff --check`。涉及独立 App 的改动要重新打包启动 `.app`。UI 改动的 PR 附截图；涉及 popover 位置、窗口层级、多显示器或 Kimi Quota 面板的改动，请在主显示器和副显示器上都验证。

5. **权限相关改动**：涉及屏幕捕获、辅助功能等 macOS 权限时，同步更新 `Packaging/Info.plist` 中对应的 `UsageDescription`，并在打包后验证权限弹窗与行为。

6. **不要自己 `git commit` / `git push`**，除非用户明确要求。本仓库的提交风格是简短祈使句，例如 `Clean native runtime`、`Fix token scan state`。

## 文档入口

- `README.md`：面向用户的整体介绍与运行方式。
- `macos-app/README.md`：独立版 App 的使用、打包、数据目录。
- `AGENTS.md`：仓库通用 agent 协作约定（结构、命名、测试、提交规范）。
- `CLAUDE.md`（本文件）：Claude Code 特有的注意事项，内容与 `AGENTS.md` 不重复的部分优先看这里。
