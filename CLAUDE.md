# Claude Code 使用说明

本文件给 Claude Code（`claude-code` CLI / IDE 扩展）在本仓库工作时使用。通用协作约定见 [`AGENTS.md`](AGENTS.md)；开始工作前请先阅读该文件。

## Claude Code 专用注意事项

1. **Claude Code 自己就是被监控对象**。TokMon 会扫描 `~/.claude/projects/`。在本仓库工作时尽量不要往这些位置写“测试数据”或临时 session 文件，否则会污染 TokMon 用量。需要造数据时用一次性目录，完事清干净。

2. **不要自己 `git commit` / `git push`**，除非用户明确要求。提交风格与其他规范见 `AGENTS.md` 的“提交与 Pull Request 规范”。

## 文档入口

- `README.md`：面向用户的整体介绍与运行方式。
- `macos-app/README.md`：独立版 App 的使用、打包、数据目录。
- `AGENTS.md`：通用 agent 协作约定。
- `CLAUDE.md`（本文件）：Claude Code 使用说明。
