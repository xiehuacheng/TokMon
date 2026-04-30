# HANDOFF.md

本文档面向接手 AgentMon 的其他 AI agent，用于快速理解当前项目状态、架构和注意事项。

## 1. 项目目标

AgentMon 是一个本地 Web 管理面板，统一管理 Claude Code 与 Codex 的 token usage、sessions、skills、MCP servers 与配置。

TokMon 已集成为默认首页，负责 token 用量监控；其它 tab 负责本地管理操作。

## 2. 当前完成度

项目已经可运行，且核心功能可用：
- TokMon 首页：token 趋势、热力图、模型/来源分布、请求日志、费用估算
- sessions 列表 / 过滤 / 分页 / 多选管理
- sessions prompt 切换 first / last
- session 详情查看，提供 Top / Bottom 快速滚动
- skills 列表、详情、启用/禁用、卸载
- skills 跨平台安装/卸载（Claude Code ↔ Codex）
- broken skill 检测与一键清理
- MCP 列表、详情、增删、启用/禁用
- MCP 跨平台安装/卸载
- settings 读取与保存

## 3. 关键架构

### 服务入口
- `src/index.ts`

职责：
- 读取 `agentmon.config.json`
- 读取 `tokmon.config.json`
- 初始化 SQLite
- 执行首次扫描
- 每 5 秒执行一次 AgentMon 元数据扫描
- 每 3 秒执行一次 TokMon usage 扫描
- 挂载路由与静态资源

### 数据库
- `src/db.ts`

主要表：
- `sessions`
- `skills`
- `mcp_servers`
- `plugins`
- `scan_state`
- `usage_records`
- `tokmon_scan_state`

注意：
- `sessions` 现在有 `first_prompt` 与 `last_prompt`
- schema 初始化后会尝试 `ALTER TABLE sessions ADD COLUMN last_prompt TEXT`
- TokMon 用量数据也写入同一个 `agentmon.db`
- AgentMon 的 session 扫描状态仍用 `scan_state`，TokMon offset 独立用 `tokmon_scan_state`

### 扫描器
- `src/scanner/claude-sessions.ts`
- `src/scanner/codex-sessions.ts`
- `src/scanner/claude-skills.ts`
- `src/scanner/codex-skills.ts`
- `src/scanner/claude-settings.ts`
- `src/scanner/codex-settings.ts`
- `src/tokmon/scanner.ts`

职责：
- 扫描本地真实文件
- 解析结构化信息
- 写入 SQLite 索引

重要逻辑：
- Claude sessions 会跳过只有 `file-history-snapshot` 的空记录
- Claude / Codex sessions 都会提取 `first_prompt` 和 `last_prompt`
- broken symlink skill 会被标记为 description=`Broken symlink -> ...`
- TokMon 扫描 Claude assistant `message.usage`
- TokMon 扫描 Codex `token_count`，并把 `cached_input_tokens` 从 input 中拆为 cache read

### API 路由
- `src/routes/sessions.ts`
- `src/routes/skills.ts`
- `src/routes/mcp.ts`
- `src/routes/settings.ts`
- `src/routes/tokmon.ts`

要点：
- POST 安装类接口现在会立即写数据库，不再依赖 scanner 延迟刷新
- DELETE 类接口会直接修改真实文件和数据库
- TokMon API 挂载到 `/api/tokmon/*`，避免和 AgentMon `/api/sessions` 冲突

## 4. 前端状态设计

所有前端逻辑都集中在 `public/app.js`。

### TokMon
关键点：
- 默认 tab 是 `tokmon`
- `public/app.js` 直接渲染 TokMon DOM，没有 iframe
- `public/tokmon-module.js` 提供 `AgentMonTokMon.mount(root)`，切换 tab 时需要调用 destroy
- TokMon 前端 API 走 `/api/tokmon/*`
- `public/tokmon/` 里保留了原始独立页面，主要用于对照和调试

### Sessions
关键状态：
- `sessionsPage`
- `sessionsPageSize`
- `sessionsFilters`
- `sessionsManageMode`
- `selectedSessionIds`
- `showLastPrompt`

### Skills
关键状态：
- `selectedSkillName`

重要：
- skills 前端不是按数据库主键选中，而是按 `name` 选中
- 这是为了支持“同名 skill 在两个平台安装”的聚合视图

### MCP
关键状态：
- `selectedMcpName`

同样按 `name` 聚合，而不是按 `source:name`

## 5. 已解决的坑

### 5.1 空 sessions
原因：Claude Code 会留下只有 `file-history-snapshot` 的 JSONL
处理：scanner 跳过 `messageCount === 0`

### 5.2 broken skills 无法显示内容
原因：很多 skill 是断链 symlink
处理：scanner 标记为 broken，前端显示 broken，并支持 cleanup

### 5.3 skills / MCP 跨平台安装要点多次才刷新
原因：POST 只改磁盘，不改数据库
处理：POST 路由立即 upsert 到数据库

### 5.4 安装后标签不刷新
原因：前端之前按 `source:name` 选中
处理：改为按 `name` 聚合选中

## 6. 目前最容易出问题的地方

1. `public/app.js` 很大，改动任何一处都可能影响其它 tab
2. `public/tokmon-module.js` 来自 TokMon 前端，体积较大，并依赖 CDN ECharts
3. `sessions.ts` 详情接口当前仍是把全部消息读入内存后再返回
4. `settings.ts` 直接覆盖用户配置文件，缺少更强校验
5. `skills.ts` / `mcp.ts` 的跨平台安装依赖“同名即同项”的假设

## 7. 如果你要继续做什么

### 推荐短期任务
- 把 `public/app.js` 拆成多个渲染辅助函数
- 给设置保存增加错误提示和格式校验
- 给跨平台安装/卸载加 toast 或操作反馈
- 让 session 详情支持真正的后端流式/分页读取

### 修改 skills / mcp 时要记住
- 列表显示是按 `name` 聚合
- 数据库存储还是按 `source:name`
- 前端 detail 选中状态必须继续用 `name`

## 8. 运行方式

```bash
npm install
npm run dev
```

默认端口：`3388`

## 9. 文档对应关系

- `README.md`：给项目使用者看
- `CLAUDE.md`：给在本仓库工作的 Claude / 开发 agent 看
- `HANDOFF.md`：给新接手本项目的 AI agent 看，强调上下文与坑点
