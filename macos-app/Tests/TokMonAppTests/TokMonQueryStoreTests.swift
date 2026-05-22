import Foundation
import Testing
@testable import TokMonApp

@Test func queryStoreAggregatesSummaryTrendRecordsAndSessions() throws {
  let dataDir = try makeTokMonTempDir()
  let db = try TokMonDatabase(appDataDir: dataDir)
  _ = try db.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "s1", model: "gpt-a", inputTokens: 10, outputTokens: 5, cacheCreation: 0, cacheRead: 2, reasoningTokens: 1, createdAt: "2026-05-14T01:10:00.000Z"))
  _ = try db.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "s1", model: "gpt-a", inputTokens: 20, outputTokens: 7, cacheCreation: 0, cacheRead: 3, reasoningTokens: 0, createdAt: "2026-05-14T01:30:00.000Z"))
  _ = try db.insertUsage(TokMonUsageRecord(source: "claude-code", sessionId: "c1", model: "claude-a", inputTokens: 8, outputTokens: 9, cacheCreation: 4, cacheRead: 1, reasoningTokens: 0, createdAt: "2026-05-15T02:00:00.000Z"))
  try db.upsertSessionMetadata(TokMonSessionMetadata(
    id: "s1",
    source: "codex",
    title: "Native TokMon planning",
    firstPrompt: "Build native TokMon",
    lastPrompt: "Continue native TokMon",
    model: "gpt-a",
    startedAt: "2026-05-14T01:09:00.000Z",
    lastActiveAt: "2026-05-14T01:31:00.000Z",
    filePath: "/tmp/s1.jsonl",
    projectPath: "/tmp",
  ))
  let store = TokMonQueryStore(database: db)
  let filter = TokMonQueryFilter(from: "2026-05-14 00:00:00", to: "2026-05-16 23:59:59", source: nil, model: nil)

  let summary = try store.summary(filter: filter)
  let trend = try store.trend(filter: filter, interval: "hour")
  let records = try store.records(filter: filter, page: 0, limit: 10)
  let sessions = try store.sessions(limit: 10)

  #expect(summary.total.totalRequests == 3)
  #expect(summary.total.totalInput == 38)
  #expect(summary.total.totalOutput == 21)
  #expect(summary.total.totalCacheRead == 6)
  #expect(summary.total.totalTokens == 65)
  #expect(summary.bySource.first { $0.source == "codex" }?.totalTokens == 47)
  #expect(summary.byModel.first { $0.model == "gpt-a" }?.totalTokens == 47)
  #expect(summary.bySource.map(\.source).sorted() == ["claude-code", "codex"])
  #expect(trend.contains { $0.bucket == "2026-05-14 09:00" && $0.requests == 2 })
  #expect(trend.first { $0.bucket == "2026-05-14 09:00" }?.value(for: .total, costRates: .zero) == 47)
  #expect(records.total == 3)
  #expect(records.rows.first?.sessionId == "c1")
  #expect(records.rows.first?.sessionTitle == nil)
  #expect(sessions.first?.sessionId == "c1")
  #expect(sessions.first { $0.sessionId == "s1" }?.title == "tmp - Build native TokMon")
  #expect(sessions.first { $0.sessionId == "s1" }?.projectName == "tmp")
  #expect(sessions.first { $0.sessionId == "s1" }?.firstPrompt == "Build native TokMon")
}

@Test func queryStoreDoesNotSurfaceEnvironmentContextSessionMetadata() throws {
  let dataDir = try makeTokMonTempDir()
  let db = try TokMonDatabase(appDataDir: dataDir)
  _ = try db.insertUsage(TokMonUsageRecord(
    source: "opencode",
    sessionId: "bad-context",
    model: "gpt-test",
    inputTokens: 10,
    outputTokens: 5,
    cacheCreation: 0,
    cacheRead: 0,
    reasoningTokens: 0,
    createdAt: "2026-05-20T01:20:10.000Z",
  ))
  let environmentContext = "<environment_context>\n  <cwd>/tmp/ContextWork</cwd>\n</environment_context>"
  try db.upsertSessionMetadata(TokMonSessionMetadata(
    id: "bad-context",
    source: "opencode",
    title: "ContextWork - \(environmentContext)",
    firstPrompt: environmentContext,
    lastPrompt: environmentContext,
    model: "gpt-test",
    startedAt: "2026-05-20T01:20:00.000Z",
    lastActiveAt: "2026-05-20T01:20:11.000Z",
    filePath: "/tmp/opencode.db",
    projectPath: "/tmp/ContextWork",
  ))

  let store = TokMonQueryStore(database: db)
  let records = try store.records(
    filter: TokMonQueryFilter(from: "2026-05-20 00:00:00", to: "2026-05-21 00:00:00", source: nil, model: nil),
    page: 0,
    limit: 10,
  )
  let sessions = try store.sessions(limit: 10)

  #expect(records.rows.first?.sessionTitle == nil)
  #expect(sessions.first?.title == nil)
  #expect(sessions.first?.firstPrompt == nil)
}

