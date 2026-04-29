# Repository Guidelines

## 项目结构与模块组织

AgentMon 是一个本地 Web 管理面板，用于统一管理 Claude Code 与 Codex 的 token usage、sessions、skills、MCP servers 和配置。后端代码位于 `src/`：`src/index.ts` 负责服务启动、配置读取、路由挂载和定时扫描；`src/db.ts` 负责 SQLite schema、upsert 和 delete helpers；`src/scanner/` 负责管理类元数据扫描；`src/tokmon/` 负责 TokMon 用量扫描；`src/routes/` 负责 API 和明确的文件变更操作。

前端保持轻量：入口是 `public/index.html`，样式在 `public/style.css`，AgentMon 浏览器逻辑集中在 `public/app.js`。TokMon 首页同页渲染，交互逻辑在 `public/tokmon-module.js`。除非项目明确决定重构，不要引入前端框架或构建工具。

## 构建、测试与本地开发命令

- `npm install`：安装运行依赖和 TypeScript 工具链。
- `npm run dev`：以 watch 模式启动 Hono 服务，默认端口为 `3388`。
- `npm start`：不带 watch 模式启动服务。

启动后打开 `http://localhost:3388`。当前没有独立 build 脚本，TypeScript 通过 `tsx` 直接运行。

## 代码风格与命名约定

遵循现有 TypeScript ESM 写法和模块边界。scanner 只做本地文件扫描与索引更新，routes 负责 API 与真实文件修改，`db.ts` 维护数据库结构和持久化 helper。TokMon API 必须保留在 `/api/tokmon/*`，不要占用 `/api/sessions`。优先使用短小直接的函数，不为临时需求增加抽象。

TypeScript 与 JavaScript 使用两个空格缩进。命名应清晰表达领域含义，例如 `scanClaudeSessions`、`sessionsPage`、`selectedSkillName`。前端状态目前应继续留在 `public/app.js`，避免无关重构影响其他 tab。

## 测试指南

当前未配置自动化测试框架。提交前至少运行 `npx tsc --noEmit` 和 `npm run dev`，并在浏览器中手动验证受影响功能。修改 TokMon 时验证首页、`/api/tokmon/summary` 和请求日志；修改 sessions、skills、MCP 或 settings 时，尽量同时验证 Claude Code 与 Codex 路径。

注意高风险操作：删除 session、清理 broken skill、卸载 skill、保存 MCP/settings 都会修改用户本地真实文件。

## 提交与 Pull Request 规范

当前目录没有可用 Git 历史，无法推断既有提交风格。建议使用简短的祈使句提交信息，例如 `Add MCP install feedback` 或 `Fix broken skill cleanup`。

PR 应包含变更摘要、影响范围、手动验证步骤；涉及 UI 的改动应附截图。任何会写入 `~/.claude`、`~/.codex`、session 文件、symlink 或配置文件的变更，都应在说明中明确标出。

## Agent 专用注意事项

较大改动前先阅读 `README.md` 和本文件。保持项目轻量架构，不要在 `public/app.js` 或 `public/tokmon-module.js` 中做无关整理。skills 和 MCP 在数据库中按 `source:name` 存储，但 UI 按 `name` 聚合展示；修改相关逻辑时必须保留这个约定。TokMon 用量数据写入 `usage_records`，扫描 offset 写入 `tokmon_scan_state`。
