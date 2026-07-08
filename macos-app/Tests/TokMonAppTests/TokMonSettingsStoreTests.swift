import Foundation
import Testing
@testable import TokMonApp

@MainActor
@Test func settingsStoreLoadsAndSavesTokMonConfiguration() async throws {
  let dataDir = try makeTokMonTempDir()
  let configStore = TokMonConfigStore(dataDir: dataDir)
  try configStore.saveConfig(TokMonConfig(
    port: 3399,
    sources: [
      "claude-code": TokMonSourceConfig(path: "~/old-claude"),
      "codex": TokMonSourceConfig(path: "~/old-codex"),
      "qwen-code": TokMonSourceConfig(path: "~/old-qwen"),
      "future-source": TokMonSourceConfig(path: "~/future"),
    ],
  ))
  let database = try TokMonDatabase(appDataDir: dataDir)
  let engine = TokMonEngine(configStore: configStore, database: database)
  let store = TokMonSettingsStore(engine: engine)

  try await store.load()
  store.draft.claudePath = "~/custom-claude"
  store.draft.codexPath = "~/custom-codex"
  store.draft.kimiCodePath = "~/custom-kimi"
  store.draft.openCodePath = "~/custom-opencode"
  store.draft.qwenCodePath = "~/custom-qwen"
  store.draft.source = "codex"
  store.draft.rangeLabel = "today"
  store.draft.liveMode = false
  store.draft.interval = "hour"
  store.draft.activeSeries = "cost"
  store.draft.menuBarDisplayItems.requests = true
  store.draft.refreshRate = 5000
  store.draft.inputRate = 3
  store.draft.outputRate = 4
  store.draft.cacheCreateRate = 5
  store.draft.cacheReadRate = 6
  store.draft.modelPricing = [
    "gpt-a": TokMonCostRates(input: 1, output: 2, cacheCreate: 3, cacheRead: 4),
    "gpt-b": TokMonCostRates(input: -1, output: 5, cacheCreate: -2, cacheRead: 6),
  ]

  try await store.save()

  let config = try configStore.loadConfig()
  let uiState = try configStore.loadUIState()
  #expect(config.port == 3399)
  #expect(config.sources["claude-code"]?.path == "~/custom-claude")
  #expect(config.sources["codex"]?.path == "~/custom-codex")
  #expect(config.sources["kimi-code"]?.path == "~/custom-kimi")
  #expect(config.sources["opencode"]?.path == "~/custom-opencode")
  #expect(config.sources["qwen-code"]?.path == "~/custom-qwen")
  #expect(config.sources["future-source"]?.path == "~/future")
  #expect(uiState.source == "codex")
  #expect(uiState.rangeLabel == "today")
  #expect(uiState.rangeHours == nil)
  #expect(uiState.rangeDays == nil)
  #expect(uiState.liveMode)
  #expect(uiState.rangeMode == "round")
  #expect(uiState.interval == "hour")
  #expect(uiState.activeSeries == "cost")
  #expect(uiState.menuBarDisplayItems.requests)
  #expect(uiState.refreshRate == 5000)
  #expect(uiState.costRates == TokMonCostRates(input: 3, output: 4, cacheCreate: 5, cacheRead: 6))
  #expect(uiState.modelPricing["gpt-a"] == TokMonCostRates(input: 1, output: 2, cacheCreate: 3, cacheRead: 4))
  #expect(uiState.modelPricing["gpt-b"] == TokMonCostRates(input: 0, output: 5, cacheCreate: 0, cacheRead: 6))
  #expect(store.statusMessage == "Settings saved.")
}

@MainActor
@Test func settingsStoreLoadsAvailableModelsAndPerModelPricing() async throws {
  let dataDir = try makeTokMonTempDir()
  let configStore = TokMonConfigStore(dataDir: dataDir)
  try configStore.saveUIState(TokMonUIState(
    source: "",
    from: "",
    to: "",
    rangeLabel: "thisWeek",
    rangeHours: nil,
    rangeDays: nil,
    liveMode: true,
    rangeMode: "round",
    interval: "day",
    activeSeries: "total",
    refreshRate: 3000,
    costRates: .zero,
    modelPricing: [
      "gpt-a": TokMonCostRates(input: 1, output: 2, cacheCreate: 3, cacheRead: 4),
    ],
  ))
  let database = try TokMonDatabase(appDataDir: dataDir)
  _ = try database.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "s1", model: "gpt-b", inputTokens: 1, outputTokens: 1, cacheCreation: 0, cacheRead: 0, reasoningTokens: 0, createdAt: "2026-05-14T01:00:00.000Z"))
  _ = try database.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "s2", model: "gpt-a", inputTokens: 1, outputTokens: 1, cacheCreation: 0, cacheRead: 0, reasoningTokens: 0, createdAt: "2026-05-13T01:00:00.000Z"))
  let engine = TokMonEngine(configStore: configStore, database: database)
  let store = TokMonSettingsStore(engine: engine)

  try await store.load()

  #expect(store.draft.modelPricing["gpt-a"] == TokMonCostRates(input: 1, output: 2, cacheCreate: 3, cacheRead: 4))
  #expect(store.draft.availableModels.map(\.model) == ["gpt-b", "gpt-a"])
}

