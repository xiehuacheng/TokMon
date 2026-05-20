import Foundation
import SQLite3
import Testing
@testable import AgentMonApp

@Test func databaseCreatesUsageAndScanStateTables() throws {
  let dataDir = try makeTokMonTempDir()
  let db = try TokMonDatabase(appDataDir: dataDir)

  #expect(try db.tableExists("usage_records"))
  #expect(try db.tableExists("tokmon_scan_state"))
  #expect(try db.tableExists("tokmon_session_metadata"))
  #expect(try db.tableExists("tokmon_usage_rollups"))
}

@Test func databaseIgnoresDuplicateUsageRecords() throws {
  let dataDir = try makeTokMonTempDir()
  let db = try TokMonDatabase(appDataDir: dataDir)
  let record = TokMonUsageRecord(
    source: "codex",
    sessionId: "session-1",
    model: "gpt-test",
    inputTokens: 10,
    outputTokens: 3,
    cacheCreation: 0,
    cacheRead: 2,
    reasoningTokens: 1,
    createdAt: "2026-05-14T01:00:00.000Z",
  )

  #expect(try db.insertUsage(record) == true)
  #expect(try db.insertUsage(record) == false)
  #expect(try db.usageRecordCount() == 1)
}

@Test func databaseMaintainsUsageRollupsOnUsageInsertAndRebuild() throws {
  let dataDir = try makeTokMonTempDir()
  let db = try TokMonDatabase(appDataDir: dataDir)
  let record = TokMonUsageRecord(
    source: "codex",
    sessionId: "session-1",
    model: "gpt-test",
    inputTokens: 10,
    outputTokens: 3,
    cacheCreation: 4,
    cacheRead: 2,
    reasoningTokens: 1,
    createdAt: "2026-05-14T01:00:00.000Z",
  )

  #expect(try db.insertUsage(record))
  #expect(try !db.insertUsage(record))

  let rows = try db.queryRows("""
    SELECT grain, period_start, requests, input_tokens, output_tokens, cache_creation, cache_read, reasoning_tokens
    FROM tokmon_usage_rollups
    ORDER BY grain
  """) { row in
    (
      grain: row.string(0),
      period: row.string(1),
      requests: row.int(2),
      input: row.int(3),
      output: row.int(4),
      cacheCreation: row.int(5),
      cacheRead: row.int(6),
      reasoning: row.int(7)
    )
  }

  #expect(rows.map(\.grain) == ["day", "month", "week", "year"])
  #expect(rows.allSatisfy { $0.requests == 1 })
  #expect(rows.allSatisfy { $0.input == 10 && $0.output == 3 && $0.cacheCreation == 4 && $0.cacheRead == 2 && $0.reasoning == 1 })
  #expect(rows.first { $0.grain == "day" }?.period == "2026-05-14 00:00:00")
  #expect(rows.first { $0.grain == "week" }?.period == "2026-05-11 00:00:00")
  #expect(rows.first { $0.grain == "month" }?.period == "2026-05-01 00:00:00")
  #expect(rows.first { $0.grain == "year" }?.period == "2026-01-01 00:00:00")

  try db.rebuildTokMonData()

  #expect(try db.queryInt("SELECT COUNT(*) FROM tokmon_usage_rollups") == 0)
}

