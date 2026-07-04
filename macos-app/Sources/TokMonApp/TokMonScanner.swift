import Foundation
import SQLite3

final class TokMonScanner {
  /// Bumped when scanning semantics change enough that existing usage_records
  /// rows may be incorrect. A mismatch triggers a database rebuild on launch.
  static let scannerVersion = 2

  private static let qwenCodeScanStateVersion = "qwen-code-telemetry-v1"

  private let database: TokMonDatabase
  var fileWatcher: TokMonFileWatcher?
  private let isoTimestampFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  init(database: TokMonDatabase, fileWatcher: TokMonFileWatcher? = nil) {
    self.database = database
    self.fileWatcher = fileWatcher
  }

  // MARK: - Directory Signature Cache

  private struct DirectorySignature: Equatable {
    let fileCount: Int
    let fileSignatures: [String]
  }

  private var directorySignatures: [String: DirectorySignature] = [:]

  private func directorySignature(for directory: URL) throws -> DirectorySignature {
    guard let enumerator = FileManager.default.enumerator(
      at: directory,
      includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
      options: [.skipsHiddenFiles]
    ) else {
      return DirectorySignature(fileCount: 0, fileSignatures: [])
    }

    var fileSignatures: [String] = []
    for case let fileURL as URL in enumerator where isScannableLogFile(fileURL) {
      let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
      let size = values?.fileSize.map(Int64.init) ?? 0
      let mtime = values?.contentModificationDate.map { String($0.timeIntervalSince1970) } ?? "missing"
      fileSignatures.append("\(fileURL.path):\(size):\(mtime)")
    }
    return DirectorySignature(fileCount: fileSignatures.count, fileSignatures: fileSignatures.sorted())
  }

  private func isScannableLogFile(_ fileURL: URL) -> Bool {
    let ext = fileURL.pathExtension.lowercased()
    if ext == "jsonl" {
      return true
    }
    // Codex compresses cold rollout files as .jsonl.zst; we surface them here
    // so the signature cache knows about them, but decompression is handled
    // separately when a reader for .zst is wired up.
    if ext == "zst" {
      let name = fileURL.lastPathComponent.lowercased()
      return name.hasSuffix(".jsonl.zst")
    }
    return false
  }

  // MARK: - Codex Session Name Cache

  private struct CodexSessionIndexCacheEntry {
    let signature: String
    let name: String?
  }

  private var codexSessionIndexCache: [String: CodexSessionIndexCacheEntry] = [:]

  // MARK: - Main Entry Points

  func scan(config: TokMonConfig) throws -> Int {
    try scan(config: config, paths: nil)
  }

  func scan(config: TokMonConfig, paths: [String]?) throws -> Int {
    let expandedPaths = paths?.map { expandedPath($0).path }

    var count = 0

    if let source = config.sources["claude-code"] {
      let sourcePath = expandedPath(source.path).path
      if let expandedPaths {
        let matchingPaths = expandedPaths.filter { $0.hasPrefix(sourcePath) }
        if !matchingPaths.isEmpty {
          count += try scanClaudeCode(paths: matchingPaths)
        } else if paths == nil || paths!.isEmpty {
          count += try scanClaudeCode(directory: expandedPath(source.path))
        }
      } else {
        count += try scanClaudeCode(directory: expandedPath(source.path))
      }
    }

    if let source = config.sources["codex"] {
      let sourcePath = expandedPath(source.path).path
      if let expandedPaths {
        let matchingPaths = expandedPaths.filter { $0.hasPrefix(sourcePath) }
        if !matchingPaths.isEmpty {
          count += try scanCodex(paths: matchingPaths)
        } else if paths == nil || paths!.isEmpty {
          count += try scanCodex(directory: expandedPath(source.path))
        }
      } else {
        count += try scanCodex(directory: expandedPath(source.path))
      }
    }

    if let source = config.sources["opencode"] {
      let sourcePath = expandedPath(source.path).path
      if let expandedPaths {
        let matchingPaths = expandedPaths.filter { $0.hasPrefix(sourcePath) || $0 == sourcePath }
        if !matchingPaths.isEmpty {
          count += try scanOpenCode(paths: matchingPaths)
        } else if paths == nil || paths!.isEmpty {
          count += try scanOpenCode(directory: expandedPath(source.path))
        }
      } else {
        count += try scanOpenCode(directory: expandedPath(source.path))
      }
    }

    if let source = config.sources["qwen-code"] {
      let sourcePath = expandedPath(source.path).path
      if let expandedPaths {
        let matchingPaths = expandedPaths.filter { $0.hasPrefix(sourcePath) }
        if !matchingPaths.isEmpty {
          count += try scanQwenCode(paths: matchingPaths)
        } else if paths == nil || paths!.isEmpty {
          count += try scanQwenCode(directory: expandedPath(source.path))
        }
      } else {
        count += try scanQwenCode(directory: expandedPath(source.path))
      }
    }

    return count
  }

