import Foundation
import Testing
@testable import AgentMonApp

@Test func queryStoreAggregatesSummaryTrendRecordsAndSessions() throws {
  let dataDir = try makeTokMonTempDir()
  let db = try TokMonDatabase(appDataDir: dataDir)
  _ = try db.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "s1", model: "gpt-a", inputTokens: 10, outputTokens: 5, cacheCreation: 0, cacheRead: 2, reasoningTokens: 1, createdAt: "2026-05-14T01:10:00.000Z"))
  _ = try db.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "s1", model: "gpt-a", inputTokens: 20, outputTokens: 7, cacheCreation: 0, cacheRead: 3, reasoningTokens: 0, createdAt: "2026-05-14T01:30:00.000Z"))
  _ = try db.insertUsage(TokMonUsageRecord(source: "claude-code", sessionId: "c1", model: "claude-a", inputTokens: 8, outputTokens: 9, cacheCreation: 4, cacheRead: 1, reasoningTokens: 0, createdAt: "2026-05-15T02:00:00.000Z"))
  let store = TokMonQueryStore(database: db)
  let filter = TokMonQueryFilter(from: "2026-05-14 00:00:00", to: "2026-05-16 23:59:59", source: nil, model: nil)

  let summary = try store.summary(filter: filter)
  let trend = try store.trend(filter: filter, interval: "hour")
  let records = try store.records(filter: filter, page: 0, limit: 10)
  let sessions = try store.sessions(limit: 10)

  #expect(summary.total.totalRequests == 3)
  #expect(summary.total.totalInput == 38)
  #expect(summary.total.totalOutput == 21)
  #expect(summary.bySource.map(\.source).sorted() == ["claude-code", "codex"])
  #expect(trend.contains { $0.bucket == "2026-05-14 09:00" && $0.requests == 2 })
  #expect(records.total == 3)
  #expect(records.rows.first?.sessionId == "c1")
  #expect(sessions.first?.sessionId == "c1")
}

@Test func queryStoreAppliesSourceAndModelFilters() throws {
  let dataDir = try makeTokMonTempDir()
  let db = try TokMonDatabase(appDataDir: dataDir)
  _ = try db.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "s1", model: "gpt-a", inputTokens: 10, outputTokens: 1, cacheCreation: 0, cacheRead: 0, reasoningTokens: 0, createdAt: "2026-05-14T01:00:00.000Z"))
  _ = try db.insertUsage(TokMonUsageRecord(source: "codex", sessionId: "s2", model: "gpt-b", inputTokens: 99, outputTokens: 1, cacheCreation: 0, cacheRead: 0, reasoningTokens: 0, createdAt: "2026-05-14T01:05:00.000Z"))
  let store = TokMonQueryStore(database: db)
  let filter = TokMonQueryFilter(from: "2026-05-14 08:00:00", to: "2026-05-14 10:00:00", source: "codex", model: "gpt-a")

  let summary = try store.summary(filter: filter)

  #expect(summary.total.totalRequests == 1)
  #expect(summary.total.totalInput == 10)
}
