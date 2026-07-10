import Foundation
import SQLite3

final class TokMonDatabase {
  private var connection: OpaquePointer?
  private let lock = NSLock()
  private var _dataVersion: UInt64 = 0

  var dataVersion: UInt64 {
    lock.lock()
    defer { lock.unlock() }
    return _dataVersion
  }

  private func bumpDataVersion() {
    _dataVersion &+= 1
  }

  convenience init(appDataDir: URL) throws {
    try FileManager.default.createDirectory(at: appDataDir, withIntermediateDirectories: true)
    try self.init(databaseURL: appDataDir.appendingPathComponent("tokmon.db"))
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

  // MARK: - Public API (locked wrappers)

  func tableExists(_ name: String) throws -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return try _tableExists(name)
  }

  func insertUsage(_ record: TokMonUsageRecord) throws -> Bool {
    lock.lock()
    defer { lock.unlock() }
    let inserted = try _insertUsage(record)
    if inserted { bumpDataVersion() }
    return inserted
  }

  func upsertSessionMetadata(_ metadata: TokMonSessionMetadata) throws {
    lock.lock()
    defer { lock.unlock() }
    try _upsertSessionMetadata(metadata)
    bumpDataVersion()
  }

  func insertUsages(_ records: [TokMonUsageRecord]) throws -> Int {
    lock.lock()
    defer { lock.unlock() }
    let count = try _insertUsages(records)
    if count > 0 { bumpDataVersion() }
    return count
  }

  func upsertSessionMetadatas(_ metadatas: [TokMonSessionMetadata]) throws {
    lock.lock()
    defer { lock.unlock() }
    try _upsertSessionMetadatas(metadatas)
    if !metadatas.isEmpty { bumpDataVersion() }
  }

  func sessionMetadata(source: String, id: String) throws -> TokMonSessionMetadata? {
    lock.lock()
    defer { lock.unlock() }
    return try _sessionMetadata(source: source, id: id)
  }

