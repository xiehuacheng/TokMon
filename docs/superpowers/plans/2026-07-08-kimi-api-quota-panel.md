# TokMon Kimi API Key 用量面板实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 TokMon macOS App 中为 Kimi Code（Coding Plan）增加 API Key 用量面板，展示周额度、5 小时滚动额度、重置倒计时，并在 Overview 页提供迷你卡片入口。

**Architecture:** 复用现有 actor + `@MainActor ObservableObject` 架构。新增 `TokMonKimiQuotaStore`（actor）负责网络请求与解析，`TokMonKeychain` 负责安全存储 API Key；`TokMonStatsStore` 在 popover 可见期间按配置间隔轮询；UI 通过新增 `.quota` popover 页面与 Overview 迷你卡片展示。

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, Security.framework, URLSession, SQLite（仅用于现有功能）

---

## 文件结构

### 新增文件

| 文件 | 职责 |
|---|---|
| `macos-app/Sources/TokMonApp/TokMonKeychain.swift` | Keychain 读写封装（含内部测试接口） |
| `macos-app/Sources/TokMonApp/TokMonKimiQuotaStore.swift` | Kimi `/usages` 请求、回退 `/usage`、JSON 解析 |
| `macos-app/Sources/TokMonApp/TokMonQuotaView.swift` | Quota 页面主视图 |
| `macos-app/Sources/TokMonApp/TokMonQuotaMiniCard.swift` | Overview 页迷你 Quota 卡片 |
| `macos-app/Tests/TokMonAppTests/TokMonKeychainTests.swift` | Keychain 增删改查测试 |
| `macos-app/Tests/TokMonAppTests/TokMonKimiQuotaTests.swift` | JSON 解析与窗口识别测试 |

### 修改文件

| 文件 | 修改点 |
|---|---|
| `macos-app/Package.swift` | `linkerSettings` 增加 `.linkedFramework("Security")` |
| `macos-app/Sources/TokMonApp/TokMonModels.swift` | 新增额度模型；`TokMonUIState` 增加 `kimiQuotaRefreshInterval` |
| `macos-app/Sources/TokMonApp/TokMonConfigStore.swift` | 读取/保存 `kimiQuotaRefreshInterval` |
| `macos-app/Sources/TokMonApp/TokMonSettingsDraft.swift` | 增加 key 与刷新间隔 draft 字段 |
| `macos-app/Sources/TokMonApp/TokMonEngine.swift` | 注入 `TokMonKimiQuotaStore` |
| `macos-app/Sources/TokMonApp/TokMonEngineActor.swift` | 设置映射、quota 刷新、Keychain 操作 |
| `macos-app/Sources/TokMonApp/TokMonSettingsStore.swift` | 增加清除 key 方法 |
| `macos-app/Sources/TokMonApp/TokMonSettingsWindow.swift` | 新增 "API Keys" 设置区块 |
| `macos-app/Sources/TokMonApp/TokMonStatsStore.swift` | 持有 `KimiQuotaSnapshot`，管理可见期轮询 |
| `macos-app/Sources/TokMonApp/StatusPopoverView.swift` | 新增 `.quota` 页面、迷你卡片 |

---

## Task 1: 额度数据模型与 UI 状态字段

**Files:**
- Modify: `macos-app/Sources/TokMonApp/TokMonModels.swift`
- Test: `macos-app/Tests/TokMonAppTests/TokMonConfigStoreTests.swift`

- [ ] **Step 1: 新增 Kimi 额度模型**

在 `TokMonModels.swift` 中 `TokMonUIState` 之前加入：

```swift
struct KimiQuotaWindow: Equatable, Sendable {
  var label: String
  var used: Double
  var limit: Double
  var remaining: Double
  var percentUsed: Double
  var resetAt: Date?
  var countdown: String?
}

struct KimiQuotaSnapshot: Equatable, Sendable {
  var weekly: KimiQuotaWindow?
  var fiveHour: KimiQuotaWindow?
  var fetchedAt: Date?
  var error: KimiQuotaError?

  static let empty = KimiQuotaSnapshot()
}

enum KimiQuotaError: Error, Equatable {
  case noAPIKey
  case invalidKey
  case endpointNotFound
  case network
  case decoding
  case rateLimited
}
```

- [ ] **Step 2: TokMonUIState 增加刷新间隔字段**

在 `TokMonUIState` 中 `refreshRate` 与 `costRates` 之间插入：

```swift
  var refreshRate: Int
  var kimiQuotaRefreshInterval: Int = 5
  var costRates: TokMonCostRates
```

在 `TokMonUIState.default` 中 `refreshRate: 3000,` 之后插入：

