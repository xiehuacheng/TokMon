import Foundation
import SQLite3
import Testing
@testable import TokMonApp

@Test func scannerKeepsCodexSessionMetadataAcrossAppends() throws {
  let dataDir = try makeTokMonTempDir()
  let sessionsDir = dataDir.appendingPathComponent("codex-sessions", isDirectory: true)
  try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
  let logURL = sessionsDir.appendingPathComponent("session.jsonl")
  try writeJSONL(
    [
      [
        "type": "session_meta",
        "payload": [
          "id": "session-123",
          "model": "gpt-test",
        ],
      ],
      [
        "type": "event_msg",
        "timestamp": "2026-05-14T00:59:00.000Z",
        "payload": [
          "type": "user_message",
          "message": "Plan native TokMon sessions",
        ],
      ],
      codexTokenCountLine(
        timestamp: "2026-05-14T01:00:00.000Z",
        inputTokens: 20,
        outputTokens: 5,
        cachedInputTokens: 3,
        reasoningOutputTokens: 2,
      ),
    ],
    to: logURL,
  )
  let database = try TokMonDatabase(appDataDir: dataDir)
  let scanner = TokMonScanner(database: database)
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "claude-code": TokMonSourceConfig(path: dataDir.appendingPathComponent("missing-claude").path),
      "codex": TokMonSourceConfig(path: sessionsDir.path),
    ],
  )

  #expect(try scanner.scan(config: config) == 1)

  try FileHandle.seekToEndAndWrite(
    JSONLine(codexTokenCountLine(
      timestamp: "2026-05-14T01:01:00.000Z",
      inputTokens: 30,
      outputTokens: 10,
      cachedInputTokens: 4,
      reasoningOutputTokens: 1,
    )),
    to: logURL,
  )

  #expect(try scanner.scan(config: config) == 1)

  let records = try database.allUsageRecords()
  #expect(records.count == 2)
  #expect(records.map(\.sessionId) == ["session-123", "session-123"])
  #expect(records.map(\.model) == ["gpt-test", "gpt-test"])
  #expect(records.map(\.inputTokens) == [17, 26])
  #expect(records.map(\.outputTokens) == [5, 10])
  #expect(records.map(\.cacheRead) == [3, 4])
  #expect(records.map(\.reasoningTokens) == [2, 1])

  let metadata = try database.sessionMetadata(source: "codex", id: "session-123")
  #expect(metadata?.title == "codex-sessions - Plan native TokMon sessions")
  #expect(metadata?.firstPrompt == "Plan native TokMon sessions")
}

@Test func scannerUsesCodexSessionNameBeforeProjectNameInRequestTitles() throws {
  let dataDir = try makeTokMonTempDir()
  let codexHome = dataDir.appendingPathComponent("codex-home", isDirectory: true)
  let sessionsDir = codexHome.appendingPathComponent("sessions", isDirectory: true)
  try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
  let logURL = sessionsDir.appendingPathComponent("named-session.jsonl")
  try writeJSONL(
    [
      [
        "type": "session_meta",
        "payload": [
          "id": "named-session",
          "model": "gpt-test",
        ],
      ],
      [
        "type": "event_msg",
        "timestamp": "2026-05-14T01:00:00.000Z",
        "payload": [
          "type": "user_message",
          "message": "Plan the status popover",
        ],
      ],
      codexTokenCountLine(
        timestamp: "2026-05-14T01:01:00.000Z",
        inputTokens: 20,
        outputTokens: 5,
      ),
    ],
    to: logURL,
  )
  try JSONLine([
    "id": "named-session",
    "thread_name": "Polished UI Session",
    "updated_at": "2026-05-14T01:05:00.000Z",
  ]).write(to: codexHome.appendingPathComponent("session_index.jsonl"), atomically: true, encoding: .utf8)
  let database = try TokMonDatabase(appDataDir: dataDir)
  let scanner = TokMonScanner(database: database)
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "codex": TokMonSourceConfig(path: sessionsDir.path),
    ],
  )

  #expect(try scanner.scan(config: config) == 1)

  let metadata = try #require(try database.sessionMetadata(source: "codex", id: "named-session"))
  let records = try TokMonQueryStore(database: database).records(
    filter: TokMonQueryFilter(from: "2026-05-14 00:00:00", to: "2026-05-15 00:00:00", source: nil, model: nil),
    page: 0,
    limit: 10,
  )

  #expect(metadata.title == "Polished UI Session - Plan the status popover")
  #expect(records.rows.first?.sessionTitle == "Polished UI Session - Plan the status popover")
}

@Test func scannerKeepsCodexTokenCountsWithSameTotalsAtDifferentTimestamps() throws {
  let dataDir = try makeTokMonTempDir()
  let sessionsDir = dataDir.appendingPathComponent("codex-sessions", isDirectory: true)
  try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
  let logURL = sessionsDir.appendingPathComponent("same-token-totals.jsonl")
  try writeJSONL(
    [
      [
        "type": "session_meta",
        "payload": [
          "id": "same-totals",
          "model": "gpt-test",
        ],
      ],
      codexTokenCountLine(
        timestamp: "2026-05-14T01:00:00.000Z",
        inputTokens: 20,
        outputTokens: 5,
        cachedInputTokens: 3,
        reasoningOutputTokens: 2,
      ),
      codexTokenCountLine(
        timestamp: "2026-05-14T01:01:00.000Z",
        inputTokens: 20,
        outputTokens: 5,
        cachedInputTokens: 3,
        reasoningOutputTokens: 2,
      ),
    ],
    to: logURL,
  )
  let database = try TokMonDatabase(appDataDir: dataDir)
  let scanner = TokMonScanner(database: database)
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "codex": TokMonSourceConfig(path: sessionsDir.path),
    ],
  )

  #expect(try scanner.scan(config: config) == 2)

  let records = try database.allUsageRecords()
  #expect(records.map(\.createdAt) == [
    "2026-05-14T01:00:00.000Z",
    "2026-05-14T01:01:00.000Z",
  ])
}

@Test func scannerImportsOpenCodeAssistantMessagesFromDatabase() throws {
  let dataDir = try makeTokMonTempDir()
  let openCodeDir = dataDir.appendingPathComponent("opencode", isDirectory: true)
  try FileManager.default.createDirectory(at: openCodeDir, withIntermediateDirectories: true)
  let openCodeDatabaseURL = openCodeDir.appendingPathComponent("opencode.db")
  try createOpenCodeDatabase(openCodeDatabaseURL)
  try insertOpenCodeSession(
    databaseURL: openCodeDatabaseURL,
    sessionId: "ses_new",
    title: "Autogenerated summary",
    directory: "/Users/orange/Project/NewWork",
    model: #"{"id":"gpt-opencode","providerID":"local"}"#,
    timeCreated: 1_779_240_000_000,
    timeUpdated: 1_779_240_050_000,
  )
  try insertOpenCodeUserMessage(
    databaseURL: openCodeDatabaseURL,
    messageId: "msg_user",
    sessionId: "ses_new",
    created: 1_779_240_009_000,
  )
  try insertOpenCodeUserTextPart(
    databaseURL: openCodeDatabaseURL,
    partId: "part_user",
    messageId: "msg_user",
    sessionId: "ses_new",
    text: "Build native TokMon",
    created: 1_779_240_009_000,
  )
  try insertOpenCodeAssistantMessage(
    databaseURL: openCodeDatabaseURL,
    messageId: "msg_1",
    sessionId: "ses_new",
    inputTokens: 123,
    outputTokens: 45,
    reasoningTokens: 6,
    cacheRead: 7,
    cacheWrite: 8,
    modelID: "gpt-opencode",
    providerID: "local",
    created: 1_779_240_010_000,
    completed: 1_779_240_011_000,
  )
  try insertOpenCodeAssistantMessage(
    databaseURL: openCodeDatabaseURL,
    messageId: "msg_2",
    sessionId: "ses_new",
    inputTokens: 20,
    outputTokens: 5,
    reasoningTokens: 0,
    cacheRead: 3,
    cacheWrite: 1,
    modelID: "gpt-opencode",
    providerID: "local",
    created: 1_779_240_020_000,
    completed: 1_779_240_021_000,
  )
  let database = try TokMonDatabase(appDataDir: dataDir)
  let scanner = TokMonScanner(database: database)
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "opencode": TokMonSourceConfig(path: openCodeDir.path),
    ],
  )

  #expect(try scanner.scan(config: config) == 2)
  #expect(try scanner.scan(config: config) == 0)

  let records = try database.allUsageRecords()
  #expect(records.count == 2)
  #expect(records.map(\.source) == ["opencode", "opencode"])
  #expect(records.map(\.sessionId) == ["ses_new", "ses_new"])
  #expect(records.map(\.model) == ["gpt-opencode", "gpt-opencode"])
  #expect(records.map(\.inputTokens) == [123, 20])
  #expect(records.map(\.outputTokens) == [45, 5])
  #expect(records.map(\.cacheRead) == [7, 3])
  #expect(records.map(\.cacheCreation) == [8, 1])
  #expect(records.map(\.reasoningTokens) == [6, 0])
  #expect(records.first?.createdAt == "2026-05-20T01:20:10.000Z")

  let metadata = try database.sessionMetadata(source: "opencode", id: "ses_new")
  #expect(metadata?.title == "NewWork - Build native TokMon")
  #expect(metadata?.firstPrompt == "Build native TokMon")
  #expect(metadata?.model == "gpt-opencode")
}