  func hasSessionMetadataContainingEnvironmentContext(source: String, filePath: String) throws -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return try _hasSessionMetadataContainingEnvironmentContext(source: source, filePath: filePath)
  }

  func sessionIdsWithEnvironmentContext(source: String, filePath: String) throws -> [String] {
    lock.lock()
    defer { lock.unlock() }
    return try _sessionIdsWithEnvironmentContext(source: source, filePath: filePath)
  }

  func usageRecordCount() throws -> Int {
    lock.lock()
    defer { lock.unlock() }
    return try _usageRecordCount()
  }

  func scanState(filePath: String) throws -> TokMonScanState {
    lock.lock()
    defer { lock.unlock() }
    return try _scanState(filePath: filePath)
  }

  func setScanState(filePath: String, state: TokMonScanState) throws {
    lock.lock()
    defer { lock.unlock() }
    try _setScanState(filePath: filePath, state: state)
    bumpDataVersion()
  }

  func rebuildTokMonData() throws {
    lock.lock()
    defer { lock.unlock() }
    try _rebuildTokMonData()
    bumpDataVersion()
  }

  func allUsageRecords() throws -> [TokMonUsageRecord] {
    lock.lock()
    defer { lock.unlock() }
    return try _allUsageRecords()
  }

  func queryRows<T>(_ sql: String, params: [TokMonSQLValue] = [], map: (TokMonSQLRow) throws -> T) throws -> [T] {
    lock.lock()
    defer { lock.unlock() }
    return try _queryRows(sql, params: params, map: map)
  }

  func queryInt(_ sql: String, params: [TokMonSQLValue] = []) throws -> Int {
    lock.lock()
    defer { lock.unlock() }
    return try _queryInt(sql, params: params)
  }

  func replaceOpenCodeProviderPrefixedUsageRecordIfNeeded(
    with canonicalRecord: TokMonUsageRecord,
    provider: String?,
  ) throws -> Bool {
    lock.lock()
    defer { lock.unlock() }
    let replaced = try _replaceOpenCodeProviderPrefixedUsageRecordIfNeeded(
      with: canonicalRecord,
      provider: provider
    )
    if replaced { bumpDataVersion() }
    return replaced
  }

  // MARK: - Private implementations (lock must be held by caller)

  private func _tableExists(_ name: String) throws -> Bool {
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

  private func _insertUsage(
    _ record: TokMonUsageRecord,
    reusingInsertStatement reusableStatement: OpaquePointer? = nil
  ) throws -> Bool {
    if let messageId = record.messageId, !messageId.isEmpty,
       let existing = try _existingUsageRecord(source: record.source, sessionId: record.sessionId, messageId: messageId) {
      let merged = TokMonUsageRecord.claudeRecordByRecency(existing, record)
      guard merged != existing else { return false }
      try subtractUsageRollups(for: existing)
      try _updateUsageRecord(merged)
      try upsertUsageRollups(for: merged)
      return true
    }
    return try _insertNewUsage(record, reusingInsertStatement: reusableStatement)
  }

  private func _insertNewUsage(
    _ record: TokMonUsageRecord,
    reusingInsertStatement reusableStatement: OpaquePointer? = nil
  ) throws -> Bool {
    let statement: OpaquePointer?
    let shouldFinalize: Bool
    if let reusableStatement {
      statement = reusableStatement
      shouldFinalize = false
      sqlite3_reset(statement)
      sqlite3_clear_bindings(statement)
    } else {
      statement = try prepare("""
        INSERT OR IGNORE INTO usage_records
          (source, session_id, model, input_tokens, output_tokens, cache_creation, cache_read, reasoning_tokens, created_at, cache_hit_supported, session_file_suffix, message_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """)
      shouldFinalize = true
    }
    defer {
      if shouldFinalize {
        sqlite3_finalize(statement)
      }
    }

    try bind(record.source, at: 1, in: statement)
    try bind(record.sessionId, at: 2, in: statement)
    try bind(record.model, at: 3, in: statement)
    try bind(record.inputTokens, at: 4, in: statement)
    try bind(record.outputTokens, at: 5, in: statement)
    try bind(record.cacheCreation, at: 6, in: statement)
    try bind(record.cacheRead, at: 7, in: statement)
    try bind(record.reasoningTokens, at: 8, in: statement)
    try bind(record.createdAt, at: 9, in: statement)
    try bind(record.cacheHitSupported ? 1 : 0, at: 10, in: statement)
    try bind(sessionFileSuffix(for: record.sessionId), at: 11, in: statement)
    try bind(record.messageId, at: 12, in: statement)
    try stepDone(statement)

    let inserted = sqlite3_changes(requiredConnection) > 0
    if inserted {
      try upsertUsageRollups(for: record)
    }
    return inserted
  }

  private func _updateUsageRecord(_ record: TokMonUsageRecord) throws {
    let statement = try prepare("""
      UPDATE usage_records
      SET model = ?,
          input_tokens = ?,
          output_tokens = ?,
          cache_creation = ?,
          cache_read = ?,
          reasoning_tokens = ?,
          created_at = ?,
          cache_hit_supported = ?,
          session_file_suffix = ?
      WHERE source = ? AND session_id = ? AND message_id = ?
    """)
    defer { sqlite3_finalize(statement) }

    try bind(record.model, at: 1, in: statement)
    try bind(record.inputTokens, at: 2, in: statement)
    try bind(record.outputTokens, at: 3, in: statement)
    try bind(record.cacheCreation, at: 4, in: statement)
    try bind(record.cacheRead, at: 5, in: statement)
    try bind(record.reasoningTokens, at: 6, in: statement)
    try bind(record.createdAt, at: 7, in: statement)
    try bind(record.cacheHitSupported ? 1 : 0, at: 8, in: statement)
    try bind(sessionFileSuffix(for: record.sessionId), at: 9, in: statement)
    try bind(record.source, at: 10, in: statement)
    try bind(record.sessionId, at: 11, in: statement)
    try bind(record.messageId, at: 12, in: statement)
    try stepDone(statement)
  }

  private func _existingUsageRecord(source: String, sessionId: String, messageId: String) throws -> TokMonUsageRecord? {
    let statement = try prepare("""
      SELECT model, input_tokens, output_tokens, cache_creation, cache_read, reasoning_tokens, created_at, cache_hit_supported
      FROM usage_records
      WHERE source = ? AND session_id = ? AND message_id = ?
      LIMIT 1
    """)
    defer { sqlite3_finalize(statement) }

    try bind(source, at: 1, in: statement)
    try bind(sessionId, at: 2, in: statement)
    try bind(messageId, at: 3, in: statement)

    guard sqlite3_step(statement) == SQLITE_ROW else {
      return nil
    }

    return TokMonUsageRecord(
      source: source,
      sessionId: sessionId,
      model: stringColumn(statement, index: 0) ?? "unknown",
      inputTokens: Int(sqlite3_column_int64(statement, 1)),
      outputTokens: Int(sqlite3_column_int64(statement, 2)),
      cacheCreation: Int(sqlite3_column_int64(statement, 3)),
      cacheRead: Int(sqlite3_column_int64(statement, 4)),
      reasoningTokens: Int(sqlite3_column_int64(statement, 5)),
      createdAt: stringColumn(statement, index: 6) ?? "",
      cacheHitSupported: Int(sqlite3_column_int64(statement, 7)) != 0,
      messageId: messageId
    )
  }

  private func _upsertSessionMetadata(_ metadata: TokMonSessionMetadata) throws {
    let statement = try prepare("""
      INSERT INTO tokmon_session_metadata
        (id, source, title, first_prompt, last_prompt, model, started_at, last_active_at, file_path, project_path, session_file_suffix)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
        session_file_suffix = COALESCE(excluded.session_file_suffix, tokmon_session_metadata.session_file_suffix),
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
    try bind(sessionFileSuffix(for: metadata.id), at: 11, in: statement)
    try stepDone(statement)
  }

  private func _insertUsages(_ records: [TokMonUsageRecord]) throws -> Int {
    guard !records.isEmpty else { return 0 }

    let insertStatement = try prepare("""
      INSERT OR IGNORE INTO usage_records
        (source, session_id, model, input_tokens, output_tokens, cache_creation, cache_read, reasoning_tokens, created_at, cache_hit_supported, session_file_suffix, message_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """)
    defer { sqlite3_finalize(insertStatement) }

    try exec("BEGIN IMMEDIATE;")
    var count = 0
    do {
      for record in records {
        if try _insertUsage(record, reusingInsertStatement: insertStatement) {
          count += 1
        }
      }
      try exec("COMMIT;")
    } catch {
      try? exec("ROLLBACK;")
      throw error
    }
    return count
  }

  private func _upsertSessionMetadatas(_ metadatas: [TokMonSessionMetadata]) throws {
    guard !metadatas.isEmpty else { return }
    let statement = try prepare("""
      INSERT INTO tokmon_session_metadata
        (id, source, title, first_prompt, last_prompt, model, started_at, last_active_at, file_path, project_path, session_file_suffix)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
        session_file_suffix = COALESCE(excluded.session_file_suffix, tokmon_session_metadata.session_file_suffix),
        updated_at = datetime('now')
    """)
    defer { sqlite3_finalize(statement) }

    try exec("BEGIN IMMEDIATE;")
    do {
      for metadata in metadatas {
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
        try bind(sessionFileSuffix(for: metadata.id), at: 11, in: statement)
        try stepDone(statement)
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
      }
      try exec("COMMIT;")
    } catch {
      try? exec("ROLLBACK;")
      throw error
    }
  }

  private func _sessionMetadata(source: String, id: String) throws -> TokMonSessionMetadata? {
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

  private func _sessionIdsWithEnvironmentContext(source: String, filePath: String) throws -> [String] {
    let statement = try prepare("""
      SELECT id
      FROM tokmon_session_metadata
      WHERE source = ?
        AND file_path = ?
        AND (
          first_prompt LIKE '<environment_context>%'
          OR title LIKE '%<environment_context>%'
          OR last_prompt LIKE '<environment_context>%'
        )
    """)
    defer { sqlite3_finalize(statement) }

    try bind(source, at: 1, in: statement)
    try bind(filePath, at: 2, in: statement)

    var ids: [String] = []
    var result = sqlite3_step(statement)
    while result == SQLITE_ROW {
      if let id = stringColumn(statement, index: 0) {
        ids.append(id)
      }
      result = sqlite3_step(statement)
    }
    guard result == SQLITE_DONE else {
      throw TokMonDatabaseError.sqlite(lastErrorMessage)
    }
    return ids
  }

  private func _hasSessionMetadataContainingEnvironmentContext(source: String, filePath: String) throws -> Bool {
    let statement = try prepare("""
      SELECT 1
      FROM tokmon_session_metadata
      WHERE source = ?
        AND file_path = ?
        AND (
          first_prompt LIKE '<environment_context>%'
          OR title LIKE '%<environment_context>%'
          OR last_prompt LIKE '<environment_context>%'
        )
      LIMIT 1
    """)
    defer { sqlite3_finalize(statement) }

    try bind(source, at: 1, in: statement)
    try bind(filePath, at: 2, in: statement)

    let result = sqlite3_step(statement)
    if result == SQLITE_ROW {
      return true
    }
    guard result == SQLITE_DONE else {
      throw TokMonDatabaseError.sqlite(lastErrorMessage)
    }
    return false
  }

  private func _usageRecordCount() throws -> Int {
    try _queryInt("SELECT COUNT(*) FROM usage_records")
  }

  private func _scanState(filePath: String) throws -> TokMonScanState {
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

  private func _setScanState(filePath: String, state: TokMonScanState) throws {
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

  private func _rebuildTokMonData() throws {
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

  private func _allUsageRecords() throws -> [TokMonUsageRecord] {
    let statement = try prepare("""
      SELECT source, session_id, model, input_tokens, output_tokens, cache_creation, cache_read, reasoning_tokens, created_at, cache_hit_supported, message_id
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
        cacheHitSupported: Int(sqlite3_column_int64(statement, 9)) != 0,
        messageId: stringColumn(statement, index: 10),
      ))
      result = sqlite3_step(statement)
    }

    guard result == SQLITE_DONE else {
      throw TokMonDatabaseError.sqlite(lastErrorMessage)
    }

    return records
  }

  private func _queryRows<T>(_ sql: String, params: [TokMonSQLValue] = [], map: (TokMonSQLRow) throws -> T) throws -> [T] {
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

  private func _queryInt(_ sql: String, params: [TokMonSQLValue] = []) throws -> Int {
    try _queryRows(sql, params: params) { row in
      row.int(0)
    }.first ?? 0
  }

  private func _replaceOpenCodeProviderPrefixedUsageRecordIfNeeded(
    with canonicalRecord: TokMonUsageRecord,
    provider: String?,
  ) throws -> Bool {
    guard canonicalRecord.source == "opencode",
          let provider,
          !provider.isEmpty,
          !canonicalRecord.model.isEmpty,
          !canonicalRecord.model.contains("/") else {
      return false
    }

    let providerModel = "\(provider)/\(canonicalRecord.model)"
    let deletedRecords = try deleteOpenCodeUsageRecords(
      sessionId: canonicalRecord.sessionId,
      model: providerModel,
      inputTokens: canonicalRecord.inputTokens,
      outputTokens: canonicalRecord.outputTokens,
      cacheCreation: canonicalRecord.cacheCreation,
      cacheRead: canonicalRecord.cacheRead,
      reasoningTokens: canonicalRecord.reasoningTokens,
      canonicalCreatedAt: canonicalRecord.createdAt,
    )
    guard !deletedRecords.isEmpty else {
      return false
    }

    for oldRecord in deletedRecords {
      try subtractUsageRollups(for: oldRecord)
    }
    _ = try _insertUsage(canonicalRecord)
    return true
  }

  // MARK: - Schema

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
        cache_hit_supported INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        session_file_suffix TEXT,
        message_id TEXT,
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
        session_file_suffix TEXT,
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
        cache_hit_input_tokens INTEGER NOT NULL DEFAULT 0,
        cache_hit_cache_read INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(grain, period_start, source, model)
      );
    """)
    let addedUsageCacheSupport = try addColumnIfMissing(
      table: "usage_records",
      column: "cache_hit_supported",
      definition: "cache_hit_supported INTEGER NOT NULL DEFAULT 1",
    )
    _ = try addColumnIfMissing(
      table: "tokmon_session_metadata",
      column: "project_path",
      definition: "project_path TEXT",
    )
    let addedRollupCacheHitInput = try addColumnIfMissing(
      table: "tokmon_usage_rollups",
      column: "cache_hit_input_tokens",
      definition: "cache_hit_input_tokens INTEGER NOT NULL DEFAULT 0",
    )
    let addedRollupCacheHitRead = try addColumnIfMissing(
      table: "tokmon_usage_rollups",
      column: "cache_hit_cache_read",
      definition: "cache_hit_cache_read INTEGER NOT NULL DEFAULT 0",
    )
    let addedSessionFileSuffix = try addColumnIfMissing(
      table: "usage_records",
      column: "session_file_suffix",
      definition: "session_file_suffix TEXT",
    )
    _ = try addColumnIfMissing(
      table: "usage_records",
      column: "message_id",
      definition: "message_id TEXT",
    )
    let addedMetadataSessionFileSuffix = try addColumnIfMissing(
      table: "tokmon_session_metadata",
      column: "session_file_suffix",
      definition: "session_file_suffix TEXT",
    )
    if addedUsageCacheSupport || addedRollupCacheHitInput || addedRollupCacheHitRead {
      try rebuildUsageRollupsFromUsageRecords()
    } else {
      try backfillUsageRollupsIfNeeded()
    }
    if addedSessionFileSuffix {
      try exec("""
        UPDATE usage_records
        SET session_file_suffix = session_id || '.jsonl'
        WHERE session_file_suffix IS NULL
      """)
    }
    if addedMetadataSessionFileSuffix {
      try exec("""
        UPDATE tokmon_session_metadata
        SET session_file_suffix = id || '.jsonl'
        WHERE session_file_suffix IS NULL
      """)
    }
    try pruneDuplicateOpenCodeProviderUsageRecords()
    try exec("""

      CREATE INDEX IF NOT EXISTS idx_usage_source ON usage_records(source);
      CREATE INDEX IF NOT EXISTS idx_usage_created ON usage_records(created_at);
      CREATE INDEX IF NOT EXISTS idx_usage_session ON usage_records(session_id);
      CREATE INDEX IF NOT EXISTS idx_usage_model ON usage_records(model);
      CREATE INDEX IF NOT EXISTS idx_usage_source_created ON usage_records(source, created_at);
      CREATE INDEX IF NOT EXISTS idx_usage_model_valid ON usage_records(model) WHERE model != '' AND model != 'unknown' AND model != '<synthetic>';
      CREATE UNIQUE INDEX IF NOT EXISTS idx_usage_message_id
        ON usage_records(source, session_id, message_id)
        WHERE message_id IS NOT NULL AND message_id != '';
      CREATE INDEX IF NOT EXISTS idx_tokmon_session_metadata_file ON tokmon_session_metadata(file_path);
      CREATE INDEX IF NOT EXISTS idx_tokmon_session_metadata_suffix ON tokmon_session_metadata(source, session_file_suffix);
      CREATE INDEX IF NOT EXISTS idx_tokmon_usage_rollups_scope ON tokmon_usage_rollups(grain, period_start, source, model);
      CREATE INDEX IF NOT EXISTS idx_rollups_period ON tokmon_usage_rollups(period_start, grain, source, model);
    """)
  }

  // MARK: - Rollups

  private func subtractUsageRollups(for record: TokMonUsageRecord) throws {
    let periods = try rollupPeriods(for: record.createdAt)
    guard !periods.isEmpty else { return }

    let statement = try prepare("""
      INSERT INTO tokmon_usage_rollups
        (grain, period_start, source, model, requests, input_tokens, output_tokens, cache_creation, cache_read, reasoning_tokens, cache_hit_input_tokens, cache_hit_cache_read)
      VALUES (?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(grain, period_start, source, model) DO UPDATE SET
        requests = tokmon_usage_rollups.requests - 1,
        input_tokens = tokmon_usage_rollups.input_tokens - excluded.input_tokens,
        output_tokens = tokmon_usage_rollups.output_tokens - excluded.output_tokens,
        cache_creation = tokmon_usage_rollups.cache_creation - excluded.cache_creation,
        cache_read = tokmon_usage_rollups.cache_read - excluded.cache_read,
        reasoning_tokens = tokmon_usage_rollups.reasoning_tokens - excluded.reasoning_tokens,
        cache_hit_input_tokens = tokmon_usage_rollups.cache_hit_input_tokens - excluded.cache_hit_input_tokens,
        cache_hit_cache_read = tokmon_usage_rollups.cache_hit_cache_read - excluded.cache_hit_cache_read
    """)
    defer { sqlite3_finalize(statement) }

    for period in periods {
      try bind(period.grain, at: 1, in: statement)
      try bind(period.start, at: 2, in: statement)
      try bind(record.source, at: 3, in: statement)
      try bind(record.model, at: 4, in: statement)
      try bind(record.inputTokens, at: 5, in: statement)
      try bind(record.outputTokens, at: 6, in: statement)
      try bind(record.cacheCreation, at: 7, in: statement)
      try bind(record.cacheRead, at: 8, in: statement)
      try bind(record.reasoningTokens, at: 9, in: statement)
      try bind(record.cacheHitSupported ? record.inputTokens : 0, at: 10, in: statement)
      try bind(record.cacheHitSupported ? record.cacheRead : 0, at: 11, in: statement)
      try stepDone(statement)
      sqlite3_reset(statement)
      sqlite3_clear_bindings(statement)
    }
  }

  private func upsertUsageRollups(for record: TokMonUsageRecord) throws {
    let periods = try rollupPeriods(for: record.createdAt)
    guard !periods.isEmpty else { return }

    let statement = try prepare("""
      INSERT INTO tokmon_usage_rollups
        (grain, period_start, source, model, requests, input_tokens, output_tokens, cache_creation, cache_read, reasoning_tokens, cache_hit_input_tokens, cache_hit_cache_read)
      VALUES (?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(grain, period_start, source, model) DO UPDATE SET
        requests = tokmon_usage_rollups.requests + 1,
        input_tokens = tokmon_usage_rollups.input_tokens + excluded.input_tokens,
        output_tokens = tokmon_usage_rollups.output_tokens + excluded.output_tokens,
        cache_creation = tokmon_usage_rollups.cache_creation + excluded.cache_creation,
        cache_read = tokmon_usage_rollups.cache_read + excluded.cache_read,
        reasoning_tokens = tokmon_usage_rollups.reasoning_tokens + excluded.reasoning_tokens,
        cache_hit_input_tokens = tokmon_usage_rollups.cache_hit_input_tokens + excluded.cache_hit_input_tokens,
        cache_hit_cache_read = tokmon_usage_rollups.cache_hit_cache_read + excluded.cache_hit_cache_read
    """)
    defer { sqlite3_finalize(statement) }

    for period in periods {
      try bind(period.grain, at: 1, in: statement)
      try bind(period.start, at: 2, in: statement)
      try bind(record.source, at: 3, in: statement)
      try bind(record.model, at: 4, in: statement)
      try bind(record.inputTokens, at: 5, in: statement)
      try bind(record.outputTokens, at: 6, in: statement)
      try bind(record.cacheCreation, at: 7, in: statement)
      try bind(record.cacheRead, at: 8, in: statement)
      try bind(record.reasoningTokens, at: 9, in: statement)
      try bind(record.cacheHitSupported ? record.inputTokens : 0, at: 10, in: statement)
      try bind(record.cacheHitSupported ? record.cacheRead : 0, at: 11, in: statement)
      try stepDone(statement)
      sqlite3_reset(statement)
      sqlite3_clear_bindings(statement)
    }
  }

  private func rollupPeriods(for createdAt: String) throws -> [(grain: String, start: String)] {
    let rows = try _queryRows("""
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
    guard try _queryInt("SELECT COUNT(*) FROM usage_records") > 0,
          try _queryInt("SELECT COUNT(*) FROM tokmon_usage_rollups") == 0 else {
      return
    }

    try insertUsageRollupsFromUsageRecords()
  }

  private func pruneDuplicateOpenCodeProviderUsageRecords() throws {
    let selectStatement = try prepare("""
      SELECT source, session_id, model, input_tokens, output_tokens, cache_creation, cache_read, reasoning_tokens, created_at, cache_hit_supported
      FROM usage_records
      WHERE source = 'opencode'
        AND instr(model, '/') > 0
        AND EXISTS (
          SELECT 1
          FROM usage_records canonical
          WHERE canonical.source = usage_records.source
            AND canonical.session_id = usage_records.session_id
            AND canonical.model = substr(usage_records.model, instr(usage_records.model, '/') + 1)
            AND canonical.input_tokens = usage_records.input_tokens
            AND canonical.output_tokens = usage_records.output_tokens
            AND canonical.cache_creation = usage_records.cache_creation
            AND canonical.cache_read = usage_records.cache_read
            AND canonical.reasoning_tokens = usage_records.reasoning_tokens
            AND ABS(strftime('%s', canonical.created_at) - strftime('%s', usage_records.created_at)) <= 120
        )
    """)
    defer { sqlite3_finalize(selectStatement) }

    var recordsToDelete: [TokMonUsageRecord] = []
    var result = sqlite3_step(selectStatement)
    while result == SQLITE_ROW {
      recordsToDelete.append(TokMonUsageRecord(
        source: stringColumn(selectStatement, index: 0) ?? "opencode",
        sessionId: stringColumn(selectStatement, index: 1) ?? "",
        model: stringColumn(selectStatement, index: 2) ?? "unknown",
        inputTokens: Int(sqlite3_column_int64(selectStatement, 3)),
        outputTokens: Int(sqlite3_column_int64(selectStatement, 4)),
        cacheCreation: Int(sqlite3_column_int64(selectStatement, 5)),
        cacheRead: Int(sqlite3_column_int64(selectStatement, 6)),
        reasoningTokens: Int(sqlite3_column_int64(selectStatement, 7)),
        createdAt: stringColumn(selectStatement, index: 8) ?? "",
        cacheHitSupported: Int(sqlite3_column_int64(selectStatement, 9)) != 0
      ))
      result = sqlite3_step(selectStatement)
    }
    guard result == SQLITE_DONE else {
      throw TokMonDatabaseError.sqlite(lastErrorMessage)
    }
    guard !recordsToDelete.isEmpty else { return }

    let deleted = try deleteRows("""
      DELETE FROM usage_records
      WHERE source = 'opencode'
        AND instr(model, '/') > 0
        AND EXISTS (
          SELECT 1
          FROM usage_records canonical
          WHERE canonical.source = usage_records.source
            AND canonical.session_id = usage_records.session_id
            AND canonical.model = substr(usage_records.model, instr(usage_records.model, '/') + 1)
            AND canonical.input_tokens = usage_records.input_tokens
            AND canonical.output_tokens = usage_records.output_tokens
            AND canonical.cache_creation = usage_records.cache_creation
            AND canonical.cache_read = usage_records.cache_read
            AND canonical.reasoning_tokens = usage_records.reasoning_tokens
            AND ABS(strftime('%s', canonical.created_at) - strftime('%s', usage_records.created_at)) <= 120
        )
    """)

    if deleted > 0 {
      for record in recordsToDelete {
        try subtractUsageRollups(for: record)
      }
    }
  }

  private func deleteOpenCodeUsageRecords(
    sessionId: String,
    model: String,
    inputTokens: Int,
    outputTokens: Int,
    cacheCreation: Int,
    cacheRead: Int,
    reasoningTokens: Int,
    canonicalCreatedAt: String,
  ) throws -> [TokMonUsageRecord] {
    let selectStatement = try prepare("""
      SELECT source, session_id, model, input_tokens, output_tokens, cache_creation, cache_read, reasoning_tokens, created_at, cache_hit_supported
      FROM usage_records
      WHERE source = 'opencode'
        AND session_id = ?
        AND model = ?
        AND input_tokens = ?
        AND output_tokens = ?
        AND cache_creation = ?
        AND cache_read = ?
        AND reasoning_tokens = ?
        AND ABS(strftime('%s', created_at) - strftime('%s', ?)) <= 120
    """)
    defer { sqlite3_finalize(selectStatement) }
    try bind(sessionId, at: 1, in: selectStatement)
    try bind(model, at: 2, in: selectStatement)
    try bind(inputTokens, at: 3, in: selectStatement)
    try bind(outputTokens, at: 4, in: selectStatement)
    try bind(cacheCreation, at: 5, in: selectStatement)
    try bind(cacheRead, at: 6, in: selectStatement)
    try bind(reasoningTokens, at: 7, in: selectStatement)
    try bind(canonicalCreatedAt, at: 8, in: selectStatement)

    var recordsToDelete: [TokMonUsageRecord] = []
    var result = sqlite3_step(selectStatement)
    while result == SQLITE_ROW {
      recordsToDelete.append(TokMonUsageRecord(
        source: stringColumn(selectStatement, index: 0) ?? "opencode",
        sessionId: stringColumn(selectStatement, index: 1) ?? sessionId,
        model: stringColumn(selectStatement, index: 2) ?? "unknown",
        inputTokens: Int(sqlite3_column_int64(selectStatement, 3)),
        outputTokens: Int(sqlite3_column_int64(selectStatement, 4)),
        cacheCreation: Int(sqlite3_column_int64(selectStatement, 5)),
        cacheRead: Int(sqlite3_column_int64(selectStatement, 6)),
        reasoningTokens: Int(sqlite3_column_int64(selectStatement, 7)),
        createdAt: stringColumn(selectStatement, index: 8) ?? canonicalCreatedAt,
        cacheHitSupported: Int(sqlite3_column_int64(selectStatement, 9)) != 0
      ))
      result = sqlite3_step(selectStatement)
    }
    guard result == SQLITE_DONE else {
      throw TokMonDatabaseError.sqlite(lastErrorMessage)
    }

    let deleteStatement = try prepare("""
      DELETE FROM usage_records
      WHERE source = 'opencode'
        AND session_id = ?
        AND model = ?
        AND input_tokens = ?
        AND output_tokens = ?
        AND cache_creation = ?
        AND cache_read = ?
        AND reasoning_tokens = ?
        AND ABS(strftime('%s', created_at) - strftime('%s', ?)) <= 120
    """)
    defer { sqlite3_finalize(deleteStatement) }
    try bind(sessionId, at: 1, in: deleteStatement)
    try bind(model, at: 2, in: deleteStatement)
    try bind(inputTokens, at: 3, in: deleteStatement)
    try bind(outputTokens, at: 4, in: deleteStatement)
    try bind(cacheCreation, at: 5, in: deleteStatement)
    try bind(cacheRead, at: 6, in: deleteStatement)
    try bind(reasoningTokens, at: 7, in: deleteStatement)
    try bind(canonicalCreatedAt, at: 8, in: deleteStatement)
    try stepDone(deleteStatement)

    return recordsToDelete
  }

  private func rebuildUsageRollupsFromUsageRecords() throws {
    try exec("DELETE FROM tokmon_usage_rollups;")
    try insertUsageRollupsFromUsageRecords()
  }

  private func insertUsageRollupsFromUsageRecords() throws {
    try exec("""
      INSERT INTO tokmon_usage_rollups
        (grain, period_start, source, model, requests, input_tokens, output_tokens, cache_creation, cache_read, reasoning_tokens, cache_hit_input_tokens, cache_hit_cache_read)
      SELECT 'day',
             datetime(created_at, 'localtime', 'start of day'),
             source,
             model,
             COUNT(*),
             COALESCE(SUM(input_tokens), 0),
             COALESCE(SUM(output_tokens), 0),
             COALESCE(SUM(cache_creation), 0),
             COALESCE(SUM(cache_read), 0),
             COALESCE(SUM(reasoning_tokens), 0),
             COALESCE(SUM(CASE WHEN cache_hit_supported != 0 THEN input_tokens ELSE 0 END), 0),
             COALESCE(SUM(CASE WHEN cache_hit_supported != 0 THEN cache_read ELSE 0 END), 0)
      FROM usage_records
      GROUP BY 2, source, model;

      INSERT INTO tokmon_usage_rollups
        (grain, period_start, source, model, requests, input_tokens, output_tokens, cache_creation, cache_read, reasoning_tokens, cache_hit_input_tokens, cache_hit_cache_read)
      SELECT 'week',
             datetime(created_at, 'localtime', 'start of day', '-' || ((strftime('%w', datetime(created_at, 'localtime')) + 6) % 7) || ' days'),
             source,
             model,
             COUNT(*),
             COALESCE(SUM(input_tokens), 0),
             COALESCE(SUM(output_tokens), 0),
             COALESCE(SUM(cache_creation), 0),
             COALESCE(SUM(cache_read), 0),
             COALESCE(SUM(reasoning_tokens), 0),
             COALESCE(SUM(CASE WHEN cache_hit_supported != 0 THEN input_tokens ELSE 0 END), 0),
             COALESCE(SUM(CASE WHEN cache_hit_supported != 0 THEN cache_read ELSE 0 END), 0)
      FROM usage_records
      GROUP BY 2, source, model;

      INSERT INTO tokmon_usage_rollups
        (grain, period_start, source, model, requests, input_tokens, output_tokens, cache_creation, cache_read, reasoning_tokens, cache_hit_input_tokens, cache_hit_cache_read)
      SELECT 'month',
             datetime(created_at, 'localtime', 'start of month'),
             source,
             model,
             COUNT(*),
             COALESCE(SUM(input_tokens), 0),
             COALESCE(SUM(output_tokens), 0),
             COALESCE(SUM(cache_creation), 0),
             COALESCE(SUM(cache_read), 0),
             COALESCE(SUM(reasoning_tokens), 0),
             COALESCE(SUM(CASE WHEN cache_hit_supported != 0 THEN input_tokens ELSE 0 END), 0),
             COALESCE(SUM(CASE WHEN cache_hit_supported != 0 THEN cache_read ELSE 0 END), 0)
      FROM usage_records
      GROUP BY 2, source, model;

      INSERT INTO tokmon_usage_rollups
        (grain, period_start, source, model, requests, input_tokens, output_tokens, cache_creation, cache_read, reasoning_tokens, cache_hit_input_tokens, cache_hit_cache_read)
      SELECT 'year',
             datetime(created_at, 'localtime', 'start of year'),
             source,
             model,
             COUNT(*),
             COALESCE(SUM(input_tokens), 0),
             COALESCE(SUM(output_tokens), 0),
             COALESCE(SUM(cache_creation), 0),
             COALESCE(SUM(cache_read), 0),
             COALESCE(SUM(reasoning_tokens), 0),
             COALESCE(SUM(CASE WHEN cache_hit_supported != 0 THEN input_tokens ELSE 0 END), 0),
             COALESCE(SUM(CASE WHEN cache_hit_supported != 0 THEN cache_read ELSE 0 END), 0)
      FROM usage_records
      GROUP BY 2, source, model;
    """)
  }

  // MARK: - Connection helpers

  private var requiredConnection: OpaquePointer {
    guard let connection else {
      preconditionFailure("TokMonDatabase connection is closed")
    }
    return connection
  }

  private func configureConnection() throws {
    guard sqlite3_busy_timeout(requiredConnection, 5_000) == SQLITE_OK else {
      throw TokMonDatabaseError.sqlite(lastErrorMessage)
    }
    try exec("PRAGMA synchronous = NORMAL;")
    try exec("PRAGMA cache_size = -64000;")
    try exec("PRAGMA temp_store = MEMORY;")
  }

  private func sessionFileSuffix(for sessionId: String) -> String {
    sessionId + ".jsonl"
  }

  private func addColumnIfMissing(table: String, column: String, definition: String) throws -> Bool {
    guard try !columnExists(table: table, column: column) else {
      return false
    }
    try exec("ALTER TABLE \(table) ADD COLUMN \(definition);")
    return true
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

  private func deleteRows(_ sql: String) throws -> Int {
    try exec(sql)
    return Int(sqlite3_changes(requiredConnection))
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