@Test func queryStoreSummaryCanUsePrecomputedRollupsForClosedDays() throws {
  let dataDir = try makeTokMonTempDir()
  let db = try TokMonDatabase(appDataDir: dataDir)
  _ = try db.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "closed", model: "gpt-a", inputTokens: 10, outputTokens: 5, cacheCreation: 2, cacheRead: 3, reasoningTokens: 1, createdAt: "2026-05-12T01:10:00.000Z"))
  _ = try db.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "today", model: "gpt-b", inputTokens: 20, outputTokens: 7, cacheCreation: 0, cacheRead: 4, reasoningTokens: 0, createdAt: "2026-05-14T01:30:00.000Z"))
  _ = try db.queryRows("""
    DELETE FROM usage_records
    WHERE session_id = 'closed'
  """) { _ in () }
  let store = TokMonQueryStore(database: db)
  let filter = TokMonQueryFilter(
    from: "2026-05-11 00:00:00",
    to: "2026-05-14 10:05:59",
    source: nil,
    model: nil,
  )

  let summary = try store.summary(filter: filter, now: makeLocalDate("2026-05-14 10:05:30"))
  let trend = try store.trend(filter: filter, interval: "day", now: makeLocalDate("2026-05-14 10:05:30"))

  #expect(summary.total.totalRequests == 2)
  #expect(summary.total.totalInput == 30)
  #expect(summary.total.totalOutput == 12)
  #expect(summary.total.totalCacheCreation == 2)
  #expect(summary.total.totalCacheRead == 7)
  #expect(summary.byModel.map(\.model).sorted() == ["gpt-a", "gpt-b"])
  #expect(trend.first { $0.bucket == "2026-05-12" }?.requests == 1)
  #expect(trend.first { $0.bucket == "2026-05-14" }?.requests == 1)
}

@Test func queryStoreSummaryUsesRollupsForClosedHistoricalPartialRanges() throws {
  let dataDir = try makeTokMonTempDir()
  let db = try TokMonDatabase(appDataDir: dataDir)
  _ = try db.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "previous-week", model: "gpt-a", inputTokens: 10, outputTokens: 1, cacheCreation: 0, cacheRead: 2, reasoningTokens: 0, createdAt: "2026-05-05T01:10:00.000Z"))
  _ = try db.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "after-partial-window", model: "gpt-a", inputTokens: 99, outputTokens: 9, cacheCreation: 0, cacheRead: 0, reasoningTokens: 0, createdAt: "2026-05-08T01:10:00.000Z"))
  _ = try db.queryRows("""
    DELETE FROM usage_records
    WHERE session_id = 'previous-week'
  """) { _ in () }
  let store = TokMonQueryStore(database: db)
  let filter = TokMonQueryFilter(
    from: "2026-05-04 00:00:00",
    to: "2026-05-07 10:05:59",
    source: "codex",
    model: nil,
  )

  let summary = try store.summary(filter: filter, now: makeLocalDate("2026-05-14 10:05:30"))

  #expect(summary.total.totalRequests == 1)
  #expect(summary.total.totalTokens == 13)
}