@Test func scannerSkipsOpenCodeEnvironmentContextWhenChoosingFirstPrompt() throws {
  let dataDir = try makeTokMonTempDir()
  let openCodeDir = dataDir.appendingPathComponent("opencode", isDirectory: true)
  try FileManager.default.createDirectory(at: openCodeDir, withIntermediateDirectories: true)
  let openCodeDatabaseURL = openCodeDir.appendingPathComponent("opencode.db")
  try createOpenCodeDatabase(openCodeDatabaseURL)
  try insertOpenCodeSession(
    databaseURL: openCodeDatabaseURL,
    sessionId: "ses_context",
    title: "Autogenerated context summary",
    directory: "/Users/orange/Project/ContextWork",
    model: #"{"id":"gpt-opencode","providerID":"local"}"#,
    timeCreated: 1_779_240_000_000,
    timeUpdated: 1_779_240_050_000,
  )
  try insertOpenCodeUserMessage(
    databaseURL: openCodeDatabaseURL,
    messageId: "msg_context",
    sessionId: "ses_context",
    created: 1_779_240_005_000,
  )
  try insertOpenCodeUserTextPart(
    databaseURL: openCodeDatabaseURL,
    partId: "part_context",
    messageId: "msg_context",
    sessionId: "ses_context",
    text: "<environment_context>\n  <cwd>/Users/orange/Project/ContextWork</cwd>\n</environment_context>",
    created: 1_779_240_005_000,
  )
  try insertOpenCodeUserMessage(
    databaseURL: openCodeDatabaseURL,
    messageId: "msg_user_real",
    sessionId: "ses_context",
    created: 1_779_240_009_000,
  )
  try insertOpenCodeUserTextPart(
    databaseURL: openCodeDatabaseURL,
    partId: "part_user_real",
    messageId: "msg_user_real",
    sessionId: "ses_context",
    text: "Actual user prompt",
    created: 1_779_240_009_000,
  )
  try insertOpenCodeAssistantMessage(
    databaseURL: openCodeDatabaseURL,
    messageId: "msg_context_assistant",
    sessionId: "ses_context",
    inputTokens: 42,
    outputTokens: 11,
    reasoningTokens: 0,
    cacheRead: 0,
    cacheWrite: 0,
    modelID: "gpt-opencode",
    providerID: "local",
    created: 1_779_240_010_000,
    completed: 1_779_240_011_000,
  )
  let database = try TokMonDatabase(appDataDir: dataDir)
  let scanner = TokMonScanner(database: database)
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "opencode": TokMonSourceConfig(path: openCodeDir.path),
    ],
  )

  #expect(try scanner.scan(config: config) == 1)

  let metadata = try database.sessionMetadata(source: "opencode", id: "ses_context")
  #expect(metadata?.title == "ContextWork - Actual user prompt")
  #expect(metadata?.firstPrompt == "Actual user prompt")
}

@Test func scannerRefreshesOpenCodeWhenWalChangesWithoutMainDatabaseChanging() throws {
  let dataDir = try makeTokMonTempDir()
  let openCodeDir = dataDir.appendingPathComponent("opencode", isDirectory: true)
  try FileManager.default.createDirectory(at: openCodeDir, withIntermediateDirectories: true)
  let openCodeDatabaseURL = openCodeDir.appendingPathComponent("opencode.db")
  try createOpenCodeDatabase(openCodeDatabaseURL)

  var writer: OpaquePointer?
  guard sqlite3_open(openCodeDatabaseURL.path, &writer) == SQLITE_OK else {
    throw TestSQLiteError("Unable to open OpenCode writer")
  }
  defer {
    sqlite3_close(writer)
  }
  try sqliteExec(writer, "PRAGMA journal_mode = WAL; PRAGMA wal_autocheckpoint = 0;")
  try insertOpenCodeSession(
    database: writer,
    sessionId: "ses_wal",
    title: "WAL work",
    directory: "/Users/orange/Project/WalWork",
    model: #"{"id":"gpt-opencode","providerID":"local"}"#,
    timeCreated: 1_779_240_000_000,
    timeUpdated: 1_779_240_050_000,
  )
  try insertOpenCodeUserMessage(
    database: writer,
    messageId: "msg_wal_user",
    sessionId: "ses_wal",
    created: 1_779_240_009_000,
  )
  try insertOpenCodeUserTextPart(
    database: writer,
    partId: "part_wal_user",
    messageId: "msg_wal_user",
    sessionId: "ses_wal",
    text: "Track OpenCode WAL updates",
    created: 1_779_240_009_000,
  )
  try insertOpenCodeAssistantMessage(
    database: writer,
    messageId: "msg_wal_1",
    sessionId: "ses_wal",
    inputTokens: 10,
    outputTokens: 2,
    reasoningTokens: 0,
    cacheRead: 0,
    cacheWrite: 0,
    modelID: "gpt-opencode",
    providerID: "local",
    created: 1_779_240_010_000,
    completed: 1_779_240_011_000,
  )

  let database = try TokMonDatabase(appDataDir: dataDir)
  let scanner = TokMonScanner(database: database)
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "opencode": TokMonSourceConfig(path: openCodeDir.path),
    ],
  )

  #expect(try scanner.scan(config: config) == 1)
  let mainDatabaseSize = try fileByteSize(openCodeDatabaseURL)
  let mainDatabaseMtime = try fileModifiedAt(openCodeDatabaseURL)

  try insertOpenCodeAssistantMessage(
    database: writer,
    messageId: "msg_wal_2",
    sessionId: "ses_wal",
    inputTokens: 30,
    outputTokens: 7,
    reasoningTokens: 1,
    cacheRead: 0,
    cacheWrite: 0,
    modelID: "gpt-opencode",
    providerID: "local",
    created: 1_779_240_020_000,
    completed: 1_779_240_021_000,
  )

  #expect(try fileByteSize(openCodeDatabaseURL) == mainDatabaseSize)
  #expect(try fileModifiedAt(openCodeDatabaseURL) == mainDatabaseMtime)
  #expect(try scanner.scan(config: config) == 1)

  let records = try database.allUsageRecords()
  #expect(records.count == 2)
  #expect(records.map(\.inputTokens) == [10, 30])
}