@MainActor
@Test func settingsStoreRebuildsAndRescansTokMonData() async throws {
  let dataDir = try makeTokMonTempDir()
  let configStore = TokMonConfigStore(dataDir: dataDir)
  let claudeRoot = dataDir.appendingPathComponent("claude", isDirectory: true)
  let sourceRoot = dataDir.appendingPathComponent("codex", isDirectory: true)
  let kimiCodeRoot = dataDir.appendingPathComponent("kimi", isDirectory: true)
  let openCodeRoot = dataDir.appendingPathComponent("opencode", isDirectory: true)
  let qwenCodeRoot = dataDir.appendingPathComponent("qwen", isDirectory: true)
  try FileManager.default.createDirectory(at: claudeRoot, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: kimiCodeRoot, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: openCodeRoot, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: qwenCodeRoot, withIntermediateDirectories: true)
  try """
  {"type":"session_meta","payload":{"id":"s1","model":"gpt-test"}}
  {"type":"event_msg","timestamp":"2026-05-14T01:00:00.000Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":10,"output_tokens":2}}}}
  """.write(to: sourceRoot.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)
  try configStore.saveConfig(TokMonConfig(
    port: 3388,
    sources: [
      "claude-code": TokMonSourceConfig(path: claudeRoot.path),
      "codex": TokMonSourceConfig(path: sourceRoot.path),
      "kimi-code": TokMonSourceConfig(path: kimiCodeRoot.path),
      "opencode": TokMonSourceConfig(path: openCodeRoot.path),
      "qwen-code": TokMonSourceConfig(path: qwenCodeRoot.path),
    ],
  ))
  let database = try TokMonDatabase(appDataDir: dataDir)
  _ = try database.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "old", model: "old", inputTokens: 1, outputTokens: 1, cacheCreation: 0, cacheRead: 0, reasoningTokens: 0, createdAt: "2026-05-13T01:00:00.000Z"))
  let engine = TokMonEngine(configStore: configStore, database: database)
  let store = TokMonSettingsStore(engine: engine)

  try await store.rebuildAndRescan()

  let records = try database.allUsageRecords()
  #expect(records.count == 1)
  #expect(records.first?.sessionId == "s1")
  #expect(records.first?.inputTokens == 10)
  #expect(store.statusMessage == "Rebuilt database and scanned 1 record.")
}

@MainActor
@Test func settingsStoreKeepsCalendarRangeWhenSavingUnownedFields() async throws {
  let dataDir = try makeTokMonTempDir()
  let configStore = TokMonConfigStore(dataDir: dataDir)
  try configStore.saveUIState(TokMonUIState(
    source: "",
    from: "2026-05-01 00:00:00",
    to: "2026-05-02 23:59:59",
    rangeLabel: "thisMonth",
    rangeHours: nil,
    rangeDays: nil,
    liveMode: true,
    rangeMode: "round",
    interval: "day",
    activeSeries: "total",
    refreshRate: 3000,
    costRates: .zero,
  ))
  let engine = TokMonEngine(configStore: configStore, database: try TokMonDatabase(appDataDir: dataDir))
  let store = TokMonSettingsStore(engine: engine)

  try await store.load()
  store.draft.refreshRate = 4000
  try await store.save()

  let state = try configStore.loadUIState()
  #expect(state.rangeLabel == "thisMonth")
  #expect(state.liveMode)
  #expect(state.rangeMode == "round")
  #expect(state.refreshRate == 4000)
}

