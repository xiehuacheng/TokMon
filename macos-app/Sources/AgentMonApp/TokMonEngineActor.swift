import Foundation

actor TokMonEngineActor {
  private let engine: TokMonEngine

  init(engine: TokMonEngine) {
    self.engine = engine
  }

  func loadSettingsDraft() throws -> TokMonSettingsDraft {
    let config = try engine.configStore.loadConfig()
    let uiState = try engine.configStore.loadUIState()
    return TokMonSettingsDraft(
      claudePath: config.sources["claude-code"]?.path ?? TokMonSettingsDraft().claudePath,
      codexPath: config.sources["codex"]?.path ?? TokMonSettingsDraft().codexPath,
      source: uiState.source,
      rangeLabel: resolvedRangeLabel(from: uiState),
      liveMode: uiState.liveMode,
      rangeMode: uiState.rangeMode,
      interval: uiState.interval,
      activeSeries: uiState.activeSeries,
      refreshRate: uiState.refreshRate,
      inputRate: uiState.costRates.input,
      outputRate: uiState.costRates.output,
      cacheCreateRate: uiState.costRates.cacheCreate,
      cacheReadRate: uiState.costRates.cacheRead,
    )
  }

  func saveSettings(draft: TokMonSettingsDraft) throws {
    var config = try engine.configStore.loadConfig()
    config.sources["claude-code"] = TokMonSourceConfig(path: draft.claudePath)
    config.sources["codex"] = TokMonSourceConfig(path: draft.codexPath)
    try engine.configStore.saveConfig(config)
    let existingState = try engine.configStore.loadUIState()
    try engine.configStore.saveUIState(uiState(from: draft, preserving: existingState))
  }

  func scan() throws -> Int {
    let config = try engine.configStore.loadConfig()
    return try engine.scanner.scan(config: config)
  }

  func rebuildAndRescan() throws -> Int {
    let config = try engine.configStore.loadConfig()
    try validateRebuildSources(config: config)
    try engine.database.rebuildTokMonData()
    return try engine.scanner.scan(config: config)
  }

  func refreshStats(
    now: Date,
    recordsLimit: Int,
    sessionsLimit: Int,
    selectedSession: TokMonUsageSessionSelection?,
  ) throws -> AgentMonStatsSnapshot {
    let config = try engine.configStore.loadConfig()
    let rawUIState = try engine.configStore.loadUIState()
    let dashboardState = TokMonStatsSnapshotBuilder.currentDashboardState(from: rawUIState, now: now)
    let inserted = try engine.scanner.scan(config: config)
    let filter = TokMonQueryFilter(
      from: dashboardState.from,
      to: dashboardState.to,
      source: dashboardState.source.isEmpty ? nil : dashboardState.source,
      model: nil,
    )
    let summary = try engine.queryStore.summary(filter: filter)
    let trend = try engine.queryStore.trend(filter: filter, interval: dashboardState.interval)
    let heatmap = try engine.queryStore.heatmap(source: filter.source, model: filter.model, endingAt: now)
    let records = try engine.queryStore.records(filter: filter, page: 0, limit: recordsLimit)
    let sessions = try engine.queryStore.sessions(filter: filter, limit: sessionsLimit)
    let selectedRecords = try selectedSession.map {
      try engine.queryStore.recordsForSession(
        filter: filter,
        source: $0.source,
        sessionId: $0.sessionId,
        limit: 20,
      )
    } ?? []

    return AgentMonStatsSnapshot(
      scanStatus: AgentMonScanStatus(
        running: false,
        phase: inserted > 0 ? "Scanned \(inserted) new records" : "Idle",
        current: 0,
        total: 0,
        processed: inserted,
        startedAt: nil,
        finishedAt: TokMonStatsSnapshotBuilder.formattedTimestamp(now),
        error: nil,
      ),
      summary: summary,
      trendBuckets: TokMonStatsSnapshotBuilder.fillTrendBuckets(trend, dashboardState: dashboardState),
      heatmapDays: heatmap,
      recordsPage: records,
      usageSessions: sessions,
      selectedUsageSession: selectedSession,
      selectedSessionRecords: selectedRecords,
      dashboardState: dashboardState,
      updatedAt: now,
    )
  }

  private func uiState(from draft: TokMonSettingsDraft, preserving existingState: TokMonUIState) -> TokMonUIState {
    let range = rangeComponents(label: draft.rangeLabel)
    return TokMonUIState(
      source: draft.source,
      from: existingState.from,
      to: existingState.to,
      rangeLabel: draft.rangeLabel,
      rangeHours: range.hours,
      rangeDays: range.days,
      liveMode: draft.liveMode,
      rangeMode: draft.rangeMode,
      interval: draft.interval,
      activeSeries: draft.activeSeries,
      refreshRate: max(1000, draft.refreshRate),
      costRates: TokMonCostRates(
        input: max(0, draft.inputRate),
        output: max(0, draft.outputRate),
        cacheCreate: max(0, draft.cacheCreateRate),
        cacheRead: max(0, draft.cacheReadRate),
      ),
    )
  }

  private func resolvedRangeLabel(from uiState: TokMonUIState) -> String {
    if let rangeLabel = uiState.rangeLabel, !rangeLabel.isEmpty {
      return rangeLabel
    }
    if let rangeHours = uiState.rangeHours {
      return "\(rangeHours)H"
    }
    if let rangeDays = uiState.rangeDays {
      return "\(rangeDays)D"
    }
    return TokMonSettingsDraft().rangeLabel
  }

  private func rangeComponents(label: String) -> (hours: Int?, days: Int?) {
    switch label {
    case "1H":
      return (1, nil)
    case "24H":
      return (24, nil)
    case "30D":
      return (nil, 30)
    case "90D":
      return (nil, 90)
    default:
      return (nil, 7)
    }
  }

  private func validateRebuildSources(config: TokMonConfig) throws {
    let paths = config.sources.values.map(\.path)
    let existingDirectories = paths
      .map(expandedURL)
      .filter { url in
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
      }

    guard !existingDirectories.isEmpty else {
      throw TokMonSettingsError.noReadableSourcePaths
    }

    let hasJSONL = existingDirectories.contains { directory in
      guard let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles],
      ) else {
        return false
      }
      for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
        if (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
          return true
        }
      }
      return false
    }

    guard hasJSONL else {
      throw TokMonSettingsError.noUsageLogsFound
    }
  }

  private func expandedURL(_ path: String) -> URL {
    if path == "~" {
      return FileManager.default.homeDirectoryForCurrentUser
    }
    if path.hasPrefix("~/") {
      return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(String(path.dropFirst(2)))
    }
    return URL(fileURLWithPath: path)
  }
}
