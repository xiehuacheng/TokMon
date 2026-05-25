import Foundation
import SQLite3

final class TokMonScanner {
  private static let qwenCodeScanStateVersion = "qwen-code-telemetry-v1"

  private let database: TokMonDatabase

  init(database: TokMonDatabase) {
    self.database = database
  }

  func scan(config: TokMonConfig) throws -> Int {
    var count = 0
    if let source = config.sources["claude-code"] {
      count += try scanClaudeCode(directory: expandedPath(source.path))
    }
    if let source = config.sources["codex"] {
      count += try scanCodex(directory: expandedPath(source.path))
    }
    if let source = config.sources["opencode"] {
      count += try scanOpenCode(directory: expandedPath(source.path))
    }
    if let source = config.sources["qwen-code"] {
      count += try scanQwenCode(directory: expandedPath(source.path))
    }
    return count
  }

  private func scanClaudeCode(directory: URL) throws -> Int {
    try scanFiles(in: directory) { fileURL in
      try scanClaudeFile(fileURL, fallbackSessionId: fileURL.deletingPathExtension().lastPathComponent)
    }
  }

  private func scanCodex(directory: URL) throws -> Int {
    return try scanFiles(in: directory) { fileURL in
      try scanCodexFile(
        fileURL,
        fallbackSessionId: codexFallbackSessionId(for: fileURL),
      )
    }
  }

  private func scanOpenCode(directory: URL) throws -> Int {
    let databaseURL = directory.appendingPathComponent("opencode.db")
    guard FileManager.default.fileExists(atPath: databaseURL.path) else {
      return 0
    }
    return try scanOpenCodeDatabase(databaseURL)
  }

  private func scanQwenCode(directory: URL) throws -> Int {
    try scanFiles(in: directory) { fileURL in
      try scanQwenCodeFile(fileURL, fallbackSessionId: fileURL.deletingPathExtension().lastPathComponent)
    }
  }

  private func scanFiles(in directory: URL, scanner: (URL) throws -> Int) throws -> Int {
    guard let enumerator = FileManager.default.enumerator(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles],
    ) else {
      return 0
    }