@Test func queryStoreSummaryComposesElapsedYearMonthWeekAndCurrentDayRollups() throws {
  let dataDir = try makeTokMonTempDir()
  let db = try TokMonDatabase(appDataDir: dataDir)
  let records = [
    TokMonUsageRecord(source: "codex", sessionId: "jan", model: "gpt-a", inputTokens: 10, outputTokens: 1, cacheCreation: 0, cacheRead: 2, reasoningTokens: 0, createdAt: "2026-01-15T01:00:00.000Z"),
    TokMonUsageRecord(source: "codex", sessionId: "mar", model: "gpt-a", inputTokens: 20, outputTokens: 2, cacheCreation: 0, cacheRead: 3, reasoningTokens: 1, createdAt: "2026-03-20T01:00:00.000Z"),
    TokMonUsageRecord(source: "codex", sessionId: "may-prior-week", model: "gpt-b", inputTokens: 30, outputTokens: 3, cacheCreation: 0, cacheRead: 4, reasoningTokens: 0, createdAt: "2026-05-05T01:00:00.000Z"),
    TokMonUsageRecord(source: "codex", sessionId: "this-week-past", model: "gpt-b", inputTokens: 40, outputTokens: 4, cacheCreation: 0, cacheRead: 5, reasoningTokens: 0, createdAt: "2026-05-12T01:00:00.000Z"),
    TokMonUsageRecord(source: "codex", sessionId: "today", model: "gpt-c", inputTokens: 50, outputTokens: 5, cacheCreation: 0, cacheRead: 6, reasoningTokens: 2, createdAt: "2026-05-14T01:00:00.000Z"),
    TokMonUsageRecord(source: "codex", sessionId: "future", model: "gpt-c", inputTokens: 999, outputTokens: 99, cacheCreation: 0, cacheRead: 9, reasoningTokens: 0, createdAt: "2026-05-15T01:00:00.000Z"),
  ]
  for record in records {
    _ = try db.insertUsage(record)
  }
  _ = try db.queryRows("""
    DELETE FROM usage_records
    WHERE session_id IN ('jan', 'mar', 'may-prior-week', 'this-week-past')
  """) { _ in () }
  let store = TokMonQueryStore(database: db)
  let filter = TokMonQueryFilter(
    from: "2026-01-01 00:00:00",
    to: "2026-05-14 10:05:59",
    source: nil,
    model: nil,
  )

  let summary = try store.summary(filter: filter, now: makeLocalDate("2026-05-14 10:05:30"))

  #expect(summary.total.totalRequests == 5)
  #expect(summary.total.totalInput == 150)
  #expect(summary.total.totalOutput == 15)
  #expect(summary.total.totalCacheRead == 20)
  #expect(summary.total.totalReasoning == 3)
  #expect(summary.total.totalTokens == 185)
  #expect(summary.byModel.map(\.model).sorted() == ["gpt-a", "gpt-b", "gpt-c"])
  #expect(summary.byModel.first { $0.model == "gpt-a" }?.requests == 2)
  #expect(summary.byModel.first { $0.model == "gpt-b" }?.requests == 2)
  #expect(summary.byModel.first { $0.model == "gpt-c" }?.requests == 1)
}

@Test func queryStoreAppliesSourceAndModelFilters() throws {
  let dataDir = try makeTokMonTempDir()
  let db = try TokMonDatabase(appDataDir: dataDir)
  _ = try db.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "s1", model: "gpt-a", inputTokens: 10, outputTokens: 1, cacheCreation: 0, cacheRead: 0, reasoningTokens: 0, createdAt: "2026-05-14T01:00:00.000Z"))
  _ = try db.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "s2", model: "gpt-b", inputTokens: 99, outputTokens: 1, cacheCreation: 0, cacheRead: 0, reasoningTokens: 0, createdAt: "2026-05-14T01:05:00.000Z"))
  let store = TokMonQueryStore(database: db)
  let filter = TokMonQueryFilter(from: "2026-05-14 08:00:00", to: "2026-05-14 10:00:00", source: "codex", model: "gpt-a")

  let summary = try store.summary(filter: filter)
  let sessions = try store.sessions(filter: filter, limit: 10)

  #expect(summary.total.totalRequests == 1)
  #expect(summary.total.totalInput == 10)
  #expect(sessions.map(\.sessionId) == ["s1"])
  #expect(sessions.first?.cacheRead == 0)
}

