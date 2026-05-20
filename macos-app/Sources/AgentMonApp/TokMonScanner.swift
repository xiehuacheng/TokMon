import Foundation

final class TokMonScanner {
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
    if let fileMtime, state.offset == fileSize, state.lastMtime == fileMtime {
      return 0
    }
    let shouldRescanFromStart = fileSize < state.offset
      || (fileSize == state.offset && (fileMtime == nil || state.lastMtime == nil || state.lastMtime != fileMtime))
    let range = shouldRescanFromStart
      ? AppendRange(offset: 0, length: fileSize, nextOffset: fileSize)
      : appendRange(fileSize: fileSize, offset: state.offset)
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
    for line in lines {
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
        offset: range.nextOffset,
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
      : appendRange(fileSize: fileSize, offset: state.offset)
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

    for line in lines {
      guard let object = parseJSONObject(line) else {
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
      let usageKey = codexUsageKey(usage)
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
        offset: range.nextOffset,
        sessionId: resolvedSessionId,
        model: lastModel,
        lastUsageKey: lastUsageKey,
        lastMtime: fileMtime,
      ),
    )
    try upsertCodexSessionMetadata(
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
    guard hasClaudeTokenUsage(record) else {
      return nil
    }
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

  private func normalizedPrompt(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty else {
      return nil
    }
    return trimmed
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

  private func sessionTitle(projectPath: String?, filePath: String, firstPrompt: String?) -> String? {
    guard let prompt = firstPrompt else {
      return nil
    }
    let projectName = normalizedPrompt(projectPath).map { URL(fileURLWithPath: $0).lastPathComponent }
      ?? projectNameFromFilePath(filePath)
    return "\(projectName) - \(prompt)"
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

  private func parseJSONObject(_ line: String) -> [String: Any]? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let data = trimmed.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }
    return object
  }

  private func readLines(_ fileURL: URL, range: AppendRange) throws -> [String] {
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer {
      try? handle.close()
    }
    try handle.seek(toOffset: UInt64(range.offset))
    let data = try handle.read(upToCount: Int(range.length)) ?? Data()
    return String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
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

  private func appendRange(fileSize: Int64, offset: Int64) -> AppendRange? {
    let start = fileSize < offset ? 0 : offset
    let length = fileSize - start
    guard length >= 0 else {
      return nil
    }
    return AppendRange(offset: start, length: length, nextOffset: fileSize)
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
    intValue(usage["input_tokens"]) != 0 || intValue(usage["output_tokens"]) != 0
  }

  private func codexUsageKey(_ usage: [String: Any]) -> String {
    [
      intValue(usage["input_tokens"]),
      intValue(usage["output_tokens"]),
      intValue(usage["cached_input_tokens"]),
      intValue(usage["reasoning_output_tokens"]),
    ].map(String.init).joined(separator: ":")
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

private struct AppendRange {
  let offset: Int64
  let length: Int64
  let nextOffset: Int64
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