    var count = 0
    for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
      guard
        let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
        values.isRegularFile == true
      else {
        continue
      }
      count += try scanner(fileURL)
    }
    return count
  }

  private func scanClaudeFile(_ fileURL: URL, fallbackSessionId: String) throws -> Int {
    let filePath = fileURL.path
    guard let fileSize = try? byteSize(fileURL) else {
      return 0
    }
    let fileMtime = fileModificationStamp(fileURL)
    let state = try database.scanState(filePath: filePath)
    if let fileMtime,
       state.offset == fileSize,
       state.lastMtime == fileMtime,
       state.lastUsageKey != nil {
      return 0
    }
    let shouldRescanFromStart = fileSize < state.offset
      || (fileSize == state.offset && (fileMtime == nil || state.lastMtime == nil || state.lastMtime != fileMtime))
      || (fileSize == state.offset && state.lastUsageKey == nil)
    let range = shouldRescanFromStart
      ? AppendRange(offset: 0, length: fileSize, nextOffset: fileSize)
      : appendRange(fileURL: fileURL, fileSize: fileSize, offset: state.offset)
    guard let range else {
      return 0
    }
    guard let lines = try? readLines(fileURL, range: range) else {
      return 0
    }

    var count = 0
    var lastUsageKey = range.offset == 0 ? nil : state.lastUsageKey
    var model = range.offset == 0 ? nil : state.model
    var firstPrompt: String?
    var lastPrompt: String?
    var startedAt: String?
    var lastActiveAt: String?
    var projectPath: String?
    var nextOffset = range.offset
    for line in lines {
      guard let object = parseJSONObject(line.text) else {
        if line.isTerminated {
          nextOffset = line.nextOffset
          continue
        }
        break
      }
      nextOffset = line.nextOffset
      if line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        continue
      }
      if let timestamp = stringValue(object["timestamp"]) {
        startedAt = startedAt ?? timestamp
        lastActiveAt = timestamp
      }
      projectPath = projectPath ?? normalizedPrompt(stringValue(object["cwd"]))
      if let prompt = claudeUserMessage(object) {
        firstPrompt = firstPrompt ?? prompt
        lastPrompt = prompt
      }
      guard let parsed = parseClaudeUsageRecord(object, fallbackSessionId: fallbackSessionId) else {
        continue
      }
      model = parsed.usage.model
      let usageKey = parsed.messageId.isEmpty ? claudeUsageKey(parsed.usage) : parsed.messageId
      if usageKey == lastUsageKey {
        continue
      }
      lastUsageKey = usageKey
      if try database.insertUsage(parsed.usage) {
        count += 1
      }
    }

    try database.setScanState(
      filePath: filePath,
      state: TokMonScanState(
        offset: nextOffset,
        sessionId: fallbackSessionId,
        model: model,
        lastUsageKey: lastUsageKey,
        lastMtime: fileMtime,
      ),
    )
    try upsertClaudeSessionMetadata(
      sessionId: fallbackSessionId,
      model: model,
      firstPrompt: firstPrompt,
      lastPrompt: lastPrompt,
      startedAt: startedAt,
      lastActiveAt: lastActiveAt,
      filePath: filePath,
      projectPath: projectPath,
    )
    return count
  }

  private func scanCodexFile(
    _ fileURL: URL,
    fallbackSessionId: String,
  ) throws -> Int {
    let filePath = fileURL.path
    guard let fileSize = try? byteSize(fileURL) else {
      return 0
    }
    let fileMtime = fileModificationStamp(fileURL)
    let state = try database.scanState(filePath: filePath)
    if let fileMtime, state.offset == fileSize, state.lastMtime == fileMtime {
      return 0
    }
    let shouldRescanFromStart = fileSize < state.offset
      || (fileSize == state.offset && (fileMtime == nil || state.lastMtime == nil || state.lastMtime != fileMtime))
    let range = shouldRescanFromStart
      ? AppendRange(offset: 0, length: fileSize, nextOffset: fileSize)
      : appendRange(fileURL: fileURL, fileSize: fileSize, offset: state.offset)
    guard let range else {
      return 0
    }
    guard let lines = try? readLines(fileURL, range: range) else {
      return 0
    }

    var count = 0
    var resolvedSessionId = range.offset == 0 ? fallbackSessionId : (state.sessionId ?? fallbackSessionId)
    var lastModel = range.offset == 0 ? "unknown" : (state.model ?? "unknown")
    var lastUsageKey = range.offset == 0 ? nil : state.lastUsageKey
    var firstPrompt: String?
    var lastPrompt: String?
    var startedAt: String?
    var lastActiveAt: String?
    var projectPath: String?

    var nextOffset = range.offset
    for line in lines {
      guard let object = parseJSONObject(line.text) else {
        if line.isTerminated {
          nextOffset = line.nextOffset
          continue
        }
        break
      }
      nextOffset = line.nextOffset
      if line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        continue
      }
      if let timestamp = stringValue(object["timestamp"]) {
        if startedAt == nil {
          startedAt = timestamp
        }
        lastActiveAt = timestamp
      }

      if let type = object["type"] as? String, type == "session_meta" || type == "turn_context" {
        let payload = parsePayload(object["payload"])
        if type == "session_meta",
           let sessionId = payload?["id"] as? String,
           !sessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          resolvedSessionId = sessionId
        }
        if let model = payload?["model"] as? String,
           !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          lastModel = model
        }
        projectPath = projectPath ?? normalizedPrompt(stringValue(payload?["cwd"]))
      }

      if let message = codexUserMessage(object) {
        firstPrompt = firstPrompt ?? message
        lastPrompt = message
      } else if firstPrompt == nil, let message = codexResponseUserMessage(object) {
        firstPrompt = message
      }

      guard let usage = codexLastTokenUsage(object), hasCodexTokenUsage(usage) else {
        continue
      }
      let usageKey = codexUsageKey(usage, timestamp: stringValue(object["timestamp"]))
      if usageKey == lastUsageKey {
        continue
      }
      lastUsageKey = usageKey

      let inputTokens = intValue(usage["input_tokens"])
      let cachedInputTokens = intValue(usage["cached_input_tokens"])
      let record = TokMonUsageRecord(
        source: "codex",
        sessionId: resolvedSessionId,
        model: lastModel,
        inputTokens: max(inputTokens - cachedInputTokens, 0),
        outputTokens: intValue(usage["output_tokens"]),
        cacheCreation: 0,
        cacheRead: cachedInputTokens,
        reasoningTokens: intValue(usage["reasoning_output_tokens"]),
        createdAt: stringValue(object["timestamp"]) ?? ISO8601DateFormatter().string(from: Date()),
      )
      if try database.insertUsage(record) {
        count += 1
      }
    }

    try database.setScanState(
      filePath: filePath,
      state: TokMonScanState(
        offset: nextOffset,
        sessionId: resolvedSessionId,
        model: lastModel,
        lastUsageKey: lastUsageKey,
        lastMtime: fileMtime,
      ),
    )
    try upsertCodexSessionMetadata(
      sessionId: resolvedSessionId,
      sessionName: codexSessionName(for: resolvedSessionId, filePath: filePath),
      model: lastModel,
      firstPrompt: firstPrompt,
      lastPrompt: lastPrompt,
      startedAt: startedAt,
      lastActiveAt: lastActiveAt,
      filePath: filePath,
      projectPath: projectPath,
    )
    return count
  }

  private func scanQwenCodeFile(_ fileURL: URL, fallbackSessionId: String) throws -> Int {
    let filePath = fileURL.path
    guard let fileSize = try? byteSize(fileURL) else {
      return 0
    }
    let fileMtime = fileModificationStamp(fileURL)
    let state = try database.scanState(filePath: filePath)
    let hasCurrentQwenCodeState = hasCurrentQwenCodeScanState(state)
    if let fileMtime,
       hasCurrentQwenCodeState,
       state.offset == fileSize,
       state.lastMtime == fileMtime {
      return 0
    }
    let shouldRescanFromStart = !hasCurrentQwenCodeState
      || fileSize < state.offset
      || (fileSize == state.offset && (fileMtime == nil || state.lastMtime == nil || state.lastMtime != fileMtime))
    let range = shouldRescanFromStart
      ? AppendRange(offset: 0, length: fileSize, nextOffset: fileSize)
      : appendRange(fileURL: fileURL, fileSize: fileSize, offset: state.offset)
    guard let range else {
      return 0
    }
    guard let lines = try? readLines(fileURL, range: range) else {
      return 0
    }

    var count = 0
    var resolvedSessionId = range.offset == 0 ? fallbackSessionId : (state.sessionId ?? fallbackSessionId)
    var lastModel = range.offset == 0 ? "unknown" : (state.model ?? "unknown")
    var lastUsageKey = range.offset == 0 ? nil : qwenCodeStoredUsageKey(state.lastUsageKey)
    var firstPrompt: String?
    var lastPrompt: String?
    var startedAt: String?
    var lastActiveAt: String?
    var projectPath: String?
    var nextOffset = range.offset

    for line in lines {
      guard let object = parseJSONObject(line.text) else {
        if line.isTerminated {
          nextOffset = line.nextOffset
          continue
        }
        break
      }
      nextOffset = line.nextOffset
      if line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        continue
      }
      if let sessionId = normalizedPrompt(stringValue(object["sessionId"])) {
        resolvedSessionId = sessionId
      }
      if let timestamp = stringValue(object["timestamp"]) {
        startedAt = startedAt ?? timestamp
        lastActiveAt = timestamp
      }
      projectPath = projectPath ?? normalizedPrompt(stringValue(object["cwd"]))
      if let prompt = qwenUserMessage(object) {
        firstPrompt = firstPrompt ?? prompt
        lastPrompt = prompt
      }
      if let telemetry = parseQwenSubagentTelemetryRecord(
        object,
        sessionId: resolvedSessionId,
        fallbackModel: lastModel,
      ) {
        lastModel = telemetry.usage.model
        if telemetry.usageKey == lastUsageKey {
          continue
        }
        lastUsageKey = telemetry.usageKey
        if try database.insertUsage(telemetry.usage) {
          count += 1
        }
        continue
      }
      guard let usage = object["usageMetadata"] as? [String: Any],
            object["type"] as? String == "assistant" else {
        continue
      }
      let model = normalizedPrompt(stringValue(object["model"])) ?? lastModel
      lastModel = model
      let usageKey = normalizedPrompt(stringValue(object["uuid"]))
        ?? qwenUsageKey(usage, timestamp: stringValue(object["timestamp"]))
      if usageKey == lastUsageKey {
        continue
      }
      lastUsageKey = usageKey
      let cacheRead = intValue(usage["cachedContentTokenCount"])
      let inputTokens = max(intValue(usage["promptTokenCount"]) - cacheRead, 0)
      let record = TokMonUsageRecord(
        source: "qwen-code",
        sessionId: resolvedSessionId,
        model: model,
        inputTokens: inputTokens,
        outputTokens: intValue(usage["candidatesTokenCount"]),
        cacheCreation: 0,
        cacheRead: cacheRead,
        reasoningTokens: intValue(usage["thoughtsTokenCount"]),
        createdAt: stringValue(object["timestamp"]) ?? ISO8601DateFormatter().string(from: Date()),
      )
      if try database.insertUsage(record) {
        count += 1
      }
    }

    try database.setScanState(
      filePath: filePath,
      state: TokMonScanState(
        offset: nextOffset,
        sessionId: resolvedSessionId,
        model: lastModel,
        lastUsageKey: qwenCodeScanStateUsageKey(lastUsageKey),
        lastMtime: fileMtime,
      ),
    )
    try upsertQwenCodeSessionMetadata(
      sessionId: resolvedSessionId,
      model: lastModel,
      firstPrompt: firstPrompt,
      lastPrompt: lastPrompt,
      startedAt: startedAt,
      lastActiveAt: lastActiveAt,
      filePath: filePath,
      projectPath: projectPath,
    )
    return count
  }

  private func scanOpenCodeDatabase(_ databaseURL: URL) throws -> Int {
    let filePath = databaseURL.path
    guard let databaseSignature = openCodeDatabaseSignature(databaseURL) else {
      return 0
    }
    let state = try database.scanState(filePath: filePath)
    if state.offset == databaseSignature.size, state.lastMtime == databaseSignature.stamp {
      if try database.hasSessionMetadataContainingEnvironmentContext(source: "opencode", filePath: filePath) {
        try backfillOpenCodeSessionMetadataIfNeeded(databaseURL)
      }
      return 0
    }

    let openCodeMessages = try openCodeUsageMessages(databaseURL)
    var count = 0
    var lastUsageKey = state.lastUsageKey
    for message in openCodeMessages where message.usageKey != state.lastUsageKey {
      let record = TokMonUsageRecord(
        source: "opencode",
        sessionId: message.session.id,
        model: message.model,
        inputTokens: message.inputTokens,
        outputTokens: message.outputTokens,
        cacheCreation: message.cacheWrite,
        cacheRead: message.cacheRead,
        reasoningTokens: message.reasoningTokens,
        createdAt: message.createdAt,
      )
      if try database.replaceOpenCodeProviderPrefixedUsageRecordIfNeeded(
        with: record,
        provider: message.provider,
      ) {
        lastUsageKey = message.usageKey
        try upsertOpenCodeSessionMetadata(message.session)
        continue
      }
      if try database.insertUsage(record) {
        count += 1
      }
      lastUsageKey = message.usageKey
      try upsertOpenCodeSessionMetadata(message.session)
    }

    if lastUsageKey == nil {
      for message in openCodeMessages {
        try upsertOpenCodeSessionMetadata(message.session)
      }
    }
    try database.setScanState(
      filePath: filePath,
      state: TokMonScanState(
        offset: databaseSignature.size,
        sessionId: openCodeMessages.last?.session.id ?? state.sessionId,
        model: openCodeMessages.last?.model ?? state.model,
        lastUsageKey: lastUsageKey,
        lastMtime: databaseSignature.stamp,
      ),
    )
    return count
  }

  private func backfillOpenCodeSessionMetadataIfNeeded(_ databaseURL: URL) throws {
    let openCodeMessages = try openCodeUsageMessages(databaseURL)
    for message in openCodeMessages {
      try upsertOpenCodeSessionMetadata(message.session)
    }
  }

  private func openCodeUsageMessages(_ databaseURL: URL) throws -> [OpenCodeUsageMessage] {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(databaseURL.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let connection else {
      let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open opencode database"
      if let connection {
        sqlite3_close(connection)
      }
      throw TokMonScannerError.openCodeDatabase(message)
    }
    defer {
      sqlite3_close(connection)
    }

    let sql = """
      SELECT m.id,
             m.session_id,
             m.time_created,
             m.time_updated,
             m.data,
             s.title,
             s.directory,
             s.model,
             s.time_created,
             s.time_updated,
             (
               SELECT json_extract(p.data, '$.text')
               FROM message user_message
               JOIN part p ON p.message_id = user_message.id
                 AND p.session_id = user_message.session_id
               WHERE user_message.session_id = m.session_id
                 AND json_extract(user_message.data, '$.role') = 'user'
                 AND json_extract(p.data, '$.type') = 'text'
                 AND NULLIF(TRIM(json_extract(p.data, '$.text')), '') IS NOT NULL
                 AND TRIM(json_extract(p.data, '$.text')) NOT LIKE '<environment_context>%'
                 AND COALESCE(json_extract(p.data, '$.ignored'), 0) = 0
                 AND COALESCE(json_extract(p.data, '$.synthetic'), 0) = 0
               ORDER BY user_message.time_created ASC,
                        user_message.id ASC,
                        p.time_created ASC,
                        p.id ASC
               LIMIT 1
             ) as first_prompt
      FROM message m
      JOIN session s ON s.id = m.session_id
      ORDER BY m.time_created ASC, m.id ASC
    """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
      throw TokMonScannerError.openCodeDatabase(String(cString: sqlite3_errmsg(connection)))
    }
    defer {
      sqlite3_finalize(statement)
    }

    var messages: [OpenCodeUsageMessage] = []
    var result = sqlite3_step(statement)
    while result == SQLITE_ROW {
      let messageId = openCodeStringColumn(statement, 0)
      let sessionId = openCodeStringColumn(statement, 1)
      let messageTimeCreated = sqlite3_column_int64(statement, 2)
      let messageTimeUpdated = sqlite3_column_int64(statement, 3)
      let messageData = openCodeStringColumn(statement, 4)
      let sessionTitle = openCodeStringColumn(statement, 5)
      let sessionDirectory = openCodeStringColumn(statement, 6)
      let sessionModel = openCodeStringColumn(statement, 7)
      let sessionTimeCreated = sqlite3_column_int64(statement, 8)
      let sessionTimeUpdated = sqlite3_column_int64(statement, 9)
      let sessionFirstPrompt = openCodeStringColumn(statement, 10)

      if let parsed = parseOpenCodeUsageMessage(
        messageId: messageId,
        sessionId: sessionId,
        messageTimeCreated: messageTimeCreated,
        messageTimeUpdated: messageTimeUpdated,
        messageData: messageData,
        sessionTitle: sessionTitle,
        sessionDirectory: sessionDirectory,
        sessionModel: sessionModel,
        sessionTimeCreated: sessionTimeCreated,
        sessionTimeUpdated: sessionTimeUpdated,
        firstPrompt: sessionFirstPrompt,
        databasePath: databaseURL.path,
      ) {
        messages.append(parsed)
      }
      result = sqlite3_step(statement)
    }

    guard result == SQLITE_DONE else {
      throw TokMonScannerError.openCodeDatabase(String(cString: sqlite3_errmsg(connection)))
    }
    return messages
  }

  private func parseOpenCodeUsageMessage(
    messageId: String,
    sessionId: String,
    messageTimeCreated: Int64,
    messageTimeUpdated: Int64,
    messageData: String,
    sessionTitle: String,
    sessionDirectory: String,
    sessionModel: String,
    sessionTimeCreated: Int64,
    sessionTimeUpdated: Int64,
    firstPrompt: String,
    databasePath: String,
  ) -> OpenCodeUsageMessage? {
    guard let object = parseJSONString(messageData),
          stringValue(object["role"]) == "assistant",
          let tokens = object["tokens"] as? [String: Any] else {
      return nil
    }

    let inputTokens = intValue(tokens["input"])
    let outputTokens = intValue(tokens["output"])
    let reasoningTokens = intValue(tokens["reasoning"])
    let cache = tokens["cache"] as? [String: Any]
    let cacheRead = intValue(cache?["read"])
    let cacheWrite = intValue(cache?["write"])
    guard inputTokens != 0 || outputTokens != 0 || reasoningTokens != 0 || cacheRead != 0 || cacheWrite != 0 else {
      return nil
    }

    let model = normalizedPrompt(stringValue(object["modelID"]))
      ?? normalizedPrompt(openCodeModelId(from: sessionModel))
      ?? "unknown"
    let provider = normalizedPrompt(stringValue(object["providerID"]))
      ?? normalizedPrompt(openCodeProviderId(from: sessionModel))
    let createdMilliseconds = openCodeMessageCreatedMilliseconds(
      object: object,
      fallback: messageTimeCreated == 0 ? messageTimeUpdated : messageTimeCreated,
    )
    let createdAt = isoTimestamp(millisecondsSince1970: createdMilliseconds)
    let title = normalizedPrompt(sessionTitle)
    let projectPath = normalizedPrompt(sessionDirectory)
    let prompt = normalizedOpenCodeUserPrompt(firstPrompt)
    let session = OpenCodeSessionSnapshot(
      id: sessionId,
      title: title,
      firstPrompt: prompt,
      model: model,
      startedAt: isoTimestamp(millisecondsSince1970: sessionTimeCreated),
      lastActiveAt: isoTimestamp(millisecondsSince1970: max(sessionTimeUpdated, messageTimeUpdated)),
      filePath: databasePath,
      projectPath: projectPath,
    )
    return OpenCodeUsageMessage(
      usageKey: "\(messageId):\(createdMilliseconds):\(inputTokens):\(outputTokens):\(cacheRead):\(cacheWrite):\(reasoningTokens)",
      session: session,
      model: model,
      provider: provider,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      cacheWrite: cacheWrite,
      cacheRead: cacheRead,
      reasoningTokens: reasoningTokens,
      createdAt: createdAt,
    )
  }

  private func parseClaudeUsageRecord(
    _ object: [String: Any],
    fallbackSessionId: String,
  ) -> (messageId: String, usage: TokMonUsageRecord)? {
    guard object["type"] as? String == "assistant" else {
      return nil
    }

    let messageObject: [String: Any]?
    if let message = object["message"] as? [String: Any] {
      messageObject = message
    } else {
      messageObject = parsePayload(object["message"])
    }

    guard let messageObject,
          let usage = messageObject["usage"] as? [String: Any] else {
      return nil
    }

    let record = TokMonUsageRecord(
      source: "claude-code",
      sessionId: stringValue(object["sessionId"]) ?? fallbackSessionId,
      model: stringValue(messageObject["model"]) ?? "unknown",
      inputTokens: intValue(usage["input_tokens"], fallback: intValue(usage["prompt_tokens"])),
      outputTokens: intValue(usage["output_tokens"], fallback: intValue(usage["completion_tokens"])),
      cacheCreation: intValue(usage["cache_creation_input_tokens"]),
      cacheRead: intValue(usage["cache_read_input_tokens"]),
      reasoningTokens: 0,
      createdAt: stringValue(object["timestamp"]) ?? ISO8601DateFormatter().string(from: Date()),
    )
    return (stringValue(messageObject["id"]) ?? "", record)
  }

  private func claudeUserMessage(_ object: [String: Any]) -> String? {
    guard object["type"] as? String == "user" else {
      return nil
    }
    let messageObject: [String: Any]?
    if let message = object["message"] as? [String: Any] {
      messageObject = message
    } else {
      messageObject = parsePayload(object["message"])
    }
    let content = messageObject?["content"] ?? object["content"]
    return extractClaudeText(from: content).flatMap(normalizedPrompt).flatMap { prompt in
      prompt.hasPrefix("<") ? nil : prompt
    }
  }

  private func extractClaudeText(from content: Any?) -> String? {
    if let text = content as? String {
      return text
    }
    guard let parts = content as? [[String: Any]] else {
      return nil
    }
    return parts.compactMap { part in
      stringValue(part["text"])
    }.first
  }

  private func codexLastTokenUsage(_ object: [String: Any]) -> [String: Any]? {
    guard object["type"] as? String == "event_msg",
          let payload = parsePayload(object["payload"]),
          payload["type"] as? String == "token_count",
          let info = payload["info"] as? [String: Any] else {
      return nil
    }
    return info["last_token_usage"] as? [String: Any]
  }

  private func codexUserMessage(_ object: [String: Any]) -> String? {
    guard object["type"] as? String == "event_msg",
          let payload = parsePayload(object["payload"]),
          payload["type"] as? String == "user_message" else {
      return nil
    }
    return normalizedPrompt(stringValue(payload["message"]))
  }

  private func codexResponseUserMessage(_ object: [String: Any]) -> String? {
    guard object["type"] as? String == "response_item",
          let payload = parsePayload(object["payload"]),
          payload["type"] as? String == "message",
          payload["role"] as? String == "user" else {
      return nil
    }
    return extractCodexText(from: payload["content"]).flatMap(normalizedPrompt)
  }

  private func qwenUserMessage(_ object: [String: Any]) -> String? {
    guard object["type"] as? String == "user",
          let message = object["message"] as? [String: Any] else {
      return nil
    }
    return extractQwenText(from: message["parts"]).flatMap(normalizedPrompt)
  }

  private func parseQwenSubagentTelemetryRecord(
    _ object: [String: Any],
    sessionId: String,
    fallbackModel: String,
  ) -> (usageKey: String, usage: TokMonUsageRecord)? {
    guard object["type"] as? String == "system",
          normalizedPrompt(stringValue(object["subtype"])) == "ui_telemetry",
          let systemPayload = parsePayload(object["systemPayload"]),
          let uiEvent = parsePayload(systemPayload["uiEvent"]),
          normalizedPrompt(stringValue(uiEvent["event.name"])) == "qwen-code.api_response",
          normalizedPrompt(stringValue(uiEvent["subagent_name"])) != nil else {
      return nil
    }

    let cacheRead = intValue(uiEvent["cached_content_token_count"])
    let inputTokens = max(intValue(uiEvent["input_token_count"]) - cacheRead, 0)
    let outputTokens = intValue(uiEvent["output_token_count"])
    let reasoningTokens = intValue(uiEvent["thoughts_token_count"])
    guard inputTokens != 0 || outputTokens != 0 || cacheRead != 0 || reasoningTokens != 0 else {
      return nil
    }

    let model = normalizedPrompt(stringValue(uiEvent["model"])) ?? fallbackModel
    let createdAt = normalizedPrompt(stringValue(uiEvent["event.timestamp"]))
      ?? stringValue(object["timestamp"])
      ?? ISO8601DateFormatter().string(from: Date())
    let usage = TokMonUsageRecord(
      source: "qwen-code",
      sessionId: sessionId,
      model: model,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      cacheCreation: 0,
      cacheRead: cacheRead,
      reasoningTokens: reasoningTokens,
      createdAt: createdAt,
    )
    return (
      normalizedPrompt(stringValue(uiEvent["response_id"]))
        ?? normalizedPrompt(stringValue(uiEvent["prompt_id"]))
        ?? qwenTelemetryUsageKey(uiEvent, timestamp: createdAt),
      usage
    )
  }

  private func extractCodexText(from content: Any?) -> String? {
    if let text = content as? String {
      return text
    }
    guard let parts = content as? [[String: Any]] else {
      return nil
    }
    let text = parts.compactMap { part in
      stringValue(part["text"])
        ?? stringValue(part["input_text"])
        ?? stringValue(part["output_text"])
    }.joined(separator: "\n")
    return text.isEmpty ? nil : text
  }

  private func extractQwenText(from parts: Any?) -> String? {
    guard let parts = parts as? [[String: Any]] else {
      return nil
    }
    let text = parts.compactMap { part in
      stringValue(part["text"])
    }.joined(separator: "\n")
    return text.isEmpty ? nil : text
  }

  private func normalizedPrompt(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty else {
      return nil
    }
    return trimmed
  }

  private func normalizedOpenCodeUserPrompt(_ value: String?) -> String? {
    guard let prompt = normalizedPrompt(value) else {
      return nil
    }
    return prompt.hasPrefix("<environment_context>") ? nil : prompt
  }

  private func hasCurrentQwenCodeScanState(_ state: TokMonScanState) -> Bool {
    state.lastUsageKey?.hasPrefix(Self.qwenCodeScanStateVersion + ":") == true
  }

  private func qwenCodeStoredUsageKey(_ value: String?) -> String? {
    guard let value else {
      return nil
    }
    let prefix = Self.qwenCodeScanStateVersion + ":"
    guard value.hasPrefix(prefix) else {
      return value
    }
    let key = String(value.dropFirst(prefix.count))
    return key.isEmpty ? nil : key
  }

  private func qwenCodeScanStateUsageKey(_ value: String?) -> String {
    Self.qwenCodeScanStateVersion + ":" + (value ?? "")
  }

  private func codexFallbackSessionId(for fileURL: URL) -> String {
    let fileName = fileURL.deletingPathExtension().lastPathComponent
    if let range = fileName.range(
      of: #"[0-9A-Fa-f]{8,}-[0-9A-Fa-f-]{20,}"#,
      options: .regularExpression,
    ) {
      return String(fileName[range])
    }
    return fileName
  }

  private func codexSessionMetadataSnapshot(
    _ fileURL: URL,
    fallbackSessionId: String,
  ) -> (sessionId: String?, model: String?, firstPrompt: String?, lastPrompt: String?, startedAt: String?, lastActiveAt: String?, projectPath: String?) {
    guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
      return (fallbackSessionId, nil, nil, nil, nil, nil, nil)
    }

    var sessionId: String?
    var model: String?
    var firstPrompt: String?
    var lastPrompt: String?
    var startedAt: String?
    var lastActiveAt: String?
    var projectPath: String?

    for line in text.components(separatedBy: "\n") {
      guard let object = parseJSONObject(line) else {
        continue
      }
      if let timestamp = stringValue(object["timestamp"]) {
        startedAt = startedAt ?? timestamp
        lastActiveAt = timestamp
      }

      if let type = object["type"] as? String, type == "session_meta" || type == "turn_context" {
        let payload = parsePayload(object["payload"])
        if type == "session_meta",
           let id = normalizedPrompt(stringValue(payload?["id"])) {
          sessionId = id
        }
        if let payloadModel = normalizedPrompt(stringValue(payload?["model"])) {
          model = payloadModel
        }
        projectPath = projectPath ?? normalizedPrompt(stringValue(payload?["cwd"]))
      }

      if let message = codexUserMessage(object) {
        firstPrompt = firstPrompt ?? message
        lastPrompt = message
      } else if firstPrompt == nil, let message = codexResponseUserMessage(object) {
        firstPrompt = message
      }
    }

    return (sessionId ?? fallbackSessionId, model, firstPrompt, lastPrompt ?? firstPrompt, startedAt, lastActiveAt, projectPath)
  }

  private func upsertCodexSessionMetadata(
    sessionId: String,
    sessionName: String?,
    model: String?,
    firstPrompt: String?,
    lastPrompt: String?,
    startedAt: String?,
    lastActiveAt: String?,
    filePath: String,
    projectPath: String?,
  ) throws {
    try database.upsertSessionMetadata(TokMonSessionMetadata(
      id: sessionId,
      source: "codex",
      title: sessionTitle(sessionName: sessionName, projectPath: projectPath, filePath: filePath, firstPrompt: firstPrompt),
      firstPrompt: firstPrompt,
      lastPrompt: lastPrompt ?? firstPrompt,
      model: model == "unknown" ? nil : model,
      startedAt: startedAt,
      lastActiveAt: lastActiveAt,
      filePath: filePath,
      projectPath: projectPath,
    ))
  }

  private func upsertClaudeSessionMetadata(
    sessionId: String,
    model: String?,
    firstPrompt: String?,
    lastPrompt: String?,
    startedAt: String?,
    lastActiveAt: String?,
    filePath: String,
    projectPath: String?,
  ) throws {
    try database.upsertSessionMetadata(TokMonSessionMetadata(
      id: sessionId,
      source: "claude-code",
      title: sessionTitle(projectPath: projectPath, filePath: filePath, firstPrompt: firstPrompt),
      firstPrompt: firstPrompt,
      lastPrompt: lastPrompt ?? firstPrompt,
      model: model == "unknown" ? nil : model,
      startedAt: startedAt,
      lastActiveAt: lastActiveAt,
      filePath: filePath,
      projectPath: projectPath,
    ))
  }

  private func upsertQwenCodeSessionMetadata(
    sessionId: String,
    model: String?,
    firstPrompt: String?,
    lastPrompt: String?,
    startedAt: String?,
    lastActiveAt: String?,
    filePath: String,
    projectPath: String?,
  ) throws {
    try database.upsertSessionMetadata(TokMonSessionMetadata(
      id: sessionId,
      source: "qwen-code",
      title: sessionTitle(projectPath: projectPath, filePath: filePath, firstPrompt: firstPrompt),
      firstPrompt: firstPrompt,
      lastPrompt: lastPrompt ?? firstPrompt,
      model: model == "unknown" ? nil : model,
      startedAt: startedAt,
      lastActiveAt: lastActiveAt,
      filePath: filePath,
      projectPath: projectPath,
    ))
  }

  private func upsertOpenCodeSessionMetadata(_ session: OpenCodeSessionSnapshot) throws {
    try database.upsertSessionMetadata(TokMonSessionMetadata(
      id: session.id,
      source: "opencode",
      title: sessionTitle(projectPath: session.projectPath, filePath: session.filePath, firstPrompt: session.firstPrompt),
      firstPrompt: session.firstPrompt,
      lastPrompt: session.firstPrompt,
      model: session.model == "unknown" ? nil : session.model,
      startedAt: session.startedAt,
      lastActiveAt: session.lastActiveAt,
      filePath: session.filePath,
      projectPath: session.projectPath,
    ))
  }

  private func claudeSessionMetadataSnapshot(
    _ fileURL: URL,
    fallbackSessionId: String,
  ) -> (sessionId: String, model: String?, firstPrompt: String?, lastPrompt: String?, startedAt: String?, lastActiveAt: String?, projectPath: String?) {
    guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
      return (fallbackSessionId, nil, nil, nil, nil, nil, nil)
    }

    var model: String?
    var firstPrompt: String?
    var lastPrompt: String?
    var startedAt: String?
    var lastActiveAt: String?
    var projectPath: String?

    for line in text.components(separatedBy: "\n") {
      guard let object = parseJSONObject(line) else {
        continue
      }
      if let timestamp = stringValue(object["timestamp"]) {
        startedAt = startedAt ?? timestamp
        lastActiveAt = timestamp
      }
      projectPath = projectPath ?? normalizedPrompt(stringValue(object["cwd"]))
      if let prompt = claudeUserMessage(object) {
        firstPrompt = firstPrompt ?? prompt
        lastPrompt = prompt
      }
      if object["type"] as? String == "assistant",
         let message = object["message"] as? [String: Any],
         let assistantModel = normalizedPrompt(stringValue(message["model"])) {
        model = assistantModel
      }
    }

    return (fallbackSessionId, model, firstPrompt, lastPrompt ?? firstPrompt, startedAt, lastActiveAt, projectPath)
  }

  private func sessionTitle(
    sessionName: String? = nil,
    projectPath: String?,
    filePath: String,
    firstPrompt: String?,
  ) -> String? {
    guard let prompt = firstPrompt else {
      return nil
    }
    let titlePrefix = normalizedPrompt(sessionName)
      ?? normalizedPrompt(projectPath).map { URL(fileURLWithPath: $0).lastPathComponent }
      ?? projectNameFromFilePath(filePath)
    return "\(titlePrefix) - \(prompt)"
  }

  private func codexSessionName(for sessionId: String, filePath: String) -> String? {
    let fileURL = URL(fileURLWithPath: filePath)
    let components = fileURL.pathComponents
    guard let sessionIndex = components.lastIndex(of: "sessions"), sessionIndex > 0 else {
      return nil
    }
    let indexURL = URL(fileURLWithPath: components[..<sessionIndex].joined(separator: "/"))
      .appendingPathComponent("session_index.jsonl")
    guard let text = try? String(contentsOf: indexURL, encoding: .utf8) else {
      return nil
    }
    for line in text.components(separatedBy: "\n") {
      guard let object = parseJSONObject(line),
            normalizedPrompt(stringValue(object["id"])) == sessionId,
            let name = normalizedPrompt(stringValue(object["thread_name"])) else {
        continue
      }
      return name
    }
    return nil
  }

  private func projectNameFromFilePath(_ filePath: String) -> String {
    let fileURL = URL(fileURLWithPath: filePath)
    let parent = fileURL.deletingLastPathComponent()
    if parent.lastPathComponent == "sessions" || parent.lastPathComponent.count == 2 || Int(parent.lastPathComponent) != nil {
      let components = parent.pathComponents
      if let index = components.lastIndex(of: "sessions"), index > 0 {
        return components[index - 1]
      }
    }
    return parent.lastPathComponent
  }

  private func parsePayload(_ payload: Any?) -> [String: Any]? {
    if let object = payload as? [String: Any] {
      return object
    }
    guard let string = payload as? String else {
      return nil
    }
    if let data = string.data(using: .utf8),
       let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      return object
    }
    var relaxedParser = RelaxedObjectLiteralParser(string)
    return relaxedParser.parse()
  }

  private func parseJSONString(_ string: String) -> [String: Any]? {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let data = trimmed.data(using: .utf8) else {
      return nil
    }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  }

  private func parseJSONObject(_ line: String) -> [String: Any]? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let data = trimmed.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }
    return object
  }

  private func openCodeModelId(from rawModel: String) -> String? {
    parseJSONString(rawModel).flatMap { object in
      stringValue(object["id"]) ?? stringValue(object["modelID"])
    }
  }

  private func openCodeProviderId(from rawModel: String) -> String? {
    parseJSONString(rawModel).flatMap { object in
      stringValue(object["providerID"]) ?? stringValue(object["provider"])
    }
  }

  private func openCodeMessageCreatedMilliseconds(object: [String: Any], fallback: Int64) -> Int64 {
    guard let time = object["time"] as? [String: Any] else {
      return fallback
    }
    let created = int64Value(time["created"])
    return created == 0 ? fallback : created
  }

  private func isoTimestamp(millisecondsSince1970: Int64) -> String {
    guard millisecondsSince1970 > 0 else {
      return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 0))
    }
    let date = Date(timeIntervalSince1970: TimeInterval(millisecondsSince1970) / 1000)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  private func readLines(_ fileURL: URL, range: AppendRange) throws -> [ScannedLine] {
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer {
      try? handle.close()
    }
    try handle.seek(toOffset: UInt64(range.offset))
    let data = try handle.read(upToCount: Int(range.length)) ?? Data()
    var lines: [ScannedLine] = []
    var lineStart = data.startIndex
    var index = data.startIndex
    while index < data.endIndex {
      if data[index] == 10 {
        let lineData = data[lineStart..<index]
        let nextOffset = range.offset + Int64(data.distance(from: data.startIndex, to: index)) + 1
        lines.append(ScannedLine(
          text: String(decoding: lineData, as: UTF8.self),
          nextOffset: nextOffset,
          isTerminated: true,
        ))
        lineStart = data.index(after: index)
      }
      index = data.index(after: index)
    }
    if lineStart < data.endIndex {
      let lineData = data[lineStart..<data.endIndex]
      lines.append(ScannedLine(
        text: String(decoding: lineData, as: UTF8.self),
        nextOffset: range.nextOffset,
        isTerminated: false,
      ))
    }
    return lines
  }

  private func byteSize(_ fileURL: URL) throws -> Int64 {
    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    if let size = attributes[.size] as? NSNumber {
      return size.int64Value
    }
    return 0
  }

  private func fileModificationStamp(_ fileURL: URL) -> String? {
    guard
      let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
      let modifiedAt = attributes[.modificationDate] as? Date
    else {
      return nil
    }
    return String(modifiedAt.timeIntervalSince1970)
  }

  private func openCodeDatabaseSignature(_ databaseURL: URL) -> (size: Int64, stamp: String)? {
    let candidates = [
      databaseURL,
      URL(fileURLWithPath: databaseURL.path + "-wal"),
      URL(fileURLWithPath: databaseURL.path + "-shm"),
    ]

    var totalSize: Int64 = 0
    let parts = candidates.compactMap { url -> String? in
      guard FileManager.default.fileExists(atPath: url.path) else {
        return nil
      }
      let size = (try? byteSize(url)) ?? 0
      totalSize += size
      let mtime = fileModificationStamp(url) ?? "missing"
      return "\(url.lastPathComponent):\(size):\(mtime)"
    }
    guard !parts.isEmpty else {
      return nil
    }
    return (totalSize, parts.joined(separator: "|"))
  }

  private func appendRange(fileURL: URL, fileSize: Int64, offset: Int64) -> AppendRange? {
    let start = fileSize < offset ? 0 : (lineStartOffset(fileURL, offset: offset) ?? offset)
    let length = fileSize - start
    guard length >= 0 else {
      return nil
    }
    return AppendRange(offset: start, length: length, nextOffset: fileSize)
  }

  private func lineStartOffset(_ fileURL: URL, offset: Int64) -> Int64? {
    guard offset > 0 else {
      return 0
    }
    guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
      return nil
    }
    defer {
      try? handle.close()
    }

    var cursor = UInt64(offset)
    do {
      try handle.seek(toOffset: cursor - 1)
      if try handle.read(upToCount: 1)?.first == 10 {
        cursor -= 1
      }
    } catch {
      return nil
    }

    while cursor > 0 {
      let chunkSize = min(cursor, 4096)
      cursor -= chunkSize
      do {
        try handle.seek(toOffset: cursor)
        let data = try handle.read(upToCount: Int(chunkSize)) ?? Data()
        if let newlineIndex = data.lastIndex(of: 10) {
          return Int64(cursor) + Int64(data.distance(from: data.startIndex, to: newlineIndex)) + 1
        }
      } catch {
        return nil
      }
    }
    return 0
  }

  private func expandedPath(_ path: String) -> URL {
    let expanded: String
    if path == "~" {
      expanded = FileManager.default.homeDirectoryForCurrentUser.path
    } else if path.hasPrefix("~/") {
      expanded = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(String(path.dropFirst(2)))
        .path
    } else {
      expanded = path
    }
    return URL(fileURLWithPath: expanded).standardizedFileURL
  }

  private func hasClaudeTokenUsage(_ usage: TokMonUsageRecord) -> Bool {
    usage.inputTokens != 0
      || usage.outputTokens != 0
      || usage.cacheCreation != 0
      || usage.cacheRead != 0
      || usage.reasoningTokens != 0
  }

  private func hasCodexTokenUsage(_ usage: [String: Any]) -> Bool {
    intValue(usage["input_tokens"]) != 0
      || intValue(usage["output_tokens"]) != 0
      || intValue(usage["cached_input_tokens"]) != 0
      || intValue(usage["reasoning_output_tokens"]) != 0
  }

  private func codexUsageKey(_ usage: [String: Any], timestamp: String?) -> String {
    [
      timestamp ?? "",
      String(intValue(usage["input_tokens"])),
      String(intValue(usage["output_tokens"])),
      String(intValue(usage["cached_input_tokens"])),
      String(intValue(usage["reasoning_output_tokens"])),
    ].joined(separator: ":")
  }

  private func qwenUsageKey(_ usage: [String: Any], timestamp: String?) -> String {
    [
      timestamp ?? "",
      String(intValue(usage["promptTokenCount"])),
      String(intValue(usage["candidatesTokenCount"])),
      String(intValue(usage["cachedContentTokenCount"])),
      String(intValue(usage["thoughtsTokenCount"])),
    ].joined(separator: ":")
  }

  private func qwenTelemetryUsageKey(_ usage: [String: Any], timestamp: String?) -> String {
    [
      timestamp ?? "",
      String(intValue(usage["input_token_count"])),
      String(intValue(usage["output_token_count"])),
      String(intValue(usage["cached_content_token_count"])),
      String(intValue(usage["thoughts_token_count"])),
    ].joined(separator: ":")
  }

  private func claudeUsageKey(_ usage: TokMonUsageRecord) -> String {
    [
      usage.sessionId,
      usage.createdAt,
      String(usage.inputTokens),
      String(usage.outputTokens),
      String(usage.cacheCreation),
      String(usage.cacheRead),
      String(usage.reasoningTokens),
    ].joined(separator: ":")
  }

  private func intValue(_ value: Any?, fallback: Int = 0) -> Int {
    switch value {
    case let value as Int:
      value
    case let value as Int64:
      Int(value)
    case let value as Double:
      Int(value)
    case let value as NSNumber:
      value.intValue
    case let value as String:
      Int(value) ?? fallback
    default:
      fallback
    }
  }

  private func int64Value(_ value: Any?, fallback: Int64 = 0) -> Int64 {
    switch value {
    case let value as Int:
      Int64(value)
    case let value as Int64:
      value
    case let value as Double:
      Int64(value)
    case let value as NSNumber:
      value.int64Value
    case let value as String:
      Int64(value) ?? fallback
    default:
      fallback
    }
  }

  private func stringValue(_ value: Any?) -> String? {
    switch value {
    case let value as String:
      value
    case let value as NSNumber:
      value.stringValue
    default:
      nil
    }
  }
}

