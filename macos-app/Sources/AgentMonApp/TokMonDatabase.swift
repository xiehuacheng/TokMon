import Foundation
import SQLite3

final class TokMonDatabase {
  private var connection: OpaquePointer?

  convenience init(appDataDir: URL) throws {
    try FileManager.default.createDirectory(at: appDataDir, withIntermediateDirectories: true)
    try self.init(databaseURL: appDataDir.appendingPathComponent("agentmon.db"))
  }

  init(databaseURL: URL) throws {
    if !databaseURL.isFileURL {
      throw TokMonDatabaseError.openFailed("Database URL must be a file URL: \(databaseURL.absoluteString)")
    }
    try FileManager.default.createDirectory(
      at: databaseURL.deletingLastPathComponent(),
      withIntermediateDirectories: true,
    )

    var db: OpaquePointer?
    guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK, let db else {
      let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
      if let db {
        sqlite3_close(db)
      }
      throw TokMonDatabaseError.openFailed(message)
    }

    connection = db
    do {
      try configureConnection()
      try initializeSchema()
    } catch {
      sqlite3_close(db)
      connection = nil
      throw error
    }
  }

  deinit {
    if let connection {
      sqlite3_close(connection)
    }
  }

  func tableExists(_ name: String) throws -> Bool {
    let statement = try prepare("""
      SELECT 1
      FROM sqlite_master
      WHERE type = 'table' AND name = ?
      LIMIT 1
    """)
    defer { sqlite3_finalize(statement) }

    try bind(name, at: 1, in: statement)
    let result = sqlite3_step(statement)
    if result == SQLITE_ROW {
      return true
    }
    guard result == SQLITE_DONE else {
      throw TokMonDatabaseError.sqlite(lastErrorMessage)
    }
    return false
  }

  func insertUsage(_ record: TokMonUsageRecord) throws -> Bool {
    let statement = try prepare("""
      INSERT OR IGNORE INTO usage_records
        (source, session_id, model, input_tokens, output_tokens, cache_creation, cache_read, reasoning_tokens, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    """)
    defer { sqlite3_finalize(statement) }

    try bind(record.source, at: 1, in: statement)
    try bind(record.sessionId, at: 2, in: statement)
    try bind(record.model, at: 3, in: statement)
    try bind(record.inputTokens, at: 4, in: statement)
    try bind(record.outputTokens, at: 5, in: statement)
    try bind(record.cacheCreation, at: 6, in: statement)
    try bind(record.cacheRead, at: 7, in: statement)
    try bind(record.reasoningTokens, at: 8, in: statement)
    try bind(record.createdAt, at: 9, in: statement)
    try stepDone(statement)

    return sqlite3_changes(requiredConnection) > 0
  }

  func usageRecordCount() throws -> Int {
    try integerValue("SELECT COUNT(*) FROM usage_records")
  }

  func scanState(filePath: String) throws -> TokMonScanState {
    let statement = try prepare("""
      SELECT last_offset, session_id, model, last_usage_key
      FROM tokmon_scan_state
      WHERE file_path = ?
    """)
    defer { sqlite3_finalize(statement) }

    try bind(filePath, at: 1, in: statement)

    let result = sqlite3_step(statement)
    guard result == SQLITE_ROW else {
      guard result == SQLITE_DONE else {
        throw TokMonDatabaseError.sqlite(lastErrorMessage)
      }
      return .empty
    }

    return TokMonScanState(
      offset: sqlite3_column_int64(statement, 0),
      sessionId: stringColumn(statement, index: 1),
      model: stringColumn(statement, index: 2),
      lastUsageKey: stringColumn(statement, index: 3),
    )
  }

  func setScanState(filePath: String, state: TokMonScanState) throws {
    let statement = try prepare("""
      INSERT INTO tokmon_scan_state (file_path, last_offset, session_id, model, last_usage_key)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(file_path) DO UPDATE SET
        last_offset = excluded.last_offset,
        session_id = excluded.session_id,
        model = excluded.model,
        last_usage_key = excluded.last_usage_key,
        updated_at = datetime('now')
    """)
    defer { sqlite3_finalize(statement) }

    try bind(filePath, at: 1, in: statement)
    try bind(state.offset, at: 2, in: statement)
    try bind(state.sessionId, at: 3, in: statement)
    try bind(state.model, at: 4, in: statement)
    try bind(state.lastUsageKey, at: 5, in: statement)
    try stepDone(statement)
  }