```swift
    kimiQuotaRefreshInterval: 5,
```

- [ ] **Step 3: 运行现有测试，确认无编译错误**

Run: `cd /Users/orange/Desktop/Project/TokMon/macos-app && swift test --filter TokMonConfigStoreTests`
Expected: PASS（模型变更尚未破坏已有测试）

- [ ] **Step 4: 提交**

```bash
git add macos-app/Sources/TokMonApp/TokMonModels.swift
git commit -m "Add Kimi quota data models and refresh interval field"
```

---

## Task 2: Keychain 封装

**Files:**
- Create: `macos-app/Sources/TokMonApp/TokMonKeychain.swift`
- Modify: `macos-app/Package.swift`
- Test: `macos-app/Tests/TokMonAppTests/TokMonKeychainTests.swift`

- [ ] **Step 1: 链接 Security.framework**

在 `macos-app/Package.swift` 的 `linkerSettings` 数组中增加：

```swift
        .linkedFramework("Security"),
```

- [ ] **Step 2: 编写 TokMonKeychain.swift**

```swift
import Foundation
import Security

enum TokMonKeychain {
  static let kimiService = "com.tokmon.kimi-code.api-key"
  static let kimiAccount = "kimi-code-api-key"

  static func saveKimiAPIKey(_ key: String) throws {
    try save(key, service: kimiService, account: kimiAccount)
  }

  static func loadKimiAPIKey() -> String? {
    load(service: kimiService, account: kimiAccount)
  }

  static func deleteKimiAPIKey() throws {
    try delete(service: kimiService, account: kimiAccount)
  }

  // MARK: - Internal primitives for testability

  static func save(_ value: String, service: String, account: String) throws {
    guard let data = value.data(using: .utf8) else {
      throw KimiKeychainError.invalidData
    }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]
    let status = SecItemAdd(query as CFDictionary, nil)
    if status == errSecDuplicateItem {
      let updateQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
      ]
      let updateAttrs: [String: Any] = [kSecValueData as String: data]
      let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)
      guard updateStatus == errSecSuccess else {
        throw KimiKeychainError.osStatus(updateStatus)
      }
    } else if status != errSecSuccess {
      throw KimiKeychainError.osStatus(status)
    }
  }

  static func load(service: String, account: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func delete(service: String, account: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KimiKeychainError.osStatus(status)
    }
  }
}

enum KimiKeychainError: Error {
  case invalidData
  case osStatus(OSStatus)
}
```

- [ ] **Step 3: 编写 Keychain 测试**

```swift
import Foundation
import Testing
@testable import TokMonApp

@Suite struct TokMonKeychainTests {
  private let testService = "com.tokmon.test.key"
  private let testAccount = "test-account"

  init() throws {
    try? TokMonKeychain.delete(service: testService, account: testAccount)
  }

  deinit {
    try? TokMonKeychain.delete(service: testService, account: testAccount)
  }

  @Test func keychainSaveLoadDelete() throws {
    let value = "sk-kimi-test-key"
    #expect(TokMonKeychain.load(service: testService, account: testAccount) == nil)

    try TokMonKeychain.save(value, service: testService, account: testAccount)
    #expect(TokMonKeychain.load(service: testService, account: testAccount) == value)

    let updated = "sk-kimi-updated"
    try TokMonKeychain.save(updated, service: testService, account: testAccount)
    #expect(TokMonKeychain.load(service: testService, account: testAccount) == updated)

    try TokMonKeychain.delete(service: testService, account: testAccount)
    #expect(TokMonKeychain.load(service: testService, account: testAccount) == nil)
  }
}
```

- [ ] **Step 4: 运行 Keychain 测试**

Run: `cd /Users/orange/Desktop/Project/TokMon/macos-app && swift test --filter TokMonKeychainTests`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add macos-app/Package.swift macos-app/Sources/TokMonApp/TokMonKeychain.swift macos-app/Tests/TokMonAppTests/TokMonKeychainTests.swift
git commit -m "Add Keychain wrapper for Kimi API key"
```

---

## Task 3: Kimi 额度网络 Store 与解析器

**Files:**
- Create: `macos-app/Sources/TokMonApp/TokMonKimiQuotaStore.swift`
- Test: `macos-app/Tests/TokMonAppTests/TokMonKimiQuotaTests.swift`

- [ ] **Step 1: 编写 TokMonKimiQuotaStore.swift**

```swift
import Foundation

