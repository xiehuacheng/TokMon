# AgentMon macOS App Prototype

这个目录是 AgentMon 的 macOS 状态栏 App 实验版本。它先不迁移业务逻辑，
而是用 SwiftUI 创建状态栏 popover，并通过 Swift 的 `Process` 启动当前
Hono/Node 服务。完整管理界面仍然由 Web dashboard 承担。

## 当前方案

- SwiftUI 负责状态栏图标和轻量统计 popover。
- 状态栏里可以打开 `http://127.0.0.1:3388` Web dashboard。
- 状态栏统计跟随 Tokens 页面当前 controls，而不是维护第二套筛选条件。
- 后端仍然运行仓库根目录的 `src/index.ts`。
- 数据库、配置文件和 Claude/Codex 本地路径沿用当前 Web 版本行为。

这个方向比 Electron 更轻，更贴近 macOS。后续可以逐步把菜单栏、权限提示、
托盘状态、自动启动、签名和 notarization 做成真正的桌面体验。

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

```bash
bash scripts/build-app.sh
open release/AgentMon.app
```

生成结果位于 `macos-app/release/AgentMon.app`。

## 注意

- 当前原型仍需要系统 `PATH` 里能找到 `node`，并且根项目已经执行过 `npm install`。
- 如果已有 AgentMon 服务占用 `3388` 端口，App 会直接连接该服务。
- 如果 App 自己启动了服务，退出 App 时会尝试关闭该服务。
- 状态栏统计默认每 3 秒刷新一次，显示 Tokens dashboard 当前 source、范围、
  granularity 和 range mode 对应的统计。
- 这个 `.app` 还没有签名、公证，也没有内置 Node runtime，适合本地验证原型。
