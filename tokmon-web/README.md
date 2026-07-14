# TokMon Web - 跨平台 Token 统计工具

原版 [TokMon](https://github.com/xiehuacheng/TokMon) 是纯 macOS 应用。这是**跨平台 Web 版**，Windows/Mac/Linux 都能用。

## 功能

- 📊 多源统一统计（Claude Code / Codex / Kimi / Qwen Code / OpenCode）
- 📈 Token 趋势图、活动热力图
- 💰 费用估算（支持自定义模型价格）
- 🔍 请求日志搜索、Session 明细
- 🎨 GitHub Dark 主题

## 快速开始

### 1. 环境要求

- Python 3.8+
- 现代浏览器（Chrome/Edge/Firefox）

### 2. 安装

```bash
# 克隆仓库
git clone https://github.com/z3275630-ops/TokMon.git
cd TokMon

# 创建虚拟环境（推荐）
python3 -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate

# 安装依赖
pip install flask flask-cors requests pyzstd
```

### 3. 运行

```bash
cd tokmon-web
python app.py
```

浏览器打开 http://localhost:7899

### 4. 扫描数据

首次运行点击界面右上角「🔄 刷新数据」按钮，扫描本地 agent 日志并存入 SQLite。

## 数据路径

| Agent | 默认路径 | 说明 |
|-------|---------|------|
| Claude Code | `~/.claude/projects` | 扫描 session 日志 |
| Codex | `~/.codex` | 扫描 sessions/ + archived_sessions/ |
| Kimi Code | `~/.kimi-code` | 扫描 wire.jsonl |
| Qwen Code | `~/.qwen/projects` | 扫描项目日志 |
| OpenCode | `~/.local/share/opencode` | 读取 opencode.db SQLite |

所有路径可在界面设置中修改。

## 目录结构

```
TokMon/
├── macos-app/              # 原版 macOS 应用
└── tokmon-web/             # Web 版（本目录）
    ├── app.py              # Flask 后端
    ├── scanner/
    │   └── scanner.py      # 日志扫描器
    └── static/
        └── index.html      # 前端界面
```

## 技术栈

- **后端**：Flask + SQLite + pyzstd
- **前端**：原生 HTML/JS + Chart.js
- **主题**：GitHub Dark

## 注意事项

- 仅扫描本地文件，不上传任何数据
- SQLite 数据库存储在 `tokmon-web/tokmon.db`
- 支持增量扫描，不会重复处理已扫描的文件

## License

MIT (same as original)