actor TokMonKimiQuotaStore {
  private let baseURL: String
  private let urlSession: URLSession

  init(baseURL: String = "https://api.kimi.com/coding/v1", urlSession: URLSession = .shared) {
    self.baseURL = baseURL
    self.urlSession = urlSession
  }

  func fetchQuota(apiKey: String) async -> KimiQuotaSnapshot {
    do {
      let snapshot = try await performFetch(apiKey: apiKey)
      return snapshot
    } catch let error as KimiQuotaError {
      return KimiQuotaSnapshot(weekly: nil, fiveHour: nil, fetchedAt: nil, error: error)
    } catch {
      return KimiQuotaSnapshot(weekly: nil, fiveHour: nil, fetchedAt: nil, error: .network)
    }
  }

  private func performFetch(apiKey: String) async throws -> KimiQuotaSnapshot {
    let data = try await fetchData(apiKey: apiKey, path: "/usages")
    return try parseUsagePayload(data, fetchedAt: Date())
  }

  private func fetchData(apiKey: String, path: String) async throws -> Data {
    guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else {
      throw KimiQuotaError.network
    }
    var request = URLRequest(url: url)
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("KimiCLI/1.6", forHTTPHeaderField: "User-Agent")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let (data, response) = try await urlSession.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw KimiQuotaError.network
    }

    switch httpResponse.statusCode {
    case 200:
      return data
    case 404:
      throw KimiQuotaError.endpointNotFound
    case 401, 403:
      throw KimiQuotaError.invalidKey
    case 429:
      throw KimiQuotaError.rateLimited
    default:
      throw KimiQuotaError.network
    }
  }
}

// MARK: - Parsing

private let isoFormatter: ISO8601DateFormatter = {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return formatter
}()

private let isoFormatterNoFraction: ISO8601DateFormatter = {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime]
  return formatter
}()

private func parseDate(_ string: String) -> Date? {
  isoFormatter.date(from: string) ?? isoFormatterNoFraction.date(from: string)
}

private func parseNumber(_ value: Any?) -> Double? {
  if let num = value as? NSNumber { return num.doubleValue }
  if let str = value as? String, let d = Double(str) { return d }
  return nil
}

private func parseUsagePayload(_ data: Data, fetchedAt: Date) throws -> KimiQuotaSnapshot {
  guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
    throw KimiQuotaError.decoding
  }

  var weekly: KimiQuotaWindow?
  var fiveHour: KimiQuotaWindow?

  if let dataList = json["data"] as? [[String: Any]] {
    for item in dataList {
      let label = (item["model_name"] as? String) == "all" ? "Weekly Usage" : "Limit"
      if let window = makeWindow(from: item, label: label, now: fetchedAt) {
        if (item["model_name"] as? String) == "all" {
          weekly = window
        }
      }
    }
  }

  if let usage = json["usage"] as? [String: Any] {
    weekly = makeWindow(from: usage, label: "Weekly Usage", now: fetchedAt)
  }

  if let limits = json["limits"] as? [[String: Any]] {
    for item in limits {
      let detail = (item["detail"] as? [String: Any]) ?? item
      let windowMeta = item["window"] as? [String: Any]
      let isFiveHour = isFiveHourWindow(windowMeta)
      if isFiveHour, let window = makeWindow(from: detail, label: "5-Hour Limit", now: fetchedAt) {
        fiveHour = window
        break
      }
    }
  }

  return KimiQuotaSnapshot(weekly: weekly, fiveHour: fiveHour, fetchedAt: fetchedAt, error: nil)
}

private func isFiveHourWindow(_ window: [String: Any]?) -> Bool {
  guard let window else { return false }
  guard let duration = parseNumber(window["duration"]) else { return false }
  let timeUnit = (window["timeUnit"] as? String)?.uppercased() ?? ""
  return duration == 300 && timeUnit.contains("MINUTE")
}

private func makeWindow(from dict: [String: Any], label: String, now: Date) -> KimiQuotaWindow? {
  guard let limit = parseNumber(dict["limit"] ?? dict["limit_amount"]) else { return nil }

  let used: Double
  if let usedValue = parseNumber(dict["used"] ?? dict["used_amount"]) {
    used = usedValue
  } else if let remaining = parseNumber(dict["remaining"]) {
    used = max(0, limit - remaining)
  } else {
    return nil
  }

  let resetAt = resetDate(from: dict)
  let countdown = resetAt.map { countdownString(from: now, to: $0) }

  return KimiQuotaWindow(
    label: label,
    used: used,
    limit: limit,
    remaining: max(0, limit - used),
    percentUsed: limit > 0 ? (used / limit) * 100 : 0,
    resetAt: resetAt,
    countdown: countdown
  )
}

