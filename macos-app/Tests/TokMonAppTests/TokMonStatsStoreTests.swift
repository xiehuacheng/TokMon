import Foundation
import Testing
@testable import TokMonApp

@MainActor
@Test func statsStoreResetsPaginationAndSelectionOnPopoverDisappear() async throws {
  let dataDir = try makeTokMonTempDir()
  let configStore = TokMonConfigStore(dataDir: dataDir)
  try configStore.saveConfig(emptyTokMonConfig(dataDir: dataDir))
  try configStore.saveUIState(TokMonUIState(
    source: "",
    from: "",
    to: "",
    rangeLabel: "today",
    rangeHours: nil,
    rangeDays: nil,
    liveMode: true,
    rangeMode: "round",
    interval: "hour",
    activeSeries: "total",
    refreshRate: 3000,
    costRates: .zero,
  ))
  let database = try TokMonDatabase(appDataDir: dataDir)
  for index in 0..<30 {
    _ = try database.insertUsage(TokMonUsageRecord(
      source: "codex",
      sessionId: "session-\(index)",
      model: "gpt-test",
      inputTokens: 10,
      outputTokens: 1,
      cacheCreation: 0,
      cacheRead: 0,
      reasoningTokens: 0,
      createdAt: "2026-05-14T01:\(String(format: "%02d", index)):00.000Z",
    ))
  }
  let engine = TokMonEngine(configStore: configStore, database: database)
  let store = TokMonStatsStore(
    engine: engine,
    nowProvider: { makeLocalDate("2026-05-14 10:05:30") },
  )

  store.popoverDidAppear()
  await store.refresh()
  #expect(store.errorMessage == nil)
  #expect(store.snapshot.recordsPage?.rows.count == 20)

  store.loadMoreRecords()
  await store.refresh()
  #expect(store.errorMessage == nil)
  #expect(store.snapshot.recordsPage?.rows.count == 30)

  store.selectUsageSession(source: "codex", sessionId: "session-5")
  await store.refresh()
  #expect(store.errorMessage == nil)
  #expect(store.snapshot.selectedUsageSession?.sessionId == "session-5")

  store.popoverDidDisappear()
  #expect(store.snapshot.selectedUsageSession == nil)
  #expect(store.snapshot.selectedSessionRecords.isEmpty)

  store.popoverDidAppear()
  await store.refresh()
  #expect(store.errorMessage == nil)
  #expect(store.snapshot.recordsPage?.rows.count == 20)
  #expect(store.snapshot.selectedUsageSession == nil)
}

