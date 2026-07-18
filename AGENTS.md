# Repository Guidelines

本文件是 TokMon 仓库的通用协作指南，适用于所有在此仓库工作的 agent（包括 Claude Code、Kimi 等）。内容覆盖项目结构、构建测试、代码风格、发布流程与特殊注意事项。

## 项目速览

TokMon 是一个 macOS 原生状态栏 App，用于统一查看 Claude Code、Codex、Kimi Code、Qwen Code 与 OpenCode 的 token usage。

- App：SwiftUI / AppKit
- 存储：SQLite3（`tokmon.db`）
- 包管理：SwiftPM（`macos-app/Package.swift`）
- 最低系统版本：macOS 14.0

面向用户的交付物是 `macos-app/release/TokMon.app` 及其 DMG。

## 项目结构与模块组织

```text
macos-app/
  Package.swift             # SwiftPM manifest
  Sources/TokMonApp/        # SwiftUI 状态栏 App 源码
  Tests/TokMonAppTests/     # Swift 测试
  Assets/                   # App icon
  Packaging/Info.plist      # .app bundle metadata
  scripts/build-app.sh      # 打包 .app
  scripts/build-dmg.sh      # 生成签名 DMG 与 Sparkle appcast.xml
  README.md                 # App 使用与打包说明
docs/
  images/                   # README 截图
```

核心模块职责（完整文件列表见 `macos-app/Sources/TokMonApp/`）：

| 文件 | 职责 |
|---|---|
| `TokMonScanner.swift` | token usage 扫描；Claude Code assistant 记录通过 `message_id` 对同一 `message.id` 的 streaming chunk 去重；增量扫描 offset 写入 `tokmon_scan_state`。 |
| `TokMonDatabase.swift` | SQLite schema、写入 helper、rollup 维护和重建。 |
| `TokMonQueryStore.swift` | summary、trend、heatmap、records、sessions 查询。 |
| `TokMonConfigStore.swift` | TokMon 配置、UI state、Kimi API Key / Quota 快照的本地 JSON 读写。 |
| `TokMonStatsStore.swift` | 状态管理、刷新调度、菜单栏数据聚合。 |
| `TokMonRuntime.swift` | 运行时协调：启动扫描、监听源目录、配额刷新、设置窗口生命周期。 |
| `TokMonSourceWatcher.swift` | 通过 FSEvents 监听各数据来源目录变化，触发增量扫描。 |
| `TokMonEngineActor.swift` | actor 隔离的扫描、查询、设置持久化操作。 |
| `TokMonKimiQuotaStore.swift` | Kimi `/usages` 与 `/usage` 额度请求、解析与缓存。 |
| `TokMonQuotaView.swift` | Kimi Quota popover 页面（支持多 key 的添加 / 删除 / 重命名 / 选择）。 |
| `TokMonGlassStyle.swift` | 主题色、玻璃态效果与动态颜色（浅色 / 深色模式）。 |
| `TokMonKeychain.swift` | Kimi API Key 的 Keychain 读写辅助；当前运行时代码由 `TokMonConfigStore` 通过本地 JSON 管理，本文件保留以备切换。 |

## 构建、测试与本地开发命令

涉及 Swift 的命令需要在 `macos-app/` 目录下执行；仓库根目录执行 `bash macos-app/scripts/...` 即可调用打包脚本。

| 命令 | 作用 |
|---|---|
| `cd macos-app && swift run TokMon` | 开发模式启动状态栏 App。 |
| `cd macos-app && swift build` | 验证 Swift 编译。 |
| `cd macos-app && swift test` | 运行原生 TokMon 测试。 |
| `bash macos-app/scripts/build-app.sh` | 打包 `macos-app/release/TokMon.app`。 |
| `bash macos-app/scripts/build-dmg.sh` | 生成签名 DMG 与 Sparkle `appcast.xml`。 |
| `git diff --check` | 提交前检查空白和补丁格式。 |

开发提示：

- 从非仓库目录启动时，设置环境变量 `TOKMON_PROJECT_ROOT=/path/to/TokMon`（见 `macos-app/Sources/TokMonApp/TokMonProjectLocator.swift`）。

## 发布流程

发布新版本时按以下步骤执行，确保 DMG、`appcast.xml` 与 `release-notes.html` 同时上传：

1. **完成所有改动并通过验证**：
   - `cd macos-app && swift test`
   - `cd /项目根目录 && git diff --check`
2. **更新版本号**：修改 `macos-app/Packaging/Info.plist`：
   - `CFBundleShortVersionString`：语义版本号，例如 `0.2.14`
   - `CFBundleVersion`：整数构建号，例如 `17`
3. **撰写中文 Release Notes**：
   - 在 `macos-app/release-notes.md` 中写入该版本的中文更新日志。
   - 内容使用 Markdown，常用二级标题 `## 主要改动`、列表 `- `、校验值代码块即可。
   - `build-dmg.sh` 会读取该文件生成 `macos-app/release/release-notes.html`，并通过 `<sparkle:releaseNotesLink>` 写入 `appcast.xml`，使 Sparkle 更新窗口能显示更新日志。