@Test func scannerBackfillsOpenCodePromptMetadataWhenDatabaseIsUnchanged() throws {
  let dataDir = try makeTokMonTempDir()
  let openCodeDir = dataDir.appendingPathComponent("opencode", isDirectory: true)
  try FileManager.default.createDirectory(at: openCodeDir, withIntermediateDirectories: true)
  let openCodeDatabaseURL = openCodeDir.appendingPathComponent("opencode.db")
  try createOpenCodeDatabase(openCodeDatabaseURL)
  try insertOpenCodeSession(
    databaseURL: openCodeDatabaseURL,
    sessionId: "ses_context_backfill",
    title: "Autogenerated context summary",
    directory: "/Users/orange/Project/ContextBackfill",
    model: #"{"id":"gpt-opencode","providerID":"local"}"#,
    timeCreated: 1_779_240_000_000,
    timeUpdated: 1_779_240_050_000,
  )
  try insertOpenCodeUserMessage(
    databaseURL: openCodeDatabaseURL,
    messageId: "msg_context_backfill",
    sessionId: "ses_context_backfill",
    created: 1_779_240_005_000,
  )
  try insertOpenCodeUserTextPart(
    databaseURL: openCodeDatabaseURL,
    partId: "part_context_backfill",
    messageId: "msg_context_backfill",
    sessionId: "ses_context_backfill",
    text: "<environment_context>\n  <cwd>/Users/orange/Project/ContextBackfill</cwd>\n</environment_context>",
    created: 1_779_240_005_000,
  )
  try insertOpenCodeUserMessage(
    databaseURL: openCodeDatabaseURL,
    messageId: "msg_actual_backfill",
    sessionId: "ses_context_backfill",
    created: 1_779_240_009_000,
  )
  try insertOpenCodeUserTextPart(
    databaseURL: openCodeDatabaseURL,
    partId: "part_actual_backfill",
    messageId: "msg_actual_backfill",
    sessionId: "ses_context_backfill",
    text: "Actual persisted prompt",
    created: 1_779_240_009_000,
  )
  try insertOpenCodeAssistantMessage(
    databaseURL: openCodeDatabaseURL,
    messageId: "msg_actual_assistant",
    sessionId: "ses_context_backfill",
    inputTokens: 42,
    outputTokens: 11,
    reasoningTokens: 0,
    cacheRead: 0,
    cacheWrite: 0,
    modelID: "gpt-opencode",
    providerID: "local",
    created: 1_779_240_010_000,
    completed: 1_779_240_011_000,
  )
  let database = try TokMonDatabase(appDataDir: dataDir)
  _ = try database.insertUsage(TokMonUsageRecord(
    source: "opencode",
    sessionId: "ses_context_backfill",
    model: "gpt-opencode",
    inputTokens: 42,
    outputTokens: 11,
    cacheCreation: 0,
    cacheRead: 0,
    reasoningTokens: 0,
    createdAt: "2026-05-20T01:20:10.000Z",
  ))
  let oldPrompt = "<environment_context>\n  <cwd>/Users/orange/Project/ContextBackfill</cwd>\n</environment_context>"
  try database.upsertSessionMetadata(TokMonSessionMetadata(
    id: "ses_context_backfill",
    source: "opencode",
    title: "ContextBackfill - \(oldPrompt)",
    firstPrompt: oldPrompt,
    lastPrompt: oldPrompt,
    model: "gpt-opencode",
    startedAt: "2026-05-20T01:20:00.000Z",
    lastActiveAt: "2026-05-20T01:20:11.000Z",
    filePath: openCodeDatabaseURL.path,
    projectPath: "/Users/orange/Project/ContextBackfill",
  ))
  let scanner = TokMonScanner(database: database)
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "opencode": TokMonSourceConfig(path: openCodeDir.path),
    ],
  )

  #expect(try scanner.scan(config: config) == 0)
  let unchangedState = try database.scanState(filePath: openCodeDatabaseURL.path)
  try database.upsertSessionMetadata(TokMonSessionMetadata(
    id: "ses_context_backfill",
    source: "opencode",
    title: "ContextBackfill - \(oldPrompt)",
    firstPrompt: oldPrompt,
    lastPrompt: oldPrompt,
    model: "gpt-opencode",
    startedAt: "2026-05-20T01:20:00.000Z",
    lastActiveAt: "2026-05-20T01:20:11.000Z",
    filePath: openCodeDatabaseURL.path,
    projectPath: "/Users/orange/Project/ContextBackfill",
  ))
  #expect(try database.scanState(filePath: openCodeDatabaseURL.path) == unchangedState)

  #expect(try scanner.scan(config: config) == 0)

  let metadata = try database.sessionMetadata(source: "opencode", id: "ses_context_backfill")
  #expect(metadata?.title == "ContextBackfill - Actual persisted prompt")
  #expect(metadata?.firstPrompt == "Actual persisted prompt")
}

@Test func scannerCanonicalizesExistingOpenCodeProviderPrefixedModelRows() throws {
  let dataDir = try makeTokMonTempDir()
  let openCodeDir = dataDir.appendingPathComponent("opencode", isDirectory: true)
  try FileManager.default.createDirectory(at: openCodeDir, withIntermediateDirectories: true)
  let openCodeDatabaseURL = openCodeDir.appendingPathComponent("opencode.db")
  try createOpenCodeDatabase(openCodeDatabaseURL)
  try insertOpenCodeSession(
    databaseURL: openCodeDatabaseURL,
    sessionId: "ses_qwen",
    title: "Qwen work",
    directory: "/Users/orange/Project/QwenWork",
    model: #"{"id":"qwen3.6-35b","providerID":"litellm"}"#,
    timeCreated: 1_779_240_000_000,
    timeUpdated: 1_779_240_050_000,
  )
  try insertOpenCodeAssistantMessage(
    databaseURL: openCodeDatabaseURL,
    messageId: "msg_qwen",
    sessionId: "ses_qwen",
    inputTokens: 123,
    outputTokens: 45,
    reasoningTokens: 6,
    cacheRead: 0,
    cacheWrite: 0,
    modelID: "qwen3.6-35b",
    providerID: "litellm",
    created: 1_779_240_010_000,
    completed: 1_779_240_011_000,
  )
  let database = try TokMonDatabase(appDataDir: dataDir)
  _ = try database.insertUsage(TokMonUsageRecord(
    source: "opencode",
    sessionId: "ses_qwen",
    model: "litellm/qwen3.6-35b",
    inputTokens: 123,
    outputTokens: 45,
    cacheCreation: 0,
    cacheRead: 0,
    reasoningTokens: 6,
    createdAt: "2026-05-20T01:20:10.000Z",
  ))
  let scanner = TokMonScanner(database: database)
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "opencode": TokMonSourceConfig(path: openCodeDir.path),
    ],
  )

  #expect(try scanner.scan(config: config) == 0)

  let records = try database.allUsageRecords()
  #expect(records.count == 1)
  #expect(records.first?.model == "qwen3.6-35b")
}

@Test func scannerSkipsUnchangedFilesAndRescansTruncatedFiles() async throws {
  let dataDir = try makeTokMonTempDir()
  let sessionsDir = dataDir.appendingPathComponent("codex-sessions", isDirectory: true)
  try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
  let logURL = sessionsDir.appendingPathComponent("truncated.jsonl")
  let scanStatePath = scannerFilePath(logURL)
  try writeJSONL(
    [
      [
        "type": "session_meta",
        "payload": [
          "id": "session-before-truncate",
          "model": "gpt-before",
        ],
      ],
      codexTokenCountLine(
        timestamp: "2026-05-14T02:00:00.000Z",
        inputTokens: 11,
        outputTokens: 4,
      ),
    ],
    to: logURL,
  )
  let database = try TokMonDatabase(appDataDir: dataDir)
  let scanner = TokMonScanner(database: database)
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "codex": TokMonSourceConfig(path: sessionsDir.path),
    ],
  )

  #expect(try scanner.scan(config: config) == 1)
  let firstOffset = try fileByteSize(logURL)
  #expect(try database.scanState(filePath: scanStatePath).offset == firstOffset)
  let firstScanState = try database.scanState(filePath: scanStatePath)

  try await Task.sleep(nanoseconds: 2_500_000_000)
  #expect(try scanner.scan(config: config) == 0)
  let secondScanState = try database.scanState(filePath: scanStatePath)
  #expect(secondScanState == firstScanState)

  try writeJSONL(
    [
      [
        "type": "session_meta",
        "payload": [
          "id": "session-after-truncate",
          "model": "gpt-after",
        ],
      ],
      codexTokenCountLine(
        timestamp: "2026-05-14T02:05:00.000Z",
        inputTokens: 7,
        outputTokens: 3,
      ),
    ],
    to: logURL,
  )

  #expect(try scanner.scan(config: config) == 1)
  let records = try database.allUsageRecords()
  #expect(records.count == 2)
  #expect(records.last?.sessionId == "session-after-truncate")
  #expect(records.last?.model == "gpt-after")
  #expect(try database.scanState(filePath: scanStatePath).offset < firstOffset)
  #expect(try database.scanState(filePath: scanStatePath).offset == fileByteSize(logURL))
}

@Test func scannerUsesCodexSessionIndexThreadNameAsSessionTitle() throws {
  let dataDir = try makeTokMonTempDir()
  let codexHome = dataDir.appendingPathComponent("codex-home", isDirectory: true)
  let sessionsDir = codexHome.appendingPathComponent("sessions", isDirectory: true)
  try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
  let logURL = sessionsDir.appendingPathComponent("indexed.jsonl")
  try writeJSONL(
    [
      [
        "type": "session_meta",
        "payload": [
          "id": "indexed-session",
          "model": "gpt-indexed",
        ],
      ],
      [
        "type": "event_msg",
        "timestamp": "2026-05-14T02:00:00.000Z",
        "payload": [
          "type": "user_message",
          "message": "First user prompt fallback",
        ],
      ],
      codexTokenCountLine(
        timestamp: "2026-05-14T02:01:00.000Z",
        inputTokens: 11,
        outputTokens: 4,
      ),
    ],
    to: logURL,
  )
  try JSONLine([
    "id": "indexed-session",
    "thread_name": "Indexed Codex Title",
    "updated_at": "2026-05-14T02:05:00.000Z",
  ]).write(to: codexHome.appendingPathComponent("session_index.jsonl"), atomically: true, encoding: .utf8)
  let database = try TokMonDatabase(appDataDir: dataDir)
  let scanner = TokMonScanner(database: database)
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "codex": TokMonSourceConfig(path: sessionsDir.path),
    ],
  )

  #expect(try scanner.scan(config: config) == 1)

  let metadata = try database.sessionMetadata(source: "codex", id: "indexed-session")
  #expect(metadata?.title == "Indexed Codex Title - First user prompt fallback")
  #expect(metadata?.firstPrompt == "First user prompt fallback")
}