@MainActor
@Test func statsStoreRefreshesFromNativeTokMonEngine() async throws {
  let dataDir = try makeTokMonTempDir()
  let configStore = TokMonConfigStore(dataDir: dataDir)
  try configStore.saveConfig(emptyTokMonConfig(dataDir: dataDir))
  try configStore.saveUIState(TokMonUIState(
    source: "codex",
    from: "",
    to: "",
    rangeLabel: "today",
    rangeHours: nil,
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
  let store = TokMonStatsStore(
    engine: engine,
    nowProvider: { makeLocalDate("2026-05-14 10:05:30") },
  )

  await store.refresh()

  #expect(store.errorMessage == nil)
  #expect(store.snapshot.scanStatus?.processed == 0)
  #expect(store.snapshot.dashboardState?.source == "codex")
  #expect(store.snapshot.dashboardState?.from == "2026-05-14 00:00:00")
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
@Test func statsStoreBuildsPreviousSummaryForTodayComparison() async throws {
  let dataDir = try makeTokMonTempDir()
  let configStore = TokMonConfigStore(dataDir: dataDir)
  try configStore.saveConfig(emptyTokMonConfig(dataDir: dataDir))
  try configStore.saveUIState(TokMonUIState(
    source: "codex",
    from: "",
    to: "",
    rangeLabel: "today",
    rangeHours: nil,
    rangeDays: nil,
    liveMode: true,
    rangeMode: "round",
    interval: "hour",
    activeSeries: "total",
    refreshRate: 3000,
    costRates: .zero,
  ))

  let database = try TokMonDatabase(appDataDir: dataDir)
  _ = try database.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "previous-day", model: "gpt-test", inputTokens: 10, outputTokens: 1, cacheCreation: 0, cacheRead: 0, reasoningTokens: 0, createdAt: "2026-05-13T01:10:00.000Z"))
  _ = try database.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "today-1", model: "gpt-test", inputTokens: 40, outputTokens: 4, cacheCreation: 0, cacheRead: 8, reasoningTokens: 0, createdAt: "2026-05-14T01:10:00.000Z"))
  _ = try database.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "today-2", model: "gpt-test", inputTokens: 20, outputTokens: 2, cacheCreation: 0, cacheRead: 0, reasoningTokens: 0, createdAt: "2026-05-14T01:20:00.000Z"))
  let engine = TokMonEngine(configStore: configStore, database: database)
  let store = TokMonStatsStore(
    engine: engine,
    nowProvider: { makeLocalDate("2026-05-14 10:05:30") },
  )

  await store.refresh()

  #expect(store.snapshot.summary?.total.totalRequests == 2)
  #expect(store.snapshot.summary?.total.totalTokens == 74)
  #expect(store.snapshot.previousSummary?.total.totalRequests == 1)
  #expect(store.snapshot.previousSummary?.total.totalTokens == 11)
}

@MainActor
@Test func statsStoreReportsNativeEngineModeWhenInjected() throws {
  let dataDir = try makeTokMonTempDir()
  let engine = TokMonEngine(
    configStore: TokMonConfigStore(dataDir: dataDir),
    database: try TokMonDatabase(appDataDir: dataDir),
  )

  let nativeStore = TokMonStatsStore(engine: engine)
  let httpFallbackStore = TokMonStatsStore()

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
  let store = TokMonStatsStore(
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
@Test func statsStoreMarksSelectedUsageSessionImmediately() async throws {
  let dataDir = try makeTokMonTempDir()
  let configStore = TokMonConfigStore(dataDir: dataDir)
  try configStore.saveConfig(emptyTokMonConfig(dataDir: dataDir))
  try configStore.saveUIState(TokMonUIState(
    source: "codex",
    from: "",
    to: "",
    rangeLabel: "today",
    rangeHours: nil,
    rangeDays: nil,
    liveMode: true,
    rangeMode: "round",
    interval: "hour",
    activeSeries: "total",
    refreshRate: 3000,
    costRates: .zero,
  ))
  let database = try TokMonDatabase(appDataDir: dataDir)
  _ = try database.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "session-1", model: "gpt-test", inputTokens: 20, outputTokens: 5, cacheCreation: 0, cacheRead: 2, reasoningTokens: 1, createdAt: "2026-05-14T01:10:00.000Z"))
  let engine = TokMonEngine(configStore: configStore, database: database)
  let store = TokMonStatsStore(
    engine: engine,
    nowProvider: { makeLocalDate("2026-05-14 10:05:30") },
  )

  await store.refresh()
  store.selectUsageSession(source: "codex", sessionId: "session-1")

  #expect(store.snapshot.selectedUsageSession?.sessionId == "session-1")
}

@MainActor
@Test func statsStoreRespectsThisWeekRangeFromUIState() async throws {
  let dataDir = try makeTokMonTempDir()
  let configStore = TokMonConfigStore(dataDir: dataDir)
  try configStore.saveConfig(emptyTokMonConfig(dataDir: dataDir))
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
  ))
  let engine = TokMonEngine(configStore: configStore, database: try TokMonDatabase(appDataDir: dataDir))
  let store = TokMonStatsStore(
    engine: engine,
    nowProvider: { makeLocalDate("2026-05-14 10:05:30") },
  )

  await store.refresh()

  #expect(store.snapshot.dashboardState?.from == "2026-05-11 00:00:00")
  #expect(store.snapshot.dashboardState?.to == "2026-05-14 10:05:59")
}

