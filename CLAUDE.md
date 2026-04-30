# CLAUDE.md

## 项目定位

AgentMon 是一个本地管理看板，用来统一查看和管理 Claude Code 与 Codex 的：
- token usage（TokMon 首页）
- sessions
- skills
- MCP servers
- settings / plugins

设计风格参考 TokMon：深色、紧凑、数据面板风格。TokMon 已作为首页集成，AgentMon 其它 tab 更偏“管理”。

## 开发原则

- 优先保持轻量：原生前端 + Hono + SQLite
- 避免引入大型前端框架
- 尽量直接复用已有 scanner / route / view 结构
- 不为暂时不需要的场景做抽象
- 任何会改动用户本地真实数据的操作都要非常明确

## 代码约定

### 后端
- `src/index.ts` 只负责启动服务、挂载路由、启动定时扫描
- `src/db.ts` 负责 schema 和 upsert / delete helpers
- `src/scanner/*` 负责从磁盘读取并写入 SQLite 索引
- `src/tokmon/*` 负责 TokMon token usage 扫描
- `src/routes/*` 负责 API 与真实文件变更
- TokMon API 挂载在 `/api/tokmon/*`，不要占用 `/api/sessions`

### 前端
- 所有前端逻辑都在 `public/app.js`
- 所有样式都在 `public/style.css`
- TokMon 首页由 `public/app.js` 渲染 DOM，并通过 `public/tokmon-module.js` 挂载交互
- 不使用构建工具，不拆组件
- 通过局部状态变量驱动视图：
  - `sessionsPage`
  - `sessionsPageSize`
  - `sessionsManageMode`
  - `selectedSessionIds`
  - `showLastPrompt`
  - `selectedSkillName`
  - `selectedMcpName`

## 关键行为

### tokmon
- 默认第一个 tab
- 与主应用同页渲染，不使用 iframe
- `public/tokmon-module.js` 提供 `AgentMonTokMon.mount(root)` 和 destroy 生命周期
- 用量数据存入 `usage_records`
- 增量扫描状态存入 `tokmon_scan_state`
- 日志路径读取 `tokmon.config.json`，缺省为 `~/.claude/projects` 和 `~/.codex/sessions`
- 费用配置仍保存在浏览器 `localStorage`

### sessions
- 外部列表分页、过滤、管理模式、多选删除/归档
- Prompt 列支持 first / last 切换
- 内部详情当前不分页，只提供 Top / Bottom 按钮

### skills
- skill 以 `source:name` 存储在数据库中
- 前端按 `name` 聚合显示跨平台安装状态
- broken symlink 会被标记为 broken
- `cleanup-broken` 会同时删除磁盘 symlink 与数据库记录

### MCP
- MCP 也按 `source:name` 存储
- 前端按 `name` 聚合跨平台安装状态
- 写操作会直接修改：
  - Claude Code：`~/.claude/settings.json`
  - Codex：`~/.codex/config.toml`

## 高风险点

- session 删除会直接删除真实 session 文件
- skill 卸载 / cleanup 会直接删除真实 symlink
- MCP / settings 保存会直接覆盖用户配置文件
- `public/app.js` 体积已经较大，改动时要注意别破坏其它 tab 的状态逻辑
- TokMon 前端依赖 CDN ECharts；离线环境下首页图表无法渲染

## 继续开发时建议优先级

1. 拆分前端状态与渲染辅助函数，减轻 `public/app.js` 复杂度
2. 为 TokMon 模块补更细的销毁/重挂载测试
3. 为 settings 保存增加更稳妥的校验和错误提示
4. 为 sessions / skills / mcp 增加更细粒度的成功提示
5. 评估是否要把 session 详情改成后端真正分页，而不是一次性全部读取
