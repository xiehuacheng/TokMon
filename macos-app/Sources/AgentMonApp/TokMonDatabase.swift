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

    let inserted = sqlite3_changes(requiredConnection) > 0
    if inserted {
      try upsertUsageRollups(for: record)
    }
    return inserted
  }

  func upsertSessionMetadata(_ metadata: TokMonSessionMetadata) throws {
    let statement = try prepare("""
      INSERT INTO tokmon_session_metadata
        (id, source, title, first_prompt, last_prompt, model, started_at, last_active_at, file_path, project_path)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(source, id) DO UPDATE SET
        title = COALESCE(excluded.title, tokmon_session_metadata.title),
        first_prompt = CASE
          WHEN excluded.first_prompt IS NOT NULL THEN excluded.first_prompt
          ELSE tokmon_session_metadata.first_prompt
        END,
        last_prompt = CASE
          WHEN excluded.last_prompt IS NOT NULL THEN excluded.last_prompt
          ELSE tokmon_session_metadata.last_prompt
        END,
        model = COALESCE(excluded.model, tokmon_session_metadata.model),
        started_at = CASE
          WHEN excluded.started_at IS NOT NULL THEN excluded.started_at
          ELSE tokmon_session_metadata.started_at
        END,
        last_active_at = CASE
          WHEN excluded.last_active_at IS NOT NULL THEN excluded.last_active_at
          ELSE tokmon_session_metadata.last_active_at
        END,
        file_path = CASE
          WHEN excluded.file_path IS NOT NULL THEN excluded.file_path
          ELSE tokmon_session_metadata.file_path
        END,
        project_path = CASE
          WHEN excluded.project_path IS NOT NULL THEN excluded.project_path
          ELSE tokmon_session_metadata.project_path
        END,
        updated_at = datetime('now')
    """)
    defer { sqlite3_finalize(statement) }

    try bind(metadata.id, at: 1, in: statement)
    try bind(metadata.source, at: 2, in: statement)
    try bind(metadata.title, at: 3, in: statement)
    try bind(metadata.firstPrompt, at: 4, in: statement)
    try bind(metadata.lastPrompt, at: 5, in: statement)
    try bind(metadata.model, at: 6, in: statement)
    try bind(metadata.startedAt, at: 7, in: statement)
    try bind(metadata.lastActiveAt, at: 8, in: statement)
    try bind(metadata.filePath, at: 9, in: statement)
    try bind(metadata.projectPath, at: 10, in: statement)
    try stepDone(statement)
  }

  func sessionMetadata(source: String, id: String) throws -> TokMonSessionMetadata? {
    let statement = try prepare("""
      SELECT id, source, title, first_prompt, last_prompt, model, started_at, last_active_at, file_path, project_path
      FROM tokmon_session_metadata
      WHERE source = ? AND id = ?
    """)
    defer { sqlite3_finalize(statement) }

    try bind(source, at: 1, in: statement)
    try bind(id, at: 2, in: statement)

    let result = sqlite3_step(statement)
    guard result == SQLITE_ROW else {
      guard result == SQLITE_DONE else {
        throw TokMonDatabaseError.sqlite(lastErrorMessage)
      }
      return nil
    }

    return TokMonSessionMetadata(
      id: stringColumn(statement, index: 0) ?? "",
      source: stringColumn(statement, index: 1) ?? "",
      title: stringColumn(statement, index: 2),
      firstPrompt: stringColumn(statement, index: 3),
      lastPrompt: stringColumn(statement, index: 4),
      model: stringColumn(statement, index: 5),
      startedAt: stringColumn(statement, index: 6),
      lastActiveAt: stringColumn(statement, index: 7),
      filePath: stringColumn(statement, index: 8),
      projectPath: stringColumn(statement, index: 9),
    )
  }

  func usageRecordCount() throws -> Int {
    try integerValue("SELECT COUNT(*) FROM usage_records")
  }

  func scanState(filePath: String) throws -> TokMonScanState {
    let statement = try prepare("""
      SELECT last_offset, session_id, model, last_usage_key, last_mtime
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
      lastMtime: stringColumn(statement, index: 4),
    )
  }

  func setScanState(filePath: String, state: TokMonScanState) throws {
    let statement = try prepare("""
      INSERT INTO tokmon_scan_state (file_path, last_offset, session_id, model, last_usage_key, last_mtime)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(file_path) DO UPDATE SET
        last_offset = excluded.last_offset,
        session_id = excluded.session_id,
        model = excluded.model,
        last_usage_key = excluded.last_usage_key,
        last_mtime = excluded.last_mtime,
        updated_at = datetime('now')
    """)
    defer { sqlite3_finalize(statement) }

    try bind(filePath, at: 1, in: statement)
    try bind(state.offset, at: 2, in: statement)
    try bind(state.sessionId, at: 3, in: statement)
    try bind(state.model, at: 4, in: statement)
    try bind(state.lastUsageKey, at: 5, in: statement)
    try bind(state.lastMtime, at: 6, in: statement)
    try stepDone(statement)
  }

  func rebuildTokMonData() throws {
    try exec("BEGIN IMMEDIATE;")
    do {
      try exec("DELETE FROM usage_records;")
      try exec("DELETE FROM tokmon_scan_state;")
      try exec("DELETE FROM tokmon_session_metadata;")
      try exec("DELETE FROM tokmon_usage_rollups;")
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
        last_mtime TEXT,
        updated_at TEXT DEFAULT (datetime('now'))
      );

      CREATE TABLE IF NOT EXISTS tokmon_session_metadata (
        id TEXT NOT NULL,
        source TEXT NOT NULL,
        title TEXT,
        first_prompt TEXT,
        last_prompt TEXT,
        model TEXT,
        started_at TEXT,
        last_active_at TEXT,
        file_path TEXT,
        project_path TEXT,
        updated_at TEXT DEFAULT (datetime('now')),
        PRIMARY KEY(source, id)
      );

      CREATE TABLE IF NOT EXISTS tokmon_usage_rollups (
        grain TEXT NOT NULL,
        period_start TEXT NOT NULL,
        source TEXT NOT NULL,
        model TEXT NOT NULL,
        requests INTEGER NOT NULL DEFAULT 0,
        input_tokens INTEGER NOT NULL DEFAULT 0,
        output_tokens INTEGER NOT NULL DEFAULT 0,
        cache_creation INTEGER NOT NULL DEFAULT 0,
        cache_read INTEGER NOT NULL DEFAULT 0,
        reasoning_tokens INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(grain, period_start, source, model)
      );
    """)
    try addColumnIfMissing(
      table: "tokmon_session_metadata",
      column: "project_path",
      definition: "project_path TEXT",
    )
    try migrateTokMonScanState()
    try backfillUsageRollupsIfNeeded()
    try exec("""

      CREATE INDEX IF NOT EXISTS idx_usage_source ON usage_records(source);
      CREATE INDEX IF NOT EXISTS idx_usage_created ON usage_records(created_at);
      CREATE INDEX IF NOT EXISTS idx_usage_session ON usage_records(session_id);
      CREATE INDEX IF NOT EXISTS idx_usage_model ON usage_records(model);
      CREATE INDEX IF NOT EXISTS idx_tokmon_session_metadata_file ON tokmon_session_metadata(file_path);
      CREATE INDEX IF NOT EXISTS idx_tokmon_usage_rollups_scope ON tokmon_usage_rollups(grain, period_start, source, model);
    """)
  }

  private func upsertUsageRollups(for record: TokMonUsageRecord) throws {
    let periods = try rollupPeriods(for: record.createdAt)
    for period in periods {
      let statement = try prepare("""
        INSERT INTO tokmon_usage_rollups
          (grain, period_start, source, model, requests, input_tokens, output_tokens, cache_creation, cache_read, reasoning_tokens)
        VALUES (?, ?, ?, ?, 1, ?, ?, ?, ?, ?)
        ON CONFLICT(grain, period_start, source, model) DO UPDATE SET
          requests = tokmon_usage_rollups.requests + 1,
          input_tokens = tokmon_usage_rollups.input_tokens + excluded.input_tokens,
          output_tokens = tokmon_usage_rollups.output_tokens + excluded.output_tokens,
          cache_creation = tokmon_usage_rollups.cache_creation + excluded.cache_creation,
          cache_read = tokmon_usage_rollups.cache_read + excluded.cache_read,
          reasoning_tokens = tokmon_usage_rollups.reasoning_tokens + excluded.reasoning_tokens
      """)
      defer { sqlite3_finalize(statement) }

      try bind(period.grain, at: 1, in: statement)
      try bind(period.start, at: 2, in: statement)
      try bind(record.source, at: 3, in: statement)
      try bind(record.model, at: 4, in: statement)
      try bind(record.inputTokens, at: 5, in: statement)
      try bind(record.outputTokens, at: 6, in: statement)
      try bind(record.cacheCreation, at: 7, in: statement)
      try bind(record.cacheRead, at: 8, in: statement)
      try bind(record.reasoningTokens, at: 9, in: statement)
      try stepDone(statement)
    }
  }

  private func rollupPeriods(for createdAt: String) throws -> [(grain: String, start: String)] {
    let rows = try queryRows("""
      SELECT datetime(?, 'localtime', 'start of day') as day_start,
             datetime(?, 'localtime', 'start of day', '-' || ((strftime('%w', datetime(?, 'localtime')) + 6) % 7) || ' days') as week_start,
             datetime(?, 'localtime', 'start of month') as month_start,
             datetime(?, 'localtime', 'start of year') as year_start
    """, params: [
      .text(createdAt),
      .text(createdAt),
      .text(createdAt),
      .text(createdAt),
      .text(createdAt),
    ]) { row in
      [
        ("day", row.string(0)),
        ("week", row.string(1)),
        ("month", row.string(2)),
        ("year", row.string(3)),
      ]
    }

    guard let periods = rows.first, periods.allSatisfy({ !$0.1.isEmpty }) else {
      throw TokMonDatabaseError.sqlite("Unable to resolve rollup periods for \(createdAt)")
    }
    return periods
  }

  private func backfillUsageRollupsIfNeeded() throws {
    guard try queryInt("SELECT COUNT(*) FROM usage_records") > 0,
          try queryInt("SELECT COUNT(*) FROM tokmon_usage_rollups") == 0 else {
      return
    }

    try exec("""
      INSERT INTO tokmon_usage_rollups
        (grain, period_start, source, model, requests, input_tokens, output_tokens, cache_creation, cache_read, reasoning_tokens)
      SELECT 'day',
             datetime(created_at, 'localtime', 'start of day'),
             source,
             model,
             COUNT(*),
             COALESCE(SUM(input_tokens), 0),
             COALESCE(SUM(output_tokens), 0),
             COALESCE(SUM(cache_creation), 0),
             COALESCE(SUM(cache_read), 0),
             COALESCE(SUM(reasoning_tokens), 0)
      FROM usage_records
      GROUP BY 2, source, model;

      INSERT INTO tokmon_usage_rollups
        (grain, period_start, source, model, requests, input_tokens, output_tokens, cache_creation, cache_read, reasoning_tokens)
      SELECT 'week',
             datetime(created_at, 'localtime', 'start of day', '-' || ((strftime('%w', datetime(created_at, 'localtime')) + 6) % 7) || ' days'),
             source,
             model,
             COUNT(*),
             COALESCE(SUM(input_tokens), 0),
             COALESCE(SUM(output_tokens), 0),
             COALESCE(SUM(cache_creation), 0),
             COALESCE(SUM(cache_read), 0),
             COALESCE(SUM(reasoning_tokens), 0)
      FROM usage_records
      GROUP BY 2, source, model;

      INSERT INTO tokmon_usage_rollups
        (grain, period_start, source, model, requests, input_tokens, output_tokens, cache_creation, cache_read, reasoning_tokens)
      SELECT 'month',
             datetime(created_at, 'localtime', 'start of month'),
             source,
             model,
             COUNT(*),
             COALESCE(SUM(input_tokens), 0),
             COALESCE(SUM(output_tokens), 0),
             COALESCE(SUM(cache_creation), 0),
             COALESCE(SUM(cache_read), 0),
             COALESCE(SUM(reasoning_tokens), 0)
      FROM usage_records
      GROUP BY 2, source, model;

      INSERT INTO tokmon_usage_rollups
        (grain, period_start, source, model, requests, input_tokens, output_tokens, cache_creation, cache_read, reasoning_tokens)
      SELECT 'year',
             datetime(created_at, 'localtime', 'start of year'),
             source,
             model,
             COUNT(*),
             COALESCE(SUM(input_tokens), 0),
             COALESCE(SUM(output_tokens), 0),
             COALESCE(SUM(cache_creation), 0),
             COALESCE(SUM(cache_read), 0),
             COALESCE(SUM(reasoning_tokens), 0)
      FROM usage_records
      GROUP BY 2, source, model;
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
    try addColumnIfMissing(
      table: "tokmon_scan_state",
      column: "last_mtime",
      definition: "last_mtime TEXT",
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