@MainActor
@Test func statsStoreBuildsPreviousSummaryForThisWeekComparison() async throws {
  let dataDir = try makeTokMonTempDir()
  let configStore = TokMonConfigStore(dataDir: dataDir)
  try configStore.saveConfig(emptyTokMonConfig(dataDir: dataDir))
  try configStore.saveUIState(TokMonUIState(
    source: "codex",
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
  ))
  let database = try TokMonDatabase(appDataDir: dataDir)
  _ = try database.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "previous-week", model: "gpt-test", inputTokens: 10, outputTokens: 1, cacheCreation: 0, cacheRead: 0, reasoningTokens: 0, createdAt: "2026-05-05T01:10:00.000Z"))
  _ = try database.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "this-week-1", model: "gpt-test", inputTokens: 20, outputTokens: 2, cacheCreation: 0, cacheRead: 3, reasoningTokens: 0, createdAt: "2026-05-12T01:10:00.000Z"))
  _ = try database.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "this-week-2", model: "gpt-test", inputTokens: 14, outputTokens: 1, cacheCreation: 0, cacheRead: 1, reasoningTokens: 0, createdAt: "2026-05-13T01:10:00.000Z"))
  let engine = TokMonEngine(configStore: configStore, database: database)
  let store = TokMonStatsStore(
    engine: engine,
    nowProvider: { makeLocalDate("2026-05-14 10:05:30") },
  )

  await store.refresh()

  #expect(store.snapshot.summary?.total.totalRequests == 2)
  #expect(store.snapshot.previousSummary?.total.totalRequests == 1)
  #expect(store.snapshot.previousSummary?.total.totalTokens == 11)
}

@MainActor
@Test func statsStoreBuildsPreviousSummaryForThisMonthComparison() async throws {
  let dataDir = try makeTokMonTempDir()
  let configStore = TokMonConfigStore(dataDir: dataDir)
  try configStore.saveConfig(emptyTokMonConfig(dataDir: dataDir))
  try configStore.saveUIState(TokMonUIState(
    source: "codex",
    from: "",
    to: "",
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
  let database = try TokMonDatabase(appDataDir: dataDir)
  _ = try database.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "previous-month", model: "gpt-test", inputTokens: 30, outputTokens: 3, cacheCreation: 0, cacheRead: 4, reasoningTokens: 0, createdAt: "2026-04-13T01:10:00.000Z"))
  _ = try database.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "this-month-1", model: "gpt-test", inputTokens: 40, outputTokens: 4, cacheCreation: 0, cacheRead: 8, reasoningTokens: 0, createdAt: "2026-05-12T01:10:00.000Z"))
  _ = try database.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "this-month-2", model: "gpt-test", inputTokens: 16, outputTokens: 2, cacheCreation: 0, cacheRead: 1, reasoningTokens: 0, createdAt: "2026-05-13T01:10:00.000Z"))
  let engine = TokMonEngine(configStore: configStore, database: database)
  let store = TokMonStatsStore(
    engine: engine,
    nowProvider: { makeLocalDate("2026-05-14 10:05:30") },
  )

  await store.refresh()

  #expect(store.snapshot.summary?.total.totalRequests == 2)
  #expect(store.snapshot.previousSummary?.total.totalRequests == 1)
  #expect(store.snapshot.previousSummary?.total.totalTokens == 37)
}