private func openCodeStringColumn(_ statement: OpaquePointer?, _ index: Int32) -> String {
  guard sqlite3_column_type(statement, index) != SQLITE_NULL,
        let rawValue = sqlite3_column_text(statement, index) else {
    return ""
  }
  return String(cString: rawValue)
}

private struct OpenCodeSessionSnapshot {
  let id: String
  let title: String?
  let firstPrompt: String?
  let model: String
  let startedAt: String?
  let lastActiveAt: String?
  let filePath: String
  let projectPath: String?
}

private struct OpenCodeUsageMessage {
  let usageKey: String
  let session: OpenCodeSessionSnapshot
  let model: String
  let provider: String?
  let inputTokens: Int
  let outputTokens: Int
  let cacheWrite: Int
  let cacheRead: Int
  let reasoningTokens: Int
  let createdAt: String
}

private enum TokMonScannerError: LocalizedError {
  case openCodeDatabase(String)

  var errorDescription: String? {
    switch self {
    case .openCodeDatabase(let message):
      "Unable to scan opencode database: \(message)"
    }
  }
}

private struct AppendRange {
  let offset: Int64
  let length: Int64
  let nextOffset: Int64
}

private struct ScannedLine {
  let text: String
  let nextOffset: Int64
  let isTerminated: Bool
}

