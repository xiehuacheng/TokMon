# AgentMon macOS App

这个目录是 AgentMon 的 macOS 状态栏 App。它用 SwiftUI 创建菜单栏图标、
popover 和原生设置窗口，TokMon 扫描、查询和配置都在 Swift 原生路径中完成。

## 功能

- SwiftUI 负责状态栏图标和轻量统计 popover。
- 状态栏里可以打开 TokMon 设置窗口，也可以退出 App。
- 状态栏统计使用原生 TokMon 设置，不依赖浏览器页面或本地 HTTP 服务。
- 打包后的 `.app` 只内置 Swift 可执行文件和 App 资源。
- 数据库和 AgentMon/TokMon 配置写入 `~/Library/Application Support/AgentMon`。
- Claude/Codex 本地路径默认仍读取用户目录下的 `~/.claude` 和 `~/.codex`。

## 开发运行

在本目录执行：

```bash
swift run AgentMon
```

如果从其他目录启动，可以显式指定项目根目录：

```bash
AGENTMON_PROJECT_ROOT=/Users/orange/Desktop/Project/AgentMon swift run AgentMon
```

## 打包为 .app

在仓库根目录执行：

```bash
bash macos-app/scripts/build-app.sh
open macos-app/release/AgentMon.app
```

也可以在 `macos-app/` 目录内执行：

```bash
bash scripts/build-app.sh
open release/AgentMon.app
```

生成结果位于 `macos-app/release/AgentMon.app`，该目录已被 `.gitignore` 忽略。

## 数据与运行时

AgentMon 的 TokMon 数据目录为：

```text
AGENTMON_DATA_DIR=~/Library/Application Support/AgentMon
```

因此 `.app` 的 SQLite 数据库、扫描状态和本地配置不会写回源码目录。

## 注意事项

- 状态栏统计默认每 3 秒刷新一次，显示当前 source、范围和 granularity 对应的统计。
- 修改 Swift 代码后，如果要验证独立版 App，需要重新运行
  `bash macos-app/scripts/build-app.sh` 并重启 `release/AgentMon.app`。
- 这个 `.app` 还没有签名、公证，首次分发给其他机器时可能需要处理 macOS
  Gatekeeper 提示。
