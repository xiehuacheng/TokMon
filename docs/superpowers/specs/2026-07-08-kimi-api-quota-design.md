# TokMon Kimi API Key 用量面板设计文档

日期：2026-07-08
状态：已实现（代码已落地，部分实现细节与本设计稿存在差异）

> **注意：** 实际代码支持多个 Kimi API Key 账户（`KimiAPIKeyAccount`），Key 按账户 ID 分别存入 Keychain，key 的增删改选集中在 popover 的 Quota 页面而非设置窗口；设置窗口仅保留刷新间隔配置。菜单栏也新增了 Kimi Weekly Quota / 5-Hour Quota 显示开关。阅读代码时请以 `TokMonQuotaView.swift`、`TokMonKimiQuotaStore.swift`、`TokMonEngineActor.swift` 和 `TokMonStatsStore.swift` 为准。

## 1. 目标

在 TokMon macOS 状态栏 App 中新增 **Kimi Code（Coding Plan）API Key 用量面板**，展示：

- **周额度（Weekly Usage）**
- **五小时滚动额度（5-Hour Throughput）**
- 剩余比例、已用/上限、重置倒计时
- 一个可在 Overview 页瞥见的迷你卡片，点击进入完整面板

## 2. 背景与约束

- Kimi Code 的用量接口目前是**未公开/逆向工程**接口，社区已有稳定使用：
  - 主端点：`GET https://api.kimi.com/coding/v1/usages`
  - 回退端点：`GET https://api.kimi.com/coding/v1/usage`
  - 认证：`Authorization: Bearer <sk-kimi-xxx>`
  - 需要 `User-Agent: KimiCLI/1.6`、`Accept: application/json`
  - 参考实现：
    - [Golden0Voyager/kimi-code-usage kimi.py](https://raw.githubusercontent.com/Golden0Voyager/kimi-code-usage/main/src/kimi_code_usage/providers/kimi.py)
    - [usagebar docs/providers/kimi.md](https://raw.githubusercontent.com/luisleineweber/usagebar/main/docs/providers/kimi.md)
- TokMon 目前：
  - 无网络请求
  - 无 Keychain 存储
  - 配置存 `~/Library/Application Support/TokMon/tokmon.config.json` 与 `tokmon-ui-state.json`
  - popover 页面现有 `overview` / `requests` / `sessions`
  - 刷新是事件驱动（popover 出现时刷新），没有全局轮询

## 3. 用户需求（已确认）

| 项 | 选择 |
|---|---|
| 目标产品 | Kimi Code（Coding Plan） |
| API Key 来源 | 在设置页手动输入 `sk-kimi-xxx` |
| Key 存储 | macOS Keychain |
| 主展示位置 | 新增 popover 页面，与 Overview/Requests/Sessions 并列 |
| 辅助展示 | Overview 页加一个迷你 Quota 卡片 |
| 自动刷新 | 可配置间隔（默认 5 分钟，可选 1/5/15/60/手动） |

## 4. 数据模型

```swift
// 一个额度窗口（周额度或 5 小时额度）
struct KimiQuotaWindow: Equatable, Sendable {
  var label: String           // "Weekly Usage" / "5h Limit"
  var used: Double            // 已用量（与 limit 同单位）
  var limit: Double           // 上限
  var remaining: Double       // 剩余量
  var percentUsed: Double     // 0.0 ~ 100.0
  var resetAt: Date?          // 额度重置时间
  var countdown: String?      // 本地化倒计时文案，如 "2h 15m"
}

struct KimiQuotaSnapshot: Equatable, Sendable {
  var weekly: KimiQuotaWindow?
  var fiveHour: KimiQuotaWindow?
  var fetchedAt: Date?
  var error: KimiQuotaError?
}

enum KimiQuotaError: Error, Equatable {
  case noAPIKey
  case invalidKey          // 401/403
  case endpointNotFound    // /usages 与 /usage 都 404
  case network             // 通用网络错误，具体 Error 通过 TokMonLog 记录
  case decoding
  case rateLimited         // 429
}
```

## 5. API 请求与解析

### 5.1 请求

```swift
let baseURL = "https://api.kimi.com/coding/v1"
var request = URLRequest(url: URL(string: baseURL + "/usages")!)
request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
request.setValue("KimiCLI/1.6", forHTTPHeaderField: "User-Agent")
request.setValue("application/json", forHTTPHeaderField: "Accept")
```

- 使用 `URLSessionConfiguration.ephemeral`（无需 cookie/cache）。
- 若 `/usages` 返回 404，则回退到 `/usage`。
- 仅处理 HTTP 状态：200 为成功；401/403 为 key 错误；429 为限流；其余为网络错误。

### 5.2 响应解析

支持两种返回形状：

**形状 A：**
```json
{
  "data": [
    { "model_name": "all", "limit": 1000, "used": 500 },
    { "model_name": "kimi-k2.6", "limit": 100, "used": 30 }
  ]
}
```
- `model_name == "all"` 视为周额度；其他条目暂忽略（未来可扩展 per-model）。

**形状 B：**
```json
{
  "usage": { "limit": "100", "remaining": "74", "resetTime": "2026-02-11T17:32:50.757941Z" },
  "limits": [
    {
      "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
      "detail": { "limit": "100", "remaining": "85", "resetTime": "2026-02-07T12:32:50.757941Z" }
    }
  ]
}
```
- `usage` 对象 → 周额度。
- `limits` 中 `window.duration == 300` 且 `timeUnit` 含 `MINUTE` → 5 小时额度。
- 字段兼容：`limit`/`limit_amount`、`used`/`used_amount`/`remaining`、`resetTime`/`reset_at`/`reset_time`/`reset_in`。
- `used` 优先；若缺失则用 `limit - remaining`。

## 6. 模块设计

### 6.1 新增文件

| 文件 | 职责 |
|---|---|
| `TokMonKeychain.swift` | Keychain 增删改查封装；service 名 `com.tokmon.kimi-code.api-key` |
| `TokMonKimiQuotaStore.swift` | actor；发起请求、解析 JSON、缓存 `KimiQuotaSnapshot` |
| `TokMonQuotaView.swift` | Quota 页面主视图 |
| `TokMonQuotaMiniCard.swift` | Overview 页迷你卡片 |

### 6.2 修改文件

| 文件 | 修改点 |
|---|---|
| `TokMonModels.swift` | 新增 `KimiQuotaWindow`、`KimiQuotaSnapshot`、`KimiQuotaError`；`TokMonUIState` 增加 `kimiQuotaRefreshInterval: Int`（分钟，`0` 表示手动刷新，默认 `5`） |
| `TokMonConfigStore.swift` | `normalizedUIState` 读取 `kimiQuotaRefreshInterval`；保存时透传 |
| `TokMonSettingsDraft.swift` | 新增 `kimiCodeAPIKey`（仅用于编辑，不持久化到 JSON）、`kimiQuotaRefreshInterval` |
| `TokMonEngineActor.swift` | `loadSettingsDraft` / `saveSettings` / `uiState(from:preserving:)` 映射新字段；提供刷新 quota 方法 |
| `TokMonSettingsWindow.swift` | 新增 "API Keys" 设置区块：安全输入框 + 刷新间隔选择 |
| `StatusPopoverView.swift` | 新增 `.quota` page、rail 按钮、Overview 页嵌入迷你卡片 |
| `TokMonStatsStore.swift` | 持有 `KimiQuotaSnapshot`；管理可见期内的自动刷新 Task |

### 6.3 Keychain 接口

```swift
enum TokMonKeychain {
  static func saveKimiAPIKey(_ key: String) throws
  static func loadKimiAPIKey() -> String?
  static func deleteKimiAPIKey() throws
}
```

- 使用 `kSecClassGenericPassword`。
- `kSecAttrService = "com.tokmon.kimi-code.api-key"`。
- `kSecAttrAccount = "kimi-code-api-key"`。
- 写入时若已存在则更新（`SecItemUpdate`）。

## 7. UI 设计

### 7.1 Quota 页面

- 顶部：页面标题 "Kimi Quota" + 刷新按钮 + 上次刷新时间。
- 两个卡片：
  - **Weekly**：进度条、已用/上限、剩余百分比、重置倒计时。
  - **5-Hour**：同上，进度条颜色可随使用率变化（如 >80% 橙色、>95% 红色）。
- 无 key 时：占位文案 + "Open Settings" 按钮。
- 错误时：红色横幅显示错误，下方保留上次成功数据（如有）。

### 7.2 Overview 迷你卡片

- 在 `overviewPage` 的 metric grid 下方、trend chart 上方插入一个可点击卡片。
- 仅展示两行：
  - `Week: 67%` + 小进度条
  - `5h: 23%` + 小进度条
- 点击后切换 `selectedPage = .quota`。
- 未配置 key 时隐藏或显示 "+ Kimi Key" 提示。

### 7.3 设置页

新增 "API Keys" section：

- **Kimi Code API Key**：SecureField，占位符 `sk-kimi-xxx`。
  - 保存时写入 Keychain。
  - 加载设置时不回显完整 key，只显示 "已配置" / "未配置"。
- **Quota Refresh Interval**：Picker / Segmented control
  - 选项：1 min / 5 min / 15 min / 60 min / Manual
  - 默认值 5 min。

## 8. 刷新策略

- **不引入全局定时器**；只在 Quota 页面可见或 Overview 迷你卡片可见时刷新。
- 具体行为：
  1. popover 出现 → `stats.popoverDidAppear()` 触发一次 quota 刷新。
  2. 如果当前页面是 `.quota` 或 Overview 显示迷你卡片，启动 `Task` 按 `kimiQuotaRefreshInterval` 周期刷新。
  3. popover 消失时取消 Task。
  4. 手动点击刷新按钮立即刷新。
- 刷新间隔写入 `TokMonUIState`，在 `TokMonStatsStore` 读取。
- 新增 `startQuotaRefreshTask()` / `stopQuotaRefreshTask()`，由 popover 出现/消失调用。

## 9. 错误处理

| 场景 | 行为 |
|---|---|
| 未配置 API Key | Quota 页面显示占位提示；Overview 迷你卡片隐藏或提示 "+ Kimi Key" |
| 401/403 | 标记 `KimiQuotaError.invalidKey`，提示检查 key 是否为 `sk-kimi-xxx` 且来自 Kimi Code 控制台 |
| 429 | 提示请求过频，稍后重试 |
| /usages 404，/usage 也失败 | `endpointNotFound`，提示接口可能已变更 |
| 网络/解析失败 | 保留旧数据，显示错误横幅 |

所有错误通过 `TokMonLog` 记录，不阻塞主流程。

## 10. 安全与隐私

- API Key 只存 Keychain，不进入 `tokmon.config.json` / `tokmon-ui-state.json`。
- 内存中只在 `TokMonSettingsDraft.kimiCodeAPIKey` 短暂持有，保存后立即清空或保留到设置窗口关闭。
- 网络请求使用 HTTPS；不记录请求/响应中的 key。
- Keychain item 的访问性使用 `kSecAttrAccessibleAfterFirstUnlock`（后台刷新不需要，popover 使用时用户已解锁）。
- 不启用 iCloud Keychain 同步（不加 `kSecAttrSynchronizable`），key 只保存在本机。

## 11. 测试计划

| 测试 | 位置 |
|---|---|
| 解析两种 JSON shape | `TokMonKimiQuotaTests.swift` |
| 5 小时窗口识别逻辑 | `TokMonKimiQuotaTests.swift` |
| `resetTime` / `reset_in` 倒计时计算 | `TokMonKimiQuotaTests.swift` |
| Keychain 增删改查 | `TokMonKeychainTests.swift`（使用独立 test service） |
| 设置 draft 保存/加载（interval + key 存在状态） | `TokMonSettingsStoreTests.swift` |
| UI 状态序列化兼容性 | `TokMonConfigStoreTests.swift` |
| 手动验证 | 填入真实 key，对比 `kimi-usage --json` 输出 |

## 12. 影响范围

- 新增网络能力：首次引入 `URLSession` 和出站 HTTPS 请求。
- 新增敏感凭证存储：首次引入 Keychain。
- 现有扫描/查询逻辑不受影响。
- 数据库 schema 不变，无需重建。
- `TokMonScanner.scannerVersion` 不需要递增（本功能与本地日志扫描无关）。

## 13. 风险与回退

| 风险 | 应对 |
|---|---|
| Kimi 未公开接口变更 | 解析器设计为宽容；接口变更时显示 `endpointNotFound` 提示，不影响 App 其他功能 |
| Keychain API 失败 | 保存时向用户提示；加载失败按未配置处理 |
| 网络异常导致 popover 卡顿 | 请求在 actor 后台执行，不阻塞 UI；UI 只读取缓存 snapshot |
| 用户反感额外权限 | Keychain 在 macOS 上无需用户授权即可访问本 App 创建的 item |

## 14. 后续扩展

- 其他 provider（OpenAI、Anthropic、Google）可按同样模式新增：
  - 一个 `APIQuotaProvider` 协议
  - 各自的 endpoint / parser
  - Keychain service 按 provider 区分
  - Quota 页面按 provider 切换或并列展示
- 未来可考虑把 Quota 数据也写入本地数据库，支持历史趋势，但本次不做。