@MainActor
@Test func statsStoreDoesNotExposePreviousSummaryForAllRange() async throws {
  let dataDir = try makeTokMonTempDir()
  let configStore = TokMonConfigStore(dataDir: dataDir)
  try configStore.saveConfig(emptyTokMonConfig(dataDir: dataDir))
  try configStore.saveUIState(TokMonUIState(
    source: "codex",
    from: "",
    to: "",
    rangeLabel: "all",
    rangeHours: nil,
    rangeDays: nil,
    liveMode: true,
    rangeMode: "round",
    interval: "day",
    activeSeries: "total",
    refreshRate: 3000,
    costRates: .zero,
  ))
  let database = try TokMonDatabase(appDataDir: dataDir)
  _ = try database.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "one", model: "gpt-test", inputTokens: 10, outputTokens: 1, cacheCreation: 0, cacheRead: 0, reasoningTokens: 0, createdAt: "2026-04-13T01:10:00.000Z"))
  let engine = TokMonEngine(configStore: configStore, database: database)
  let store = TokMonStatsStore(
    engine: engine,
    nowProvider: { makeLocalDate("2026-05-14 10:05:30") },
  )

  await store.refresh()

  #expect(store.snapshot.previousSummary == nil)
}

@MainActor
@Test func statsStoreUpdatesNativeDashboardRangeSelection() async throws {
  let dataDir = try makeTokMonTempDir()
  let configStore = TokMonConfigStore(dataDir: dataDir)
  try configStore.saveConfig(emptyTokMonConfig(dataDir: dataDir))
  try configStore.saveUIState(TokMonUIState(
    source: "",
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
  let engine = TokMonEngine(configStore: configStore, database: try TokMonDatabase(appDataDir: dataDir))
  let store = TokMonStatsStore(
    engine: engine,
    nowProvider: { makeLocalDate("2026-05-14 10:05:30") },
  )

  await store.updateDashboardRange("thisMonth")

  #expect(store.snapshot.dashboardState?.rangeLabel == "thisMonth")
  #expect(store.snapshot.dashboardState?.rangeHours == nil)
  #expect(store.snapshot.dashboardState?.rangeDays == nil)
  #expect(store.snapshot.dashboardState?.interval == "day")
  #expect(store.snapshot.dashboardState?.rangeMode == "round")
  #expect(store.snapshot.dashboardState?.from == "2026-05-01 00:00:00")
  #expect(store.snapshot.dashboardState?.to == "2026-05-14 10:05:59")

  let persistedState = try configStore.loadUIState()
  #expect(persistedState.rangeLabel == "thisMonth")
  #expect(persistedState.rangeHours == nil)
  #expect(persistedState.rangeDays == nil)
  #expect(persistedState.interval == "day")
  #expect(persistedState.rangeMode == "round")
  #expect(persistedState.liveMode)
}

@MainActor
@Test func statsStoreChangingRangePreservesExpensiveActivityData() async throws {
  let dataDir = try makeTokMonTempDir()
  let configStore = TokMonConfigStore(dataDir: dataDir)
  try configStore.saveConfig(emptyTokMonConfig(dataDir: dataDir))
  try configStore.saveUIState(TokMonUIState(
    source: "",
    from: "",
    to: "",
    rangeLabel: "today",
    rangeHours: nil,
    rangeDays: nil,
    liveMode: true,
    rangeMode: "round",
    interval: "hour",
    activeSeries: "total",
    refreshRate: 3000,
    costRates: .zero,
  ))
  let database = try TokMonDatabase(appDataDir: dataDir)
  _ = try database.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "today", model: "gpt-test", inputTokens: 10, outputTokens: 1, cacheCreation: 0, cacheRead: 0, reasoningTokens: 0, createdAt: "2026-05-14T01:10:00.000Z"))
  _ = try database.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "week", model: "gpt-test", inputTokens: 30, outputTokens: 3, cacheCreation: 0, cacheRead: 0, reasoningTokens: 0, createdAt: "2026-05-13T01:10:00.000Z"))
  let engine = TokMonEngine(configStore: configStore, database: database)
  let store = TokMonStatsStore(
    engine: engine,
    nowProvider: { makeLocalDate("2026-05-14 10:05:30") },
  )

  await store.refresh()
  let originalHeatmap = store.snapshot.heatmapDays
  let originalRecords = store.snapshot.recordsPage
  let originalSessions = store.snapshot.usageSessions
  await store.updateDashboardRange("thisWeek")

  #expect(store.snapshot.dashboardState?.rangeLabel == "thisWeek")
  #expect(store.snapshot.summary?.total.totalRequests == 2)
  #expect(store.snapshot.trendBuckets.contains { $0.bucket == "2026-05-13" && $0.requests == 1 })
  #expect(store.snapshot.heatmapDays == originalHeatmap)
  #expect(store.snapshot.recordsPage == originalRecords)
  #expect(store.snapshot.usageSessions == originalSessions)
}

