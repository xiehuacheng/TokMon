import Foundation
import SQLite3
import Testing
@testable import AgentMonApp

@Test func databaseCreatesUsageAndScanStateTables() throws {
  let dataDir = try makeTokMonTempDir()
  let db = try TokMonDatabase(appDataDir: dataDir)

  #expect(try db.tableExists("usage_records"))
  #expect(try db.tableExists("tokmon_scan_state"))
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
  try db.setScanState(filePath: "/tmp/claude.jsonl", state: TokMonScanState(offset: 42, sessionId: "claude-1", model: nil, lastUsageKey: "key"))

  try db.rebuildTokMonData()

  #expect(try db.usageRecordCount() == 0)
  #expect(try db.scanState(filePath: "/tmp/claude.jsonl") == .empty)
}

@Test func databaseMigratesLegacyScanStateColumns() throws {
  let dataDir = try makeTokMonTempDir()
  let databaseURL = dataDir.appendingPathComponent("agentmon.db")
  try withRawSQLiteDatabase(at: databaseURL) { db in
    try rawSQLiteExec(db, """
      CREATE TABLE tokmon_scan_state (
        file_path TEXT PRIMARY KEY,
        last_offset INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT DEFAULT (datetime('now'))
      );
      INSERT INTO tokmon_scan_state (file_path, last_offset)
      VALUES ('/tmp/legacy.jsonl', 24);
    """)
  }

  let db = try TokMonDatabase(appDataDir: dataDir)
  let legacyState = try db.scanState(filePath: "/tmp/legacy.jsonl")
  try db.setScanState(
    filePath: "/tmp/legacy.jsonl",
    state: TokMonScanState(offset: 48, sessionId: "session-legacy", model: "gpt-legacy", lastUsageKey: "legacy-key"),
  )
  let migratedState = try db.scanState(filePath: "/tmp/legacy.jsonl")

  #expect(legacyState.offset == 24)
  #expect(legacyState.sessionId == nil)
  #expect(migratedState.offset == 48)
  #expect(migratedState.sessionId == "session-legacy")
  #expect(migratedState.model == "gpt-legacy")
  #expect(migratedState.lastUsageKey == "legacy-key")
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
