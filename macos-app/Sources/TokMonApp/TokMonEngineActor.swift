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
    let defaults = TokMonSettingsDraft()
    return TokMonSettingsDraft(
      claudePath: config.sources["claude-code"]?.path ?? defaults.claudePath,
      codexPath: config.sources["codex"]?.path ?? defaults.codexPath,
      kimiCodePath: config.sources["kimi-code"]?.path ?? defaults.kimiCodePath,
      openCodePath: config.sources["opencode"]?.path ?? defaults.openCodePath,
      qwenCodePath: config.sources["qwen-code"]?.path ?? defaults.qwenCodePath,
      source: uiState.source,
      rangeLabel: resolvedRangeLabel(from: uiState),
      liveMode: true,
      interval: TokMonRangePreset(label: uiState.rangeLabel).interval,
      activeSeries: uiState.activeSeries,
      menuBarDisplayItems: uiState.menuBarDisplayItems,
      refreshRate: uiState.refreshRate,
      inputRate: uiState.costRates.input,
      outputRate: uiState.costRates.output,
      cacheCreateRate: uiState.costRates.cacheCreate,
      cacheReadRate: uiState.costRates.cacheRead,
      modelPricing: uiState.modelPricing,
      kimiQuotaRefreshInterval: uiState.kimiQuotaRefreshInterval,
      launchAtLogin: uiState.launchAtLogin,
      sourceColors: uiState.sourceColors,
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

  func updateDashboardCustomRange(from: String, to: String) throws {
    var uiState = try engine.configStore.loadUIState()
    uiState.rangeLabel = TokMonRangePreset.custom.label
    uiState.rangeHours = TokMonRangePreset.custom.hours
    uiState.rangeDays = TokMonRangePreset.custom.days
    uiState.from = from
    uiState.to = to
    uiState.liveMode = true
    uiState.rangeMode = "round"
    uiState.interval = TokMonRangePreset.custom.interval
    try engine.configStore.saveUIState(uiState)
  }

  func updateDashboardCustomRangeAndRefreshRangeStats(
    from: String,
    to: String,
    preserving existingSnapshot: TokMonStatsSnapshot,
    now: Date,
  ) throws -> TokMonStatsSnapshot {
    try updateDashboardCustomRange(from: from, to: to)
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
      sources: dashboardState.source,
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
      sources: dashboardState.source,
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
      sources: dashboardState.source,
      model: nil,
    )
    let summary = try engine.queryStore.summary(filter: filter, now: now)
    let previousSummary = try TokMonStatsSnapshotBuilder
      .previousFilter(from: dashboardState)
      .map { try engine.queryStore.summary(filter: $0, now: now) }
    let trend = try engine.queryStore.trend(filter: filter, interval: dashboardState.interval, now: now)
    let heatmap = try engine.queryStore.heatmap(sources: filter.sources, model: filter.model, endingAt: now)
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

  func loadKimiAPIKeyAccounts() throws -> [KimiAPIKeyAccount] {
    try engine.configStore.loadUIState().kimiAPIKeyAccounts
  }

  func loadKimiAPIKey(id: String) -> String? {
    engine.configStore.loadKimiAPIKeys()[id]
  }

  func loadAllKimiAPIKeys() -> [String: String] {
    engine.configStore.loadKimiAPIKeys()
  }

  func addKimiAPIKey(_ key: String, label: String) async throws -> KimiAPIKeyAccount {
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.hasPrefix("sk-kimi-") else {
      throw KimiQuotaError.invalidKey
    }
    var keys = engine.configStore.loadKimiAPIKeys()
    let id = UUID().uuidString
    keys[id] = trimmed
    try engine.configStore.saveKimiAPIKeys(keys)
    let account = KimiAPIKeyAccount(id: id, label: label.isEmpty ? "Kimi Key" : label)
    var uiState = try engine.configStore.loadUIState()
    uiState.kimiAPIKeyAccounts.append(account)
    if uiState.selectedKimiAPIKeyID == nil {
      uiState.selectedKimiAPIKeyID = id
    }
    try engine.configStore.saveUIState(uiState)
    return account
  }

  func removeKimiAPIKey(id: String) async throws {
    var keys = engine.configStore.loadKimiAPIKeys()
    keys.removeValue(forKey: id)
    try engine.configStore.saveKimiAPIKeys(keys)
    var uiState = try engine.configStore.loadUIState()
    uiState.kimiAPIKeyAccounts.removeAll { $0.id == id }
    if uiState.selectedKimiAPIKeyID == id {
      uiState.selectedKimiAPIKeyID = uiState.kimiAPIKeyAccounts.first?.id
    }
    try engine.configStore.saveUIState(uiState)
  }

  func renameKimiAPIKey(id: String, newLabel: String) async throws {
    let trimmed = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    var uiState = try engine.configStore.loadUIState()
    if let index = uiState.kimiAPIKeyAccounts.firstIndex(where: { $0.id == id }) {
      uiState.kimiAPIKeyAccounts[index].label = trimmed
      try engine.configStore.saveUIState(uiState)
    }
  }

  func updateKimiAPIKeyEndDates(id: String, weekly: Date?, fiveHour: Date?) async throws {
    var uiState = try engine.configStore.loadUIState()
    guard let index = uiState.kimiAPIKeyAccounts.firstIndex(where: { $0.id == id }) else {
      return
    }
    if let weekly {
      uiState.kimiAPIKeyAccounts[index].weeklyEndAt = weekly
    }
    if let fiveHour {
      uiState.kimiAPIKeyAccounts[index].fiveHourEndAt = fiveHour
    }
    try engine.configStore.saveUIState(uiState)
  }

  func refreshKimiQuota(forKeyID id: String, apiKey: String) async -> KimiQuotaSnapshot {
    guard !apiKey.isEmpty else {
      return KimiQuotaSnapshot(weekly: nil, fiveHour: nil, fetchedAt: nil, error: .noAPIKey)
    }
    return await engine.kimiQuotaStore.fetchQuota(apiKey: apiKey)
  }

  func refreshAllKimiQuotas(apiKeys: [String: String]) async -> [String: KimiQuotaSnapshot] {
    let accounts = (try? loadKimiAPIKeyAccounts()) ?? []
    guard !accounts.isEmpty else { return [:] }
    return await withTaskGroup(of: (String, KimiQuotaSnapshot).self) { group in
      for account in accounts {
        let apiKey = apiKeys[account.id] ?? ""
        group.addTask {
          (account.id, await self.refreshKimiQuota(forKeyID: account.id, apiKey: apiKey))
        }
      }
      var result: [String: KimiQuotaSnapshot] = [:]
      for await (id, snapshot) in group {
        result[id] = snapshot
      }
      return result
    }
  }

  func loadKimiQuotaRefreshInterval() throws -> Int {
    let state = try engine.configStore.loadUIState()
    return max(0, state.kimiQuotaRefreshInterval)
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
      menuBarDisplayItems: draft.menuBarDisplayItems,
      refreshRate: max(1000, draft.refreshRate),
      kimiQuotaRefreshInterval: max(0, draft.kimiQuotaRefreshInterval),
      launchAtLogin: draft.launchAtLogin,
      costRates: TokMonCostRates(
        input: max(0, draft.inputRate),
        output: max(0, draft.outputRate),
        cacheCreate: max(0, draft.cacheCreateRate),
        cacheRead: max(0, draft.cacheReadRate),
      ),
      modelPricing: normalizedModelPricing(draft.modelPricing),
      kimiAPIKeyAccounts: existingState.kimiAPIKeyAccounts,
      selectedKimiAPIKeyID: existingState.selectedKimiAPIKeyID,
      sourceColors: normalizedSourceColors(draft.sourceColors)
    )
  }

  private func normalizedSourceColors(_ colors: [String: TokMonSourceColor]) -> [String: TokMonSourceColor] {
    var result = TokMonSourceColor.defaultColors
    for (source, color) in colors where TokMonSourceColor.defaultColors.keys.contains(source) {
      result[source] = color
    }
    return result
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