@Test func scannerBackfillsCodexTitleForUnchangedScanState() throws {
  let dataDir = try makeTokMonTempDir()
  let codexHome = dataDir.appendingPathComponent("codex-home", isDirectory: true)
  let nestedSessionsDir = codexHome
    .appendingPathComponent("sessions", isDirectory: true)
    .appendingPathComponent("2026", isDirectory: true)
    .appendingPathComponent("05", isDirectory: true)
  try FileManager.default.createDirectory(at: nestedSessionsDir, withIntermediateDirectories: true)
  let logURL = nestedSessionsDir.appendingPathComponent("rollout-2026-05-14T01-00-00-real-session-id.jsonl")
  try writeJSONL(
    [
      [
        "type": "session_meta",
        "payload": [
          "id": "real-session-id",
          "model": "gpt-indexed",
        ],
      ],
      [
        "type": "event_msg",
        "timestamp": "2026-05-14T02:00:00.000Z",
        "payload": [
          "type": "user_message",
          "message": "Fallback title from prompt",
        ],
      ],
      codexTokenCountLine(
        timestamp: "2026-05-14T02:01:00.000Z",
        inputTokens: 11,
        outputTokens: 4,
      ),
    ],
    to: logURL,
  )
  try JSONLine([
    "id": "real-session-id",
    "thread_name": "Session Index Real Title",
    "updated_at": "2026-05-14T02:05:00.000Z",
  ]).write(to: codexHome.appendingPathComponent("session_index.jsonl"), atomically: true, encoding: .utf8)
  let database = try TokMonDatabase(appDataDir: dataDir)
  _ = try database.insertUsage(TokMonUsageRecord(
    source: "codex",
    sessionId: "real-session-id",
    model: "gpt-indexed",
    inputTokens: 11,
    outputTokens: 4,
    cacheCreation: 0,
    cacheRead: 0,
    reasoningTokens: 0,
    createdAt: "2026-05-14T02:01:00.000Z",
  ))
  try database.setScanState(
    filePath: scannerFilePath(logURL),
    state: TokMonScanState(
      offset: fileByteSize(logURL),
      sessionId: nil,
      model: nil,
      lastUsageKey: nil,
    ),
  )
  let scanner = TokMonScanner(database: database)
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "codex": TokMonSourceConfig(path: nestedSessionsDir.path),
    ],
  )

  #expect(try scanner.scan(config: config) == 0)

  let metadata = try database.sessionMetadata(source: "codex", id: "real-session-id")
  #expect(metadata?.title == "Session Index Real Title - Fallback title from prompt")
  #expect(metadata?.firstPrompt == "Fallback title from prompt")
  #expect(metadata?.model == "gpt-indexed")
  let sessions = try TokMonQueryStore(database: database).sessions(limit: 10)
  #expect(sessions.first?.title == "Session Index Real Title - Fallback title from prompt")
}

@Test func scannerDedupesClaudeAssistantUsageByMessageId() throws {
  let dataDir = try makeTokMonTempDir()
  let projectsDir = dataDir.appendingPathComponent("claude-projects", isDirectory: true)
  try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
  let logURL = projectsDir.appendingPathComponent("claude-session.jsonl")
  let duplicateMessage = [
    "id": "msg-duplicate",
    "model": "claude-test",
    "usage": [
      "input_tokens": 12,
      "output_tokens": 6,
      "cache_creation_input_tokens": 2,
      "cache_read_input_tokens": 3,
    ],
  ] as [String: Any]
  try writeJSONL(
    [
      [
        "type": "assistant",
        "sessionId": "claude-session",
        "timestamp": "2026-05-14T03:00:00.000Z",
        "message": duplicateMessage,
      ],
      [
        "type": "assistant",
        "sessionId": "claude-session",
        "timestamp": "2026-05-14T03:01:00.000Z",
        "message": try jsonString(duplicateMessage),
      ],
    ],
    to: logURL,
  )
  let database = try TokMonDatabase(appDataDir: dataDir)
  let scanner = TokMonScanner(database: database)
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "claude-code": TokMonSourceConfig(path: projectsDir.path),
    ],
  )

  #expect(try scanner.scan(config: config) == 1)

  let records = try database.allUsageRecords()
  #expect(records.count == 1)
  #expect(records[0].source == "claude-code")
  #expect(records[0].sessionId == "claude-session")
  #expect(records[0].model == "claude-test")
  #expect(records[0].inputTokens == 12)
  #expect(records[0].outputTokens == 6)
  #expect(records[0].cacheCreation == 2)
  #expect(records[0].cacheRead == 3)
}

@Test func scannerImportsClaudeUsageLineCompletedAfterPartialRead() throws {
  let dataDir = try makeTokMonTempDir()
  let projectsDir = dataDir.appendingPathComponent("claude-projects", isDirectory: true)
  try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
  let logURL = projectsDir.appendingPathComponent("claude-session.jsonl")
  let usageLine = try JSONLine([
    "type": "assistant",
    "sessionId": "claude-session",
    "timestamp": "2026-05-14T03:00:00.000Z",
    "message": [
      "id": "msg-partial",
      "model": "claude-test",
      "usage": [
        "input_tokens": 12,
        "output_tokens": 6,
        "cache_creation_input_tokens": 2,
        "cache_read_input_tokens": 3,
      ],
    ],
  ])
  let splitIndex = usageLine.index(usageLine.startIndex, offsetBy: usageLine.count / 2)
  try String(usageLine[..<splitIndex]).write(to: logURL, atomically: true, encoding: .utf8)

  let database = try TokMonDatabase(appDataDir: dataDir)
  let scanner = TokMonScanner(database: database)
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "claude-code": TokMonSourceConfig(path: projectsDir.path),
    ],
  )

  #expect(try scanner.scan(config: config) == 0)

  let handle = try FileHandle(forWritingTo: logURL)
  try handle.seekToEnd()
  try handle.write(contentsOf: Data(String(usageLine[splitIndex...]).utf8))
  try handle.close()

  #expect(try scanner.scan(config: config) == 1)
  let records = try database.allUsageRecords()
  #expect(records.count == 1)
  let record = try #require(records.first)
  #expect(record.source == "claude-code")
  #expect(record.sessionId == "claude-session")
  #expect(record.model == "claude-test")
  #expect(record.inputTokens == 12)
  #expect(record.outputTokens == 6)
}

@Test func scannerMergesClaudeUsageRecordsWithSameMessageId() throws {
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
          "id": "msg-cache-partial",
          "model": "claude-test",
          "usage": [
            "input_tokens": 50936,
            "output_tokens": 0,
            "cache_creation_input_tokens": 0,
            "cache_read_input_tokens": 0,
          ],
        ],
      ],
      [
        "type": "assistant",
        "sessionId": "claude-session",
        "timestamp": "2026-05-14T03:00:01.000Z",
        "message": [
          "id": "msg-cache-partial",
          "model": "claude-test",
          "usage": [
            "input_tokens": 38904,
            "output_tokens": 532,
            "cache_creation_input_tokens": 0,
            "cache_read_input_tokens": 12032,
          ],
        ],
      ],
    ],
    to: logURL,
  )
  let database = try TokMonDatabase(appDataDir: dataDir)
  let scanner = TokMonScanner(database: database)
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "claude-code": TokMonSourceConfig(path: projectsDir.path),
    ],
  )

  #expect(try scanner.scan(config: config) == 1)

  let records = try database.allUsageRecords()
  #expect(records.count == 1)
  #expect(records[0].inputTokens == 38904)
  #expect(records[0].outputTokens == 532)
  #expect(records[0].cacheRead == 12032)
}

@Test func scannerMergesClaudeRecordsByTotalTokensWhenTimestampsAreEqual() throws {
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
          "id": "msg-tie",
          "model": "claude-test",
          "usage": [
            "input_tokens": 100,
            "output_tokens": 0,
          ],
        ],
      ],
      [
        "type": "assistant",
        "sessionId": "claude-session",
        "timestamp": "2026-05-14T03:00:00.000Z",
        "message": [
          "id": "msg-tie",
          "model": "claude-test",
          "usage": [
            "input_tokens": 50,
            "output_tokens": 100,
          ],
        ],
      ],
    ],
    to: logURL,
  )
  let database = try TokMonDatabase(appDataDir: dataDir)
  let scanner = TokMonScanner(database: database)
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "claude-code": TokMonSourceConfig(path: projectsDir.path),
    ],
  )

  #expect(try scanner.scan(config: config) == 1)

  let records = try database.allUsageRecords()
  #expect(records.count == 1)
  #expect(records[0].inputTokens == 50)
  #expect(records[0].outputTokens == 100)
}