private func resetDate(from dict: [String: Any]) -> Date? {
  if let resetTime = dict["resetTime"] as? String ?? dict["reset_at"] as? String ?? dict["reset_time"] as? String {
    return parseDate(resetTime)
  }
  if let resetIn = parseNumber(dict["reset_in"]) {
    return Date().addingTimeInterval(resetIn)
  }
  return nil
}

private func countdownString(from now: Date, to resetAt: Date) -> String {
  let diff = resetAt.timeIntervalSince(now)
  guard diff > 0 else { return "0m" }
  let hours = Int(diff) / 3600
  let minutes = (Int(diff) % 3600) / 60
  if hours > 0 {
    return "\(hours)h \(minutes)m"
  }
  return "\(minutes)m"
}
```

- [ ] **Step 2: 编写解析测试**

```swift
import Foundation
import Testing
@testable import TokMonApp

@Suite struct TokMonKimiQuotaTests {
  @Test func parseShapeAWeeklyOnly() throws {
    let json = """
    {
      "data": [
        { "model_name": "all", "limit": 1000, "used": 500 }
      ]
    }
    """.data(using: .utf8)!

    let store = TokMonKimiQuotaStore()
    let snapshot = try await store.parseForTests(json: json)

    #expect(snapshot.weekly?.limit == 1000)
    #expect(snapshot.weekly?.used == 500)
    #expect(snapshot.weekly?.percentUsed == 50)
    #expect(snapshot.fiveHour == nil)
  }

  @Test func parseShapeBWeeklyAndFiveHour() throws {
    let json = """
    {
      "usage": { "limit": "100", "remaining": "74", "resetTime": "2026-02-11T17:32:50.757941Z" },
      "limits": [
        {
          "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
          "detail": { "limit": "100", "remaining": "85", "resetTime": "2026-02-07T12:32:50.757941Z" }
        }
      ]
    }
    """.data(using: .utf8)!

    let store = TokMonKimiQuotaStore()
    let snapshot = try await store.parseForTests(json: json)

    #expect(snapshot.weekly?.limit == 100)
    #expect(snapshot.weekly?.used == 26)
    #expect(snapshot.fiveHour?.limit == 100)
    #expect(snapshot.fiveHour?.used == 15)
    #expect(snapshot.fiveHour?.label == "5-Hour Limit")
  }

  @Test func parseResetInCountdown() throws {
    let json = """
    {
      "usage": { "limit": 100, "used": 10, "reset_in": 7200 }
    }
    """.data(using: .utf8)!

    let store = TokMonKimiQuotaStore()
    let snapshot = try await store.parseForTests(json: json)

    #expect(snapshot.weekly?.used == 10)
    #expect(snapshot.weekly?.countdown == "2h 0m")
  }
}
```

- [ ] **Step 3: 为测试暴露 parseForTests**

在 `TokMonKimiQuotaStore.swift` 的 `actor TokMonKimiQuotaStore` 内部增加：

```swift
  func parseForTests(json: Data) throws -> KimiQuotaSnapshot {
    try parseUsagePayload(json, fetchedAt: Date())
  }
```

- [ ] **Step 4: 运行解析测试**

Run: `cd /Users/orange/Desktop/Project/TokMon/macos-app && swift test --filter TokMonKimiQuotaTests`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add macos-app/Sources/TokMonApp/TokMonKimiQuotaStore.swift macos-app/Tests/TokMonAppTests/TokMonKimiQuotaTests.swift
git commit -m "Add Kimi quota network store and parser"
```

---

## Task 4: 设置持久化与 Engine Actor 桥接

**Files:**
- Modify: `macos-app/Sources/TokMonApp/TokMonConfigStore.swift`
- Modify: `macos-app/Sources/TokMonApp/TokMonSettingsDraft.swift`
- Modify: `macos-app/Sources/TokMonApp/TokMonEngine.swift`
- Modify: `macos-app/Sources/TokMonApp/TokMonEngineActor.swift`
- Test: `macos-app/Tests/TokMonAppTests/TokMonSettingsStoreTests.swift`

- [ ] **Step 1: TokMonConfigStore 读取刷新间隔**

在 `normalizedUIState(from:)` 中 `refreshRate` 行之后插入：

```swift
      kimiQuotaRefreshInterval: intValue(object["kimiQuotaRefreshInterval"]) ?? defaults.kimiQuotaRefreshInterval,
```

- [ ] **Step 2: TokMonSettingsDraft 增加字段**

在末尾 `availableModels` 之前插入：

```swift
  var kimiCodeAPIKey: String = ""
  var kimiCodeAPIKeyConfigured: Bool = false
  var kimiQuotaRefreshInterval: Int = TokMonUIState.default.kimiQuotaRefreshInterval
```

