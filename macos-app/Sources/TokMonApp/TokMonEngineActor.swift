import Foundation

actor TokMonEngineActor {
  private let engine: TokMonEngine

  init(engine: TokMonEngine) {
    self.engine = engine
  }

  func loadSettingsDraft() throws -> TokMonSettingsDraft {
    let config = try engine.configStore.loadConfig()
    let uiState = try engine.configStore.loadUIState()
    let models = try engine.queryStore.models()
    return TokMonSettingsDraft(
      claudePath: config.sources["claude-code"]?.path ?? TokMonSettingsDraft().claudePath,
      codexPath: config.sources["codex"]?.path ?? TokMonSettingsDraft().codexPath,
      kimiCodePath: config.sources["kimi-code"]?.path ?? TokMonSettingsDraft().kimiCodePath,
      openCodePath: config.sources["opencode"]?.path ?? TokMonSettingsDraft().openCodePath,
      qwenCodePath: config.sources["qwen-code"]?.path ?? TokMonSettingsDraft().qwenCodePath,
      source: uiState.source,
      rangeLabel: resolvedRangeLabel(from: uiState),
      liveMode: true,
      interval: TokMonRangePreset(label: uiState.rangeLabel).interval,
      activeSeries: uiState.activeSeries,
      menuBarDisplayMode: uiState.menuBarDisplayMode,
      refreshRate: uiState.refreshRate,
      inputRate: uiState.costRates.input,
      outputRate: uiState.costRates.output,
      cacheCreateRate: uiState.costRates.cacheCreate,
      cacheReadRate: uiState.costRates.cacheRead,
      modelPricing: uiState.modelPricing,
      availableModels: models,
    )
  }

  func saveSettings(draft: TokMonSettingsDraft) throws {
    var config = try engine.configStore.loadConfig()
    config.sources["claude-code"] = TokMonSourceConfig(path: draft.claudePath)
    config.sources["codex"] = TokMonSourceConfig(path: draft.codexPath)
    config.sources["kimi-code"] = TokMonSourceConfig(path: draft.kimiCodePath)
    config.sources["opencode"] = TokMonSourceConfig(path: draft.openCodePath)
    config.sources["qwen-code"] = TokMonSourceConfig(path: draft.qwenCodePath)
    try engine.configStore.saveConfig(config)
    let existingState = try engine.configStore.loadUIState()
    try engine.configStore.saveUIState(uiState(from: draft, preserving: existingState))
  }

  func updateDashboardRange(label: String) throws {
    var uiState = try engine.configStore.loadUIState()
    let preset = TokMonRangePreset(label: label)
    uiState.rangeLabel = preset.label
    uiState.rangeHours = preset.hours
    uiState.rangeDays = preset.days
    uiState.liveMode = true
    uiState.rangeMode = "round"
    uiState.interval = preset.interval
    try engine.configStore.saveUIState(uiState)
  }

  func updateDashboardRangeAndRefreshRangeStats(
    label: String,
    preserving existingSnapshot: TokMonStatsSnapshot,
    now: Date,
  ) throws -> TokMonStatsSnapshot {
    try updateDashboardRange(label: label)
    return try refreshRangeStats(preserving: existingSnapshot, now: now)
  }

  func scan(paths: [String]? = nil) throws -> Int {
    let config = try engine.configStore.loadConfig()
    return try engine.scanner.scan(config: config, paths: paths)
  }

  func databaseDataVersion() -> UInt64 {
    engine.database.dataVersion
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
  ) throws -> TokMonStatsSnapshot {
    let config = try engine.configStore.loadConfig()
    let rawUIState = try engine.configStore.loadUIState()
    let inserted = try engine.scanner.scan(config: config)
    return try statsSnapshot(
      rawUIState: rawUIState,
      now: now,
      inserted: inserted,
      recordsLimit: recordsLimit,
      sessionsLimit: sessionsLimit,
      selectedSession: selectedSession,
    )
  }

  func refreshStatsWithoutScan(
    now: Date,
    recordsLimit: Int,
    sessionsLimit: Int,
    selectedSession: TokMonUsageSessionSelection?,
  ) throws -> TokMonStatsSnapshot {
    try statsSnapshot(
      rawUIState: engine.configStore.loadUIState(),
      now: now,
      inserted: 0,
      recordsLimit: recordsLimit,
      sessionsLimit: sessionsLimit,
      selectedSession: selectedSession,
    )
  }

  func refreshRangeStats(
    preserving existingSnapshot: TokMonStatsSnapshot,
    now: Date,
  ) throws -> TokMonStatsSnapshot {
    let rawUIState = try engine.configStore.loadUIState()
    let dashboardState = TokMonStatsSnapshotBuilder.currentDashboardState(from: rawUIState, now: now)
    let filter = TokMonQueryFilter(
      from: dashboardState.from,
      to: dashboardState.to,
      source: dashboardState.source.isEmpty ? nil : dashboardState.source,
      model: nil,
    )
    let summary = try engine.queryStore.summary(filter: filter, now: now)
    let previousSummary = try TokMonStatsSnapshotBuilder
      .previousFilter(from: dashboardState)
      .map { try engine.queryStore.summary(filter: $0, now: now) }
    let trend = try engine.queryStore.trend(filter: filter, interval: dashboardState.interval, now: now)

    return TokMonStatsSnapshot(
      scanStatus: TokMonScanStatus(
        running: false,
        phase: "Idle",
        current: 0,
        total: 0,
        processed: 0,
        startedAt: nil,
        finishedAt: TokMonStatsSnapshotBuilder.formattedTimestamp(now),
        error: nil,
      ),
      summary: summary,
      previousSummary: previousSummary,
      trendBuckets: TokMonStatsSnapshotBuilder.fillTrendBuckets(trend, dashboardState: dashboardState),
      heatmapDays: existingSnapshot.heatmapDays,
      yearHeatmapDays: existingSnapshot.yearHeatmapDays,
      recordsPage: existingSnapshot.recordsPage,
      usageSessions: existingSnapshot.usageSessions,
      selectedUsageSession: existingSnapshot.selectedUsageSession,
      selectedSessionRecords: existingSnapshot.selectedSessionRecords,
      dashboardState: dashboardState,
      updatedAt: now,
    )
  }

  func selectedUsageSessionRecords(
    preserving existingSnapshot: TokMonStatsSnapshot,
    selectedSession: TokMonUsageSessionSelection,
    now: Date,
  ) throws -> [TokMonRecordRow] {
    let dashboardState: TokMonDashboardState
    if let existingDashboardState = existingSnapshot.dashboardState {
      dashboardState = existingDashboardState
    } else {
      dashboardState = TokMonStatsSnapshotBuilder.currentDashboardState(
        from: try engine.configStore.loadUIState(),
        now: now,
      )
    }
    let filter = TokMonQueryFilter(
      from: dashboardState.from,
      to: dashboardState.to,
      source: dashboardState.source.isEmpty ? nil : dashboardState.source,
      model: nil,
    )
    return try engine.queryStore.recordsForSession(
      filter: filter,
      source: selectedSession.source,
      sessionId: selectedSession.sessionId,
      limit: 20,
    )
  }

  private func statsSnapshot(
    rawUIState: TokMonUIState,
    now: Date,
    inserted: Int,
    recordsLimit: Int,
    sessionsLimit: Int,
    selectedSession: TokMonUsageSessionSelection?,
  ) throws -> TokMonStatsSnapshot {
    let dashboardState = TokMonStatsSnapshotBuilder.currentDashboardState(from: rawUIState, now: now)
    let filter = TokMonQueryFilter(
      from: dashboardState.from,
      to: dashboardState.to,
      source: dashboardState.source.isEmpty ? nil : dashboardState.source,
      model: nil,
    )
    let summary = try engine.queryStore.summary(filter: filter, now: now)
    let previousSummary = try TokMonStatsSnapshotBuilder
      .previousFilter(from: dashboardState)
      .map { try engine.queryStore.summary(filter: $0, now: now) }
    let trend = try engine.queryStore.trend(filter: filter, interval: dashboardState.interval, now: now)
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

    return TokMonStatsSnapshot(
      scanStatus: TokMonScanStatus(
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
      previousSummary: previousSummary,
      trendBuckets: TokMonStatsSnapshotBuilder.fillTrendBuckets(trend, dashboardState: dashboardState),
      heatmapDays: heatmap,
      yearHeatmapDays: [],
      recordsPage: records,
      usageSessions: sessions,
      selectedUsageSession: selectedSession,
      selectedSessionRecords: selectedRecords,
      dashboardState: dashboardState,
      updatedAt: now,
    )
  }

  private func uiState(from draft: TokMonSettingsDraft, preserving existingState: TokMonUIState) -> TokMonUIState {
    let preset = TokMonRangePreset(label: draft.rangeLabel)
    return TokMonUIState(
      source: draft.source,
      from: existingState.from,
      to: existingState.to,
      rangeLabel: preset.label,
      rangeHours: preset.hours,
      rangeDays: preset.days,
      liveMode: true,
      rangeMode: "round",
      interval: preset.interval,
      activeSeries: draft.activeSeries,
      menuBarDisplayMode: draft.menuBarDisplayMode,
      refreshRate: max(1000, draft.refreshRate),
      costRates: TokMonCostRates(
        input: max(0, draft.inputRate),
        output: max(0, draft.outputRate),
        cacheCreate: max(0, draft.cacheCreateRate),
        cacheRead: max(0, draft.cacheReadRate),
      ),
      modelPricing: normalizedModelPricing(draft.modelPricing),
    )
  }

  private func normalizedModelPricing(_ pricing: [String: TokMonCostRates]) -> [String: TokMonCostRates] {
    pricing.reduce(into: [:]) { result, item in
      let model = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !model.isEmpty else {
        return
      }
      result[model] = item.value.normalized()
    }
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

  private func validateRebuildSources(config: TokMonConfig) throws {
    let directories = config.sources.values.map { expandedURL($0.path) }
    guard !directories.isEmpty else {
      throw TokMonSettingsError.noReadableSourcePaths
    }

    for directory in directories {
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        throw TokMonSettingsError.noReadableSourcePaths
      }
      guard FileManager.default.isReadableFile(atPath: directory.path) else {
        throw TokMonSettingsError.noReadableSourcePaths
      }
    }

    let hasUsageLogs = directories.contains { directory in
      if FileManager.default.fileExists(atPath: directory.appendingPathComponent("opencode.db").path) {
        return true
      }
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

    guard hasUsageLogs else {
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
