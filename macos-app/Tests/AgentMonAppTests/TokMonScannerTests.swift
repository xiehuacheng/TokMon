import Foundation
import Testing
@testable import AgentMonApp

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
}

@Test func scannerSkipsUnchangedFilesAndRescansTruncatedFiles() throws {
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
  #expect(try scanner.scan(config: config) == 0)

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

private func writeJSONL(_ values: [[String: Any]], to url: URL) throws {
  let content = try values.map(JSONLine).joined(separator: "\n") + "\n"
  try content.write(to: url, atomically: true, encoding: .utf8)
}

private func fileByteSize(_ url: URL) throws -> Int64 {
  let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
  return (attributes[.size] as? NSNumber)?.int64Value ?? 0
}

private func scannerFilePath(_ url: URL) -> String {
  if url.path.hasPrefix("/var/") {
    return "/private" + url.path
  }
  return url.path
}

private func JSONLine(_ value: [String: Any]) throws -> String {
  let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
  return String(decoding: data, as: UTF8.self) + "\n"
}

private func jsonString(_ value: [String: Any]) throws -> String {
  let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
  return String(decoding: data, as: UTF8.self)
}