@Test func databaseBackfillsUsageRollupsForExistingUsageRecords() throws {
  let dataDir = try makeTokMonTempDir()
  let databaseURL = dataDir.appendingPathComponent("agentmon.db")
  try withRawSQLiteDatabase(at: databaseURL) { db in
    try rawSQLiteExec(db, """
      CREATE TABLE usage_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source TEXT NOT NULL,
        session_id TEXT NOT NULL,
        model TEXT NOT NULL DEFAULT 'unknown',
        input_tokens INTEGER NOT NULL DEFAULT 0,
        output_tokens INTEGER NOT NULL DEFAULT 0,
        cache_creation INTEGER NOT NULL DEFAULT 0,
        cache_read INTEGER NOT NULL DEFAULT 0,
        reasoning_tokens INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        UNIQUE(source, session_id, created_at, input_tokens, output_tokens)
      );
      INSERT INTO usage_records
        (source, session_id, model, input_tokens, output_tokens, cache_creation, cache_read, reasoning_tokens, created_at)
      VALUES
        ('codex', 'existing-1', 'gpt-existing', 10, 3, 1, 2, 4, '2026-05-14T01:00:00.000Z'),
        ('codex', 'existing-2', 'gpt-existing', 20, 7, 0, 5, 0, '2026-05-15T01:00:00.000Z');
    """)
  }

  let db = try TokMonDatabase(appDataDir: dataDir)

  let rows = try db.queryRows("""
    SELECT grain, SUM(requests), SUM(input_tokens), SUM(output_tokens), SUM(cache_creation), SUM(cache_read), SUM(reasoning_tokens)
    FROM tokmon_usage_rollups
    GROUP BY grain
    ORDER BY grain
  """) { row in
    (
      grain: row.string(0),
      requests: row.int(1),
      input: row.int(2),
      output: row.int(3),
      cacheCreation: row.int(4),
      cacheRead: row.int(5),
      reasoning: row.int(6)
    )
  }

  #expect(rows.map(\.grain) == ["day", "month", "week", "year"])
  #expect(rows.allSatisfy { $0.requests == 2 })
  #expect(rows.allSatisfy { $0.input == 30 && $0.output == 10 && $0.cacheCreation == 1 && $0.cacheRead == 7 && $0.reasoning == 4 })
}

@Test func databasePersistsTokMonScanState() throws {
  let dataDir = try makeTokMonTempDir()
  let db = try TokMonDatabase(appDataDir: dataDir)
  try db.setScanState(
    filePath: "/tmp/session.jsonl",
    state: TokMonScanState(offset: 128, sessionId: "session-1", model: "gpt-test", lastUsageKey: "10:3:2:1"),
  )

  let state = try db.scanState(filePath: "/tmp/session.jsonl")

  #expect(state.offset == 128)
  #expect(state.sessionId == "session-1")
  #expect(state.model == "gpt-test")
  #expect(state.lastUsageKey == "10:3:2:1")
}

@Test func databaseRebuildClearsTokMonTables() throws {
  let dataDir = try makeTokMonTempDir()
  let db = try TokMonDatabase(appDataDir: dataDir)
  _ = try db.insertUsage(TokMonUsageRecord(
    source: "claude-code",
    sessionId: "claude-1",
    model: "claude-test",
    inputTokens: 7,
    outputTokens: 5,
    cacheCreation: 1,
    cacheRead: 2,
    reasoningTokens: 0,
    createdAt: "2026-05-14T02:00:00.000Z",
  ))
  try db.upsertSessionMetadata(TokMonSessionMetadata(
    id: "claude-1",
    source: "claude-code",
    title: "Claude test session",
    firstPrompt: "Claude test session",
    lastPrompt: "Claude follow-up",
    model: "claude-test",
    startedAt: "2026-05-14T02:00:00.000Z",
    lastActiveAt: "2026-05-14T02:01:00.000Z",
    filePath: "/tmp/claude.jsonl",
    projectPath: "/tmp",
  ))
  try db.setScanState(filePath: "/tmp/claude.jsonl", state: TokMonScanState(offset: 42, sessionId: "claude-1", model: nil, lastUsageKey: "key"))

  try db.rebuildTokMonData()

  #expect(try db.usageRecordCount() == 0)
  #expect(try db.scanState(filePath: "/tmp/claude.jsonl") == .empty)
  #expect(try db.sessionMetadata(source: "claude-code", id: "claude-1") == nil)
}


private func withRawSQLiteDatabase(at url: URL, _ body: (OpaquePointer?) throws -> Void) throws {
  var db: OpaquePointer?
  guard sqlite3_open(url.path, &db) == SQLITE_OK else {
    defer {
      if let db {
        sqlite3_close(db)
      }
    }
    throw RawSQLiteError.openFailed
  }
  defer { sqlite3_close(db) }
  try body(db)
}

private func rawSQLiteExec(_ db: OpaquePointer?, _ sql: String) throws {
  var errorMessage: UnsafeMutablePointer<CChar>?
  let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
  if result != SQLITE_OK {
    let message = errorMessage.map { String(cString: $0) } ?? "unknown SQLite error"
    sqlite3_free(errorMessage)
    throw RawSQLiteError.execFailed(message)
  }
}

private enum RawSQLiteError: LocalizedError {
  case openFailed
  case execFailed(String)
}