@MainActor
@Test func statsStoreChangingRangeDoesNotScanLogFilesImmediately() async throws {
  let dataDir = try makeTokMonTempDir()
  let configStore = TokMonConfigStore(dataDir: dataDir)
  let codexDir = dataDir.appendingPathComponent("codex-sessions", isDirectory: true)
  try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
  let logURL = codexDir.appendingPathComponent("pending.jsonl")
  try """
  {"type":"session_meta","payload":{"id":"pending-session","model":"gpt-test"}}
  {"type":"event_msg","timestamp":"2026-05-14T01:10:00.000Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":20,"output_tokens":5,"cached_input_tokens":2,"reasoning_output_tokens":1}}}}
  """.write(to: logURL, atomically: true, encoding: .utf8)
  try configStore.saveConfig(TokMonConfig(
    port: 3388,
    sources: [
      "codex": TokMonSourceConfig(path: codexDir.path),
    ],
  ))
  try configStore.saveUIState(TokMonUIState(
    source: "",
    from: "",
    to: "",
    rangeLabel: "today",
    rangeHours: nil,
    rangeDays: nil,
    liveMode: true,
    rangeMode: "round",
    interval: "hour",
    activeSeries: "total",
    refreshRate: 3000,
    costRates: .zero,
  ))
  let database = try TokMonDatabase(appDataDir: dataDir)
  let engine = TokMonEngine(configStore: configStore, database: database)
  let store = TokMonStatsStore(
    engine: engine,
    nowProvider: { makeLocalDate("2026-05-14 10:05:30") },
  )

  await store.updateDashboardRange("thisWeek")

  #expect(store.snapshot.scanStatus?.processed == 0)
  #expect(store.snapshot.summary?.total.totalRequests == 0)
  #expect(try database.usageRecordCount() == 0)
}

@Test func dashboardCalendarRangePresetsResolveToRoundedBoundaries() {
  let now = makeLocalDate("2026-05-14 10:05:30")

  let cases: [(String, String, String, String)] = [
    ("today", "2026-05-14 00:00:00", "2026-05-14 10:05:59", "hour"),
    ("thisWeek", "2026-05-11 00:00:00", "2026-05-14 10:05:59", "day"),
    ("thisMonth", "2026-05-01 00:00:00", "2026-05-14 10:05:59", "day"),
    ("all", "0001-01-01 00:00:00", "9999-12-31 23:59:59", "day"),
  ]

  for (label, expectedFrom, expectedTo, expectedInterval) in cases {
    let preset = TokMonRangePreset(label: label)
    let state = TokMonStatsSnapshotBuilder.currentDashboardState(from: TokMonUIState(
      source: "",
      from: "",
      to: "",
      rangeLabel: label,
      rangeHours: preset.hours,
      rangeDays: preset.days,
      liveMode: true,
      rangeMode: "exact",
      interval: preset.interval,
      activeSeries: "total",
      refreshRate: 3000,
      costRates: .zero,
    ), now: now)

    #expect(state.rangeMode == "round")
    #expect(state.interval == expectedInterval)
    #expect(state.from == expectedFrom)
    #expect(state.to == expectedTo)
  }
}

