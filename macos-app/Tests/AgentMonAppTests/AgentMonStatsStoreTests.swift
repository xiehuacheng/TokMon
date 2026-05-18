import Foundation
import Testing
@testable import AgentMonApp

@MainActor
@Test func statsStoreRefreshesFromNativeTokMonEngine() async throws {
  let dataDir = try makeTokMonTempDir()
  let configStore = TokMonConfigStore(dataDir: dataDir)
  try configStore.saveConfig(emptyTokMonConfig(dataDir: dataDir))
  try configStore.saveUIState(TokMonUIState(
    source: "codex",
    from: "",
    to: "",
    rangeLabel: "24H",
    rangeHours: 24,
    rangeDays: nil,
    liveMode: true,
    rangeMode: "exact",
    interval: "hour",
    activeSeries: "input",
    refreshRate: 4000,
    costRates: TokMonCostRates(input: 1, output: 2, cacheCreate: 3, cacheRead: 4),
  ))

  let database = try TokMonDatabase(appDataDir: dataDir)
  _ = try database.insertUsage(TokMonUsageRecord(
    source: "codex",
    sessionId: "session-1",
    model: "gpt-test",
    inputTokens: 20,
    outputTokens: 5,
    cacheCreation: 0,
    cacheRead: 2,
    reasoningTokens: 1,
    createdAt: "2026-05-14T01:10:00.000Z",
  ))
  let engine = TokMonEngine(configStore: configStore, database: database)
  let store = AgentMonStatsStore(
    engine: engine,
    nowProvider: { makeLocalDate("2026-05-14 10:05:30") },
  )

  await store.refresh()

  #expect(store.errorMessage == nil)
  #expect(store.snapshot.scanStatus?.processed == 0)
  #expect(store.snapshot.dashboardState?.source == "codex")
  #expect(store.snapshot.dashboardState?.from == "2026-05-13 10:05:00")
  #expect(store.snapshot.dashboardState?.to == "2026-05-14 10:05:59")
  #expect(store.snapshot.summary?.total.totalRequests == 1)
  #expect(store.snapshot.summary?.total.totalInput == 20)
  #expect(store.snapshot.trendBuckets.contains { $0.bucket == "2026-05-14 09:00" && $0.requests == 1 })
  #expect(store.snapshot.heatmapDays.contains { $0.day == "2026-05-14" && $0.requests == 1 })
  #expect(store.snapshot.recordsPage?.total == 1)
  #expect(store.snapshot.recordsPage?.rows.first?.sessionId == "session-1")
  #expect(store.snapshot.usageSessions.first?.sessionId == "session-1")
  #expect(store.snapshot.usageSessions.first?.cacheRead == 2)
}

@MainActor
@Test func statsStoreReportsNativeEngineModeWhenInjected() throws {
  let dataDir = try makeTokMonTempDir()
  let engine = TokMonEngine(
    configStore: TokMonConfigStore(dataDir: dataDir),
    database: try TokMonDatabase(appDataDir: dataDir),
  )

  let nativeStore = AgentMonStatsStore(engine: engine)
  let httpFallbackStore = AgentMonStatsStore()

  #expect(nativeStore.usesNativeEngine)
  #expect(!httpFallbackStore.usesNativeEngine)
}

@MainActor
@Test func statsStoreLoadsSelectedUsageSessionRecords() async throws {
  let dataDir = try makeTokMonTempDir()
  let configStore = TokMonConfigStore(dataDir: dataDir)
  try configStore.saveConfig(emptyTokMonConfig(dataDir: dataDir))
  try configStore.saveUIState(TokMonUIState(
    source: "codex",
    from: "",
    to: "",
    rangeLabel: "24H",
    rangeHours: 24,
    rangeDays: nil,
    liveMode: true,
    rangeMode: "exact",
    interval: "hour",
    activeSeries: "total",
    refreshRate: 3000,
    costRates: .zero,
  ))
  let database = try TokMonDatabase(appDataDir: dataDir)
  _ = try database.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "session-1", model: "gpt-test", inputTokens: 20, outputTokens: 5, cacheCreation: 0, cacheRead: 2, reasoningTokens: 1, createdAt: "2026-05-14T01:10:00.000Z"))
  _ = try database.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "session-2", model: "gpt-test", inputTokens: 99, outputTokens: 9, cacheCreation: 0, cacheRead: 0, reasoningTokens: 0, createdAt: "2026-05-14T01:15:00.000Z"))
  let engine = TokMonEngine(configStore: configStore, database: database)
  let store = AgentMonStatsStore(
    engine: engine,
    nowProvider: { makeLocalDate("2026-05-14 10:05:30") },
  )

  store.selectUsageSession(source: "codex", sessionId: "session-1")
  await store.refresh()

  #expect(store.snapshot.selectedUsageSession?.sessionId == "session-1")
  #expect(store.snapshot.selectedSessionRecords.map(\.sessionId) == ["session-1"])
  #expect(store.snapshot.selectedSessionRecords.first?.reasoningTokens == 1)
}

@MainActor
@Test func statsStoreHonorsRoundDayRangeFromNativeUIState() async throws {
  let dataDir = try makeTokMonTempDir()
  let configStore = TokMonConfigStore(dataDir: dataDir)
  try configStore.saveConfig(emptyTokMonConfig(dataDir: dataDir))
  try configStore.saveUIState(TokMonUIState(
    source: "",
    from: "",
    to: "",
    rangeLabel: "7D",
    rangeHours: nil,
    rangeDays: 7,
    liveMode: true,
    rangeMode: "round",
    interval: "day",
    activeSeries: "total",
    refreshRate: 3000,
    costRates: .zero,
  ))
  let engine = TokMonEngine(configStore: configStore, database: try TokMonDatabase(appDataDir: dataDir))
  let store = AgentMonStatsStore(
    engine: engine,
    nowProvider: { makeLocalDate("2026-05-14 10:05:30") },
  )

  await store.refresh()

  #expect(store.snapshot.dashboardState?.from == "2026-05-08 00:00:00")
  #expect(store.snapshot.dashboardState?.to == "2026-05-14 10:05:59")
}

@MainActor
@Test func statsStoreUsesFixedRangeFromNativeUIState() async throws {
  let dataDir = try makeTokMonTempDir()
  let configStore = TokMonConfigStore(dataDir: dataDir)
  try configStore.saveConfig(emptyTokMonConfig(dataDir: dataDir))
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
  let store = AgentMonStatsStore(engine: engine)

  await store.refresh()

  #expect(store.snapshot.dashboardState?.from == "2026-05-01 00:00:00")
  #expect(store.snapshot.dashboardState?.to == "2026-05-02 23:59:59")
}


private func emptyTokMonConfig(dataDir: URL) throws -> TokMonConfig {
  let claudeDir = dataDir.appendingPathComponent("claude-projects", isDirectory: true)
  let codexDir = dataDir.appendingPathComponent("codex-sessions", isDirectory: true)
  try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
  return TokMonConfig(
    port: 3388,
    sources: [
      "claude-code": TokMonSourceConfig(path: claudeDir.path),
      "codex": TokMonSourceConfig(path: codexDir.path),
    ],
  )
}