private struct RelaxedObjectLiteralParser {
  private let characters: [Character]
  private var index = 0

  init(_ source: String) {
    characters = Array(source)
  }

  mutating func parse() -> [String: Any]? {
    skipWhitespace()
    guard let object = parseObject() else {
      return nil
    }
    skipWhitespace()
    return index == characters.count ? object : nil
  }

  private mutating func parseObject() -> [String: Any]? {
    guard consume("{") else {
      return nil
    }
    skipWhitespace()

    var object: [String: Any] = [:]
    if consume("}") {
      return object
    }

    while index < characters.count {
      skipWhitespace()
      guard let key = parseKey() else {
        return nil
      }
      skipWhitespace()
      guard consume(":") else {
        return nil
      }
      skipWhitespace()
      guard let value = parseValue() else {
        return nil
      }
      object[key] = value
      skipWhitespace()

      if consume("}") {
        return object
      }
      guard consume(",") else {
        return nil
      }
      skipWhitespace()
      if consume("}") {
        return object
      }
    }

    return nil
  }

  private mutating func parseKey() -> String? {
    if peek() == "'" || peek() == "\"" {
      return parseString()
    }

    let start = index
    while index < characters.count {
      let character = characters[index]
      if character.isLetter || character.isNumber || character == "_" || character == "$" || character == "-" {
        index += 1
      } else {
        break
      }
    }

    guard index > start else {
      return nil
    }
    return String(characters[start..<index])
  }

