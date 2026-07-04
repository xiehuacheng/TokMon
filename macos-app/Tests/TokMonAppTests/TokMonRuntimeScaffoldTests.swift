import Foundation
import Testing
@testable import TokMonApp

private func makeMigrationTestEngine(
  dataDir: URL,
  claudePath: String
) throws -> (engineActor: TokMonEngineActor, database: TokMonDatabase) {
  let configStore = TokMonConfigStore(dataDir: dataDir)
  var config = try configStore.loadConfig()
  for key in config.sources.keys {
    if key == "claude-code" { continue }
    let emptyDir = dataDir.appendingPathComponent("empty-\(key)", isDirectory: true)
    try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
    config.sources[key] = TokMonSourceConfig(path: emptyDir.path)
  }
  config.sources["claude-code"] = TokMonSourceConfig(path: claudePath)
  try configStore.saveConfig(config)
  let database = try TokMonDatabase(appDataDir: dataDir)
  let engine = TokMonEngine(configStore: configStore, database: database)
  return (TokMonEngineActor(engine: engine), database)
}

private func makeUserDefaultsSuite(name: String) -> UserDefaults {
  let defaults = UserDefaults(suiteName: name)!
  defaults.removePersistentDomain(forName: name)
  return defaults
}

@Test func runtimeMigratesScannerVersionWhenStoredVersionIsOlder() async throws {
  let dataDir = try makeTokMonTempDir()
  let projectsDir = dataDir.appendingPathComponent("claude-projects", isDirectory: true)
  try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
  let logURL = projectsDir.appendingPathComponent("claude-session.jsonl")
  try writeJSONL(
    [
      [
        "type": "user",
        "sessionId": "claude-session",
        "timestamp": "2026-05-14T03:00:00.000Z",
        "message": [
          "content": "Hello"
        ],
      ],
    ],
    to: logURL
  )

  let engine = try makeMigrationTestEngine(dataDir: dataDir, claudePath: projectsDir.path)
  let engineActor = engine.engineActor
  let database = engine.database
  _ = try database.insertUsage(TokMonUsageRecord(
    source: "claude-code",
    sessionId: "manual-session",
    model: "manual-model",
    inputTokens: 1,
    outputTokens: 1,
    cacheCreation: 0,
    cacheRead: 0,
    reasoningTokens: 0,
    createdAt: "2026-05-14T02:00:00.000Z"
  ))

  let suiteName = "test-runtime-migration-\(UUID().uuidString)"
  let defaults = makeUserDefaultsSuite(name: suiteName)
  defaults.set(1, forKey: "tokmonScannerVersion")

  await TokMonRuntime.migrateScannerVersion(
    engineActor: engineActor,
    defaults: defaults,
    currentVersion: 2
  )

  #expect(defaults.object(forKey: "tokmonScannerVersion") as? Int == 2)
  #expect(try database.usageRecordCount() == 0)
  defaults.removePersistentDomain(forName: suiteName)
}

@Test func runtimeSkipsMigrationWhenStoredVersionIsCurrent() async throws {
  let dataDir = try makeTokMonTempDir()
  let projectsDir = dataDir.appendingPathComponent("claude-projects", isDirectory: true)
  try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
  let logURL = projectsDir.appendingPathComponent("claude-session.jsonl")
  try writeJSONL(
    [
      [
        "type": "assistant",
        "sessionId": "claude-session",
        "timestamp": "2026-05-14T03:00:00.000Z",
        "message": [
          "id": "msg-1",
          "model": "claude-test",
          "usage": [
            "input_tokens": 12,
            "output_tokens": 6,
          ],
        ],
      ],
    ],
    to: logURL
  )

  let engine = try makeMigrationTestEngine(dataDir: dataDir, claudePath: projectsDir.path)
  let engineActor = engine.engineActor
  let database = engine.database
  _ = try database.insertUsage(TokMonUsageRecord(
    source: "claude-code",
    sessionId: "manual-session",
    model: "manual-model",
    inputTokens: 1,
    outputTokens: 1,
    cacheCreation: 0,
    cacheRead: 0,
    reasoningTokens: 0,
    createdAt: "2026-05-14T02:00:00.000Z"
  ))

  let suiteName = "test-runtime-skip-\(UUID().uuidString)"
  let defaults = makeUserDefaultsSuite(name: suiteName)
  defaults.set(2, forKey: "tokmonScannerVersion")

  await TokMonRuntime.migrateScannerVersion(
    engineActor: engineActor,
    defaults: defaults,
    currentVersion: 2
  )

  #expect(defaults.object(forKey: "tokmonScannerVersion") as? Int == 2)
  #expect(try database.usageRecordCount() == 1)
  defaults.removePersistentDomain(forName: suiteName)
}

@Test func runtimeDoesNotUpdateVersionWhenRebuildFails() async throws {
  let dataDir = try makeTokMonTempDir()
  let missingClaudePath = dataDir.appendingPathComponent("missing-claude").path

  let engine = try makeMigrationTestEngine(dataDir: dataDir, claudePath: missingClaudePath)
  let engineActor = engine.engineActor
  let database = engine.database
  _ = try database.insertUsage(TokMonUsageRecord(
    source: "claude-code",
    sessionId: "manual-session",
    model: "manual-model",
    inputTokens: 1,
    outputTokens: 1,
    cacheCreation: 0,
    cacheRead: 0,
    reasoningTokens: 0,
    createdAt: "2026-05-14T02:00:00.000Z"
  ))

  let suiteName = "test-runtime-failure-\(UUID().uuidString)"
  let defaults = makeUserDefaultsSuite(name: suiteName)
  defaults.set(1, forKey: "tokmonScannerVersion")

  await TokMonRuntime.migrateScannerVersion(
    engineActor: engineActor,
    defaults: defaults,
    currentVersion: 2
  )

  #expect(defaults.object(forKey: "tokmonScannerVersion") as? Int == 1)
  #expect(try database.usageRecordCount() == 1)
  defaults.removePersistentDomain(forName: suiteName)
}

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