@MainActor
@Test func settingsStoreDoesNotClearDatabaseWhenRebuildSourcePathsAreMissing() async throws {
  let dataDir = try makeTokMonTempDir()
  let configStore = TokMonConfigStore(dataDir: dataDir)
  try configStore.saveConfig(TokMonConfig(
    port: 3388,
    sources: [
      "claude-code": TokMonSourceConfig(path: dataDir.appendingPathComponent("missing-claude").path),
      "codex": TokMonSourceConfig(path: dataDir.appendingPathComponent("missing-codex").path),
    ],
  ))
  let database = try TokMonDatabase(appDataDir: dataDir)
  _ = try database.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "existing", model: "gpt", inputTokens: 1, outputTokens: 1, cacheCreation: 0, cacheRead: 0, reasoningTokens: 0, createdAt: "2026-05-13T01:00:00.000Z"))
  let engine = TokMonEngine(configStore: configStore, database: database)
  let store = TokMonSettingsStore(engine: engine)

  do {
    try await store.rebuildAndRescan()
    Issue.record("Expected rebuild to fail before clearing data.")
  } catch {}

  #expect(try database.allUsageRecords().map(\.sessionId) == ["existing"])
}

@MainActor
@Test func settingsStoreDoesNotClearDatabaseWhenAnyConfiguredSourcePathIsMissing() async throws {
  let dataDir = try makeTokMonTempDir()
  let configStore = TokMonConfigStore(dataDir: dataDir)
  let codexDir = dataDir.appendingPathComponent("codex", isDirectory: true)
  try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
  try """
  {"type":"session_meta","payload":{"id":"s1","model":"gpt-test"}}
  {"type":"event_msg","timestamp":"2026-05-14T01:00:00.000Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":10,"output_tokens":2}}}}
  """.write(to: codexDir.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)
  try configStore.saveConfig(TokMonConfig(
    port: 3388,
    sources: [
      "claude-code": TokMonSourceConfig(path: dataDir.appendingPathComponent("missing-claude").path),
      "codex": TokMonSourceConfig(path: codexDir.path),
    ],
  ))
  let database = try TokMonDatabase(appDataDir: dataDir)
  _ = try database.insertUsage(TokMonUsageRecord(source: "claude-code", sessionId: "existing", model: "claude", inputTokens: 1, outputTokens: 1, cacheCreation: 0, cacheRead: 0, reasoningTokens: 0, createdAt: "2026-05-13T01:00:00.000Z"))
  let engine = TokMonEngine(configStore: configStore, database: database)
  let store = TokMonSettingsStore(engine: engine)

  do {
    try await store.rebuildAndRescan()
    Issue.record("Expected rebuild to fail when any configured source path is missing.")
  } catch {}

  #expect(try database.allUsageRecords().map(\.sessionId) == ["existing"])
}

@Suite struct TokMonSettingsStoreQuotaTests {
  @Test func settingsDraftPreservesKimiQuotaInterval() async throws {
    let dataDir = try makeTokMonTempDir()
    let configStore = TokMonConfigStore(dataDir: dataDir)
    let database = try TokMonDatabase(appDataDir: dataDir)
    let engine = TokMonEngine(configStore: configStore, database: database)
    let actor = TokMonEngineActor(engine: engine)

    var draft = try await actor.loadSettingsDraft()
    draft.kimiQuotaRefreshInterval = 15
    try await actor.saveSettings(draft: draft)

    let reloaded = try await actor.loadSettingsDraft()
    #expect(reloaded.kimiQuotaRefreshInterval == 15)
  }

  @Test func engineActorAddsAndRemovesKimiAPIKeys() async throws {
    let dataDir = try makeTokMonTempDir()
    let configStore = TokMonConfigStore(dataDir: dataDir)
    let database = try TokMonDatabase(appDataDir: dataDir)
    let engine = TokMonEngine(configStore: configStore, database: database)
    let actor = TokMonEngineActor(engine: engine)

    let account = try await actor.addKimiAPIKey("sk-kimi-test-add", label: "Test Key")
    defer {
      Task { try? await actor.removeKimiAPIKey(id: account.id) }
    }

    let accounts = try await actor.loadKimiAPIKeyAccounts()
    #expect(accounts.contains(where: { $0.id == account.id && $0.label == "Test Key" }))

    let state = try configStore.loadUIState()
    #expect(state.selectedKimiAPIKeyID == account.id)

    try await actor.removeKimiAPIKey(id: account.id)
    let remaining = try await actor.loadKimiAPIKeyAccounts()
    #expect(!remaining.contains(where: { $0.id == account.id }))
    #expect(try configStore.loadUIState().selectedKimiAPIKeyID == nil)
  }

  @Test func engineActorRejectsInvalidKimiAPIKey() async throws {
    let dataDir = try makeTokMonTempDir()
    let database = try TokMonDatabase(appDataDir: dataDir)
    let engine = TokMonEngine(configStore: TokMonConfigStore(dataDir: dataDir), database: database)
    let actor = TokMonEngineActor(engine: engine)

    await #expect(throws: KimiQuotaError.invalidKey) {
      try await actor.addKimiAPIKey("not-a-kimi-key", label: "Bad")
    }
  }
}