  // MARK: - Source Scanners

  private func scanClaudeCode(directory: URL) throws -> Int {
    try scanFiles(in: directory) { fileURL in
      try scanClaudeFile(fileURL, fallbackSessionId: fileURL.deletingPathExtension().lastPathComponent)
    }
  }

  private func scanClaudeCode(paths: [String]) throws -> Int {
    var count = 0
    for path in paths {
      let url = URL(fileURLWithPath: path)
      if url.pathExtension == "jsonl" {
        count += try scanClaudeFile(url, fallbackSessionId: url.deletingPathExtension().lastPathComponent)
      } else if url.hasDirectoryPath {
        count += try scanFiles(in: url, fileURLs: nil) { fileURL in
          try scanClaudeFile(fileURL, fallbackSessionId: fileURL.deletingPathExtension().lastPathComponent)
        }
      }
    }
    return count
  }

  private func scanCodex(directory: URL) throws -> Int {
    // Codex stores live sessions under `sessions/` and archived ones under
    // `archived_sessions/`. Accept either the codex home directory or one of
    // the two session directories directly, so existing `~/.codex/sessions`
    // configs keep working. If none of those subdirectories exist, scan the
    // directory itself as a fallback.
    let directoryName = directory.lastPathComponent.lowercased()
    if directoryName == "sessions" || directoryName == "archived_sessions" {
      return try scanCodexSessionDirectory(directory)
    }

    var count = 0
    var scannedSubdirectory = false
    let sessionsDir = directory.appendingPathComponent("sessions", isDirectory: true)
    if FileManager.default.fileExists(atPath: sessionsDir.path) {
      count += try scanCodexSessionDirectory(sessionsDir)
      scannedSubdirectory = true
    }
    let archivedDir = directory.appendingPathComponent("archived_sessions", isDirectory: true)
    if FileManager.default.fileExists(atPath: archivedDir.path) {
      count += try scanCodexSessionDirectory(archivedDir)
      scannedSubdirectory = true
    }
    if !scannedSubdirectory {
      count += try scanCodexSessionDirectory(directory)
    }
    return count
  }

  private func scanCodexSessionDirectory(_ directory: URL) throws -> Int {
    try scanFiles(in: directory) { fileURL in
      try scanCodexFile(
        fileURL,
        fallbackSessionId: codexFallbackSessionId(for: fileURL),
      )
    }
  }

  private func scanCodex(paths: [String]) throws -> Int {
    var count = 0
    for path in paths {
      let url = URL(fileURLWithPath: path)
      if isScannableLogFile(url) {
        count += try scanCodexFile(url, fallbackSessionId: codexFallbackSessionId(for: url))
      } else if url.hasDirectoryPath {
        count += try scanCodex(directory: url)
      }
    }
    return count
  }

  private func scanOpenCode(directory: URL) throws -> Int {
    let databaseURL = directory.appendingPathComponent("opencode.db")
    guard FileManager.default.fileExists(atPath: databaseURL.path) else {
      return 0
    }
    return try scanOpenCodeDatabase(databaseURL)
  }

