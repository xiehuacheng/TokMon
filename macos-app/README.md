# AgentMon macOS App

这个目录是 AgentMon 的 macOS 状态栏 App。它用 SwiftUI 创建菜单栏图标和
popover，并通过 Swift 的 `Process` 启动内置的 Hono/Node 服务。dashboard
作为 App 的内置管理界面提供完整功能，状态栏 popover 提供快速入口和轻量
实时看板。

## 功能

- SwiftUI 负责状态栏图标和轻量统计 popover。
- 状态栏里可以打开内置 dashboard，也可以退出 App。
- 状态栏右上角的刷新图标会重启 dashboard 服务，适合服务异常时快速恢复。
- App 启动时会自动启动本地服务；退出时会关闭由 App 启动的服务。
- 如果 `3388` 已有健康的 AgentMon 服务，App 会连接现有服务而不重复启动。
- 状态栏统计跟随 Tokens 页面当前 controls，而不是维护第二套筛选条件；状态区使用 `Range / Source` 与 `Mode / Time` 的 2x2 排布展示当前范围、来源、Live/Fixed、Hour/Day 和 Exact/Round。
- 打包后的 `.app` 会内置 Node runtime、`src/`、`public/` 和 `node_modules/`。
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

调试前端或后端时也可以从仓库根目录运行 `npm run dev`，但这只是开发方式；
面向用户的交付入口仍是 macOS App。

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

打包脚本会选择一个能加载当前 `better-sqlite3` 原生模块、且不依赖 Homebrew
动态 `libnode` 的 Node runtime。必要时可以显式指定：

```bash
AGENTMON_NODE_RUNTIME=/path/to/node bash scripts/build-app.sh
```

## 数据与运行时

通过 App 启动时，服务会设置：

```text
AGENTMON_DATA_DIR=~/Library/Application Support/AgentMon
```

因此独立版 App 的 SQLite 数据库、扫描状态和本地配置不会写回源码目录。Web
dashboard 的前端资源来自 `.app` 内置的 `Contents/Resources/AgentMonServer/public`。

## 注意事项

- 如果已有 AgentMon 服务占用 `3388` 端口，App 会直接连接该服务。
- 如果 App 自己启动了服务，退出 App 时会尝试关闭该服务。
- 状态栏统计默认每 3 秒刷新一次，显示 Tokens dashboard 当前 source、范围、
  granularity 和 range mode 对应的统计。
- Web dashboard 的 Tokens 页面使用 vendored ECharts（`public/vendor/echarts.min.js`），独立版 App 可离线加载图表资源。
- 修改 `public/`、`src/` 或 Swift 代码后，如果要验证独立版 App，需要重新运行
  `bash macos-app/scripts/build-app.sh` 并重启 `release/AgentMon.app`。
- 这个 `.app` 还没有签名、公证，首次分发给其他机器时可能需要处理 macOS
  Gatekeeper 提示。
