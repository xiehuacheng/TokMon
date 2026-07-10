# Claude Code 使用说明

本文件给 Claude Code（`claude-code` CLI / IDE 扩展）在本仓库工作时使用。内容与本仓库的 `AGENTS.md` 保持一致，优先读本文件了解完整约定。

## 项目速览

TokMon 是一个 macOS 原生状态栏 App，用于统一查看 Claude Code、Codex、Kimi Code、Qwen Code 与 OpenCode 的 token usage。技术栈：

- App：SwiftUI / AppKit
- 存储：SQLite3（`tokmon.db`）
- 壳：SwiftPM 状态栏 App（`macos-app/`）

面向用户的交付物是 `.app`。

## 项目结构与模块组织

- macOS App 在 `macos-app/`：`Package.swift` + `Sources/TokMonApp/` 是 SwiftUI 状态栏 App，`Assets/` 存 App icon，`Packaging/Info.plist` 是 bundle metadata，`scripts/build-app.sh` 负责打包 `.app`。
- 测试在 `macos-app/Tests/TokMonAppTests/`。
- 文档在根目录和 `docs/`：`README.md` 是项目总览，`macos-app/README.md` 是 App 使用与打包说明，`AGENTS.md` / `CLAUDE.md` 是 agent 协作约定，`docs/images/` 存 README 截图。

主要模块职责：

- `TokMonScanner.swift`：token usage 扫描，结果写 `usage_records`（Claude Code assistant 记录含 `message_id`，用于同一 `message.id` 的 streaming chunk 去重），增量 offset 写 `tokmon_scan_state`。
- `TokMonDatabase.swift`：SQLite schema、写入 helper、rollup 维护和重建。
- `TokMonQueryStore.swift`：summary、trend、heatmap、records、sessions 查询。
- `TokMonConfigStore.swift`：TokMon 配置和 UI state 读写。
- `TokMonGlassStyle.swift`：主题色、玻璃态效果与动态颜色（浅色 / 深色模式）。
- `TokMonKeychain.swift`：Kimi API Key 的 Keychain 存取（按账户隔离）。
- `TokMonKimiQuotaStore.swift`：Kimi `/usages` 与 `/usage` 额度请求、解析与缓存。
- `TokMonQuotaView.swift`：Kimi Quota popover 页面（支持多 key 的添加 / 删除 / 重命名 / 选择）。
- `TokMonStatsStore.swift`：状态管理、刷新调度、菜单栏数据聚合。

## 构建、测试与本地开发命令

- `swift run TokMon`（在 `macos-app/` 下）：开发模式启动状态栏 App。
- `swift build`（在 `macos-app/` 下）：验证 Swift 编译。
- `swift test`（在 `macos-app/` 下）：运行原生 TokMon 测试。
- `bash macos-app/scripts/build-app.sh`：打包 `macos-app/release/TokMon.app`，面向用户的交付入口。
- `bash macos-app/scripts/build-dmg.sh`：生成签名 DMG 与 Sparkle `appcast.xml`。
- `git diff --check`：提交前检查空白和补丁格式。

## 发布流程

发布新版本时按以下步骤执行，确保 DMG 与 `appcast.xml` 同时上传：

1. **完成所有改动并通过验证**：
   - `cd macos-app && swift test`
   - `cd /项目根目录 && git diff --check`
   - `bash macos-app/scripts/build-app.sh`
   - `bash macos-app/scripts/build-dmg.sh`
2. **更新版本号**：修改 `macos-app/Packaging/Info.plist`：
   - `CFBundleShortVersionString`：语义版本号，例如 `0.2.11`
   - `CFBundleVersion`：整数构建号，例如 `14`
3. **重新打包**（版本号变更后必须重新执行）：
   - `bash macos-app/scripts/build-app.sh`
   - `bash macos-app/scripts/build-dmg.sh`
4. **清理旧版 DMG**（避免 `macos-app/release/` 出现重复安装包）。
5. **提交并打 tag**：
   - `git add -A`
   - `git commit -m "Release TokMon X.Y.Z"`
   - `git tag -a vX.Y.Z -m "TokMon X.Y.Z"`
6. **推送**：
   - `git push origin main`
   - `git push origin vX.Y.Z`
7. **创建 GitHub Release**：
   - Release title：`TokMon X.Y.Z`
   - Tag：`vX.Y.Z`
   - 发布说明基于上一个版本的 tag 差异撰写，覆盖完整变更。
   - **必须上传两个资源**：`TokMon-X.Y.Z.dmg` 和 `appcast.xml`。
   - 在发布说明中写明 DMG 的 SHA-256。

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

## Claude Code 专用注意事项

1. **Claude Code 自己就是被监控对象**。TokMon 会扫描 `~/.claude/projects/`。在本仓库工作时尽量不要往这些位置写“测试数据”或临时 session 文件，否则会污染 TokMon 用量。需要造数据时用一次性目录，完事清干净。

2. **数据库操作优先走 `TokMonDatabase` 的 helper**。新增 schema 时同步更新重建逻辑和 Swift 测试，否则“重建数据库”会遗漏新表。

3. **环境变量**：
   - `TOKMON_PROJECT_ROOT`：Swift App 从其他目录启动时的仓库路径（见 `macos-app/Sources/TokMonApp/TokMonProjectLocator.swift`）。

4. **权限相关改动**：涉及屏幕捕获、辅助功能等 macOS 权限时，同步更新 `Packaging/Info.plist` 中对应的 `UsageDescription`，并在打包后验证权限弹窗与行为。

5. **不要自己 `git commit` / `git push`**，除非用户明确要求。本仓库的提交风格是简短祈使句，例如 `Clean native runtime`、`Fix token scan state`。

## 文档入口

- `README.md`：面向用户的整体介绍与运行方式。
- `macos-app/README.md`：独立版 App 的使用、打包、数据目录。
- `AGENTS.md`：通用 agent 协作约定，内容与本文档保持一致。
- `CLAUDE.md`（本文件）：Claude Code 使用说明。