  private func scanOpenCode(paths: [String]) throws -> Int {
    var count = 0
    for path in paths {
      let url = URL(fileURLWithPath: path)
      let databaseURL: URL
      if url.lastPathComponent == "opencode.db" {
        databaseURL = url
      } else {
        databaseURL = url.appendingPathComponent("opencode.db")
      }
      guard FileManager.default.fileExists(atPath: databaseURL.path) else {
        continue
      }
      count += try scanOpenCodeDatabase(databaseURL)
    }
    return count
  }

  private func scanQwenCode(directory: URL) throws -> Int {
    try scanFiles(in: directory) { fileURL in
      try scanQwenCodeFile(fileURL, fallbackSessionId: fileURL.deletingPathExtension().lastPathComponent)
    }
  }

  private func scanQwenCode(paths: [String]) throws -> Int {
    var count = 0
    for path in paths {
      let url = URL(fileURLWithPath: path)
      if url.pathExtension == "jsonl" {
        count += try scanQwenCodeFile(url, fallbackSessionId: url.deletingPathExtension().lastPathComponent)
      } else if url.hasDirectoryPath {
        count += try scanFiles(in: url, fileURLs: nil) { fileURL in
          try scanQwenCodeFile(fileURL, fallbackSessionId: fileURL.deletingPathExtension().lastPathComponent)
        }
      }
    }
    return count
  }

  // MARK: - File Enumeration