  func rebuildTokMonData() throws {
    try exec("BEGIN IMMEDIATE;")
    do {
      try exec("DELETE FROM usage_records;")
      try exec("DELETE FROM tokmon_scan_state;")
      try exec("COMMIT;")
    } catch {
      try? exec("ROLLBACK;")
      throw error
    }
  }

  func allUsageRecords() throws -> [TokMonUsageRecord] {
    let statement = try prepare("""
      SELECT source, session_id, model, input_tokens, output_tokens, cache_creation, cache_read, reasoning_tokens, created_at
      FROM usage_records
      ORDER BY created_at ASC, id ASC
    """)
    defer { sqlite3_finalize(statement) }

    var records: [TokMonUsageRecord] = []
    var result = sqlite3_step(statement)
    while result == SQLITE_ROW {
      records.append(TokMonUsageRecord(
        source: stringColumn(statement, index: 0) ?? "",
        sessionId: stringColumn(statement, index: 1) ?? "",
        model: stringColumn(statement, index: 2) ?? "unknown",
        inputTokens: Int(sqlite3_column_int64(statement, 3)),
        outputTokens: Int(sqlite3_column_int64(statement, 4)),
        cacheCreation: Int(sqlite3_column_int64(statement, 5)),
        cacheRead: Int(sqlite3_column_int64(statement, 6)),
        reasoningTokens: Int(sqlite3_column_int64(statement, 7)),
        createdAt: stringColumn(statement, index: 8) ?? "",
      ))
      result = sqlite3_step(statement)
    }

    guard result == SQLITE_DONE else {
      throw TokMonDatabaseError.sqlite(lastErrorMessage)
    }

    return records
  }

  func queryRows<T>(_ sql: String, params: [TokMonSQLValue] = [], map: (TokMonSQLRow) throws -> T) throws -> [T] {
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }

    for (offset, param) in params.enumerated() {
      try bind(param, at: Int32(offset + 1), in: statement)
    }

    var rows: [T] = []
    var result = sqlite3_step(statement)
    while result == SQLITE_ROW {
      rows.append(try map(TokMonSQLRow(statement: statement)))
      result = sqlite3_step(statement)
    }

    guard result == SQLITE_DONE else {
      throw TokMonDatabaseError.sqlite(lastErrorMessage)
    }