@Test func queryStoreAllRangeCanIncludeRecordsOutsideCurrentCalendarBounds() throws {
  let dataDir = try makeTokMonTempDir()
  let db = try TokMonDatabase(appDataDir: dataDir)
  _ = try db.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "ancient", model: "gpt-a", inputTokens: 10, outputTokens: 1, cacheCreation: 0, cacheRead: 0, reasoningTokens: 0, createdAt: "1970-01-01T00:00:00.000Z"))
  _ = try db.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "current", model: "gpt-a", inputTokens: 20, outputTokens: 2, cacheCreation: 0, cacheRead: 0, reasoningTokens: 0, createdAt: "2026-05-14T01:00:00.000Z"))
  _ = try db.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "future", model: "gpt-a", inputTokens: 30, outputTokens: 3, cacheCreation: 0, cacheRead: 0, reasoningTokens: 0, createdAt: "2100-01-01T00:00:00.000Z"))
  let store = TokMonQueryStore(database: db)

  let allSummary = try store.summary(filter: TokMonQueryFilter(
    from: "0001-01-01 00:00:00",
    to: "9999-12-31 23:59:59",
    source: nil,
    model: nil,
  ))
  let boundedSummary = try store.summary(filter: TokMonQueryFilter(
    from: "2026-05-01 00:00:00",
    to: "2026-05-31 23:59:59",
    source: nil,
    model: nil,
  ))

  #expect(allSummary.total.totalRequests == 3)
  #expect(allSummary.total.totalInput == 60)
  #expect(boundedSummary.total.totalRequests == 1)
}

@Test func queryStoreReturnsRecordsForSpecificUsageSession() throws {
  let dataDir = try makeTokMonTempDir()
  let db = try TokMonDatabase(appDataDir: dataDir)
  _ = try db.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "s1", model: "gpt-a", inputTokens: 10, outputTokens: 1, cacheCreation: 0, cacheRead: 0, reasoningTokens: 0, createdAt: "2026-05-14T01:00:00.000Z"))
  _ = try db.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "s2", model: "gpt-a", inputTokens: 20, outputTokens: 2, cacheCreation: 0, cacheRead: 0, reasoningTokens: 0, createdAt: "2026-05-14T01:05:00.000Z"))
  _ = try db.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "s1", model: "gpt-a", inputTokens: 30, outputTokens: 3, cacheCreation: 0, cacheRead: 0, reasoningTokens: 4, createdAt: "2026-05-14T01:10:00.000Z"))
  let store = TokMonQueryStore(database: db)
  let filter = TokMonQueryFilter(from: "2026-05-14 08:00:00", to: "2026-05-14 10:00:00", source: "codex", model: nil)

  let rows = try store.recordsForSession(filter: filter, source: "codex", sessionId: "s1", limit: 10)

  #expect(rows.map(\.inputTokens) == [30, 10])
  #expect(rows.map(\.reasoningTokens) == [4, 0])
}

@Test func usageSessionsUseMixedModelLabelWhenSessionContainsMultipleModels() throws {
  let dataDir = try makeTokMonTempDir()
  let db = try TokMonDatabase(appDataDir: dataDir)
  _ = try db.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "s1", model: "gpt-a", inputTokens: 10, outputTokens: 1, cacheCreation: 0, cacheRead: 0, reasoningTokens: 0, createdAt: "2026-05-14T01:00:00.000Z"))
  _ = try db.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "s1", model: "gpt-b", inputTokens: 20, outputTokens: 2, cacheCreation: 0, cacheRead: 3, reasoningTokens: 0, createdAt: "2026-05-14T01:10:00.000Z"))
  let store = TokMonQueryStore(database: db)

  let sessions = try store.sessions(limit: 10)

  #expect(sessions.count == 1)
  #expect(sessions.first?.model == "Mixed")
  #expect(sessions.first?.requests == 2)
  #expect(sessions.first?.cacheRead == 3)
}

@Test func heatmapReturnsRecentLocalDaysAndFillsDaysWithoutUsage() throws {
  let dataDir = try makeTokMonTempDir()
  let db = try TokMonDatabase(appDataDir: dataDir)
  _ = try db.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "s1", model: "gpt-a", inputTokens: 10, outputTokens: 1, cacheCreation: 0, cacheRead: 0, reasoningTokens: 0, createdAt: "2026-05-14T01:00:00.000Z"))
  let store = TokMonQueryStore(database: db)

  let days = try store.heatmap(source: nil, model: nil, endingAt: makeLocalDate("2026-05-14 10:05:30"))

  #expect(days.count == 140)
  #expect(days.first?.day == "2025-12-26")
  #expect(days.last?.day == "2026-05-14")
  #expect(days.filter { $0.requests == 0 }.count == 139)
  #expect(days.first { $0.day == "2026-05-14" }?.requests == 1)
}