  private func scanFiles(in directory: URL, fileURLs: [URL]? = nil, scanner: (URL) throws -> Int) throws -> Int {
    if let fileURLs {
      var count = 0
      for fileURL in fileURLs where isScannableLogFile(fileURL) {
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

    // Check directory signature cache for full scans
    let signature = try directorySignature(for: directory)
    if let cached = directorySignatures[directory.path], cached == signature {
      return 0
    }
    directorySignatures[directory.path] = signature

    guard let enumerator = FileManager.default.enumerator(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles],
    ) else {
      return 0
    }

    var count = 0
    for case let fileURL as URL in enumerator where isScannableLogFile(fileURL) {
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

  // MARK: - Individual File Scanners

  private func scanClaudeFile(_ fileURL: URL, fallbackSessionId: String) throws -> Int {
    let filePath = fileURL.path
    let attributes = fileAttributes(fileURL)
    let fileSize = attributes.size
    let fileMtime = attributes.mtime
    let state = try database.scanState(filePath: filePath)
    if let fileMtime,
       state.offset == fileSize,
       state.lastMtime == fileMtime,
       state.lastUsageKey != nil {
      return 0
    }
    let shouldRescanFromStart = fileSize < state.offset
      || (fileSize == state.offset && (fileMtime == nil || state.lastMtime == nil || state.lastMtime != fileMtime))
    let range = shouldRescanFromStart
      ? AppendRange(offset: 0, length: fileSize, nextOffset: fileSize)
      : appendRange(fileURL: fileURL, fileSize: fileSize, offset: state.offset, lastMtime: state.lastMtime)
    guard let range else {
      return 0
    }
    guard let lines = try? readLines(fileURL, range: range) else {
      return 0
    }

    var pendingByMessageId: [String: TokMonUsageRecord] = [:]
    var orderedMessageIds: [String] = []
    var recordsWithoutMessageId: [TokMonUsageRecord] = []
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
      guard let record = parseClaudeUsageRecord(object, fallbackSessionId: fallbackSessionId) else {
        continue
      }
      model = record.model
      if let messageId = record.messageId, !messageId.isEmpty {
        if let existing = pendingByMessageId[messageId] {
          pendingByMessageId[messageId] = TokMonUsageRecord.claudeRecordByRecency(existing, record)
        } else {
          pendingByMessageId[messageId] = record
          orderedMessageIds.append(messageId)
        }
      } else {
        recordsWithoutMessageId.append(record)
      }
    }

    var recordsToInsert: [TokMonUsageRecord] = recordsWithoutMessageId
    for messageId in orderedMessageIds {
      if let record = pendingByMessageId[messageId] {
        recordsToInsert.append(record)
      }
    }

    var count = 0
    if !recordsToInsert.isEmpty {
      count = try database.insertUsages(recordsToInsert)
    }

    let newLastKey: String?
    if let lastMessageId = orderedMessageIds.last,
       let lastRecord = pendingByMessageId[lastMessageId] {
      newLastKey = ClaudeUsageKey(messageId: lastMessageId, record: lastRecord).jsonString
    } else if let lastNoMessageId = recordsWithoutMessageId.last {
      newLastKey = claudeUsageKey(lastNoMessageId)
    } else {
      newLastKey = state.lastUsageKey
    }

    try database.setScanState(
      filePath: filePath,
      state: TokMonScanState(
        offset: nextOffset,
        sessionId: fallbackSessionId,
        model: model,
        lastUsageKey: newLastKey,
        lastMtime: fileMtime,
      ),
    )

    let metadata = TokMonSessionMetadata(
      id: fallbackSessionId,
      source: "claude-code",
      title: sessionTitle(projectPath: projectPath, filePath: filePath, firstPrompt: firstPrompt),
      firstPrompt: firstPrompt,
      lastPrompt: lastPrompt ?? firstPrompt,
      model: model == "unknown" ? nil : model,
      startedAt: startedAt,
      lastActiveAt: lastActiveAt,
      filePath: filePath,
      projectPath: projectPath,
    )
    try database.upsertSessionMetadatas([metadata])

    return count
  }

  private func scanCodexFile(
    _ fileURL: URL,
    fallbackSessionId: String,
  ) throws -> Int {
    let filePath = fileURL.path
    let attributes = fileAttributes(fileURL)
    let fileSize = attributes.size
    let fileMtime = attributes.mtime
    let state = try database.scanState(filePath: filePath)
    if let fileMtime, state.offset == fileSize, state.lastMtime == fileMtime {
      return 0
    }
    let shouldRescanFromStart = fileSize < state.offset
      || (fileSize == state.offset && (fileMtime == nil || state.lastMtime == nil || state.lastMtime != fileMtime))
    let range = shouldRescanFromStart
      ? AppendRange(offset: 0, length: fileSize, nextOffset: fileSize)
      : appendRange(fileURL: fileURL, fileSize: fileSize, offset: state.offset, lastMtime: state.lastMtime)
    guard let range else {
      return 0
    }
    guard let lines = try? readLines(fileURL, range: range) else {
      return 0
    }

    var records: [TokMonUsageRecord] = []
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
        // Codex protocol: SessionMeta carries model_provider, TurnContextItem carries model.
        // Prefer the explicit model from turn_context, then model from session_meta (some
        // older/derived logs still include it), then fall back to model_provider.
        if type == "turn_context",
           let model = normalizedPrompt(stringValue(payload?["model"])) {
          lastModel = model
        } else if type == "session_meta",
                  let model = normalizedPrompt(stringValue(payload?["model"])) {
          lastModel = model
        } else if type == "session_meta",
                  lastModel == "unknown" || lastModel.isEmpty,
                  let modelProvider = normalizedPrompt(stringValue(payload?["model_provider"])) {
          lastModel = modelProvider
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
        createdAt: stringValue(object["timestamp"]) ?? isoTimestampFormatter.string(from: Date()),
      )
      records.append(record)
    }

    var count = 0
    if !records.isEmpty {
      count = try database.insertUsages(records)
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

    // Codex keeps live session logs open for the whole session. FSEvents often
    // misses appends to open files, so start a per-file kqueue monitor for any
    // file that has been written to recently.
    if let fileWatcher,
       let fileMtime,
       let mtime = Double(fileMtime),
       Date().timeIntervalSince1970 - mtime < 300 {
      Task {
        await fileWatcher.watch(path: filePath)
      }
    }

    let metadata = TokMonSessionMetadata(
      id: resolvedSessionId,
      source: "codex",
      title: sessionTitle(sessionName: codexSessionName(for: resolvedSessionId, filePath: filePath), projectPath: projectPath, filePath: filePath, firstPrompt: firstPrompt),
      firstPrompt: firstPrompt,
      lastPrompt: lastPrompt ?? firstPrompt,
      model: lastModel == "unknown" ? nil : lastModel,
      startedAt: startedAt,
      lastActiveAt: lastActiveAt,
      filePath: filePath,
      projectPath: projectPath,
    )
    try database.upsertSessionMetadatas([metadata])

    return count
  }

  private func scanQwenCodeFile(_ fileURL: URL, fallbackSessionId: String) throws -> Int {
    let filePath = fileURL.path
    let attributes = fileAttributes(fileURL)
    let fileSize = attributes.size
    let fileMtime = attributes.mtime
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
      : appendRange(fileURL: fileURL, fileSize: fileSize, offset: state.offset, lastMtime: state.lastMtime)
    guard let range else {
      return 0
    }
    guard let lines = try? readLines(fileURL, range: range) else {
      return 0
    }

    var records: [TokMonUsageRecord] = []
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
        records.append(telemetry.usage)
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
        createdAt: stringValue(object["timestamp"]) ?? isoTimestampFormatter.string(from: Date()),
      )
      records.append(record)
    }

    var count = 0
    if !records.isEmpty {
      count = try database.insertUsages(records)
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

    let metadata = TokMonSessionMetadata(
      id: resolvedSessionId,
      source: "qwen-code",
      title: sessionTitle(projectPath: projectPath, filePath: filePath, firstPrompt: firstPrompt),
      firstPrompt: firstPrompt,
      lastPrompt: lastPrompt ?? firstPrompt,
      model: lastModel == "unknown" ? nil : lastModel,
      startedAt: startedAt,
      lastActiveAt: lastActiveAt,
      filePath: filePath,
      projectPath: projectPath,
    )
    try database.upsertSessionMetadatas([metadata])

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

    let after: Int64? = state.lastUsageKey.flatMap { key in
      let parts = key.split(separator: ":")
      guard parts.count >= 2 else { return nil }
      return Int64(parts[1])
    }

    let openCodeMessages = try openCodeUsageMessages(databaseURL, after: after)
    var count = 0
    var lastUsageKey = state.lastUsageKey
    var sessionMetadatas: [TokMonSessionMetadata] = []
    var seenSessions = Set<String>()

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
        if !seenSessions.contains(message.session.id) {
          seenSessions.insert(message.session.id)
          sessionMetadatas.append(openCodeSessionMetadata(message.session))
        }
        continue
      }
      if try database.insertUsage(record) {
        count += 1
      }
      lastUsageKey = message.usageKey
      if !seenSessions.contains(message.session.id) {
        seenSessions.insert(message.session.id)
        sessionMetadatas.append(openCodeSessionMetadata(message.session))
      }
    }

