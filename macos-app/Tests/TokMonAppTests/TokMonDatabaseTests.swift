import Foundation
import SQLite3
import Testing
@testable import TokMonApp

@Test func databaseMergesClaudeUsageRecordsByMessageId() throws {
  let dataDir = try makeTokMonTempDir()
  let db = try TokMonDatabase(appDataDir: dataDir)
  let partial = TokMonUsageRecord(
    source: "claude-code",
    sessionId: "session-1",
    model: "claude-test",
    inputTokens: 1000,
    outputTokens: 0,
    cacheCreation: 0,
    cacheRead: 0,
    reasoningTokens: 0,
    createdAt: "2026-05-14T01:00:00.000Z",
    messageId: "msg-1",
  )
  let later = TokMonUsageRecord(
    source: "claude-code",
    sessionId: "session-1",
    model: "claude-test",
    inputTokens: 1000,
    outputTokens: 500,
    cacheCreation: 200,
    cacheRead: 50,
    reasoningTokens: 0,
    createdAt: "2026-05-14T01:00:01.000Z",
    messageId: "msg-1",
  )

  #expect(try db.insertUsage(partial) == true)
  #expect(try db.insertUsage(later) == true)

  let records = try db.allUsageRecords()
  #expect(records.count == 1)
  #expect(records[0].inputTokens == 1000)
  #expect(records[0].outputTokens == 500)
  #expect(records[0].cacheCreation == 200)
  #expect(records[0].cacheRead == 50)
}

@Test func databaseMergesClaudeUsageRecordsByTotalTokensWhenTimestampsAreEqual() throws {
  let dataDir = try makeTokMonTempDir()
  let db = try TokMonDatabase(appDataDir: dataDir)
  let partial = TokMonUsageRecord(
    source: "claude-code",
    sessionId: "session-1",
    model: "claude-test",
    inputTokens: 100,
    outputTokens: 0,
    cacheCreation: 0,
    cacheRead: 0,
    reasoningTokens: 0,
    createdAt: "2026-05-14T01:00:00.000Z",
    messageId: "msg-tie",
  )
  let later = TokMonUsageRecord(
    source: "claude-code",
    sessionId: "session-1",
    model: "claude-test",
    inputTokens: 50,
    outputTokens: 100,
    cacheCreation: 0,
    cacheRead: 0,
    reasoningTokens: 0,
    createdAt: "2026-05-14T01:00:00.000Z",
    messageId: "msg-tie",
  )

  #expect(try db.insertUsage(partial) == true)
  #expect(try db.insertUsage(later) == true)

  let records = try db.allUsageRecords()
  #expect(records.count == 1)
  #expect(records[0].inputTokens == 50)
  #expect(records[0].outputTokens == 100)
}

@Test func databaseKeepsSameMessageIdAcrossSourcesAndSessions() throws {
  let dataDir = try makeTokMonTempDir()
  let db = try TokMonDatabase(appDataDir: dataDir)
  let claudeRecord = TokMonUsageRecord(
    source: "claude-code",
    sessionId: "session-a",
    model: "claude-test",
    inputTokens: 10,
    outputTokens: 5,
    cacheCreation: 0,
    cacheRead: 0,
    reasoningTokens: 0,
    createdAt: "2026-05-14T01:00:00.000Z",
    messageId: "msg-shared",
  )
  let codexRecord = TokMonUsageRecord(
    source: "codex",
    sessionId: "session-b",
    model: "gpt-test",
    inputTokens: 10,
    outputTokens: 5,
    cacheCreation: 0,
    cacheRead: 0,
    reasoningTokens: 0,
    createdAt: "2026-05-14T01:00:00.000Z",
    messageId: "msg-shared",
  )

  #expect(try db.insertUsage(claudeRecord) == true)
  #expect(try db.insertUsage(codexRecord) == true)

  #expect(try db.usageRecordCount() == 2)
}