@Test func scannerDoesNotMergeClaudeAssistantRecordsWithoutMessageId() throws {
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
          "model": "claude-test",
          "usage": [
            "input_tokens": 42,
            "output_tokens": 7,
          ],
        ],
      ],
      [
        "type": "assistant",
        "sessionId": "claude-session",
        "timestamp": "2026-05-14T03:00:00.000Z",
        "message": [
          "model": "claude-test",
          "usage": [
            "input_tokens": 42,
            "output_tokens": 7,
          ],
        ],
      ],
    ],
    to: logURL,
  )
  let database = try TokMonDatabase(appDataDir: dataDir)
  let scanner = TokMonScanner(database: database)
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "claude-code": TokMonSourceConfig(path: projectsDir.path),
    ],
  )

  #expect(try scanner.scan(config: config) == 1)

  let records = try database.allUsageRecords()
  #expect(records.count == 1)
  #expect(records[0].inputTokens == 42)
  #expect(records[0].outputTokens == 7)
}

@Test func scannerParsesClaudeNestedCacheCreation() throws {
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
          "id": "msg-nested-cache",
          "model": "claude-test",
          "usage": [
            "input_tokens": 100,
            "output_tokens": 50,
            "cache_creation": [
              "ephemeral_5m_input_tokens": 5381,
              "ephemeral_1h_input_tokens": 42,
            ],
            "cache_read_input_tokens": 123,
          ],
        ],
      ],
    ],
    to: logURL,
  )
  let database = try TokMonDatabase(appDataDir: dataDir)
  let scanner = TokMonScanner(database: database)
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "claude-code": TokMonSourceConfig(path: projectsDir.path),
    ],
  )

  #expect(try scanner.scan(config: config) == 1)

  let records = try database.allUsageRecords()
  #expect(records.count == 1)
  #expect(records[0].inputTokens == 100)
  #expect(records[0].outputTokens == 50)
  #expect(records[0].cacheCreation == 5423)
  #expect(records[0].cacheRead == 123)
}

@Test func scannerReplacesClaudePartialRecordOnIncrementalScan() throws {
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
          "id": "msg-cache-incremental",
          "model": "claude-test",
          "usage": [
            "input_tokens": 1000,
            "output_tokens": 0,
            "cache_creation_input_tokens": 0,
            "cache_read_input_tokens": 0,
          ],
        ],
      ],
    ],
    to: logURL,
  )
  let database = try TokMonDatabase(appDataDir: dataDir)
  let scanner = TokMonScanner(database: database)
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "claude-code": TokMonSourceConfig(path: projectsDir.path),
    ],
  )

  #expect(try scanner.scan(config: config) == 1)

  let handle = try FileHandle(forWritingTo: logURL)
  try handle.seekToEnd()
  try handle.write(contentsOf: Data("\n".utf8))
  try handle.write(contentsOf: Data(try JSONLine([
    "type": "assistant",
    "sessionId": "claude-session",
    "timestamp": "2026-05-14T03:00:01.000Z",
    "message": [
      "id": "msg-cache-incremental",
      "model": "claude-test",
      "usage": [
        "input_tokens": 800,
        "output_tokens": 100,
        "cache_creation_input_tokens": 0,
        "cache_read_input_tokens": 500,
      ],
    ],
  ]).utf8))
  try handle.close()

  #expect(try scanner.scan(config: config) == 1)

  let records = try database.allUsageRecords()
  #expect(records.count == 1)
  #expect(records[0].inputTokens == 800)
  #expect(records[0].outputTokens == 100)
  #expect(records[0].cacheRead == 500)
}

@Test func scannerRecoversClaudeUsageWhenSavedOffsetPointsInsideLine() throws {
  let dataDir = try makeTokMonTempDir()
  let projectsDir = dataDir.appendingPathComponent("claude-projects", isDirectory: true)
  try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
  let logURL = projectsDir.appendingPathComponent("claude-session.jsonl")
  let usageLine = try JSONLine([
    "type": "assistant",
    "sessionId": "claude-session",
    "timestamp": "2026-05-14T03:00:00.000Z",
    "message": [
      "id": "msg-recovered",
      "model": "claude-test",
      "usage": [
        "input_tokens": 21,
        "output_tokens": 9,
      ],
    ],
  ])
  try usageLine.write(to: logURL, atomically: true, encoding: .utf8)

  let database = try TokMonDatabase(appDataDir: dataDir)
  let splitIndex = usageLine.index(usageLine.startIndex, offsetBy: usageLine.count / 2)
  let staleOffset = Int64(String(usageLine[..<splitIndex]).utf8.count)
  try database.setScanState(
    filePath: scannerFilePath(logURL),
    state: TokMonScanState(
      offset: staleOffset,
      sessionId: "claude-session",
      model: nil,
      lastUsageKey: nil,
    ),
  )
  let scanner = TokMonScanner(database: database)
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "claude-code": TokMonSourceConfig(path: projectsDir.path),
    ],
  )

  #expect(try scanner.scan(config: config) == 1)
  let record = try #require(try database.allUsageRecords().first)
  #expect(record.sessionId == "claude-session")
  #expect(record.model == "claude-test")
  #expect(record.inputTokens == 21)
  #expect(record.outputTokens == 9)
}

@Test func scannerRechecksPreviousClaudeLineWhenAppendingAfterStaleOffset() throws {
  let dataDir = try makeTokMonTempDir()
  let projectsDir = dataDir.appendingPathComponent("claude-projects", isDirectory: true)
  try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
  let logURL = projectsDir.appendingPathComponent("claude-session.jsonl")
  let missedLine = try JSONLine([
    "type": "assistant",
    "sessionId": "claude-session",
    "timestamp": "2026-05-14T03:00:00.000Z",
    "message": [
      "id": "msg-missed",
      "model": "claude-test",
      "usage": [
        "input_tokens": 13,
        "output_tokens": 5,
      ],
    ],
  ])
  try missedLine.write(to: logURL, atomically: true, encoding: .utf8)

  let database = try TokMonDatabase(appDataDir: dataDir)
  try database.setScanState(
    filePath: scannerFilePath(logURL),
    state: TokMonScanState(
      offset: Int64(missedLine.utf8.count),
      sessionId: "claude-session",
      model: nil,
      lastUsageKey: nil,
    ),
  )
  let appendedLine = try JSONLine([
    "type": "assistant",
    "sessionId": "claude-session",
    "timestamp": "2026-05-14T03:01:00.000Z",
    "message": [
      "id": "msg-appended",
      "model": "claude-test",
      "usage": [
        "input_tokens": 8,
        "output_tokens": 4,
      ],
    ],
  ])
  let handle = try FileHandle(forWritingTo: logURL)
  try handle.seekToEnd()
  try handle.write(contentsOf: Data(appendedLine.utf8))
  try handle.close()

  let scanner = TokMonScanner(database: database)
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "claude-code": TokMonSourceConfig(path: projectsDir.path),
    ],
  )

  #expect(try scanner.scan(config: config) == 2)
  let records = try database.allUsageRecords()
  #expect(records.map(\.inputTokens) == [13, 8])
}

@Test func scannerSkipsClaudeAssistantRequestsWithZeroTokenUsage() throws {
  let dataDir = try makeTokMonTempDir()
  let projectsDir = dataDir.appendingPathComponent("claude-projects", isDirectory: true)
  try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
  let logURL = projectsDir.appendingPathComponent("claude-session.jsonl")
  try writeJSONL(
    [
      [
        "type": "assistant",
        "sessionId": "claude-session",
        "timestamp": "2026-05-24T06:08:17.667Z",
        "message": [
          "id": "chatcmpl-zero",
          "type": "message",
          "role": "assistant",
          "model": "qwen3.6-35b",
          "usage": [
            "input_tokens": 0,
            "cache_creation_input_tokens": 0,
            "cache_read_input_tokens": 0,
            "output_tokens": 0,
          ],
          "content": [
            [
              "type": "text",
              "text": "Done",
            ],
          ],
        ],
      ],
      [
        "type": "assistant",
        "sessionId": "claude-session",
        "timestamp": "2026-05-24T06:08:18.667Z",
        "message": [
          "id": "chatcmpl-nonzero",
          "type": "message",
          "role": "assistant",
          "model": "qwen3.6-35b",
          "usage": [
            "input_tokens": 5,
            "output_tokens": 3,
          ],
          "content": [
            [
              "type": "text",
              "text": "Done",
            ],
          ],
        ],
      ],
    ],
    to: logURL,
  )
  let database = try TokMonDatabase(appDataDir: dataDir)
  let scanner = TokMonScanner(database: database)
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "claude-code": TokMonSourceConfig(path: projectsDir.path),
    ],
  )

  #expect(try scanner.scan(config: config) == 1)
  let records = try database.allUsageRecords()
  #expect(records.count == 1)
  let record = try #require(records.first)
  #expect(record.source == "claude-code")
  #expect(record.sessionId == "claude-session")
  #expect(record.model == "qwen3.6-35b")
  #expect(record.inputTokens == 5)
  #expect(record.outputTokens == 3)
}

