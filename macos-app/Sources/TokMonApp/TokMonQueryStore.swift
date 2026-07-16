import Foundation

final class TokMonQueryStore {
  private let database: TokMonDatabase?

  init() {
    database = nil
  }

  init(database: TokMonDatabase) {
    self.database = database
  }

  func summary(filter: TokMonQueryFilter, now: Date = Date()) throws -> TokMonSummary {
    if let rollupSummary = try summaryFromRollupSegments(filter: filter, now: now) {
      return rollupSummary
    }

    let scoped = scopedWhere(filter: filter)
    let sourceColumn = column("source", tablePrefix: scoped.tablePrefix)
    let modelColumn = column("model", tablePrefix: scoped.tablePrefix)
    let total = try requiredDatabase.queryRows("""
      SELECT COUNT(*) as total_requests,
             COALESCE(SUM(input_tokens), 0) as total_input,
             COALESCE(SUM(output_tokens), 0) as total_output,
             COALESCE(SUM(cache_creation), 0) as total_cache_creation,
             COALESCE(SUM(cache_read), 0) as total_cache_read,
             COALESCE(SUM(reasoning_tokens), 0) as total_reasoning,
             COALESCE(SUM(CASE WHEN cache_hit_supported != 0 THEN input_tokens ELSE 0 END), 0) as total_cache_hit_input,
             COALESCE(SUM(CASE WHEN cache_hit_supported != 0 THEN cache_read ELSE 0 END), 0) as total_cache_hit_cache_read
      FROM usage_records
      \(scoped.whereSQL)
    """, params: scoped.params) { row in
      TokMonTotals(
        totalRequests: row.int(0),
        totalInput: row.int(1),
        totalOutput: row.int(2),
        totalCacheCreation: row.int(3),
        totalCacheRead: row.int(4),
        totalReasoning: row.int(5),
        totalCacheHitInput: row.int(6),
        totalCacheHitCacheRead: row.int(7),
      )
    }.first ?? TokMonTotals(
      totalRequests: 0,
      totalInput: 0,
      totalOutput: 0,
      totalCacheCreation: 0,
      totalCacheRead: 0,
      totalReasoning: 0,
    )

    let bySource = try requiredDatabase.queryRows("""
      SELECT \(sourceColumn) as source,
             COUNT(*) as requests,
             COALESCE(SUM(input_tokens), 0) as input_tokens,
             COALESCE(SUM(output_tokens), 0) as output_tokens,
             COALESCE(SUM(cache_creation), 0) as cache_creation,
             COALESCE(SUM(cache_read), 0) as cache_read,
             COALESCE(SUM(CASE WHEN cache_hit_supported != 0 THEN input_tokens ELSE 0 END), 0) as cache_hit_input_tokens,
             COALESCE(SUM(CASE WHEN cache_hit_supported != 0 THEN cache_read ELSE 0 END), 0) as cache_hit_cache_read
      FROM usage_records
      \(scoped.whereSQL)
      GROUP BY \(sourceColumn)
    """, params: scoped.params) { row in
      TokMonSourceTotals(
        source: row.string(0),
        requests: row.int(1),
        inputTokens: row.int(2),
        outputTokens: row.int(3),
        cacheCreation: row.int(4),
        cacheRead: row.int(5),
        cacheHitInputTokens: row.int(6),
        cacheHitCacheRead: row.int(7),
      )
    }

    let byModel = try requiredDatabase.queryRows("""
      SELECT \(modelColumn) as model,
             \(sourceColumn) as source,
             COUNT(*) as requests,
             COALESCE(SUM(input_tokens), 0) as input_tokens,
             COALESCE(SUM(output_tokens), 0) as output_tokens,
             COALESCE(SUM(cache_creation), 0) as cache_creation,
             COALESCE(SUM(cache_read), 0) as cache_read,
             COALESCE(SUM(CASE WHEN cache_hit_supported != 0 THEN input_tokens ELSE 0 END), 0) as cache_hit_input_tokens,
             COALESCE(SUM(CASE WHEN cache_hit_supported != 0 THEN cache_read ELSE 0 END), 0) as cache_hit_cache_read
      FROM usage_records
      \(scoped.whereSQL)
      GROUP BY \(modelColumn), \(sourceColumn)
      ORDER BY requests DESC
    """, params: scoped.params) { row in
      TokMonModelTotals(
        model: row.string(0),
        source: row.string(1),
        requests: row.int(2),
        inputTokens: row.int(3),
        outputTokens: row.int(4),
        cacheCreation: row.int(5),
        cacheRead: row.int(6),
        cacheHitInputTokens: row.int(7),
        cacheHitCacheRead: row.int(8),
      )
    }

    return TokMonSummary(total: total, bySource: bySource, byModel: byModel)
  }