@Test func databaseMaintainsRollupsWhenMergingClaudeUsageRecords() throws {
  let dataDir = try makeTokMonTempDir()
  let db = try TokMonDatabase(appDataDir: dataDir)
  let partial = TokMonUsageRecord(
    source: "claude-code",
    sessionId: "session-1",
    model: "claude-test",
    inputTokens: 1000,
    outputTokens: 0,
    cacheCreation: 0,
    cacheRead: 0,
    reasoningTokens: 0,
    createdAt: "2026-05-14T01:00:00.000Z",
    messageId: "msg-rollup",
  )
  let later = TokMonUsageRecord(
    source: "claude-code",
    sessionId: "session-1",
    model: "claude-test",
    inputTokens: 1000,
    outputTokens: 500,
    cacheCreation: 200,
    cacheRead: 50,
    reasoningTokens: 0,
    createdAt: "2026-05-14T01:00:01.000Z",
    messageId: "msg-rollup",
  )

  #expect(try db.insertUsage(partial) == true)
  #expect(try db.insertUsage(later) == true)

  let summary = try TokMonQueryStore(database: db).summary(
    filter: TokMonQueryFilter(
      from: "2026-05-14 00:00:00",
      to: "2026-05-15 00:00:00",
      sources: ["claude-code"],
      model: nil
    )
  )
  #expect(summary.total.totalRequests == 1)
  #expect(summary.total.totalInput == 1000)
  #expect(summary.total.totalOutput == 500)
  #expect(summary.total.totalCacheCreation == 200)
  #expect(summary.total.totalCacheRead == 50)
}

@Test func databaseReturnsFalseForIdenticalClaudeUsageMerge() throws {
  let dataDir = try makeTokMonTempDir()
  let db = try TokMonDatabase(appDataDir: dataDir)
  let record = TokMonUsageRecord(
    source: "claude-code",
    sessionId: "session-1",
    model: "claude-test",
    inputTokens: 100,
    outputTokens: 50,
    cacheCreation: 0,
    cacheRead: 0,
    reasoningTokens: 0,
    createdAt: "2026-05-14T01:00:00.000Z",
    messageId: "msg-identical",
  )

  #expect(try db.insertUsage(record) == true)
  #expect(try db.insertUsage(record) == false)
  #expect(try db.usageRecordCount() == 1)
}

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
  let databaseURL = dataDir.appendingPathComponent("tokmon.db")
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

@Test func databasePrunesDuplicateOpenCodeProviderPrefixedUsageRecords() throws {
  let dataDir = try makeTokMonTempDir()
  let databaseURL = dataDir.appendingPathComponent("tokmon.db")
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
        ('opencode', 'ses_qwen', 'litellm/qwen3.6-35b', 123, 45, 0, 0, 6, '2026-05-20T01:20:11.000Z'),
        ('opencode', 'ses_qwen', 'qwen3.6-35b', 123, 45, 0, 0, 6, '2026-05-20T01:20:10.000Z');
    """)
  }

  let db = try TokMonDatabase(appDataDir: dataDir)
  let records = try db.allUsageRecords()

  #expect(records.count == 1)
  #expect(records.first?.model == "qwen3.6-35b")
  #expect(try db.queryInt("SELECT COALESCE(SUM(requests), 0) FROM tokmon_usage_rollups") == 4)
}

@Test func databaseKeepsOpenCodeProviderPrefixedRecordsWithDifferentTimestamps() throws {
  let dataDir = try makeTokMonTempDir()
  let databaseURL = dataDir.appendingPathComponent("tokmon.db")
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
        ('opencode', 'ses_qwen', 'litellm/qwen3.6-35b', 123, 45, 0, 0, 6, '2026-05-20T01:30:10.000Z'),
        ('opencode', 'ses_qwen', 'qwen3.6-35b', 123, 45, 0, 0, 6, '2026-05-20T01:20:10.000Z');
    """)
  }

  let db = try TokMonDatabase(appDataDir: dataDir)
  let records = try db.allUsageRecords()

  #expect(records.count == 2)
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

@Test func databaseLockProtectsConcurrentAccess() throws {
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
    createdAt: "2026-05-14T01:00:00.000Z"
  )

  let group = DispatchGroup()
  var errors: [Error] = []
  let errorLock = NSLock()

  for _ in 0..<20 {
    group.enter()
    DispatchQueue.global().async {
      do {
        _ = try db.insertUsage(record)
      } catch {
        errorLock.lock()
        errors.append(error)
        errorLock.unlock()
      }
      group.leave()
    }
  }

  group.wait()
  #expect(errors.isEmpty, "Concurrent inserts should not throw: \(errors)")
  #expect(try db.usageRecordCount() == 1, "Duplicate inserts should be ignored")
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