    return rows
  }

  func queryInt(_ sql: String, params: [TokMonSQLValue] = []) throws -> Int {
    try queryRows(sql, params: params) { row in
      row.int(0)
    }.first ?? 0
  }

  private var requiredConnection: OpaquePointer {
    guard let connection else {
      preconditionFailure("TokMonDatabase connection is closed")
    }
    return connection
  }

  private func initializeSchema() throws {
    try exec("PRAGMA journal_mode = WAL;")
    try exec("""
      CREATE TABLE IF NOT EXISTS usage_records (
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

      CREATE TABLE IF NOT EXISTS tokmon_scan_state (
        file_path TEXT PRIMARY KEY,
        last_offset INTEGER NOT NULL DEFAULT 0,
        session_id TEXT,
        model TEXT,
        last_usage_key TEXT,
        updated_at TEXT DEFAULT (datetime('now'))
      );
    """)
    try migrateTokMonScanState()
    try exec("""

      CREATE INDEX IF NOT EXISTS idx_usage_source ON usage_records(source);
      CREATE INDEX IF NOT EXISTS idx_usage_created ON usage_records(created_at);
      CREATE INDEX IF NOT EXISTS idx_usage_session ON usage_records(session_id);
      CREATE INDEX IF NOT EXISTS idx_usage_model ON usage_records(model);
    """)
  }

  private func configureConnection() throws {
    guard sqlite3_busy_timeout(requiredConnection, 5_000) == SQLITE_OK else {
      throw TokMonDatabaseError.sqlite(lastErrorMessage)
    }
  }

  private func migrateTokMonScanState() throws {
    try addColumnIfMissing(
      table: "tokmon_scan_state",
      column: "session_id",
      definition: "session_id TEXT",
    )
    try addColumnIfMissing(
      table: "tokmon_scan_state",
      column: "model",
      definition: "model TEXT",
    )
    try addColumnIfMissing(
      table: "tokmon_scan_state",
      column: "last_usage_key",
      definition: "last_usage_key TEXT",
    )
  }

  private func addColumnIfMissing(table: String, column: String, definition: String) throws {
    guard try !columnExists(table: table, column: column) else {
      return
    }
    try exec("ALTER TABLE \(table) ADD COLUMN \(definition);")
  }

  private func columnExists(table: String, column: String) throws -> Bool {
    let statement = try prepare("PRAGMA table_info(\(table))")
    defer { sqlite3_finalize(statement) }

    var result = sqlite3_step(statement)
    while result == SQLITE_ROW {
      if stringColumn(statement, index: 1) == column {
        return true
      }
      result = sqlite3_step(statement)
    }

    guard result == SQLITE_DONE else {
      throw TokMonDatabaseError.sqlite(lastErrorMessage)
    }
    return false
  }

  private func exec(_ sql: String) throws {
    var errorMessage: UnsafeMutablePointer<CChar>?
    let result = sqlite3_exec(requiredConnection, sql, nil, nil, &errorMessage)
    if result != SQLITE_OK {
      let message = errorMessage.map { String(cString: $0) } ?? lastErrorMessage
      sqlite3_free(errorMessage)
      throw TokMonDatabaseError.sqlite(message)
    }
  }

  private func prepare(_ sql: String) throws -> OpaquePointer? {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(requiredConnection, sql, -1, &statement, nil) == SQLITE_OK else {
      throw TokMonDatabaseError.sqlite(lastErrorMessage)
    }
    return statement
  }

  private func stepDone(_ statement: OpaquePointer?) throws {
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw TokMonDatabaseError.sqlite(lastErrorMessage)
    }
  }

  private func integerValue(_ sql: String) throws -> Int {
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }

    let result = sqlite3_step(statement)
    guard result == SQLITE_ROW else {
      guard result == SQLITE_DONE else {
        throw TokMonDatabaseError.sqlite(lastErrorMessage)
      }
      return 0
    }
    return Int(sqlite3_column_int64(statement, 0))
  }

  private func bind(_ value: String, at index: Int32, in statement: OpaquePointer?) throws {
    guard sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
      throw TokMonDatabaseError.sqlite(lastErrorMessage)
    }
  }

  private func bind(_ value: String?, at index: Int32, in statement: OpaquePointer?) throws {
    guard let value else {
      try bindNull(at: index, in: statement)
      return
    }
    try bind(value, at: index, in: statement)
  }

  private func bind(_ value: Int, at index: Int32, in statement: OpaquePointer?) throws {
    guard sqlite3_bind_int64(statement, index, sqlite3_int64(value)) == SQLITE_OK else {
      throw TokMonDatabaseError.sqlite(lastErrorMessage)
    }
  }

  private func bind(_ value: Int64, at index: Int32, in statement: OpaquePointer?) throws {
    guard sqlite3_bind_int64(statement, index, sqlite3_int64(value)) == SQLITE_OK else {
      throw TokMonDatabaseError.sqlite(lastErrorMessage)
    }
  }

  private func bind(_ value: TokMonSQLValue, at index: Int32, in statement: OpaquePointer?) throws {
    switch value {
    case .text(let text):
      try bind(text, at: index, in: statement)
    case .int(let int):
      try bind(int, at: index, in: statement)
    }
  }

  private func bindNull(at index: Int32, in statement: OpaquePointer?) throws {
    guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
      throw TokMonDatabaseError.sqlite(lastErrorMessage)
    }
  }

  private func stringColumn(_ statement: OpaquePointer?, index: Int32) -> String? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
      return nil
    }
    guard let rawValue = sqlite3_column_text(statement, index) else {
      return nil
    }
    return String(cString: rawValue)
  }

  private var lastErrorMessage: String {
    String(cString: sqlite3_errmsg(requiredConnection))
  }
}

private enum TokMonDatabaseError: LocalizedError {
  case openFailed(String)
  case sqlite(String)

  var errorDescription: String? {
    switch self {
    case .openFailed(let message):
      "Unable to open TokMon database: \(message)"
    case .sqlite(let message):
      "TokMon database error: \(message)"
    }
  }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum TokMonSQLValue {
  case text(String)
  case int(Int)
}

struct TokMonSQLRow {
  fileprivate let statement: OpaquePointer?

  func string(_ index: Int32) -> String {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
      return ""
    }
    guard let rawValue = sqlite3_column_text(statement, index) else {
      return ""
    }
    return String(cString: rawValue)
  }

  func int(_ index: Int32) -> Int {
    Int(sqlite3_column_int64(statement, index))
  }
}
