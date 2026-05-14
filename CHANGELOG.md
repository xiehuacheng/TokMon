# 更新日志

## v0.1.1 - 2026-05-14

### 改进

- 将 AgentMon 的后台扫描调整为按需工作：只有状态栏面板或 Web dashboard 处于打开/可见状态时，才会续租 activity 并启动扫描刷新；关闭后自动静默，降低空闲时的 Node CPU 与内存占用。
- 优化 TokMon 日志扫描：未变化的日志文件只检查文件大小，增长时只读取新增内容，避免周期性整文件读取导致资源尖刺。
- 优化 Claude Code / Codex session 扫描：缓存文件 size / mtime，文件未变化时跳过重复解析，只更新活跃状态。
- 状态栏面板的费用估算改为根据最新 summary 和价格配置实时计算，不再依赖 Web dashboard 打开后写回的旧金额。

### 修复

- 修复状态栏面板中 Est. Cost 只有打开 Web dashboard 后才更新的问题。
- 修复 Codex token 日志仅追加 usage 行时，增量扫描可能丢失 session id / model 上下文的问题。

### 验证

- 新增 TokMon 增量扫描回归测试。
- 新增 activity lease 回归测试。
- 新增状态栏费用计算回归测试。
