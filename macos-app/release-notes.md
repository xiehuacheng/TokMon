## 主要改动

- 设置窗口新增 **General** 区块，支持开机自启（Launch at Login）。
- **Sources** 改为每个来源独立开关 + **Select All** 全选，复选框移至各来源名称左侧，路径输入框在右侧。
- **Menu Bar** 显示项新增 **Cache Hit Rate**，并改为紧凑对齐的两列布局。
- 移除设置窗口中的 **Scan Now**，即时刷新统一使用 popover 工具栏的刷新按钮。
- Popover 时间范围新增 **Custom**，可在同一 popover 内选择起止日期。
- **Requests / Sessions** 页面新增关键字搜索过滤。
- 缓存命中率曲线图与热力图会根据数据分布动态调整纵坐标，避免固定 0-1 范围导致变化不明显。
- 未配置 Kimi API Key 时，自动隐藏 Quota 卡片与 Quota 页签。
- 自动更新窗口现在会通过 appcast 显示对应版本的更新日志（release-notes.html）。
- 同步更新 README、AGENTS.md、CLAUDE.md 与相关测试断言。