@Test func scannerBackfillsClaudeZeroUsageWhenLegacyStateReachedEndOfFile() throws {
  let dataDir = try makeTokMonTempDir()
  let projectsDir = dataDir.appendingPathComponent("claude-projects", isDirectory: true)
  try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
  let logURL = projectsDir.appendingPathComponent("claude-session.jsonl")
  try writeJSONL(
    [
      [
        "type": "assistant",
        "sessionId": "claude-session",
        "timestamp": "2026-05-24T06:08:17.667Z",
        "message": [
          "id": "chatcmpl-zero",
          "type": "message",
          "role": "assistant",
          "model": "qwen3.6-35b",
          "usage": [
            "input_tokens": 0,
            "output_tokens": 0,
          ],
        ],
      ],
      [
        "type": "assistant",
        "sessionId": "claude-session",
        "timestamp": "2026-05-24T06:08:18.667Z",
        "message": [
          "id": "chatcmpl-nonzero",
          "type": "message",
          "role": "assistant",
          "model": "qwen3.6-35b",
          "usage": [
            "input_tokens": 7,
            "output_tokens": 2,
          ],
        ],
      ],
    ],
    to: logURL,
  )
  let database = try TokMonDatabase(appDataDir: dataDir)
  try database.setScanState(
    filePath: scannerFilePath(logURL),
    state: TokMonScanState(
      offset: fileByteSize(logURL),
      sessionId: "claude-session",
      model: nil,
      lastUsageKey: nil,
      lastMtime: nil,
    ),
  )
  let scanner = TokMonScanner(database: database)
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "claude-code": TokMonSourceConfig(path: projectsDir.path),
    ],
  )

  #expect(try scanner.scan(config: config) == 1)
  let records = try database.allUsageRecords()
  #expect(records.count == 1)
  let record = try #require(records.first)
  #expect(record.inputTokens == 7)
  #expect(record.outputTokens == 2)
}

@Test func scannerImportsCodexArchivedSessionsFromCodexHome() throws {
  let dataDir = try makeTokMonTempDir()
  let codexHome = dataDir.appendingPathComponent("codex-home", isDirectory: true)
  let sessionsDir = codexHome.appendingPathComponent("sessions", isDirectory: true)
  let archivedDir = codexHome.appendingPathComponent("archived_sessions", isDirectory: true)
  try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: archivedDir, withIntermediateDirectories: true)

  let liveLogURL = sessionsDir.appendingPathComponent("live.jsonl")
  try writeJSONL(
    [
      [
        "type": "session_meta",
        "payload": [
          "id": "live-session",
          "model": "gpt-live",
        ],
      ],
      codexTokenCountLine(
        timestamp: "2026-05-14T01:00:00.000Z",
        inputTokens: 10,
        outputTokens: 2,
      ),
    ],
    to: liveLogURL,
  )

  let archivedLogURL = archivedDir.appendingPathComponent("archived.jsonl")
  try writeJSONL(
    [
      [
        "type": "session_meta",
        "payload": [
          "id": "archived-session",
          "model": "gpt-archived",
        ],
      ],
      codexTokenCountLine(
        timestamp: "2026-05-14T02:00:00.000Z",
        inputTokens: 20,
        outputTokens: 4,
      ),
    ],
    to: archivedLogURL,
  )

  let database = try TokMonDatabase(appDataDir: dataDir)
  let scanner = TokMonScanner(database: database)
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "codex": TokMonSourceConfig(path: codexHome.path),
    ],
  )

  #expect(try scanner.scan(config: config) == 2)

  let records = try database.allUsageRecords()
  #expect(records.count == 2)
  #expect(records.map(\.sessionId).sorted() == ["archived-session", "live-session"])
  #expect(records.map(\.model).sorted() == ["gpt-archived", "gpt-live"])
}

@Test func scannerFallsBackToCodexModelProviderWhenModelIsMissing() throws {
  let dataDir = try makeTokMonTempDir()
  let sessionsDir = dataDir.appendingPathComponent("codex-sessions", isDirectory: true)
  try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
  let logURL = sessionsDir.appendingPathComponent("model-provider.jsonl")
  try writeJSONL(
    [
      [
        "type": "session_meta",
        "payload": [
          "id": "model-provider-session",
          "model_provider": "gpt-provider-fallback",
        ],
      ],
      codexTokenCountLine(
        timestamp: "2026-05-14T03:00:00.000Z",
        inputTokens: 15,
        outputTokens: 5,
      ),
    ],
    to: logURL,
  )

  let database = try TokMonDatabase(appDataDir: dataDir)
  let scanner = TokMonScanner(database: database)
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "codex": TokMonSourceConfig(path: sessionsDir.path),
    ],
  )

  #expect(try scanner.scan(config: config) == 1)

  let records = try database.allUsageRecords()
  #expect(records.count == 1)
  let record = try #require(records.first)
  #expect(record.sessionId == "model-provider-session")
  #expect(record.model == "gpt-provider-fallback")
  #expect(record.inputTokens == 15)
  #expect(record.outputTokens == 5)
}

@Test func scannerParsesCodexJavaScriptPayloadStrings() throws {
  let dataDir = try makeTokMonTempDir()
  let sessionsDir = dataDir.appendingPathComponent("codex-sessions", isDirectory: true)
  try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
  let logURL = sessionsDir.appendingPathComponent("javascript-payload.jsonl")
  try writeJSONL(
    [
      [
        "type": "session_meta",
        "payload": "{id: 'session-js', model: 'gpt-js'}",
      ],
      [
        "type": "event_msg",
        "timestamp": "2026-05-14T04:00:00.000Z",
        "payload": "{type: 'token_count', info: {last_token_usage: {input_tokens: 20, output_tokens: 5, cached_input_tokens: 3, reasoning_output_tokens: 2}}}",
      ],
    ],
    to: logURL,
  )
  let database = try TokMonDatabase(appDataDir: dataDir)
  let scanner = TokMonScanner(database: database)
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "codex": TokMonSourceConfig(path: sessionsDir.path),
    ],
  )

  #expect(try scanner.scan(config: config) == 1)

  let records = try database.allUsageRecords()
  #expect(records.count == 1)
  #expect(records.first?.sessionId == "session-js")
  #expect(records.first?.model == "gpt-js")
  #expect(records.first?.inputTokens == 17)
  #expect(records.first?.cacheRead == 3)
  #expect(records.first?.reasoningTokens == 2)
}

@Test func scannerParsesCodexRelaxedPayloadWithArraysEscapesAndScientificNotation() throws {
  let dataDir = try makeTokMonTempDir()
  let sessionsDir = dataDir.appendingPathComponent("codex-sessions", isDirectory: true)
  try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
  let logURL = sessionsDir.appendingPathComponent("relaxed-payload.jsonl")
  // Codex sometimes writes payload as a JavaScript object literal string. This
  // line uses single quotes, an array, escaped quotes, a unicode escape, and
  // scientific notation to exercise the relaxed parser.
  let payload = #"{id: 'session-relaxed', model: 'gpt-relaxed', tags: ['a', 'b', 'c\'d'], label: 'quote: \"hi\" 中文', ratio: 1.5e-2}"#
  try writeJSONL(
    [
      [
        "type": "session_meta",
        "payload": payload,
      ],
      [
        "type": "event_msg",
        "timestamp": "2026-05-14T05:00:00.000Z",
        "payload": "{type: 'token_count', info: {last_token_usage: {input_tokens: 30, output_tokens: 10, cached_input_tokens: 5, reasoning_output_tokens: 1}}}",
      ],
    ],
    to: logURL,
  )
  let database = try TokMonDatabase(appDataDir: dataDir)
  let scanner = TokMonScanner(database: database)
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "codex": TokMonSourceConfig(path: sessionsDir.path),
    ],
  )

  #expect(try scanner.scan(config: config) == 1)

  let records = try database.allUsageRecords()
  #expect(records.count == 1)
  let record = try #require(records.first)
  #expect(record.sessionId == "session-relaxed")
  #expect(record.model == "gpt-relaxed")
  #expect(record.inputTokens == 25)
  #expect(record.outputTokens == 10)
  #expect(record.cacheRead == 5)
  #expect(record.reasoningTokens == 1)
}

