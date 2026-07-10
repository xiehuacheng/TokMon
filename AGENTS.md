# Repository Guidelines

## 项目结构与模块组织

TokMon 是一个 macOS 原生状态栏 App，用于统一查看 Claude Code、Codex、Kimi Code、Qwen Code 与 OpenCode 的 token usage。面向用户的交付形态是 `.app`。

- macOS App 在 `macos-app/`：`Package.swift` + `Sources/TokMonApp/` 是 SwiftUI 状态栏 App，`Assets/` 存 App icon，`Packaging/Info.plist` 是 bundle metadata，`scripts/build-app.sh` 负责打包 `.app`。
- 测试在 `macos-app/Tests/TokMonAppTests/`。
- 文档在根目录和 `docs/`：`README.md` 是项目总览，`macos-app/README.md` 是 App 使用与打包说明，`AGENTS.md` / `CLAUDE.md` 是 agent 协作约定，`docs/images/` 存 README 截图。

## 构建、测试与本地开发命令

- `swift run TokMon`（在 `macos-app/` 下）：开发模式启动状态栏 App。
- `swift build`（在 `macos-app/` 下）：验证 Swift 编译。
- `swift test`（在 `macos-app/` 下）：运行原生 TokMon 测试。
- `bash macos-app/scripts/build-app.sh`：打包 `macos-app/release/TokMon.app`，面向用户的交付入口。
- `git diff --check`：提交前检查空白和补丁格式。

## 代码风格与命名约定

macOS 侧的 Swift 代码按 SwiftPM 约定放在 `Sources/TokMonApp/`，文件按职责拆分（`TokMonStatsStore.swift`、`StatusPopoverView.swift`、`TokMonSettingsWindow.swift`、`TokMonKimiQuotaStore.swift` 等）；新增文件遵循同样的命名风格。

Swift 使用两个空格缩进。命名应清晰表达领域含义，例如 `TokMonScanner`、`TokMonQueryStore`、`selectedUsageSession`。优先使用短小直接的函数，不为临时需求增加抽象。

## 测试指南

提交前至少运行 `cd macos-app && swift test` 和 `git diff --check`。修改 TokMon 时验证原生 popover、设置窗口、扫描/重建、summary/trend/heatmap/records/sessions/quota 相关路径。涉及独立版 App 的改动需要重新跑 `bash macos-app/scripts/build-app.sh` 并启动 `release/TokMon.app` 确认。

## 提交与 Pull Request 规范

使用简短的祈使句提交信息，例如 `Clean native runtime` 或 `Fix token scan state`。

PR 应包含变更摘要、影响范围、手动验证步骤；涉及 UI 的改动应附截图。任何会写入 `~/.claude`、`~/.codex`、session 文件或配置文件的变更，都应在说明中明确标出。

## Agent 专用注意事项

较大改动前先阅读 `README.md` 和本文件。保持项目轻量架构。TokMon 用量数据写入 `usage_records`（Claude Code assistant 记录含 `message_id`，用于同一 `message.id` 的 streaming chunk 去重），扫描 offset 写入 `tokmon_scan_state`。扫描或合并语义变化时递增 `TokMonScanner.scannerVersion`，App 会在版本不匹配时自动重建数据库并重新全量扫描。

独立版 App 的 SQLite 数据库、扫描状态和本地配置写入 `~/Library/Application Support/TokMon`。改动路径解析或配置加载时务必保留这个差异。