    if lastUsageKey == nil {
      for message in openCodeMessages {
        if !seenSessions.contains(message.session.id) {
          seenSessions.insert(message.session.id)
          sessionMetadatas.append(openCodeSessionMetadata(message.session))
        }
      }
    }

    if !sessionMetadatas.isEmpty {
      try database.upsertSessionMetadatas(sessionMetadatas)
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
    let sessionsNeedingBackfill = try database.sessionIdsWithEnvironmentContext(source: "opencode", filePath: databaseURL.path)
    guard !sessionsNeedingBackfill.isEmpty else { return }

    let state = try database.scanState(filePath: databaseURL.path)
    let after: Int64? = state.lastUsageKey.flatMap { key in
      let parts = key.split(separator: ":")
      guard parts.count >= 2 else { return nil }
      return Int64(parts[1])
    }

    let openCodeMessages = try openCodeUsageMessages(databaseURL, sessionIds: sessionsNeedingBackfill, after: after)
    var sessionMetadatas: [TokMonSessionMetadata] = []
    var seenSessions = Set<String>()
    for message in openCodeMessages {
      if !seenSessions.contains(message.session.id) {
        seenSessions.insert(message.session.id)
        sessionMetadatas.append(openCodeSessionMetadata(message.session))
      }
    }
    if !sessionMetadatas.isEmpty {
      try database.upsertSessionMetadatas(sessionMetadatas)
    }
  }

