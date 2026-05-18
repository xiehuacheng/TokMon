import Foundation
import Testing
@testable import AgentMonApp

@MainActor
@Test func settingsStoreLoadsAndSavesTokMonConfiguration() async throws {
  let dataDir = try makeTokMonTempDir()
  let configStore = TokMonConfigStore(dataDir: dataDir)
  try configStore.saveConfig(TokMonConfig(
    port: 3399,
    sources: [
      "claude-code": TokMonSourceConfig(path: "~/old-claude"),
      "codex": TokMonSourceConfig(path: "~/old-codex"),
      "future-source": TokMonSourceConfig(path: "~/future"),
    ],
  ))
  let database = try TokMonDatabase(appDataDir: dataDir)
  let engine = TokMonEngine(configStore: configStore, database: database)
  let store = TokMonSettingsStore(engine: engine)

  try await store.load()
  store.draft.claudePath = "~/custom-claude"
  store.draft.codexPath = "~/custom-codex"
  store.draft.source = "codex"
  store.draft.rangeLabel = "24H"
  store.draft.liveMode = false
  store.draft.rangeMode = "round"
  store.draft.interval = "hour"
  store.draft.activeSeries = "cost"
  store.draft.refreshRate = 5000
  store.draft.inputRate = 3
  store.draft.outputRate = 4
  store.draft.cacheCreateRate = 5
  store.draft.cacheReadRate = 6

  try await store.save()

  let config = try configStore.loadConfig()
  let uiState = try configStore.loadUIState()
  #expect(config.port == 3399)
  #expect(config.sources["claude-code"]?.path == "~/custom-claude")
  #expect(config.sources["codex"]?.path == "~/custom-codex")
  #expect(config.sources["future-source"]?.path == "~/future")
  #expect(uiState.source == "codex")
  #expect(uiState.rangeLabel == "24H")
  #expect(uiState.rangeHours == 24)
  #expect(uiState.rangeDays == nil)
  #expect(uiState.liveMode == false)
  #expect(uiState.rangeMode == "round")
  #expect(uiState.interval == "hour")
  #expect(uiState.activeSeries == "cost")
  #expect(uiState.refreshRate == 5000)
  #expect(uiState.costRates == TokMonCostRates(input: 3, output: 4, cacheCreate: 5, cacheRead: 6))
  #expect(store.statusMessage == "Settings saved.")
}