@Test func rangePresetDisplayLabelsAreEnglish() {
  #expect(TokMonRangePreset.allCases.map(\.label) == [
    "today",
    "thisWeek",
    "thisMonth",
    "all",
  ])
  #expect(TokMonRangePreset.allCases.map(\.displayLabel) == [
    "Today",
    "This Week",
    "This Month",
    "All",
  ])
}

@MainActor
@Test func statsStoreUsesAllRangeFromNativeUIState() async throws {
  let dataDir = try makeTokMonTempDir()
  let configStore = TokMonConfigStore(dataDir: dataDir)
  try configStore.saveConfig(emptyTokMonConfig(dataDir: dataDir))
  try configStore.saveUIState(TokMonUIState(
    source: "",
    from: "2026-05-01 00:00:00",
    to: "2026-05-02 23:59:59",
    rangeLabel: "all",
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
  let store = TokMonStatsStore(
    engine: engine,
    nowProvider: { makeLocalDate("2026-05-14 10:05:30") },
  )

  await store.refresh()

  #expect(store.snapshot.dashboardState?.from == "0001-01-01 00:00:00")
  #expect(store.snapshot.dashboardState?.to == "9999-12-31 23:59:59")
}

@MainActor
@Test func statsStoreAllRangeIncludesMoreRecordsThanThisMonth() async throws {
  let dataDir = try makeTokMonTempDir()
  let configStore = TokMonConfigStore(dataDir: dataDir)
  try configStore.saveConfig(emptyTokMonConfig(dataDir: dataDir))
  try configStore.saveUIState(TokMonUIState(
    source: "",
    from: "",
    to: "",
    rangeLabel: "all",
    rangeHours: nil,
    rangeDays: nil,
    liveMode: true,
    rangeMode: "round",
    interval: "day",
    activeSeries: "total",
    refreshRate: 3000,
    costRates: .zero,
  ))
  let database = try TokMonDatabase(appDataDir: dataDir)
  _ = try database.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "old", model: "gpt-test", inputTokens: 10, outputTokens: 1, cacheCreation: 0, cacheRead: 0, reasoningTokens: 0, createdAt: "2026-04-14T01:10:00.000Z"))
  _ = try database.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "current", model: "gpt-test", inputTokens: 20, outputTokens: 2, cacheCreation: 0, cacheRead: 0, reasoningTokens: 0, createdAt: "2026-05-14T01:10:00.000Z"))
  let engine = TokMonEngine(configStore: configStore, database: database)
  let store = TokMonStatsStore(
    engine: engine,
    nowProvider: { makeLocalDate("2026-05-14 10:05:30") },
  )

  await store.refresh()
  let allRequests = store.snapshot.summary?.total.totalRequests
  await store.updateDashboardRange("thisMonth")
  let thisMonthRequests = store.snapshot.summary?.total.totalRequests

  #expect(allRequests == 2)
  #expect(thisMonthRequests == 1)
}


private func emptyTokMonConfig(dataDir: URL) throws -> TokMonConfig {
  let claudeDir = dataDir.appendingPathComponent("claude-projects", isDirectory: true)
  let codexDir = dataDir.appendingPathComponent("codex-sessions", isDirectory: true)
  let openCodeDir = dataDir.appendingPathComponent("opencode", isDirectory: true)
  let qwenCodeDir = dataDir.appendingPathComponent("qwen-projects", isDirectory: true)
  try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: openCodeDir, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: qwenCodeDir, withIntermediateDirectories: true)
  return TokMonConfig(
    port: 3388,
    sources: [
      "claude-code": TokMonSourceConfig(path: claudeDir.path),
      "codex": TokMonSourceConfig(path: codexDir.path),
      "opencode": TokMonSourceConfig(path: openCodeDir.path),
      "qwen-code": TokMonSourceConfig(path: qwenCodeDir.path),
    ],
  )
}