- [ ] **Step 3: TokMonEngine 注入 quota store**

将 `TokMonEngine` 改为：

```swift
final class TokMonEngine: @unchecked Sendable {
  let configStore: TokMonConfigStore
  let database: TokMonDatabase
  let scanner: TokMonScanner
  let queryStore: TokMonQueryStore
  let kimiQuotaStore: TokMonKimiQuotaStore

  init(
    configStore: TokMonConfigStore,
    database: TokMonDatabase,
    scanner: TokMonScanner? = nil,
    queryStore: TokMonQueryStore? = nil,
    kimiQuotaStore: TokMonKimiQuotaStore? = nil
  ) {
    self.configStore = configStore
    self.database = database
    self.scanner = scanner ?? TokMonScanner(database: database)
    self.queryStore = queryStore ?? TokMonQueryStore(database: database)
    self.kimiQuotaStore = kimiQuotaStore ?? TokMonKimiQuotaStore()
  }
}
```

- [ ] **Step 4: TokMonEngineActor 加载/保存设置并暴露 quota 方法**

在 `loadSettingsDraft()` 返回的 `TokMonSettingsDraft` 初始化中 `modelPricing: uiState.modelPricing,` 之后插入：

```swift
      kimiCodeAPIKey: "",
      kimiCodeAPIKeyConfigured: TokMonKeychain.loadKimiAPIKey() != nil,
      kimiQuotaRefreshInterval: uiState.kimiQuotaRefreshInterval,
```

在 `saveSettings(draft:)` 中 `try engine.configStore.saveConfig(config)` 之后插入：

```swift
    if !draft.kimiCodeAPIKey.isEmpty {
      try TokMonKeychain.saveKimiAPIKey(draft.kimiCodeAPIKey)
    }
```

在 `uiState(from:preserving:)` 中 `modelPricing: normalizedModelPricing(draft.modelPricing),` 之后插入：

```swift
      kimiQuotaRefreshInterval: max(0, draft.kimiQuotaRefreshInterval),
```

在 `TokMonEngineActor` 中新增以下方法：

```swift
  func refreshKimiQuota() async -> KimiQuotaSnapshot {
    guard let apiKey = TokMonKeychain.loadKimiAPIKey(), !apiKey.isEmpty else {
      return KimiQuotaSnapshot(weekly: nil, fiveHour: nil, fetchedAt: nil, error: .noAPIKey)
    }
    return await engine.kimiQuotaStore.fetchQuota(apiKey: apiKey)
  }

  func deleteKimiAPIKey() throws {
    try TokMonKeychain.deleteKimiAPIKey()
  }

  func loadKimiQuotaRefreshInterval() throws -> Int {
    let state = try engine.configStore.loadUIState()
    return max(0, state.kimiQuotaRefreshInterval)
  }
```

- [ ] **Step 5: 更新 TokMonSettingsStoreTests**

在 `macos-app/Tests/TokMonAppTests/TokMonSettingsStoreTests.swift` 中新增测试（若文件不存在则创建）：

```swift
import Foundation
import Testing
@testable import TokMonApp

@Suite struct TokMonSettingsStoreQuotaTests {
  @Test func settingsDraftPreservesKimiQuotaInterval() throws {
    let dataDir = try makeTokMonTempDir()
    let configStore = TokMonConfigStore(dataDir: dataDir)
    let database = try TokMonDatabase(appDataDir: dataDir)
    let engine = TokMonEngine(configStore: configStore, database: database)
    let actor = TokMonEngineActor(engine: engine)

    var draft = try actor.loadSettingsDraft()
    draft.kimiQuotaRefreshInterval = 15
    try actor.saveSettings(draft: draft)

    let reloaded = try actor.loadSettingsDraft()
    #expect(reloaded.kimiQuotaRefreshInterval == 15)
  }
}
```

- [ ] **Step 6: 运行相关测试**

Run: `cd /Users/orange/Desktop/Project/TokMon/macos-app && swift test --filter TokMonSettingsStoreQuotaTests`
Expected: PASS

- [ ] **Step 7: 提交**

```bash
git add macos-app/Sources/TokMonApp/TokMonConfigStore.swift macos-app/Sources/TokMonApp/TokMonSettingsDraft.swift macos-app/Sources/TokMonApp/TokMonEngine.swift macos-app/Sources/TokMonApp/TokMonEngineActor.swift macos-app/Tests/TokMonAppTests/TokMonSettingsStoreTests.swift
git commit -m "Wire Kimi quota settings through engine actor"
```

---

## Task 5: 设置窗口 UI