  func trend(filter: TokMonQueryFilter, interval: String, now: Date = Date()) throws -> [TokMonTrendBucket] {
    let scoped = scopedWhere(filter: filter, now: now, preferRollups: interval == "day")
    let format = interval == "day" ? "%Y-%m-%d" : "%Y-%m-%d %H:00"
    let bucketExpression = scoped.usesRollups ? "strftime('\(format)', period_start)" : "strftime('\(format)', created_at, 'localtime')"
    let requestsExpression = scoped.usesRollups ? "COALESCE(SUM(requests), 0)" : "COUNT(*)"
    let cacheHitInputExpression = scoped.usesRollups
      ? "COALESCE(SUM(cache_hit_input_tokens), 0)"
      : "COALESCE(SUM(CASE WHEN cache_hit_supported != 0 THEN input_tokens ELSE 0 END), 0)"
    let cacheHitReadExpression = scoped.usesRollups
      ? "COALESCE(SUM(cache_hit_cache_read), 0)"
      : "COALESCE(SUM(CASE WHEN cache_hit_supported != 0 THEN cache_read ELSE 0 END), 0)"
    let tableAlias = scoped.tablePrefix.map { " \($0)" } ?? ""
    return try requiredDatabase.queryRows("""
      SELECT \(bucketExpression) as bucket,
             COALESCE(SUM(input_tokens), 0) as input_tokens,
             COALESCE(SUM(output_tokens), 0) as output_tokens,
             COALESCE(SUM(cache_creation), 0) as cache_creation,
             COALESCE(SUM(cache_read), 0) as cache_read,
             \(requestsExpression) as requests,
             \(cacheHitInputExpression) as cache_hit_input_tokens,
             \(cacheHitReadExpression) as cache_hit_cache_read
      FROM \(scoped.tableName)\(tableAlias)
      \(scoped.whereSQL)
      GROUP BY bucket
      ORDER BY bucket
    """, params: scoped.params) { row in
      TokMonTrendBucket(
        bucket: row.string(0),
        inputTokens: row.int(1),
        outputTokens: row.int(2),
        cacheCreation: row.int(3),
        cacheRead: row.int(4),
        requests: row.int(5),
        cacheHitInputTokens: row.int(6),
        cacheHitCacheRead: row.int(7),
      )
    }
  }

  func heatmap(sources: [String], model: String?, endingAt: Date = Date(), days: Int = 112) throws -> [TokMonHeatmapDay] {
    let calendar = Calendar.current
    let endDay = calendar.startOfDay(for: endingAt)
    guard let startDay = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: endDay) else {
      return []
    }

    let sqlFormatter = DateFormatter()
    sqlFormatter.locale = Locale(identifier: "en_US_POSIX")
    sqlFormatter.timeZone = .current
    sqlFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

    var whereSQL = "WHERE grain = 'day' AND datetime(period_start) BETWEEN datetime(?) AND datetime(?)"
    var params: [TokMonSQLValue] = [
      .text(sqlFormatter.string(from: startDay)),
      .text(sqlFormatter.string(from: calendar.date(byAdding: DateComponents(day: 1, second: -1), to: endDay) ?? endDay)),
    ]
    appendOptionalFilters(sources: sources, model: model, tablePrefix: nil, whereSQL: &whereSQL, params: &params)