@MainActor
@Test func settingsStoreRebuildsAndRescansTokMonData() async throws {
  let dataDir = try makeTokMonTempDir()
  let configStore = TokMonConfigStore(dataDir: dataDir)
  let claudeRoot = dataDir.appendingPathComponent("claude", isDirectory: true)
  let sourceRoot = dataDir.appendingPathComponent("codex", isDirectory: true)
  try FileManager.default.createDirectory(at: claudeRoot, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
  try """
  {"type":"session_meta","payload":{"id":"s1","model":"gpt-test"}}
  {"type":"event_msg","timestamp":"2026-05-14T01:00:00.000Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":10,"output_tokens":2}}}}
  """.write(to: sourceRoot.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)
  try configStore.saveConfig(TokMonConfig(
    port: 3388,
    sources: [
      "claude-code": TokMonSourceConfig(path: claudeRoot.path),
      "codex": TokMonSourceConfig(path: sourceRoot.path),
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
@Test func settingsStorePreservesFixedRangeWhenSavingUnownedFields() async throws {
  let dataDir = try makeTokMonTempDir()
  let configStore = TokMonConfigStore(dataDir: dataDir)
  try configStore.saveUIState(TokMonUIState(
    source: "",
    from: "2026-05-01 00:00:00",
    to: "2026-05-02 23:59:59",
    rangeLabel: nil,
    rangeHours: nil,
    rangeDays: nil,
    liveMode: false,
    rangeMode: "exact",
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
  #expect(state.from == "2026-05-01 00:00:00")
  #expect(state.to == "2026-05-02 23:59:59")
  #expect(state.liveMode == false)
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
@Test func settingsStoreRunsLegacyParityCheck() async throws {
  let dataDir = try makeTokMonTempDir()
  let configStore = TokMonConfigStore(dataDir: dataDir)
  try configStore.saveUIState(TokMonUIState(
    source: "codex",
    from: "2026-05-14 08:00:00",
    to: "2026-05-14 10:00:00",
    rangeLabel: nil,
    rangeHours: nil,
    rangeDays: nil,
    liveMode: false,
    rangeMode: "exact",
    interval: "hour",
    activeSeries: "total",
    refreshRate: 3000,
    costRates: .zero,
  ))
  let database = try TokMonDatabase(appDataDir: dataDir)
  try createLegacySessionsTable(in: database)
  let engine = TokMonEngine(configStore: configStore, database: database)
  let store = TokMonSettingsStore(engine: engine)

  try await store.runParityCheck(now: makeLocalDate("2026-05-14 10:05:30"))

  #expect(store.parityReport?.passed == true)
  #expect(store.statusMessage == "Legacy parity passed.")
}

@MainActor
@Test func settingsStoreReportsLegacyParityDifferences() async throws {
  let dataDir = try makeTokMonTempDir()
  let configStore = TokMonConfigStore(dataDir: dataDir)
  try configStore.saveUIState(TokMonUIState(
    source: "codex",
    from: "2026-05-14 08:00:00",
    to: "2026-05-14 10:00:00",
    rangeLabel: nil,
    rangeHours: nil,
    rangeDays: nil,
    liveMode: false,
    rangeMode: "exact",
    interval: "hour",
    activeSeries: "total",
    refreshRate: 3000,
    costRates: .zero,
  ))
  let database = try TokMonDatabase(appDataDir: dataDir)
  try createLegacySessionsTable(in: database)
  _ = try database.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "s1", model: "gpt-a", inputTokens: 10, outputTokens: 2, cacheCreation: 1, cacheRead: 0, reasoningTokens: 0, createdAt: "2026-05-14T01:00:00.000Z"))
  _ = try database.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "s1", model: "gpt-b", inputTokens: 20, outputTokens: 3, cacheCreation: 0, cacheRead: 4, reasoningTokens: 0, createdAt: "2026-05-14T01:10:00.000Z"))
  let engine = TokMonEngine(configStore: configStore, database: database)
  let store = TokMonSettingsStore(engine: engine)

  try await store.runParityCheck(now: makeLocalDate("2026-05-14 10:05:30"))

  #expect(store.parityReport?.passed == false)
  #expect(store.parityReport?.differences.contains {
    $0.endpoint == "sessions" && $0.path == "0.model" && $0.native == "Mixed"
  } == true)
  #expect(store.parityReport?.differences.contains {
    $0.endpoint == "sessions" && $0.path == "0.cache_creation" && $0.native == "1" && $0.legacy == "<missing>"
  } == true)
  #expect(store.parityReport?.differences.contains {
    $0.endpoint == "sessions" && $0.path == "0.cache_read" && $0.native == "4" && $0.legacy == "<missing>"
  } == true)
  #expect(store.parityReport?.differences.contains {
    $0.endpoint == "records" && $0.path == "__error"
  } == false)
  #expect(store.statusMessage.hasPrefix("Legacy parity failed with "))
}

@MainActor
@Test func settingsStoreReportsMissingLegacySessionsTableForRecordsParity() async throws {
  let dataDir = try makeTokMonTempDir()
  let configStore = TokMonConfigStore(dataDir: dataDir)
  try configStore.saveUIState(TokMonUIState(
    source: "codex",
    from: "2026-05-14 08:00:00",
    to: "2026-05-14 10:00:00",
    rangeLabel: nil,
    rangeHours: nil,
    rangeDays: nil,
    liveMode: false,
    rangeMode: "exact",
    interval: "hour",
    activeSeries: "total",
    refreshRate: 3000,
    costRates: .zero,
  ))
  let database = try TokMonDatabase(appDataDir: dataDir)
  _ = try database.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "s1", model: "gpt-a", inputTokens: 10, outputTokens: 2, cacheCreation: 0, cacheRead: 0, reasoningTokens: 0, createdAt: "2026-05-14T01:00:00.000Z"))
  let engine = TokMonEngine(configStore: configStore, database: database)
  let store = TokMonSettingsStore(engine: engine)

  try await store.runParityCheck(now: makeLocalDate("2026-05-14 10:05:30"))

  #expect(store.parityReport?.passed == false)
  #expect(store.parityReport?.differences.contains {
    $0.endpoint == "records" && $0.path == "__error" && $0.native == "<missing>"
  } == true)
  #expect(store.statusMessage.hasPrefix("Legacy parity failed with "))
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

private func createLegacySessionsTable(in database: TokMonDatabase) throws {
  _ = try database.queryRows("""
    CREATE TABLE IF NOT EXISTS sessions (
      id TEXT PRIMARY KEY,
      source TEXT NOT NULL,
      file_path TEXT
    )
  """) { _ in () }
}
