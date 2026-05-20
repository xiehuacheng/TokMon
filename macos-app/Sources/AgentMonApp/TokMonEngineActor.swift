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
      source: uiState.source,
      rangeLabel: resolvedRangeLabel(from: uiState),
      liveMode: true,
      interval: TokMonRangePreset(label: uiState.rangeLabel).interval,
      activeSeries: uiState.activeSeries,
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
    preserving existingSnapshot: AgentMonStatsSnapshot,
    now: Date,
  ) throws -> AgentMonStatsSnapshot {
    try updateDashboardRange(label: label)
    return try refreshRangeStats(preserving: existingSnapshot, now: now)
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

  func legacyParityCheck(now: Date) throws -> TokMonParityReport {
    let context = try parityContext(now: now)
    return try engine.parityVerifier.compare(
      native: nativeParitySnapshot(context: context),
      legacy: legacyRouteParitySnapshot(context: context),
    )
  }

  func refreshStats(
    now: Date,
    recordsLimit: Int,
    sessionsLimit: Int,
    selectedSession: TokMonUsageSessionSelection?,
  ) throws -> AgentMonStatsSnapshot {
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
  ) throws -> AgentMonStatsSnapshot {
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
    preserving existingSnapshot: AgentMonStatsSnapshot,
    now: Date,
  ) throws -> AgentMonStatsSnapshot {
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

    return AgentMonStatsSnapshot(
      scanStatus: AgentMonScanStatus(
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
    preserving existingSnapshot: AgentMonStatsSnapshot,
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
  ) throws -> AgentMonStatsSnapshot {
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

  private func parityContext(now: Date) throws -> TokMonParityContext {
    let uiState = try engine.configStore.loadUIState()
    let dashboardState = TokMonStatsSnapshotBuilder.currentDashboardState(from: uiState, now: now)
    let filter = TokMonQueryFilter(
      from: dashboardState.from,
      to: dashboardState.to,
      source: dashboardState.source.isEmpty ? nil : dashboardState.source,
      model: nil,
    )
    return TokMonParityContext(now: now, dashboardState: dashboardState, filter: filter)
  }

  private func nativeParitySnapshot(context: TokMonParityContext) throws -> TokMonParitySnapshot {
    let filter = context.filter
    let summary = try engine.queryStore.summary(filter: filter)
    let trend = try engine.queryStore.trend(filter: filter, interval: context.dashboardState.interval)
    let heatmap = try engine.queryStore.heatmap(source: filter.source, model: filter.model, endingAt: context.now)
    let models = try engine.queryStore.models()
    let records = try engine.queryStore.records(filter: filter, page: 0, limit: 50)
    let sessions = try engine.queryStore.sessions(limit: 50)

    return TokMonParitySnapshot(
      summary: parityFields(summary),
      trend: parityFields(trend),
      heatmap: parityFields(heatmap.filter { $0.requests > 0 }),
      models: parityFields(models),
      records: parityFields(records, linkedSessionID: { $0.sessionId }),
      sessions: parityFields(sessions),
    )
  }

  private func legacyRouteParitySnapshot(context: TokMonParityContext) throws -> TokMonParitySnapshot {
    TokMonParitySnapshot(
      summary: try legacySummaryFields(filter: context.filter),
      trend: try legacyTrendFields(filter: context.filter, interval: context.dashboardState.interval),
      heatmap: try legacyHeatmapFields(source: context.filter.source, model: context.filter.model, now: context.now),
      models: try legacyModelFields(),
      records: try legacyRecordFields(filter: context.filter, page: 0, limit: 50),
      sessions: try legacySessionFields(),
    )
  }

  private func legacySummaryFields(filter: TokMonQueryFilter) throws -> [String: String] {
    let scoped = scopedWhere(filter: filter)
    let total = try engine.database.queryRows("""
      SELECT COUNT(*) as total_requests,
             COALESCE(SUM(input_tokens), 0) as total_input,
             COALESCE(SUM(output_tokens), 0) as total_output,
             COALESCE(SUM(cache_creation), 0) as total_cache_creation,
             COALESCE(SUM(cache_read), 0) as total_cache_read,
             COALESCE(SUM(reasoning_tokens), 0) as total_reasoning
      FROM usage_records \(scoped.whereSQL)
    """, params: scoped.params) { row in
      TokMonTotals(
        totalRequests: row.int(0),
        totalInput: row.int(1),
        totalOutput: row.int(2),
        totalCacheCreation: row.int(3),
        totalCacheRead: row.int(4),
        totalReasoning: row.int(5),
      )
    }.first ?? TokMonTotals(totalRequests: 0, totalInput: 0, totalOutput: 0, totalCacheCreation: 0, totalCacheRead: 0, totalReasoning: 0)

    let bySource = try engine.database.queryRows("""
      SELECT source, COUNT(*) as requests,
             SUM(input_tokens) as input_tokens, SUM(output_tokens) as output_tokens,
             SUM(cache_creation) as cache_creation, SUM(cache_read) as cache_read
      FROM usage_records \(scoped.whereSQL)
      GROUP BY source
    """, params: scoped.params) { row in
      TokMonSourceTotals(
        source: row.string(0),
        requests: row.int(1),
        inputTokens: row.int(2),
        outputTokens: row.int(3),
        cacheCreation: row.int(4),
        cacheRead: row.int(5),
      )
    }

    let byModel = try engine.database.queryRows("""
      SELECT model, source, COUNT(*) as requests,
             SUM(input_tokens) as input_tokens, SUM(output_tokens) as output_tokens,
             SUM(cache_creation) as cache_creation, SUM(cache_read) as cache_read
      FROM usage_records \(scoped.whereSQL)
      GROUP BY model, source ORDER BY requests DESC
    """, params: scoped.params) { row in
      TokMonModelTotals(
        model: row.string(0),
        source: row.string(1),
        requests: row.int(2),
        inputTokens: row.int(3),
        outputTokens: row.int(4),
        cacheCreation: row.int(5),
        cacheRead: row.int(6),
      )
    }

    return parityFields(TokMonSummary(total: total, bySource: bySource, byModel: byModel))
  }

  private func legacyTrendFields(filter: TokMonQueryFilter, interval: String) throws -> [String: String] {
    let format = interval == "day" ? "%Y-%m-%d" : "%Y-%m-%d %H:00"
    let scoped = scopedWhere(filter: filter)
    let rows = try engine.database.queryRows("""
      SELECT strftime('\(format)', created_at, 'localtime') as bucket,
             SUM(input_tokens) as input_tokens,
             SUM(output_tokens) as output_tokens,
             SUM(cache_creation) as cache_creation,
             SUM(cache_read) as cache_read,
             COUNT(*) as requests
      FROM usage_records
      \(scoped.whereSQL)
      GROUP BY bucket ORDER BY bucket
    """, params: scoped.params) { row in
      TokMonTrendBucket(
        bucket: row.string(0),
        inputTokens: row.int(1),
        outputTokens: row.int(2),
        cacheCreation: row.int(3),
        cacheRead: row.int(4),
        requests: row.int(5),
      )
    }
    return parityFields(rows)
  }

  private func legacyHeatmapFields(source: String?, model: String?, now: Date) throws -> [String: String] {
    var whereSQL = "WHERE created_at >= datetime(?, '-365 days')"
    var params: [TokMonSQLValue] = [.text(sqliteUTCDateTime(now))]
    appendOptionalFilters(source: source, model: model, tablePrefix: nil, whereSQL: &whereSQL, params: &params)

    let rows = try engine.database.queryRows("""
      SELECT strftime('%Y-%m-%d', created_at, 'localtime') as day,
             COUNT(*) as requests,
             SUM(input_tokens) as input_tokens,
             SUM(output_tokens) as output_tokens,
             SUM(cache_creation) as cache_creation,
             SUM(cache_read) as cache_read
      FROM usage_records
      \(whereSQL)
      GROUP BY day
    """, params: params) { row in
      TokMonHeatmapDay(
        day: row.string(0),
        requests: row.int(1),
        inputTokens: row.int(2),
        outputTokens: row.int(3),
        cacheCreation: row.int(4),
        cacheRead: row.int(5),
      )
    }
    return parityFields(rows)
  }

  private func legacyModelFields() throws -> [String: String] {
    let rows = try engine.database.queryRows("""
      SELECT model, MAX(created_at) as last_used
      FROM usage_records
      WHERE model != '' AND model != 'unknown' AND model != '<synthetic>'
      GROUP BY model
      ORDER BY last_used DESC
    """) { row in
      TokMonModelOption(model: row.string(0), lastUsed: row.string(1))
    }
    return parityFields(rows)
  }

  private func legacyRecordFields(filter: TokMonQueryFilter, page: Int, limit: Int) throws -> [String: String] {
    let normalizedPage = max(0, page)
    let normalizedLimit = max(1, limit)
    let scoped = scopedWhere(filter: filter, tablePrefix: "u")
    let total = try engine.database.queryInt("SELECT COUNT(*) as c FROM usage_records u \(scoped.whereSQL)", params: scoped.params)
    var rowParams = scoped.params
    rowParams.append(.int(normalizedLimit))
    rowParams.append(.int(normalizedPage * normalizedLimit))

    guard try engine.database.tableExists("sessions") else {
      return [
        "__error": "Legacy /api/tokmon/records requires the sessions table.",
        "total": "\(total)",
        "page": "\(normalizedPage)",
        "limit": "\(normalizedLimit)",
      ]
    }

    let rows: [(record: TokMonRecordRow, linkedSessionID: String)] = try engine.database.queryRows("""
      SELECT u.source,
             u.session_id,
             COALESCE(s_exact.id, s_file.id, u.session_id) as linked_session_id,
             u.model,
             u.input_tokens,
             u.output_tokens,
             u.cache_creation,
             u.cache_read,
             u.reasoning_tokens,
             datetime(u.created_at, 'localtime') as created_at
      FROM usage_records u
      LEFT JOIN sessions s_exact
        ON s_exact.source = u.source
        AND s_exact.id = u.session_id
      LEFT JOIN sessions s_file
        ON s_file.source = u.source
        AND s_exact.id IS NULL
        AND substr(s_file.file_path, -length(u.session_id || '.jsonl')) = u.session_id || '.jsonl'
      \(scoped.whereSQL)
      ORDER BY u.created_at DESC
      LIMIT ? OFFSET ?
    """, params: rowParams) { row in
      (
        TokMonRecordRow(
          source: row.string(0),
          sessionId: row.string(1),
          model: row.string(3),
          inputTokens: row.int(4),
          outputTokens: row.int(5),
          cacheCreation: row.int(6),
          cacheRead: row.int(7),
          reasoningTokens: row.int(8),
          createdAt: row.string(9),
        ),
        row.string(2)
      )
    }

    return parityFields(
      TokMonRecordsPage(total: total, page: normalizedPage, limit: normalizedLimit, rows: rows.map(\.record)),
      linkedSessionID: { record in
        rows.first { $0.record.id == record.id }?.linkedSessionID ?? record.sessionId
      },
    )
  }

  private func legacySessionFields() throws -> [String: String] {
    let rows = try engine.database.queryRows("""
      SELECT session_id, source, model,
             COUNT(*) as requests,
             SUM(input_tokens) as input_tokens,
             SUM(output_tokens) as output_tokens,
             MIN(created_at) as first_at,
             MAX(created_at) as last_at
      FROM usage_records
      GROUP BY session_id, source
      ORDER BY last_at DESC
      LIMIT 50
    """) { row in
      TokMonUsageSession(
        sessionId: row.string(0),
        source: row.string(1),
        title: nil,
        model: row.string(2),
        requests: row.int(3),
        inputTokens: row.int(4),
        outputTokens: row.int(5),
        cacheCreation: 0,
        cacheRead: 0,
        firstAt: row.string(6),
        lastAt: row.string(7),
      )
    }
    return parityFields(rows, includeCacheFields: false)
  }

  private func parityFields(_ summary: TokMonSummary) -> [String: String] {
    var fields: [String: String] = [
      "total.total_requests": "\(summary.total.totalRequests)",
      "total.total_input": "\(summary.total.totalInput)",
      "total.total_output": "\(summary.total.totalOutput)",
      "total.total_cache_creation": "\(summary.total.totalCacheCreation)",
      "total.total_cache_read": "\(summary.total.totalCacheRead)",
      "total.total_reasoning": "\(summary.total.totalReasoning)",
      "bySource.count": "\(summary.bySource.count)",
      "byModel.count": "\(summary.byModel.count)",
      "byModel.order": summary.byModel.map { "\($0.source):\($0.model)" }.joined(separator: ","),
    ]

    for source in summary.bySource {
      fields["bySource.\(source.source).requests"] = "\(source.requests)"
      fields["bySource.\(source.source).input_tokens"] = "\(source.inputTokens)"
      fields["bySource.\(source.source).output_tokens"] = "\(source.outputTokens)"
      fields["bySource.\(source.source).cache_creation"] = "\(source.cacheCreation)"
      fields["bySource.\(source.source).cache_read"] = "\(source.cacheRead)"
    }

    for model in summary.byModel {
      let key = "\(model.source):\(model.model)"
      fields["byModel.\(key).requests"] = "\(model.requests)"
      fields["byModel.\(key).input_tokens"] = "\(model.inputTokens)"
      fields["byModel.\(key).output_tokens"] = "\(model.outputTokens)"
      fields["byModel.\(key).cache_creation"] = "\(model.cacheCreation)"
      fields["byModel.\(key).cache_read"] = "\(model.cacheRead)"
    }

    return fields
  }

  private func parityFields(_ buckets: [TokMonTrendBucket]) -> [String: String] {
    var fields = ["count": "\(buckets.count)", "order": buckets.map(\.bucket).joined(separator: ",")]
    for bucket in buckets {
      fields["\(bucket.bucket).input_tokens"] = "\(bucket.inputTokens)"
      fields["\(bucket.bucket).output_tokens"] = "\(bucket.outputTokens)"
      fields["\(bucket.bucket).cache_creation"] = "\(bucket.cacheCreation)"
      fields["\(bucket.bucket).cache_read"] = "\(bucket.cacheRead)"
      fields["\(bucket.bucket).requests"] = "\(bucket.requests)"
    }
    return fields
  }

  private func parityFields(_ days: [TokMonHeatmapDay]) -> [String: String] {
    var fields = ["count": "\(days.count)"]
    for day in days {
      fields["\(day.day).requests"] = "\(day.requests)"
      fields["\(day.day).input_tokens"] = "\(day.inputTokens)"
      fields["\(day.day).output_tokens"] = "\(day.outputTokens)"
      fields["\(day.day).cache_creation"] = "\(day.cacheCreation)"
      fields["\(day.day).cache_read"] = "\(day.cacheRead)"
    }
    return fields
  }

  private func parityFields(_ models: [TokMonModelOption]) -> [String: String] {
    var fields = ["count": "\(models.count)"]
    for (index, model) in models.enumerated() {
      fields["\(index).model"] = model.model
      fields["\(index).last_used"] = model.lastUsed
    }
    return fields
  }

  private func parityFields(
    _ page: TokMonRecordsPage,
    linkedSessionID: (TokMonRecordRow) -> String,
  ) -> [String: String] {
    var fields = [
      "total": "\(page.total)",
      "page": "\(page.page)",
      "limit": "\(page.limit)",
      "rows.count": "\(page.rows.count)",
    ]
    for (index, row) in page.rows.enumerated() {
      fields["\(index).source"] = row.source
      fields["\(index).session_id"] = row.sessionId
      fields["\(index).linked_session_id"] = linkedSessionID(row)
      fields["\(index).model"] = row.model
      fields["\(index).input_tokens"] = "\(row.inputTokens)"
      fields["\(index).output_tokens"] = "\(row.outputTokens)"
      fields["\(index).cache_creation"] = "\(row.cacheCreation)"
      fields["\(index).cache_read"] = "\(row.cacheRead)"
      fields["\(index).reasoning_tokens"] = "\(row.reasoningTokens)"
      fields["\(index).created_at"] = row.createdAt
    }
    return fields
  }

  private func parityFields(_ sessions: [TokMonUsageSession], includeCacheFields: Bool = true) -> [String: String] {
    var fields = ["count": "\(sessions.count)"]
    for (index, session) in sessions.enumerated() {
      fields["\(index).session_id"] = session.sessionId
      fields["\(index).source"] = session.source
      fields["\(index).model"] = session.model
      fields["\(index).requests"] = "\(session.requests)"
      fields["\(index).input_tokens"] = "\(session.inputTokens)"
      fields["\(index).output_tokens"] = "\(session.outputTokens)"
      if includeCacheFields {
        fields["\(index).cache_creation"] = "\(session.cacheCreation)"
        fields["\(index).cache_read"] = "\(session.cacheRead)"
      }
      fields["\(index).first_at"] = session.firstAt
      fields["\(index).last_at"] = session.lastAt
    }
    return fields
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

    let hasJSONL = directories.contains { directory in
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

  private func scopedWhere(
    filter: TokMonQueryFilter,
    tablePrefix: String? = nil,
  ) -> (whereSQL: String, params: [TokMonSQLValue]) {
    let createdColumn = column("created_at", tablePrefix: tablePrefix)
    var clauses: [String] = []
    var params: [TokMonSQLValue] = []
    if filter.hasTimeRange {
      clauses.append("datetime(\(createdColumn), 'localtime') BETWEEN datetime(?) AND datetime(?)")
      params.append(.text(filter.from))
      params.append(.text(filter.to))
    }
    var whereSQL = clauses.isEmpty ? "WHERE 1 = 1" : "WHERE \(clauses.joined(separator: " AND "))"
    appendOptionalFilters(source: filter.source, model: filter.model, tablePrefix: tablePrefix, whereSQL: &whereSQL, params: &params)
    return (whereSQL, params)
  }

  private func appendOptionalFilters(
    source: String?,
    model: String?,
    tablePrefix: String?,
    whereSQL: inout String,
    params: inout [TokMonSQLValue],
  ) {
    if let source, !source.isEmpty {
      whereSQL += " AND \(column("source", tablePrefix: tablePrefix)) = ?"
      params.append(.text(source))
    }
    if let model, !model.isEmpty {
      whereSQL += " AND \(column("model", tablePrefix: tablePrefix)) = ?"
      params.append(.text(model))
    }
  }

  private func column(_ name: String, tablePrefix: String?) -> String {
    guard let tablePrefix else {
      return name
    }
    return "\(tablePrefix).\(name)"
  }

  private func sqliteUTCDateTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.string(from: date)
  }
}

private struct TokMonParityContext {
  let now: Date
  let dashboardState: TokMonDashboardState
  let filter: TokMonQueryFilter
}