**Files:**
- Modify: `macos-app/Sources/TokMonApp/TokMonSettingsWindow.swift`
- Modify: `macos-app/Sources/TokMonApp/TokMonSettingsStore.swift`

- [ ] **Step 1: TokMonSettingsStore 增加清除 key 方法**

在 `rebuildAndRescan()` 之后加入：

```swift
  func clearKimiAPIKey() async throws {
    try await runBusyAction {
      try await engineActor.deleteKimiAPIKey()
      draft.kimiCodeAPIKey = ""
      draft.kimiCodeAPIKeyConfigured = false
      statusMessage = "Kimi API key cleared."
    }
  }
```

- [ ] **Step 2: 设置窗口新增 API Keys 区块**

在 `TokMonSettingsWindow.swift` 的 `SettingsSection("Maintenance")` 之后、`footer` 之前插入：

```swift
            SettingsSection("API Keys") {
              FieldRow("Kimi Code") {
                HStack(spacing: 8) {
                  SecureField("sk-kimi-xxx", text: $store.draft.kimiCodeAPIKey)
                    .settingsTextField(width: 300)
                  Text(store.draft.kimiCodeAPIKeyConfigured ? "Configured" : "Not configured")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(store.draft.kimiCodeAPIKeyConfigured ? .secondary : TokMonGlass.danger)
                }
              }
              FieldRow("Refresh") {
                Picker("Refresh Interval", selection: $store.draft.kimiQuotaRefreshInterval) {
                  Text("Manual").tag(0)
                  Text("1 min").tag(1)
                  Text("5 min").tag(5)
                  Text("15 min").tag(15)
                  Text("60 min").tag(60)
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
              }
              FieldRow("Actions") {
                HStack(spacing: 8) {
                  Button("Clear Key") {
                    Task { try? await store.clearKimiAPIKey() }
                  }
                  .tokMonGlassButton()
                  .disabled(!store.draft.kimiCodeAPIKeyConfigured)
                }
              }
            }
```

- [ ] **Step 3: 编译验证**

Run: `cd /Users/orange/Desktop/Project/TokMon/macos-app && swift build`
Expected: PASS

- [ ] **Step 4: 提交**

```bash
git add macos-app/Sources/TokMonApp/TokMonSettingsWindow.swift macos-app/Sources/TokMonApp/TokMonSettingsStore.swift
git commit -m "Add Kimi API key and refresh interval to settings window"
```

---

## Task 6: Popover 页面与 Overview 迷你卡片

**Files:**
- Create: `macos-app/Sources/TokMonApp/TokMonQuotaView.swift`
- Create: `macos-app/Sources/TokMonApp/TokMonQuotaMiniCard.swift`
- Modify: `macos-app/Sources/TokMonApp/StatusPopoverView.swift`
- Modify: `macos-app/Sources/TokMonApp/TokMonStatsStore.swift`

- [ ] **Step 1: TokMonStatsStore 增加 quota 状态与轮询**

在 `TokMonStatsStore` 中，于 `@Published private(set) var errorMessage: String?` 之后添加：

```swift
  @Published private(set) var kimiQuotaSnapshot: KimiQuotaSnapshot?
```

在 `private var isPopoverVisible = false` 之后添加：

```swift
  private var quotaRefreshTask: Task<Void, Never>?
```

在 `popoverDidAppear()` 中 `requestRefresh()` 之后添加：

```swift
    startQuotaRefreshTask()
```

在 `popoverDidDisappear()` 末尾添加：

```swift
    stopQuotaRefreshTask()
```

在 `TokMonStatsStore` 末尾新增方法：

```swift
  func refreshKimiQuota() async {
    guard let nativeEngineActor else { return }
    kimiQuotaSnapshot = await nativeEngineActor.refreshKimiQuota()
  }

  private func startQuotaRefreshTask() {
    stopQuotaRefreshTask()
    guard isPopoverVisible, let nativeEngineActor else { return }

    quotaRefreshTask = Task { [weak self] in
      await self?.refreshKimiQuota()
      while !Task.isCancelled {
        let interval = (try? await nativeEngineActor.loadKimiQuotaRefreshInterval()) ?? 5
        guard interval > 0 else { break }
        try? await Task.sleep(for: .seconds(interval * 60))
        guard !Task.isCancelled else { break }
        await self?.refreshKimiQuota()
      }
    }
  }

  private func stopQuotaRefreshTask() {
    quotaRefreshTask?.cancel()
    quotaRefreshTask = nil
  }
```

- [ ] **Step 2: TokMonQuotaView.swift**