    let rows = try requiredDatabase.queryRows("""
      SELECT strftime('%Y-%m-%d', period_start) as day,
             COALESCE(SUM(requests), 0) as requests,
             COALESCE(SUM(input_tokens), 0) as input_tokens,
             COALESCE(SUM(output_tokens), 0) as output_tokens,
             COALESCE(SUM(cache_creation), 0) as cache_creation,
             COALESCE(SUM(cache_read), 0) as cache_read,
             COALESCE(SUM(cache_hit_input_tokens), 0) as cache_hit_input_tokens,
             COALESCE(SUM(cache_hit_cache_read), 0) as cache_hit_cache_read
      FROM tokmon_usage_rollups
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
        cacheHitInputTokens: row.int(6),
        cacheHitCacheRead: row.int(7),
      )
    }

    return fillHeatmapDays(rows: rows, startDay: startDay, endDay: endDay, calendar: calendar)
  }

  func models() throws -> [TokMonModelOption] {
    return try requiredDatabase.queryRows("""
      SELECT model, MAX(created_at) as last_used
      FROM usage_records
      WHERE model != '' AND model != 'unknown' AND model != '<synthetic>'
      GROUP BY model
      ORDER BY last_used DESC
    """) { row in
      TokMonModelOption(model: row.string(0), lastUsed: row.string(1))
    }
  }

  func records(filter: TokMonQueryFilter, page: Int, limit: Int) throws -> TokMonRecordsPage {
    let normalizedPage = max(0, page)
    let normalizedLimit = max(1, limit)
    let scoped = scopedWhere(filter: filter, tablePrefix: "u")
    let total = try requiredDatabase.queryInt("SELECT COUNT(*) FROM usage_records u \(scoped.whereSQL)", params: scoped.params)
    var rowParams = scoped.params
    rowParams.append(.int(normalizedLimit))
    rowParams.append(.int(normalizedPage * normalizedLimit))
    let rows = try requiredDatabase.queryRows("""
      SELECT u.source,
             u.session_id,
             COALESCE(metadata_exact.title, metadata_file.title) as session_title,
             COALESCE(metadata_exact.first_prompt, metadata_file.first_prompt) as first_prompt,
             COALESCE(metadata_exact.project_path, metadata_file.project_path) as project_path,
             COALESCE(metadata_exact.file_path, metadata_file.file_path) as metadata_file_path,
             u.model,
             u.input_tokens,
             u.output_tokens,
             u.cache_creation,
             u.cache_read,
             u.reasoning_tokens,
             datetime(u.created_at, 'localtime') as created_at
      FROM usage_records u
      LEFT JOIN tokmon_session_metadata metadata_exact
        ON metadata_exact.source = u.source
        AND metadata_exact.id = u.session_id
      LEFT JOIN tokmon_session_metadata metadata_file
        ON metadata_file.source = u.source
        AND metadata_exact.id IS NULL
        AND metadata_file.session_file_suffix = u.session_file_suffix
      \(scoped.whereSQL)
      ORDER BY u.created_at DESC
      LIMIT ? OFFSET ?
    """, params: rowParams) { row in
      let fallbackTitle = displaySessionTitle(row.string(2))
      let firstPrompt = displayPrompt(row.string(3))
      let projectName = sessionProjectName(
        projectPath: row.string(4).isEmpty ? nil : row.string(4),
        filePath: row.string(5).isEmpty ? nil : row.string(5),
      )
      return TokMonRecordRow(
        source: row.string(0),
        sessionId: row.string(1),
        sessionTitle: sessionTitle(
          fallbackTitle: fallbackTitle,
          firstPrompt: firstPrompt,
          projectName: projectName,
        ),
        model: row.string(6),
        inputTokens: row.int(7),
        outputTokens: row.int(8),
        cacheCreation: row.int(9),
        cacheRead: row.int(10),
        reasoningTokens: row.int(11),
        createdAt: row.string(12),
      )
    }

    return TokMonRecordsPage(total: total, page: normalizedPage, limit: normalizedLimit, rows: rows)
  }

  func recordsForSession(
    filter: TokMonQueryFilter,
    source: String,
    sessionId: String,
    limit: Int,
  ) throws -> [TokMonRecordRow] {
    let scoped = scopedWhere(filter: filter, tablePrefix: "u")
    var params = scoped.params
    params.append(.text(source))
    params.append(.text(sessionId))
    params.append(.int(max(1, limit)))

    return try requiredDatabase.queryRows("""
      SELECT u.source,
             u.session_id,
             COALESCE(metadata_exact.title, metadata_file.title) as session_title,
             COALESCE(metadata_exact.first_prompt, metadata_file.first_prompt) as first_prompt,
             COALESCE(metadata_exact.project_path, metadata_file.project_path) as project_path,
             COALESCE(metadata_exact.file_path, metadata_file.file_path) as metadata_file_path,
             u.model,
             u.input_tokens,
             u.output_tokens,
             u.cache_creation,
             u.cache_read,
             u.reasoning_tokens,
             datetime(u.created_at, 'localtime') as created_at
      FROM usage_records u
      LEFT JOIN tokmon_session_metadata metadata_exact
        ON metadata_exact.source = u.source
        AND metadata_exact.id = u.session_id
      LEFT JOIN tokmon_session_metadata metadata_file
        ON metadata_file.source = u.source
        AND metadata_exact.id IS NULL
        AND metadata_file.session_file_suffix = u.session_file_suffix
      \(scoped.whereSQL)
      AND u.source = ?
      AND u.session_id = ?
      ORDER BY u.created_at DESC
      LIMIT ?
    """, params: params) { row in
      let fallbackTitle = displaySessionTitle(row.string(2))
      let firstPrompt = displayPrompt(row.string(3))
      let projectName = sessionProjectName(
        projectPath: row.string(4).isEmpty ? nil : row.string(4),
        filePath: row.string(5).isEmpty ? nil : row.string(5),
      )
      return TokMonRecordRow(
        source: row.string(0),
        sessionId: row.string(1),
        sessionTitle: sessionTitle(
          fallbackTitle: fallbackTitle,
          firstPrompt: firstPrompt,
          projectName: projectName,
        ),
        model: row.string(6),
        inputTokens: row.int(7),
        outputTokens: row.int(8),
        cacheCreation: row.int(9),
        cacheRead: row.int(10),
        reasoningTokens: row.int(11),
        createdAt: row.string(12),
      )
    }
  }

  func sessions(limit: Int) throws -> [TokMonUsageSession] {
    try sessions(filter: nil, limit: limit)
  }

  func sessions(filter: TokMonQueryFilter?, limit: Int) throws -> [TokMonUsageSession] {
    let scoped = filter.map { scopedWhere(filter: $0) }
    let whereSQL = scoped?.whereSQL ?? ""
    let params = scoped?.params ?? []
    var rowParams = params
    rowParams.append(.int(max(1, limit)))

    return try requiredDatabase.queryRows("""
      SELECT grouped.session_id,
             grouped.source,
             COALESCE(metadata_exact.title, metadata_file.title) as title,
             COALESCE(metadata_exact.first_prompt, metadata_file.first_prompt) as first_prompt,
             COALESCE(metadata_exact.project_path, metadata_file.project_path) as project_path,
             COALESCE(metadata_exact.file_path, metadata_file.file_path) as metadata_file_path,
             grouped.model,
             grouped.requests,
             grouped.input_tokens,
             grouped.output_tokens,
             grouped.cache_creation,
             grouped.cache_read,
             grouped.first_at,
             grouped.last_at
      FROM (
        SELECT session_id,
               source,
               CASE WHEN COUNT(DISTINCT model) = 1 THEN MIN(model) ELSE 'Mixed' END as model,
               COUNT(*) as requests,
               COALESCE(SUM(input_tokens), 0) as input_tokens,
               COALESCE(SUM(output_tokens), 0) as output_tokens,
               COALESCE(SUM(cache_creation), 0) as cache_creation,
               COALESCE(SUM(cache_read), 0) as cache_read,
               MIN(created_at) as first_at,
               MAX(created_at) as last_at
        FROM usage_records
        \(whereSQL)
        GROUP BY session_id, source
      ) grouped
      LEFT JOIN tokmon_session_metadata metadata_exact
        ON metadata_exact.source = grouped.source
        AND metadata_exact.id = grouped.session_id
      LEFT JOIN tokmon_session_metadata metadata_file
        ON metadata_file.source = grouped.source
        AND metadata_exact.id IS NULL
        AND substr(metadata_file.file_path, -length(grouped.session_id || '.jsonl')) = grouped.session_id || '.jsonl'
      ORDER BY grouped.last_at DESC
      LIMIT ?
    """, params: rowParams) { row in
      let fallbackTitle = displaySessionTitle(row.string(2))
      let firstPrompt = displayPrompt(row.string(3))
      let projectName = sessionProjectName(
        projectPath: row.string(4).isEmpty ? nil : row.string(4),
        filePath: row.string(5).isEmpty ? nil : row.string(5),
      )
      return TokMonUsageSession(
        sessionId: row.string(0),
        source: row.string(1),
        title: sessionTitle(
          fallbackTitle: fallbackTitle,
          firstPrompt: firstPrompt,
          projectName: projectName,
        ),
        projectName: projectName,
        firstPrompt: firstPrompt,
        model: row.string(6),
        requests: row.int(7),
        inputTokens: row.int(8),
        outputTokens: row.int(9),
        cacheCreation: row.int(10),
        cacheRead: row.int(11),
        firstAt: row.string(12),
        lastAt: row.string(13),
      )
    }
  }

  private var requiredDatabase: TokMonDatabase {
    get throws {
      guard let database else {
        throw TokMonQueryStoreError.missingDatabase
      }
      return database
    }
  }

  private func summaryFromRollupSegments(filter: TokMonQueryFilter, now: Date) throws -> TokMonSummary? {
    if isAllRange(filter) {
      return try summaryFromYearRollups(filter: filter)
    }

    guard let segments = rollupSegments(filter: filter, now: now), !segments.isEmpty else {
      return nil
    }
    let segmentsEnd = segments
      .compactMap { parseDate($0.end) }
      .max()
    let rawTail = rawUsageTailSegment(filter: filter, after: segmentsEnd)

    var unionQueries = segments.map { segment in
      """
      SELECT source, model, requests, input_tokens, output_tokens, cache_creation, cache_read, reasoning_tokens, cache_hit_input_tokens, cache_hit_cache_read
      FROM tokmon_usage_rollups
      WHERE grain = '\(segment.grain)'
        AND datetime(period_start) BETWEEN datetime(?) AND datetime(?)
      """
    }
    if rawTail != nil {
      unionQueries.append("""
        SELECT source,
               model,
               COUNT(*) as requests,
               COALESCE(SUM(input_tokens), 0) as input_tokens,
               COALESCE(SUM(output_tokens), 0) as output_tokens,
               COALESCE(SUM(cache_creation), 0) as cache_creation,
               COALESCE(SUM(cache_read), 0) as cache_read,
               COALESCE(SUM(reasoning_tokens), 0) as reasoning_tokens,
               COALESCE(SUM(CASE WHEN cache_hit_supported != 0 THEN input_tokens ELSE 0 END), 0) as cache_hit_input_tokens,
               COALESCE(SUM(CASE WHEN cache_hit_supported != 0 THEN cache_read ELSE 0 END), 0) as cache_hit_cache_read
        FROM usage_records
        WHERE datetime(created_at, 'localtime') BETWEEN datetime(?) AND datetime(?)
        GROUP BY source, model
        """)
    }
    let joinedUnionSQL = unionQueries.joined(separator: "\nUNION ALL\n")
    var params = segments.flatMap { segment in
      [TokMonSQLValue.text(segment.start), TokMonSQLValue.text(segment.end)]
    }
    if let rawTail {
      params.append(.text(rawTail.start))
      params.append(.text(rawTail.end))
    }
    let filteredSQL = appendOuterFilters(
      to: """
      SELECT source, model, requests, input_tokens, output_tokens, cache_creation, cache_read, reasoning_tokens, cache_hit_input_tokens, cache_hit_cache_read
      FROM (\(joinedUnionSQL)) rollup_segments
      """,
      filter: filter,
    )
    let filteredParams = appendOuterFilterParams(to: params, filter: filter)

    return try summaryFromAggregatedRowsSQL(filteredSQL, params: filteredParams)
  }

  private func summaryFromYearRollups(filter: TokMonQueryFilter) throws -> TokMonSummary {
    let baseSQL = """
      SELECT source, model, requests, input_tokens, output_tokens, cache_creation, cache_read, reasoning_tokens, cache_hit_input_tokens, cache_hit_cache_read
      FROM tokmon_usage_rollups
      WHERE grain = 'year'
      """
    let filteredSQL = appendOuterFilters(
      to: "SELECT * FROM (\(baseSQL)) rollup_years",
      filter: filter,
    )
    let filteredParams = appendOuterFilterParams(to: [], filter: filter)

    return try summaryFromAggregatedRowsSQL(filteredSQL, params: filteredParams)
  }

  private func summaryFromAggregatedRowsSQL(_ filteredSQL: String, params filteredParams: [TokMonSQLValue]) throws -> TokMonSummary {
    let rows = try requiredDatabase.queryRows("""
      WITH filtered AS (\(filteredSQL))
      SELECT 'total' as agg_type,
             NULL as source,
             NULL as model,
             COALESCE(SUM(requests), 0) as requests,
             COALESCE(SUM(input_tokens), 0) as input_tokens,
             COALESCE(SUM(output_tokens), 0) as output_tokens,
             COALESCE(SUM(cache_creation), 0) as cache_creation,
             COALESCE(SUM(cache_read), 0) as cache_read,
             COALESCE(SUM(reasoning_tokens), 0) as reasoning_tokens,
             COALESCE(SUM(cache_hit_input_tokens), 0) as cache_hit_input_tokens,
             COALESCE(SUM(cache_hit_cache_read), 0) as cache_hit_cache_read
      FROM filtered
      UNION ALL
      SELECT 'source',
             source,
             NULL,
             COALESCE(SUM(requests), 0),
             COALESCE(SUM(input_tokens), 0),
             COALESCE(SUM(output_tokens), 0),
             COALESCE(SUM(cache_creation), 0),
             COALESCE(SUM(cache_read), 0),
             COALESCE(SUM(reasoning_tokens), 0),
             COALESCE(SUM(cache_hit_input_tokens), 0),
             COALESCE(SUM(cache_hit_cache_read), 0)
      FROM filtered
      GROUP BY source
      UNION ALL
      SELECT 'model',
             source,
             model,
             COALESCE(SUM(requests), 0),
             COALESCE(SUM(input_tokens), 0),
             COALESCE(SUM(output_tokens), 0),
             COALESCE(SUM(cache_creation), 0),
             COALESCE(SUM(cache_read), 0),
             COALESCE(SUM(reasoning_tokens), 0),
             COALESCE(SUM(cache_hit_input_tokens), 0),
             COALESCE(SUM(cache_hit_cache_read), 0)
      FROM filtered
      GROUP BY source, model
    """, params: filteredParams) { row -> (aggType: String, source: String, model: String, requests: Int, inputTokens: Int, outputTokens: Int, cacheCreation: Int, cacheRead: Int, reasoningTokens: Int, cacheHitInputTokens: Int, cacheHitCacheRead: Int) in
      (
        aggType: row.string(0),
        source: row.string(1),
        model: row.string(2),
        requests: row.int(3),
        inputTokens: row.int(4),
        outputTokens: row.int(5),
        cacheCreation: row.int(6),
        cacheRead: row.int(7),
        reasoningTokens: row.int(8),
        cacheHitInputTokens: row.int(9),
        cacheHitCacheRead: row.int(10)
      )
    }

    var total = TokMonTotals(
      totalRequests: 0,
      totalInput: 0,
      totalOutput: 0,
      totalCacheCreation: 0,
      totalCacheRead: 0,
      totalReasoning: 0,
    )
    var bySource: [TokMonSourceTotals] = []
    var byModel: [TokMonModelTotals] = []

    for row in rows {
      switch row.aggType {
      case "total":
        total = TokMonTotals(
          totalRequests: row.requests,
          totalInput: row.inputTokens,
          totalOutput: row.outputTokens,
          totalCacheCreation: row.cacheCreation,
          totalCacheRead: row.cacheRead,
          totalReasoning: row.reasoningTokens,
          totalCacheHitInput: row.cacheHitInputTokens,
          totalCacheHitCacheRead: row.cacheHitCacheRead,
        )
      case "source":
        bySource.append(TokMonSourceTotals(
          source: row.source,
          requests: row.requests,
          inputTokens: row.inputTokens,
          outputTokens: row.outputTokens,
          cacheCreation: row.cacheCreation,
          cacheRead: row.cacheRead,
          cacheHitInputTokens: row.cacheHitInputTokens,
          cacheHitCacheRead: row.cacheHitCacheRead,
        ))
      case "model":
        byModel.append(TokMonModelTotals(
          model: row.model,
          source: row.source,
          requests: row.requests,
          inputTokens: row.inputTokens,
          outputTokens: row.outputTokens,
          cacheCreation: row.cacheCreation,
          cacheRead: row.cacheRead,
          cacheHitInputTokens: row.cacheHitInputTokens,
          cacheHitCacheRead: row.cacheHitCacheRead,
        ))
      default:
        break
      }
    }

    byModel.sort { $0.requests > $1.requests }

    return TokMonSummary(total: total, bySource: bySource, byModel: byModel)
  }

  private func isAllRange(_ filter: TokMonQueryFilter) -> Bool {
    filter.hasTimeRange
      && filter.from <= "0001-01-01 00:00:00"
      && filter.to >= "9999-12-31 23:59:59"
  }

  private func rawUsageTailSegment(filter: TokMonQueryFilter, after segmentsEnd: Date?) -> (start: String, end: String)? {
    guard let segmentsEnd, let filterEnd = parseDate(filter.to) else {
      return nil
    }
    guard let start = Calendar.current.date(byAdding: .second, value: 1, to: segmentsEnd), start <= filterEnd else {
      return nil
    }
    return (formatDate(start), filter.to)
  }

  private struct RollupSegment {
    let grain: String
    let start: String
    let end: String
  }

  private func rollupSegments(filter: TokMonQueryFilter, now: Date) -> [RollupSegment]? {
    guard filter.hasTimeRange else {
      return nil
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    guard let from = formatter.date(from: filter.from), formatter.date(from: filter.to) != nil else {
      return nil
    }

    let calendar = Calendar.current
    let startOfToday = calendar.startOfDay(for: now)
    let rollupEnd = min(parseDate(filter.to) ?? now, startOfToday)
    guard from < startOfToday, from == calendar.startOfDay(for: from) else {
      return nil
    }

    var cursor = from
    var segments: [RollupSegment] = []

    while let nextYear = calendar.date(byAdding: .year, value: 1, to: cursor),
          nextYear <= rollupEnd,
          isStartOfYear(cursor, calendar: calendar) {
      segments.append(.init(grain: "year", start: formatDate(cursor), end: formatDate(calendar.date(byAdding: .second, value: -1, to: nextYear) ?? cursor)))
      cursor = nextYear
    }

    while let nextMonth = calendar.date(byAdding: .month, value: 1, to: cursor),
          nextMonth <= rollupEnd,
          isStartOfMonth(cursor, calendar: calendar) {
      segments.append(.init(grain: "month", start: formatDate(cursor), end: formatDate(calendar.date(byAdding: .second, value: -1, to: nextMonth) ?? cursor)))
      cursor = nextMonth
    }

    while let nextWeek = calendar.date(byAdding: .day, value: 7, to: cursor),
          nextWeek <= rollupEnd,
          isStartOfWeek(cursor, calendar: calendar) {
      segments.append(.init(grain: "week", start: formatDate(cursor), end: formatDate(calendar.date(byAdding: .second, value: -1, to: nextWeek) ?? cursor)))
      cursor = nextWeek
    }

    while let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor),
          nextDay <= rollupEnd {
      segments.append(.init(grain: "day", start: formatDate(cursor), end: formatDate(calendar.date(byAdding: .second, value: -1, to: nextDay) ?? cursor)))
      cursor = nextDay
    }

    guard !segments.isEmpty else {
      return nil
    }
    return segments
  }

  private func appendOuterFilters(to sql: String, filter: TokMonQueryFilter) -> String {
    var clauses: [String] = []
    if !filter.sources.isEmpty {
      let placeholders = Array(repeating: "?", count: filter.sources.count).joined(separator: ", ")
      clauses.append("source IN (\(placeholders))")
    }
    if let model = filter.model, !model.isEmpty {
      clauses.append("model = ?")
    }
    guard !clauses.isEmpty else {
      return sql
    }
    return "\(sql) WHERE \(clauses.joined(separator: " AND "))"
  }

  private func appendOuterFilterParams(to params: [TokMonSQLValue], filter: TokMonQueryFilter) -> [TokMonSQLValue] {
    var result = params
    if !filter.sources.isEmpty {
      result.append(contentsOf: filter.sources.map { .text($0) })
    }
    if let model = filter.model, !model.isEmpty {
      result.append(.text(model))
    }
    return result
  }

  private func isStartOfYear(_ date: Date, calendar: Calendar) -> Bool {
    calendar.component(.month, from: date) == 1 && calendar.component(.day, from: date) == 1 && isStartOfDay(date, calendar: calendar)
  }

  private func isStartOfMonth(_ date: Date, calendar: Calendar) -> Bool {
    calendar.component(.day, from: date) == 1 && isStartOfDay(date, calendar: calendar)
  }

  private func isStartOfWeek(_ date: Date, calendar: Calendar) -> Bool {
    (calendar.component(.weekday, from: date) + 5) % 7 == 0 && isStartOfDay(date, calendar: calendar)
  }

  private func isStartOfDay(_ date: Date, calendar: Calendar) -> Bool {
    calendar.component(.hour, from: date) == 0
      && calendar.component(.minute, from: date) == 0
      && calendar.component(.second, from: date) == 0
  }

  private func scopedWhere(
    filter: TokMonQueryFilter,
    tablePrefix: String? = nil,
    now: Date = Date(),
    preferRollups: Bool = false,
  ) -> (whereSQL: String, params: [TokMonSQLValue], tableName: String, tablePrefix: String?, usesRollups: Bool) {
    let usesRollups = preferRollups && filter.hasTimeRange && canUseDayRollups(filter: filter, now: now)
    let resolvedTableName = usesRollups ? "tokmon_usage_rollups" : "usage_records"
    let resolvedTablePrefix = tablePrefix
    let createdColumn = column(usesRollups ? "period_start" : "created_at", tablePrefix: resolvedTablePrefix)
    var clauses: [String] = []
    var params: [TokMonSQLValue] = []
    if usesRollups {
      clauses.append("\(column("grain", tablePrefix: resolvedTablePrefix)) = 'day'")
    }
    if filter.hasTimeRange {
      if usesRollups {
        clauses.append("datetime(\(createdColumn)) BETWEEN datetime(?) AND datetime(?)")
      } else {
        clauses.append("datetime(\(createdColumn), 'localtime') BETWEEN datetime(?) AND datetime(?)")
      }
      params.append(.text(filter.from))
      params.append(.text(filter.to))
    }
    var whereSQL = clauses.isEmpty ? "WHERE 1 = 1" : "WHERE \(clauses.joined(separator: " AND "))"
    appendOptionalFilters(sources: filter.sources, model: filter.model, tablePrefix: resolvedTablePrefix, whereSQL: &whereSQL, params: &params)
    return (whereSQL, params, resolvedTableName, resolvedTablePrefix, usesRollups)
  }

  private func canUseDayRollups(filter: TokMonQueryFilter, now: Date) -> Bool {
    guard filter.hasTimeRange else {
      return false
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    guard let from = formatter.date(from: filter.from), let to = formatter.date(from: filter.to) else {
      return false
    }
    let calendar = Calendar.current
    let startOfNow = calendar.startOfDay(for: now)
    guard from < startOfNow else {
      return false
    }
    return (calendar.dateComponents([.second], from: from).second ?? 0) == 0
      && (calendar.dateComponents([.minute], from: from).minute ?? 0) == 0
      && (calendar.dateComponents([.hour], from: from).hour ?? 0) == 0
      && to >= now
  }

  private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.string(from: date)
  }

  private func parseDate(_ value: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.date(from: value)
  }

  private func appendOptionalFilters(
    sources: [String],
    model: String?,
    tablePrefix: String?,
    whereSQL: inout String,
    params: inout [TokMonSQLValue],
  ) {
    if !sources.isEmpty {
      let placeholders = Array(repeating: "?", count: sources.count).joined(separator: ", ")
      whereSQL += " AND \(column("source", tablePrefix: tablePrefix)) IN (\(placeholders))"
      params.append(contentsOf: sources.map { .text($0) })
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

  private func sessionTitle(
    fallbackTitle: String?,
    firstPrompt: String?,
    projectName: String?,
  ) -> String? {
    guard let firstPrompt, !firstPrompt.isEmpty else {
      return fallbackTitle
    }

    if let fallbackTitle,
       let split = splitSessionTitle(fallbackTitle),
       split.firstPrompt == firstPrompt,
       !isIgnoredSessionTitlePrefix(split.prefix) {
      return "\(split.prefix) - \(firstPrompt)"
    }

    let projectName = projectName ?? ""
    guard !projectName.isEmpty else {
      return firstPrompt
    }
    return "\(projectName) - \(firstPrompt)"
  }

  private func displaySessionTitle(_ value: String) -> String? {
    guard let title = displayPrompt(value) else {
      return nil
    }
    return title.contains("<environment_context>") ? nil : title
  }

  private func displayPrompt(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return nil
    }
    return trimmed.hasPrefix("<environment_context>") ? nil : trimmed
  }

  private func sessionProjectName(projectPath: String?, filePath: String?) -> String? {
    let projectName = projectPath.map { URL(fileURLWithPath: $0).lastPathComponent }
      ?? filePath.map(projectNameFromFilePath)
    guard let projectName, !projectName.isEmpty else {
      return nil
    }
    return projectName
  }

  private func splitSessionTitle(_ title: String) -> (prefix: String, firstPrompt: String)? {
    let separator = " - "
    guard let range = title.range(of: separator) else {
      return nil
    }
    let prefix = String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    let firstPrompt = String(title[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prefix.isEmpty, !firstPrompt.isEmpty else {
      return nil
    }
    return (prefix, firstPrompt)
  }

  private func projectNameFromFilePath(_ filePath: String) -> String {
    let fileURL = URL(fileURLWithPath: filePath)
    let parent = fileURL.deletingLastPathComponent()
    let components = parent.pathComponents
    if let index = components.lastIndex(of: "sessions"), index > 0 {
      return components[index - 1]
    }
    return parent.lastPathComponent
  }

  private func isIgnoredSessionTitlePrefix(_ prefix: String) -> Bool {
    let normalized = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized == ".codex"
  }

  private func fillHeatmapDays(
    rows: [TokMonHeatmapDay],
    startDay: Date,
    endDay: Date,
    calendar: Calendar,
  ) -> [TokMonHeatmapDay] {
    let lookup = Dictionary(uniqueKeysWithValues: rows.map { ($0.day, $0) })
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd"

    var result: [TokMonHeatmapDay] = []
    var day = startDay
    while day <= endDay {
      let key = formatter.string(from: day)
      result.append(lookup[key] ?? TokMonHeatmapDay(day: key, requests: 0, inputTokens: 0, outputTokens: 0, cacheCreation: 0, cacheRead: 0))
      guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
      day = next
    }
    return result
  }
}

private enum TokMonQueryStoreError: LocalizedError {
  case missingDatabase

  var errorDescription: String? {
    switch self {
    case .missingDatabase:
      "TokMon query store requires a database before queries can run."
    }
  }
}
