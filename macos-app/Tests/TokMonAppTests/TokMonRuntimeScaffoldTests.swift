import Foundation
import Testing
@testable import TokMonApp

@Test func nativeTokMonRuntimeTypesAreAvailable() {
  _ = TokMonConfig.self
  _ = TokMonUIState.self
  _ = TokMonUsageRecord.self
  _ = TokMonEngine.self
  _ = TokMonConfigStore.self
  _ = TokMonDatabase.self
  _ = TokMonScanner.self
  _ = TokMonQueryStore.self
}

@Test func tokMonEngineBindsDefaultQueryStoreToDatabase() throws {
  let dataDir = try makeTokMonTempDir()
  let configStore = TokMonConfigStore(dataDir: dataDir)
  let database = try TokMonDatabase(appDataDir: dataDir)
  _ = try database.insertUsage(TokMonUsageRecord(
    source: "codex",
    sessionId: "session-1",
    model: "gpt-test",
    inputTokens: 12,
    outputTokens: 4,
    cacheCreation: 0,
    cacheRead: 2,
    reasoningTokens: 1,
    createdAt: "2026-05-14T01:00:00.000Z",
  ))

  let engine = TokMonEngine(configStore: configStore, database: database)
  let summary = try engine.queryStore.summary(filter: TokMonQueryFilter(
    from: "2026-05-14 08:00:00",
    to: "2026-05-14 10:00:00",
    source: "codex",
    model: nil,
  ))

  #expect(summary.total.totalRequests == 1)
  #expect(summary.total.totalInput == 12)
}