@Test func scannerImportsQwenCodeUsageMetadataFromChatLogs() throws {
  let dataDir = try makeTokMonTempDir()
  let qwenRoot = dataDir.appendingPathComponent("qwen-projects", isDirectory: true)
  let chatsDir = qwenRoot
    .appendingPathComponent("-Users-orange-Desktop-Project-job-LLM", isDirectory: true)
    .appendingPathComponent("chats", isDirectory: true)
  try FileManager.default.createDirectory(at: chatsDir, withIntermediateDirectories: true)
  let logURL = chatsDir.appendingPathComponent("qwen-session.jsonl")
  try writeJSONL(
    [
      [
        "uuid": "user-1",
        "sessionId": "qwen-session",
        "timestamp": "2026-05-24T12:48:56.747Z",
        "type": "user",
        "cwd": "/Users/orange/Desktop/Project/job/LLM",
        "message": [
          "role": "user",
          "parts": [
            ["text": "Plan the ASR service"],
          ],
        ],
      ],
      [
        "uuid": "assistant-1",
        "sessionId": "qwen-session",
        "timestamp": "2026-05-24T12:49:00.000Z",
        "type": "assistant",
        "cwd": "/Users/orange/Desktop/Project/job/LLM",
        "model": "qwen3-coder-plus",
        "message": [
          "role": "assistant",
          "parts": [
            ["text": "Sure"],
          ],
        ],
        "usageMetadata": [
          "promptTokenCount": 19179,
          "candidatesTokenCount": 9,
          "thoughtsTokenCount": 3,
          "totalTokenCount": 19191,
          "cachedContentTokenCount": 100,
        ],
      ],
    ],
    to: logURL,
  )
  let database = try TokMonDatabase(appDataDir: dataDir)
  let scanner = TokMonScanner(database: database)
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "qwen-code": TokMonSourceConfig(path: qwenRoot.path),
    ],
  )

  #expect(try scanner.scan(config: config) == 1)
  let record = try #require(try database.allUsageRecords().first)
  #expect(record.source == "qwen-code")
  #expect(record.sessionId == "qwen-session")
  #expect(record.model == "qwen3-coder-plus")
  #expect(record.inputTokens == 19079)
  #expect(record.outputTokens == 9)
  #expect(record.cacheRead == 100)
  #expect(record.reasoningTokens == 3)

  let metadata = try #require(try database.sessionMetadata(source: "qwen-code", id: "qwen-session"))
  #expect(metadata.title == "LLM - Plan the ASR service")
  #expect(metadata.model == "qwen3-coder-plus")
}

@Test func scannerImportsQwenCodeSubagentTelemetryFromChatLogs() throws {
  let dataDir = try makeTokMonTempDir()
  let qwenRoot = dataDir.appendingPathComponent("qwen-projects", isDirectory: true)
  let chatsDir = qwenRoot
    .appendingPathComponent("-Users-orange-Desktop-Project-job-LLM", isDirectory: true)
    .appendingPathComponent("chats", isDirectory: true)
  try FileManager.default.createDirectory(at: chatsDir, withIntermediateDirectories: true)
  let logURL = chatsDir.appendingPathComponent("qwen-subagent-session.jsonl")
  try writeJSONL(
    [
      [
        "uuid": "user-1",
        "sessionId": "qwen-session",
        "timestamp": "2026-05-24T12:48:56.747Z",
        "type": "user",
        "cwd": "/Users/orange/Desktop/Project/job/LLM",
        "message": [
          "role": "user",
          "parts": [
            ["text": "Explore the ASR project"],
          ],
        ],
      ],
      [
        "uuid": "assistant-main",
        "sessionId": "qwen-session",
        "timestamp": "2026-05-24T12:49:04.373Z",
        "type": "assistant",
        "cwd": "/Users/orange/Desktop/Project/job/LLM",
        "model": "qwen3.6-27b",
        "message": [
          "role": "model",
          "parts": [
            ["text": "I will explore it."],
          ],
        ],
        "usageMetadata": [
          "promptTokenCount": 19185,
          "candidatesTokenCount": 238,
          "thoughtsTokenCount": 0,
          "totalTokenCount": 19423,
          "cachedContentTokenCount": 0,
        ],
      ],
      [
        "uuid": "subagent-response",
        "sessionId": "qwen-session",
        "timestamp": "2026-05-24T12:49:20.841Z",
        "type": "system",
        "cwd": "/Users/orange/Desktop/Project/job/LLM",
        "subtype": "ui_telemetry",
        "systemPayload": [
          "uiEvent": [
            "event.name": "qwen-code.api_response",
            "event.timestamp": "2026-05-24T12:49:20.841Z",
            "response_id": "chatcmpl-subagent",
            "model": "qwen3.6-27b",
            "input_token_count": 11357,
            "output_token_count": 211,
            "cached_content_token_count": 57,
            "thoughts_token_count": 13,
            "total_token_count": 11581,
            "prompt_id": "qwen-session#Explore-9e5f1bb1#0",
            "subagent_name": "Explore",
          ],
        ],
      ],
    ],
    to: logURL,
  )
  let database = try TokMonDatabase(appDataDir: dataDir)
  let scanner = TokMonScanner(database: database)
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "qwen-code": TokMonSourceConfig(path: qwenRoot.path),
    ],
  )

  #expect(try scanner.scan(config: config) == 2)
  let records = try database.allUsageRecords()
  #expect(records.map(\.source) == ["qwen-code", "qwen-code"])
  #expect(records.map(\.sessionId) == ["qwen-session", "qwen-session"])
  #expect(records.map(\.model) == ["qwen3.6-27b", "qwen3.6-27b"])
  #expect(records.map(\.inputTokens) == [19185, 11300])
  #expect(records.map(\.outputTokens) == [238, 211])
  #expect(records.map(\.cacheRead) == [0, 57])
  #expect(records.map(\.reasoningTokens) == [0, 13])

  let metadata = try #require(try database.sessionMetadata(source: "qwen-code", id: "qwen-session"))
  #expect(metadata.title == "LLM - Explore the ASR project")
  #expect(metadata.model == "qwen3.6-27b")
}

@Test func scannerBackfillsQwenCodeSubagentTelemetryAfterLegacyScanStateReachedEndOfFile() throws {
  let dataDir = try makeTokMonTempDir()
  let qwenRoot = dataDir.appendingPathComponent("qwen-projects", isDirectory: true)
  let chatsDir = qwenRoot
    .appendingPathComponent("-Users-orange-Desktop-Project-job-LLM", isDirectory: true)
    .appendingPathComponent("chats", isDirectory: true)
  try FileManager.default.createDirectory(at: chatsDir, withIntermediateDirectories: true)
  let logURL = chatsDir.appendingPathComponent("legacy-qwen-subagent-session.jsonl")
  try writeJSONL(
    [
      [
        "uuid": "user-1",
        "sessionId": "qwen-session",
        "timestamp": "2026-05-24T12:48:56.747Z",
        "type": "user",
        "cwd": "/Users/orange/Desktop/Project/job/LLM",
        "message": [
          "role": "user",
          "parts": [
            ["text": "Explore the ASR project"],
          ],
        ],
      ],
      [
        "uuid": "subagent-response",
        "sessionId": "qwen-session",
        "timestamp": "2026-05-24T12:49:20.841Z",
        "type": "system",
        "cwd": "/Users/orange/Desktop/Project/job/LLM",
        "subtype": "ui_telemetry",
        "systemPayload": [
          "uiEvent": [
            "event.name": "qwen-code.api_response",
            "event.timestamp": "2026-05-24T12:49:20.841Z",
            "response_id": "chatcmpl-subagent",
            "model": "qwen3.6-27b",
            "input_token_count": 11357,
            "output_token_count": 211,
            "cached_content_token_count": 57,
            "thoughts_token_count": 13,
            "total_token_count": 11581,
            "prompt_id": "qwen-session#Explore-9e5f1bb1#0",
            "subagent_name": "Explore",
          ],
        ],
      ],
    ],
    to: logURL,
  )
  let database = try TokMonDatabase(appDataDir: dataDir)
  try database.setScanState(
    filePath: scannerFilePath(logURL),
    state: TokMonScanState(
      offset: try fileByteSize(logURL),
      sessionId: "qwen-session",
      model: "qwen3.6-27b",
      lastUsageKey: nil,
      lastMtime: String(try fileModifiedAt(logURL).timeIntervalSince1970),
    ),
  )
  let scanner = TokMonScanner(database: database)
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "qwen-code": TokMonSourceConfig(path: qwenRoot.path),
    ],
  )

  #expect(try scanner.scan(config: config) == 1)
  let record = try #require(try database.allUsageRecords().first)
  #expect(record.source == "qwen-code")
  #expect(record.sessionId == "qwen-session")
  #expect(record.model == "qwen3.6-27b")
  #expect(record.inputTokens == 11300)
  #expect(record.outputTokens == 211)
  #expect(record.cacheRead == 57)
  #expect(record.reasoningTokens == 13)
}