  private func openCodeSessionMetadata(_ session: OpenCodeSessionSnapshot) -> TokMonSessionMetadata {
    TokMonSessionMetadata(
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
    )
  }

  private func openCodeUsageMessages(_ databaseURL: URL, after: Int64? = nil) throws -> [OpenCodeUsageMessage] {
    try openCodeUsageMessages(databaseURL, sessionIds: nil, after: after)
  }

  private func openCodeUsageMessages(_ databaseURL: URL, sessionIds: [String]?, after: Int64? = nil) throws -> [OpenCodeUsageMessage] {
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

    var conditions: [String] = []
    if let sessionIds, !sessionIds.isEmpty {
      let placeholders = sessionIds.map { _ in "?" }.joined(separator: ",")
      conditions.append("m.session_id IN (\(placeholders))")
    }
    if after != nil {
      conditions.append("m.time_created >= ?")
    }
    let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")

    // Use a CTE with a window function to compute the first real user prompt
    // per session once, then LEFT JOIN it, avoiding the correlated subquery
    // that re-scanned message/part for every assistant row.
    let sql = """
      WITH first_prompts AS (
        SELECT
          user_message.session_id AS session_id,
          json_extract(p.data, '$.text') AS prompt_text,
          ROW_NUMBER() OVER (
            PARTITION BY user_message.session_id
            ORDER BY user_message.time_created ASC,
                     user_message.id ASC,
                     p.time_created ASC,
                     p.id ASC
          ) AS rn
        FROM message user_message
        JOIN part p ON p.message_id = user_message.id
          AND p.session_id = user_message.session_id
        WHERE json_extract(user_message.data, '$.role') = 'user'
          AND json_extract(p.data, '$.type') = 'text'
          AND NULLIF(TRIM(json_extract(p.data, '$.text')), '') IS NOT NULL
          AND TRIM(json_extract(p.data, '$.text')) NOT LIKE '<environment_context>%'
          AND COALESCE(json_extract(p.data, '$.ignored'), 0) = 0
          AND COALESCE(json_extract(p.data, '$.synthetic'), 0) = 0
      )
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
             fp.prompt_text AS first_prompt
      FROM message m
      JOIN session s ON s.id = m.session_id
      LEFT JOIN first_prompts fp ON fp.session_id = m.session_id AND fp.rn = 1
      \(whereClause)
      ORDER BY m.time_created ASC, m.id ASC
    """

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
      throw TokMonScannerError.openCodeDatabase(String(cString: sqlite3_errmsg(connection)))
    }
    defer {
      sqlite3_finalize(statement)
    }