  private mutating func parseValue() -> Any? {
    skipWhitespace()
    switch peek() {
    case "{":
      return parseObject()
    case "'", "\"":
      return parseString()
    default:
      if let literal = parseLiteral() {
        return literal
      }
      return parseNumber()
    }
  }

  private mutating func parseString() -> String? {
    guard let quote = peek(), quote == "'" || quote == "\"" else {
      return nil
    }
    index += 1

    var result = ""
    while index < characters.count {
      let character = characters[index]
      index += 1

      if character == quote {
        return result
      }

      if character == "\\" {
        guard index < characters.count else {
          return nil
        }
        let escaped = characters[index]
        index += 1
        switch escaped {
        case "n":
          result.append("\n")
        case "r":
          result.append("\r")
        case "t":
          result.append("\t")
        default:
          result.append(escaped)
        }
      } else {
        result.append(character)
      }
    }

    return nil
  }

  private mutating func parseLiteral() -> Any? {
    if consumeKeyword("true") {
      return true
    }
    if consumeKeyword("false") {
      return false
    }
    if consumeKeyword("null") {
      return NSNull()
    }
    return nil
  }

  private mutating func parseNumber() -> Any? {
    let start = index
    if peek() == "-" {
      index += 1
    }
    while let character = peek(), character.isNumber {
      index += 1
    }
    if peek() == "." {
      index += 1
      while let character = peek(), character.isNumber {
        index += 1
      }
    }

    guard index > start else {
      return nil
    }

    let rawValue = String(characters[start..<index])
    if rawValue.contains(".") {
      return Double(rawValue)
    }
    return Int(rawValue)
  }

  private mutating func skipWhitespace() {
    while let character = peek(), character.isWhitespace {
      index += 1
    }
  }

  private func peek() -> Character? {
    index < characters.count ? characters[index] : nil
  }

  private mutating func consume(_ expected: Character) -> Bool {
    guard peek() == expected else {
      return false
    }
    index += 1
    return true
  }

  private mutating func consumeKeyword(_ keyword: String) -> Bool {
    let end = index + keyword.count
    guard end <= characters.count else {
      return false
    }
    guard String(characters[index..<end]) == keyword else {
      return false
    }
    index = end
    return true
  }
}