4. **打包**（版本号或 release notes 变更后必须重新执行，确保产物携带最新信息）：
   - `bash macos-app/scripts/build-app.sh`
   - `bash macos-app/scripts/build-dmg.sh`
5. **清理旧版 DMG**（避免 `macos-app/release/` 出现重复安装包）。
6. **提交并打 tag**：
   - `git add -A`
   - `git commit -m "Release TokMon X.Y.Z"`
   - `git tag -a vX.Y.Z -m "TokMon vX.Y.Z"`
7. **推送**：
   - `git push origin main`
   - `git push origin vX.Y.Z`
8. **创建 GitHub Release**：
   - Release title：`TokMon vX.Y.Z`
   - Tag：`vX.Y.Z`
   - 发布说明使用 `macos-app/release-notes.md` 的中文内容，覆盖完整变更。
   - **必须上传三个资源**：`TokMon-X.Y.Z.dmg`、`appcast.xml`、`release-notes.html`。
   - 在发布说明中写明 DMG 的 SHA-256。
   - 发布说明、`release-notes.html` 的标题与正文均使用中文撰写；避免直接暴露英文 commit message。

### 安装指引文案模板

Release Notes 与 `macos-app/README.md` 中的 DMG 安装说明按以下结构组织：

1. **安装指引**：仅保留下载 DMG、将 `TokMon.app` 拖入 `Applications` 的步骤。
2. **安全提示**：置于文档最下方，统一使用以下 Gatekeeper 说明：

> 首次启动若出现 Gatekeeper 提示，是因为 `.app` 仅做了本地 ad-hoc 签名、未经过 Apple 公证；系统会弹出安全性检查，请前往「系统设置 → 隐私与安全性 → 安全性」，点击「仍要打开」完成通过处理。

## 代码风格与命名约定

- Swift 文件按职责拆分放在 `macos-app/Sources/TokMonApp/`；新增文件遵循 `TokMon<Domain>.swift` / `<Feature>View.swift` 等命名风格（例如 `TokMonStatsStore.swift`、`StatusPopoverView.swift`、`TokMonSettingsWindow.swift`）。
- Swift 使用两个空格缩进。
- 命名应清晰表达领域含义，例如 `TokMonScanner`、`TokMonQueryStore`、`selectedUsageSession`。
- 优先使用短小直接的函数，不为临时需求增加抽象。

## 测试指南

- 提交前至少运行 `cd macos-app && swift test` 和 `git diff --check`。
- 修改 TokMon 时验证原生 popover、设置窗口、扫描/重建、summary/trend/heatmap/records/sessions/quota 相关路径。
- 涉及 `TokMonSettingsWindow.swift` 或 `StatusPopoverView.swift` 的文案、Section 名称、标签文案变更时，同步检查并更新 `TokMonPackagingTests.swift` 中对源码字符串的断言。
- 涉及独立版 App 的改动需要重新跑 `bash macos-app/scripts/build-app.sh` 并启动 `macos-app/release/TokMon.app` 确认。

## 提交与 Pull Request 规范

- 使用简短的祈使句提交信息，例如 `Clean native runtime` 或 `Fix token scan state`。
- **不要自己 `git commit` / `git push`**，除非用户明确要求。
- PR 应包含变更摘要、影响范围、手动验证步骤；涉及 UI 的改动应附截图。
- 任何会写入 `~/.claude`、`~/.codex`、session 文件或配置文件的变更，都应在说明中明确标出。

## Agent 通用注意事项

较大改动前先阅读 `README.md` 和本文件。保持项目轻量架构。

- **数据写入位置**：TokMon 用量数据写入 `usage_records` 表，增量扫描 offset 存在 `tokmon_scan_state` 表。Claude Code assistant 记录含 `message_id`，用于同一 `message.id` 的 streaming chunk 去重。
- **scannerVersion**：扫描或合并语义变化时递增 `TokMonScanner.scannerVersion`。App 启动时若检测到存储版本低于当前版本，会自动重建数据库并重新全量扫描。
- **独立版 App 数据目录**：独立版 App 的 SQLite 数据库、扫描状态和本地配置写入 `~/Library/Application Support/TokMon`。首次启动时会从旧版 `~/Library/Application Support/AgentMon` 迁移数据（仅当 TokMon 目录不存在时）。改动路径解析或配置加载时务必保留这个差异。
- **数据库操作**：新增 schema 时同步更新重建逻辑和 Swift 测试；数据库操作优先走 `TokMonDatabase` 的 helper，避免直接拼接 SQL。
- **权限文案**：涉及屏幕捕获等 macOS 权限时，同步更新 `Packaging/Info.plist` 中对应的 `UsageDescription`（例如 `NSScreenCaptureUsageDescription`），并在打包后验证权限弹窗与行为。

## 文档入口

- `README.md`：面向用户的整体介绍与运行方式。
- `macos-app/README.md`：独立版 App 的使用、打包、数据目录。
- `AGENTS.md`（本文件）：通用 agent 协作约定。
- `CLAUDE.md`：Claude Code 使用说明。
