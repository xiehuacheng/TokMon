# TokMon macOS App

这个目录是 TokMon 的 macOS 状态栏 App。它用 SwiftUI 创建菜单栏图标、
popover 和原生设置窗口，TokMon 扫描、查询和配置都在 Swift 原生路径中完成。

## 功能

- SwiftUI 负责状态栏图标和紧凑统计 popover。
- 状态栏里可以打开 TokMon 设置窗口，也可以退出 App。
- 状态栏统计使用原生 TokMon 设置，不依赖浏览器页面或本地 HTTP 服务。
- 打包后的 `.app` 只内置 Swift 可执行文件和 App 资源。
- 数据库和 TokMon 配置写入 `~/Library/Application Support/TokMon`。
- 支持浅色与深色模式，主题色会根据系统外观自动调整以保证可读性。
- 状态栏图标与文字会跟随系统深浅色及屏幕焦点状态自动调整颜色。
- 点击 popover 右上角的相机图标可将当前面板截图复制到剪贴板；首次使用会请求屏幕录制权限。
- Claude Code、Codex、Kimi Code、Qwen Code 和 OpenCode 本地路径默认读取用户目录下的 `~/.claude`、`~/.codex`、`~/.kimi-code`、`~/.qwen` 和 `~/.local/share/opencode`。
  - Codex 会扫描 `~/.codex/sessions/` 下的实时 session，以及 `~/.codex/archived_sessions/` 下的归档 session。
  - Claude Code、Kimi Code 与 Qwen Code 分别扫描 `~/.claude/projects/`、`~/.kimi-code/` 与 `~/.qwen/projects/` 下的 `.jsonl` 日志。

## 开发运行

在本目录执行：

```bash
swift run TokMon
```

如果从其他目录启动，可以显式指定项目根目录：

```bash
TOKMON_PROJECT_ROOT=/path/to/TokMon swift run TokMon
```

## 打包为 .app

在仓库根目录执行：

```bash
bash macos-app/scripts/build-app.sh
open macos-app/release/TokMon.app
```

也可以在 `macos-app/` 目录内执行：

```bash
bash scripts/build-app.sh
open release/TokMon.app
```

生成结果位于 `macos-app/release/TokMon.app`，该目录已被 `.gitignore` 忽略。

## 数据与运行时

TokMon 数据目录为：

```text
~/Library/Application Support/TokMon
```

旧版 `~/Library/Application Support/AgentMon` 会在首次启动时迁移到 `~/Library/Application Support/TokMon`，但不会覆盖已经存在的 TokMon 数据目录。

因此 `.app` 的 SQLite 数据库、扫描状态和本地配置不会写回源码目录。

### 数据一致性

- `usage_records` 表为 Claude Code assistant 记录保存 `message_id`，用于同一 `message.id` 下多个 streaming chunk 的去重。
- 合并规则按最近优先：保留 `createdAt` 最新的一条；若时间相同，则保留 total tokens 更大的那条。
- `TokMonScanner.scannerVersion` 在扫描或合并语义变化时递增；App 启动时若检测到存储版本低于当前版本，会自动重建数据库并重新全量扫描。

## 注意事项

- 状态栏统计默认每 3 秒刷新一次，显示当前 source、范围和 interval 对应的统计。
- 修改 Swift 代码后，如果要验证独立版 App，需要重新运行
  `bash macos-app/scripts/build-app.sh` 并重启 `release/TokMon.app`。
- 这个 `.app` 还没有签名、公证，首次分发给其他机器时可能需要处理 macOS
  Gatekeeper 提示。
- 截图功能使用 ScreenCaptureKit，首次点击相机图标时会请求屏幕录制权限；权限
  说明文本位于 `Packaging/Info.plist` 的 `NSScreenCaptureUsageDescription`。
- 涉及 popover 位置或窗口层级的改动，请在主显示器和副显示器上都进行验证。

## 发布前检查

```bash
cd macos-app
swift test
swift build
cd ..
git diff --check
bash macos-app/scripts/build-app.sh
hdiutil create -volname TokMon -srcfolder macos-app/release/TokMon.app -ov -format UDZO macos-app/release/TokMon-<version>.dmg
hdiutil attach -nobrowse -readonly macos-app/release/TokMon-<version>.dmg
open macos-app/release/TokMon.app
```

发布 GitHub Release 时上传 `macos-app/release/TokMon-<version>.dmg`，并在发布说明中写入 DMG 的 SHA-256。