    var bindIndex: Int32 = 1
    if let sessionIds {
      for sessionId in sessionIds {
        sqlite3_bind_text(statement, bindIndex, sessionId, -1, SQLITE_TRANSIENT)
        bindIndex += 1
      }
    }
    if let after {
      sqlite3_bind_int64(statement, bindIndex, after)
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
  ) -> TokMonUsageRecord? {
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
      cacheCreation: claudeCacheCreation(from: usage),
      cacheRead: intValue(usage["cache_read_input_tokens"]),
      reasoningTokens: 0,
      createdAt: stringValue(object["timestamp"]) ?? isoTimestampFormatter.string(from: Date()),
      messageId: stringValue(messageObject["id"])
    )
    guard hasClaudeTokenUsage(record) else {
      return nil
    }
    return record
  }

  private func claudeCacheCreation(from usage: [String: Any]) -> Int {
    let flat = intValue(usage["cache_creation_input_tokens"])
    if flat > 0 { return flat }
    guard let nested = usage["cache_creation"] as? [String: Any] else { return flat }
    let ephemeral5m = intValue(nested["ephemeral_5m_input_tokens"])
    let ephemeral1h = intValue(nested["ephemeral_1h_input_tokens"])
    let nestedTotal = ephemeral5m + ephemeral1h
    return nestedTotal > 0 ? nestedTotal : flat
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
      ?? isoTimestampFormatter.string(from: Date())
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

    let attributes = fileAttributes(indexURL)
    let signature = "\(attributes.size):\(attributes.mtime ?? "missing")"

    let cacheKey = indexURL.path
    if let cached = codexSessionIndexCache[cacheKey], cached.signature == signature {
      return cached.name
    }

    guard let text = try? String(contentsOf: indexURL, encoding: .utf8) else {
      codexSessionIndexCache[cacheKey] = CodexSessionIndexCacheEntry(signature: signature, name: nil)
      return nil
    }
    for line in text.components(separatedBy: "\n") {
      guard let object = parseJSONObject(line),
            normalizedPrompt(stringValue(object["id"])) == sessionId,
            let name = normalizedPrompt(stringValue(object["thread_name"])) else {
        continue
      }
      codexSessionIndexCache[cacheKey] = CodexSessionIndexCacheEntry(signature: signature, name: name)
      return name
    }
    codexSessionIndexCache[cacheKey] = CodexSessionIndexCacheEntry(signature: signature, name: nil)
    return nil
  }

  private func projectNameFromFilePath(_ filePath: String) -> String {
    let fileURL = URL(fileURLWithPath: filePath)
    let parent = fileURL.deletingLastPathComponent()
    let components = parent.pathComponents

    // Codex nests sessions under sessions/YYYY/MM/DD. In that case the project
    // directory is the parent of the .codex directory (e.g. /Users/foo/bar/.codex).
    if let sessionsIndex = components.lastIndex(of: "sessions"), sessionsIndex > 1 {
      let codexIndex = sessionsIndex - 1
      if components[codexIndex].lowercased() == ".codex" {
        return components[codexIndex - 1]
      }
    }

    if parent.lastPathComponent == "sessions" || parent.lastPathComponent.count == 2 || Int(parent.lastPathComponent) != nil {
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
      return isoTimestampFormatter.string(from: Date(timeIntervalSince1970: 0))
    }
    let date = Date(timeIntervalSince1970: TimeInterval(millisecondsSince1970) / 1000)
    return isoTimestampFormatter.string(from: date)
  }

  private let maxReadLinesBytesPerCall: Int64 = 4 * 1024 * 1024

  private func readLines(_ fileURL: URL, range: AppendRange) throws -> [ScannedLine] {
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer {
      try? handle.close()
    }
    try handle.seek(toOffset: UInt64(range.offset))

    var lines: [ScannedLine] = []
    var buffer = Data()
    var bufferStartOffset: Int64 = 0  // relative to range.offset
    var readOffset: Int64 = 0         // relative to range.offset

    while readOffset < range.length {
      let remaining = range.length - readOffset
      let readLength = min(remaining, maxReadLinesBytesPerCall)
      guard readLength > 0 else { break }
      let chunk = try handle.read(upToCount: Int(readLength)) ?? Data()
      guard !chunk.isEmpty else { break }

      buffer.append(chunk)
      readOffset += Int64(chunk.count)

      var lineStart = buffer.startIndex
      var index = buffer.startIndex
      var foundNewline = false
      while index < buffer.endIndex {
        if buffer[index] == 10 {
          let lineData = buffer[lineStart..<index]
          let absoluteNextOffset = range.offset + bufferStartOffset + Int64(buffer.distance(from: buffer.startIndex, to: index)) + 1
          lines.append(ScannedLine(
            text: String(decoding: lineData, as: UTF8.self),
            nextOffset: absoluteNextOffset,
            isTerminated: true,
          ))
          lineStart = buffer.index(after: index)
          foundNewline = true
        }
        index = buffer.index(after: index)
      }

      if foundNewline {
        if lineStart < buffer.endIndex {
          let trailing = buffer[lineStart...]
          bufferStartOffset += Int64(buffer.distance(from: buffer.startIndex, to: lineStart))
          buffer = Data(trailing)
        } else {
          buffer = Data()
          bufferStartOffset = readOffset
        }
      }
    }

    if !buffer.isEmpty {
      let absoluteNextOffset = range.offset + bufferStartOffset + Int64(buffer.count)
      lines.append(ScannedLine(
        text: String(decoding: buffer, as: UTF8.self),
        nextOffset: absoluteNextOffset,
        isTerminated: false,
      ))
    }

    return lines
  }

  // MARK: - File Attributes (Merged stat calls)

  private func fileAttributes(_ fileURL: URL) -> (size: Int64, mtime: String?) {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path) else {
      return (0, nil)
    }
    let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
    let mtime = (attributes[.modificationDate] as? Date).map { String($0.timeIntervalSince1970) }
    return (size, mtime)
  }

  private func byteSize(_ fileURL: URL) throws -> Int64 {
    fileAttributes(fileURL).size
  }

  private func fileModificationStamp(_ fileURL: URL) -> String? {
    fileAttributes(fileURL).mtime
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
      let attributes = fileAttributes(url)
      totalSize += attributes.size
      let mtime = attributes.mtime ?? "missing"
      return "\(url.lastPathComponent):\(attributes.size):\(mtime)"
    }
    guard !parts.isEmpty else {
      return nil
    }
    return (totalSize, parts.joined(separator: "|"))
  }

  // MARK: - Append Range with lastMtime optimization

  private func appendRange(fileURL: URL, fileSize: Int64, offset: Int64, lastMtime: String?) -> AppendRange? {
    let start: Int64
    if fileSize < offset {
      start = 0
    } else if lastMtime != nil && offset > 0 {
      // Trust that the previous scan ended at a line boundary
      start = offset
    } else {
      start = lineStartOffset(fileURL, offset: offset) ?? offset
    }
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

private struct ClaudeUsageKey: Codable {
  let messageId: String
  let createdAt: String
  let inputTokens: Int
  let outputTokens: Int
  let cacheCreation: Int
  let cacheRead: Int
  let reasoningTokens: Int

  init(messageId: String, record: TokMonUsageRecord) {
    self.messageId = messageId
    createdAt = record.createdAt
    inputTokens = record.inputTokens
    outputTokens = record.outputTokens
    cacheCreation = record.cacheCreation
    cacheRead = record.cacheRead
    reasoningTokens = record.reasoningTokens
  }

  var jsonString: String {
    let data = try? JSONEncoder().encode(self)
    return data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
  }

  init?(jsonString: String) {
    guard let data = jsonString.data(using: .utf8),
          let decoded = try? JSONDecoder().decode(ClaudeUsageKey.self, from: data) else {
      return nil
    }
    self = decoded
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
    case "[":
      return parseArray()
    case "'", "\"":
      return parseString()
    default:
      if let literal = parseLiteral() {
        return literal
      }
      return parseNumber()
    }
  }

  private mutating func parseArray() -> [Any]? {
    guard consume("[") else {
      return nil
    }
    skipWhitespace()

    var array: [Any] = []
    if consume("]") {
      return array
    }

    while index < characters.count {
      skipWhitespace()
      guard let value = parseValue() else {
        return nil
      }
      array.append(value)
      skipWhitespace()

      if consume("]") {
        return array
      }
      guard consume(",") else {
        return nil
      }
      skipWhitespace()
      if consume("]") {
        return array
      }
    }

    return nil
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
        case "b":
          result.append("\u{0008}")
        case "f":
          result.append("\u{000C}")
        case "\\":
          result.append("\\")
        case "\"":
          result.append("\"")
        case "'":
          result.append("'")
        case "u":
          guard index + 4 <= characters.count,
                let code = Int(String(characters[index..<index + 4]), radix: 16) else {
            return nil
          }
          guard let scalar = UnicodeScalar(code) else { return nil }
          result.append(Character(scalar))
          index += 4
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
    if let expChar = peek(), expChar == "e" || expChar == "E" {
      index += 1
      if let signChar = peek(), signChar == "+" || signChar == "-" {
        index += 1
      }
      while let character = peek(), character.isNumber {
        index += 1
      }
    }

    guard index > start else {
      return nil
    }

    let rawValue = String(characters[start..<index])
    if rawValue.contains(".") || rawValue.lowercased().contains("e") {
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

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