```swift
import SwiftUI

struct TokMonQuotaView: View {
  let snapshot: KimiQuotaSnapshot?
  let onRefresh: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Kimi Quota")
          .font(.system(size: 13, weight: .heavy, design: .rounded))
        Spacer()
        Button(action: onRefresh) {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.plain)
      }

      if let error = snapshot?.error {
        errorView(error)
      }

      if let weekly = snapshot?.weekly {
        quotaCard(title: "Weekly", window: weekly)
      }

      if let fiveHour = snapshot?.fiveHour {
        quotaCard(title: "5-Hour", window: fiveHour)
      }

      if snapshot?.weekly == nil && snapshot?.fiveHour == nil {
        Text("No quota data available.")
          .font(.system(size: 12, weight: .medium, design: .rounded))
          .foregroundStyle(.secondary)
      }

      if let fetchedAt = snapshot?.fetchedAt {
        Text("Updated \(fetchedAt.formatted(date: .omitted, time: .shortened))")
          .font(.system(size: 10, weight: .medium, design: .rounded))
          .foregroundStyle(.secondary)
      }
    }
    .padding(9)
    .hudCard()
  }

  private func quotaCard(title: String, window: KimiQuotaWindow) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(title)
          .font(.system(size: 12, weight: .semibold, design: .rounded))
        Spacer()
        Text("\(Int(window.percentUsed))%")
          .font(.system(size: 12, weight: .heavy, design: .rounded))
          .foregroundStyle(color(for: window.percentUsed))
      }
      GeometryReader { geo in
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(.quaternary)
          .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
              .fill(color(for: window.percentUsed))
              .frame(width: geo.size.width * min(window.percentUsed / 100, 1))
          }
      }
      .frame(height: 6)
      HStack {
        Text("\(Int(window.used)) / \(Int(window.limit))")
          .font(.system(size: 11, weight: .medium, design: .rounded))
          .foregroundStyle(.secondary)
        Spacer()
        if let countdown = window.countdown {
          Text("Resets in \(countdown)")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private func errorView(_ error: KimiQuotaError) -> some View {
    let message: String = switch error {
    case .noAPIKey:
      "Add your Kimi Code API key in Settings."
    case .invalidKey:
      "Invalid API key. Make sure it is a Kimi Code key (sk-kimi-xxx)."
    case .endpointNotFound:
      "Kimi quota endpoint not found. The API may have changed."
    case .rateLimited:
      "Rate limited. Please retry later."
    case .network, .decoding:
      "Could not load quota. Check your network."
    }
    return Text(message)
      .font(.system(size: 12, weight: .semibold, design: .rounded))
      .foregroundStyle(TokMonGlass.danger)
      .lineLimit(2)
  }

  private func color(for percent: Double) -> Color {
    if percent >= 95 { return TokMonGlass.danger }
    if percent >= 80 { return .orange }
    return TokMonGlass.accent
  }
}
```

- [ ] **Step 3: TokMonQuotaMiniCard.swift**

```swift
import SwiftUI

struct TokMonQuotaMiniCard: View {
  let snapshot: KimiQuotaSnapshot?
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("Kimi Quota")
            .font(.system(size: 12, weight: .heavy, design: .rounded))
          Spacer()
          Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
        }

        if let error = snapshot?.error, snapshot?.weekly == nil && snapshot?.fiveHour == nil {
          Text(errorLabel(error))
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(TokMonGlass.danger)
        } else {
          row(label: "Week", window: snapshot?.weekly)
          row(label: "5h", window: snapshot?.fiveHour)
        }
      }
      .padding(9)
      .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    .buttonStyle(.plain)
    .hudCard()
  }

  private func row(label: String, window: KimiQuotaWindow?) -> some View {
    HStack(spacing: 8) {
      Text(label)
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(.secondary)
        .frame(width: 32, alignment: .leading)
      GeometryReader { geo in
        RoundedRectangle(cornerRadius: 3, style: .continuous)
          .fill(.quaternary)
          .overlay(alignment: .leading) {
            if let window {
              RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color(for: window.percentUsed))
                .frame(width: geo.size.width * min(window.percentUsed / 100, 1))
            }
          }
      }
      .frame(height: 5)
      Text(window.map { "\(Int($0.percentUsed))%" } ?? "—")
        .font(.system(size: 11, weight: .heavy, design: .rounded))
        .foregroundStyle(window.map { color(for: $0.percentUsed) } ?? .secondary)
        .frame(width: 34, alignment: .trailing)
    }
  }

  private func errorLabel(_ error: KimiQuotaError) -> String {
    switch error {
    case .noAPIKey:
      return "+ Kimi Key"
    default:
      return "Quota unavailable"
    }
  }

  private func color(for percent: Double) -> Color {
    if percent >= 95 { return TokMonGlass.danger }
    if percent >= 80 { return .orange }
    return TokMonGlass.accent
  }
}
```