@Test func scannerContinuesAfterUnreadableJsonlFile() throws {
  let dataDir = try makeTokMonTempDir()
  let sessionsDir = dataDir.appendingPathComponent("codex-sessions", isDirectory: true)
  try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
  let unreadableURL = sessionsDir.appendingPathComponent("unreadable.jsonl")
  try "not readable\n".write(to: unreadableURL, atomically: true, encoding: .utf8)
  try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadableURL.path)
  defer {
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: unreadableURL.path)
  }
  let goodURL = sessionsDir.appendingPathComponent("good.jsonl")
  try writeJSONL(
    [
      codexTokenCountLine(
        timestamp: "2026-05-14T05:00:00.000Z",
        inputTokens: 9,
        outputTokens: 2,
      ),
    ],
    to: goodURL,
  )
  let database = try TokMonDatabase(appDataDir: dataDir)
  let scanner = TokMonScanner(database: database)
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "codex": TokMonSourceConfig(path: sessionsDir.path),
    ],
  )

  #expect(try scanner.scan(config: config) == 1)
  #expect(try database.usageRecordCount() == 1)
}

private extension FileHandle {
  static func seekToEndAndWrite(_ string: String, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer {
      try? handle.close()
    }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(string.utf8))
  }
}

private func codexTokenCountLine(
  timestamp: String,
  inputTokens: Int,
  outputTokens: Int,
  cachedInputTokens: Int = 0,
  reasoningOutputTokens: Int = 0,
) -> [String: Any] {
  [
    "type": "event_msg",
    "timestamp": timestamp,
    "payload": [
      "type": "token_count",
      "info": [
        "last_token_usage": [
          "input_tokens": inputTokens,
          "output_tokens": outputTokens,
          "cached_input_tokens": cachedInputTokens,
          "reasoning_output_tokens": reasoningOutputTokens,
        ],
      ],
    ],
  ]
}

private func fileByteSize(_ url: URL) throws -> Int64 {
  let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
  return (attributes[.size] as? NSNumber)?.int64Value ?? 0
}

private func fileModifiedAt(_ url: URL) throws -> Date {
  let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
  guard let modifiedAt = attributes[.modificationDate] as? Date else {
    throw TestSQLiteError("Missing modification date for \(url.path)")
  }
  return modifiedAt
}

private func scannerFilePath(_ url: URL) -> String {
  if url.path.hasPrefix("/var/") {
    return "/private" + url.path
  }
  return url.path
}

private func jsonString(_ value: [String: Any]) throws -> String {
  let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
  return String(decoding: data, as: UTF8.self)
}

private func createOpenCodeDatabase(_ url: URL) throws {
  try withSQLiteDatabase(url) { db in
    try sqliteExec(db, """
      CREATE TABLE session (
        id text PRIMARY KEY,
        project_id text NOT NULL,
        title text NOT NULL,
        directory text NOT NULL,
        model text,
        time_created integer NOT NULL,
        time_updated integer NOT NULL
      );
      CREATE TABLE message (
        id text PRIMARY KEY,
        session_id text NOT NULL,
        time_created integer NOT NULL,
        time_updated integer NOT NULL,
        data text NOT NULL
      );
      CREATE TABLE part (
        id text PRIMARY KEY,
        message_id text NOT NULL,
        session_id text NOT NULL,
        time_created integer NOT NULL,
        time_updated integer NOT NULL,
        data text NOT NULL
      );
    """)
  }
}

private func insertOpenCodeSession(
  databaseURL: URL,
  sessionId: String,
  title: String,
  directory: String,
  model: String,
  timeCreated: Int64,
  timeUpdated: Int64,
) throws {
  try withSQLiteDatabase(databaseURL) { db in
    try insertOpenCodeSession(
      database: db,
      sessionId: sessionId,
      title: title,
      directory: directory,
      model: model,
      timeCreated: timeCreated,
      timeUpdated: timeUpdated,
    )
  }
}

private func insertOpenCodeSession(
  database: OpaquePointer?,
  sessionId: String,
  title: String,
  directory: String,
  model: String,
  timeCreated: Int64,
  timeUpdated: Int64,
) throws {
  try sqliteExec(database, """
    INSERT INTO session (id, project_id, title, directory, model, time_created, time_updated)
    VALUES ('\(sessionId)', 'project-1', '\(title)', '\(directory)', '\(model)', \(timeCreated), \(timeUpdated));
  """)
}

private func insertOpenCodeAssistantMessage(
  databaseURL: URL,
  messageId: String,
  sessionId: String,
  inputTokens: Int,
  outputTokens: Int,
  reasoningTokens: Int,
  cacheRead: Int,
  cacheWrite: Int,
  modelID: String,
  providerID: String,
  created: Int64,
  completed: Int64,
) throws {
  try withSQLiteDatabase(databaseURL) { db in
    try insertOpenCodeAssistantMessage(
      database: db,
      messageId: messageId,
      sessionId: sessionId,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      reasoningTokens: reasoningTokens,
      cacheRead: cacheRead,
      cacheWrite: cacheWrite,
      modelID: modelID,
      providerID: providerID,
      created: created,
      completed: completed,
    )
  }
}

private func insertOpenCodeAssistantMessage(
  database: OpaquePointer?,
  messageId: String,
  sessionId: String,
  inputTokens: Int,
  outputTokens: Int,
  reasoningTokens: Int,
  cacheRead: Int,
  cacheWrite: Int,
  modelID: String,
  providerID: String,
  created: Int64,
  completed: Int64,
) throws {
  let data = try jsonString([
    "role": "assistant",
    "tokens": [
      "total": inputTokens + outputTokens + reasoningTokens + cacheRead + cacheWrite,
      "input": inputTokens,
      "output": outputTokens,
      "reasoning": reasoningTokens,
      "cache": [
        "read": cacheRead,
        "write": cacheWrite,
      ],
    ],
    "modelID": modelID,
    "providerID": providerID,
    "time": [
      "created": created,
      "completed": completed,
    ],
  ])
  try sqliteExec(database, """
    INSERT INTO message (id, session_id, time_created, time_updated, data)
    VALUES ('\(messageId)', '\(sessionId)', \(created), \(completed), '\(data.replacingOccurrences(of: "'", with: "''"))');
  """)
}

private func insertOpenCodeUserMessage(
  databaseURL: URL,
  messageId: String,
  sessionId: String,
  created: Int64,
) throws {
  try withSQLiteDatabase(databaseURL) { db in
    try insertOpenCodeUserMessage(
      database: db,
      messageId: messageId,
      sessionId: sessionId,
      created: created,
    )
  }
}

private func insertOpenCodeUserMessage(
  database: OpaquePointer?,
  messageId: String,
  sessionId: String,
  created: Int64,
) throws {
  let data = try jsonString([
    "role": "user",
    "time": [
      "created": created,
    ],
  ])
  try sqliteExec(database, """
    INSERT INTO message (id, session_id, time_created, time_updated, data)
    VALUES ('\(messageId)', '\(sessionId)', \(created), \(created), '\(data.replacingOccurrences(of: "'", with: "''"))');
  """)
}

private func insertOpenCodeUserTextPart(
  databaseURL: URL,
  partId: String,
  messageId: String,
  sessionId: String,
  text: String,
  created: Int64,
) throws {
  try withSQLiteDatabase(databaseURL) { db in
    try insertOpenCodeUserTextPart(
      database: db,
      partId: partId,
      messageId: messageId,
      sessionId: sessionId,
      text: text,
      created: created,
    )
  }
}

private func insertOpenCodeUserTextPart(
  database: OpaquePointer?,
  partId: String,
  messageId: String,
  sessionId: String,
  text: String,
  created: Int64,
) throws {
  let data = try jsonString([
    "type": "text",
    "text": text,
    "time": [
      "start": created,
      "end": created + 1,
    ],
  ])
  try sqliteExec(database, """
    INSERT INTO part (id, message_id, session_id, time_created, time_updated, data)
    VALUES ('\(partId)', '\(messageId)', '\(sessionId)', \(created), \(created), '\(data.replacingOccurrences(of: "'", with: "''"))');
  """)
}

private func withSQLiteDatabase(_ url: URL, _ action: (OpaquePointer?) throws -> Void) throws {
  var db: OpaquePointer?
  guard sqlite3_open(url.path, &db) == SQLITE_OK else {
    let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open SQLite database"
    if let db {
      sqlite3_close(db)
    }
    throw TestSQLiteError(message)
  }
  defer {
    sqlite3_close(db)
  }
  try action(db)
}

private func sqliteExec(_ db: OpaquePointer?, _ sql: String) throws {
  var errorMessage: UnsafeMutablePointer<CChar>?
  let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
  guard result == SQLITE_OK else {
    let message = errorMessage.map { String(cString: $0) } ?? "SQLite exec failed"
    sqlite3_free(errorMessage)
    throw TestSQLiteError(message)
  }
}

private struct TestSQLiteError: Error {
  let message: String

  init(_ message: String) {
    self.message = message
  }
}