- [ ] **Step 4: StatusPopoverView 接入 Quota 页面与迷你卡片**

将 `TokMonPopoverPage` 改为：

```swift
private enum TokMonPopoverPage: String, CaseIterable, Identifiable {
  case overview
  case requests
  case sessions
  case quota

  var id: String { rawValue }

  var title: String {
    switch self {
    case .overview:
      "Tokens"
    case .requests:
      "Requests"
    case .sessions:
      "Sessions"
    case .quota:
      "Quota"
    }
  }
}
```

在 `currentPage` 的 switch 中增加：

```swift
    case .quota:
      quotaPage
```

在 `overviewPage` 的 `TokMonHudMetricGrid(...)` 之后、`TokMonHudTrendCard(...)` 之前插入：

```swift
      TokMonQuotaMiniCard(snapshot: stats.kimiQuotaSnapshot) {
        withAnimation(TokMonMotion.softSnappySpring) {
          selectedPage = .quota
        }
      }
```

在 `StatusPopoverView` 中新增 `quotaPage`：

```swift
  private var quotaPage: some View {
    TokMonQuotaView(snapshot: stats.kimiQuotaSnapshot) {
      Task { await stats.refreshKimiQuota() }
    }
    .padding(9)
    .font(.system(size: 12, weight: .regular, design: .rounded))
  }
```

- [ ] **Step 5: 编译与测试**

Run: `cd /Users/orange/Desktop/Project/TokMon/macos-app && swift test`
Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add macos-app/Sources/TokMonApp/TokMonStatsStore.swift macos-app/Sources/TokMonApp/StatusPopoverView.swift macos-app/Sources/TokMonApp/TokMonQuotaView.swift macos-app/Sources/TokMonApp/TokMonQuotaMiniCard.swift
git commit -m "Add Kimi quota popover page and overview mini card"
```

---

## Task 7: 集成验证与收尾

**Files:**
- 项目整体

- [ ] **Step 1: 静态检查**

Run: `cd /Users/orange/Desktop/Project/TokMon && git diff --check`
Expected: 无空白错误

- [ ] **Step 2: 全量测试**

Run: `cd /Users/orange/Desktop/Project/TokMon/macos-app && swift test`
Expected: PASS

- [ ] **Step 3: 编译验证**

Run: `cd /Users/orange/Desktop/Project/TokMon/macos-app && swift build`
Expected: PASS

- [ ] **Step 4: 打包并手动验证**

Run:

```bash
cd /Users/orange/Desktop/Project/TokMon
bash macos-app/scripts/build-app.sh
```

手动步骤：
1. 启动 `macos-app/release/TokMon.app`。
2. 打开设置，输入真实 `sk-kimi-xxx` key，选择刷新间隔 1 min，保存。
3. 点击状态栏图标，确认 Overview 出现迷你 Quota 卡片。
4. 点击 Quota 页面，确认 Weekly / 5-Hour 数据与 `kimi-usage --json` 一致。
5. 点击刷新按钮，确认数据更新。
6. 在设置中清除 key，确认 Quota 页面提示 "Add your Kimi Code API key in Settings"。

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "Integrate Kimi API quota panel"
```

---

## Self-Review

### Spec coverage

| 设计文档要求 | 对应任务 |
|---|---|
| 周额度、5 小时额度展示 | Task 3（解析）、Task 6（UI） |
| 剩余比例、已用/上限、倒计时 | Task 3（`makeWindow`）、Task 6（视图） |
| Overview 迷你卡片 | Task 6 |
| Keychain 存储 API Key | Task 2 |
| 设置页输入与刷新间隔 | Task 5 |
| 可配置刷新间隔 | Task 1、Task 4、Task 5 |
| 错误处理 | Task 3、Task 6 |
| 测试 | Task 2、Task 3、Task 4、Task 7 |

### Placeholder scan

已检查：无 `TBD`、`TODO`、`implement later`、未给出的测试代码或模糊描述。所有新增文件均给出完整代码，修改点给出具体文件与插入位置。

### Type consistency

- 模型：`KimiQuotaWindow`、`KimiQuotaSnapshot`、`KimiQuotaError` 在所有任务中名称一致。
- UIState/draft 字段：`kimiQuotaRefreshInterval`、`kimiCodeAPIKey`、`kimiCodeAPIKeyConfigured` 命名一致。
- 方法：`refreshKimiQuota()`、`deleteKimiAPIKey()`、`loadKimiQuotaRefreshInterval()` 在 Actor 与 Store 中命名一致。
