import Foundation

final class TokMonQueryStore {
  private let database: TokMonDatabase?

  init() {
    database = nil
  }

  init(database: TokMonDatabase) {
    self.database = database
  }

  func summary(filter: TokMonQueryFilter) throws -> TokMonSummary {
    let scoped = scopedWhere(filter: filter)
    let total = try requiredDatabase.queryRows("""
      SELECT COUNT(*) as total_requests,
             COALESCE(SUM(input_tokens), 0) as total_input,
             COALESCE(SUM(output_tokens), 0) as total_output,
             COALESCE(SUM(cache_creation), 0) as total_cache_creation,
             COALESCE(SUM(cache_read), 0) as total_cache_read,
             COALESCE(SUM(reasoning_tokens), 0) as total_reasoning
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
      SELECT source,
             COUNT(*) as requests,
             COALESCE(SUM(input_tokens), 0) as input_tokens,
             COALESCE(SUM(output_tokens), 0) as output_tokens,
             COALESCE(SUM(cache_creation), 0) as cache_creation,
             COALESCE(SUM(cache_read), 0) as cache_read
      FROM usage_records
      \(scoped.whereSQL)
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

    let byModel = try requiredDatabase.queryRows("""
      SELECT model,
             source,
             COUNT(*) as requests,
             COALESCE(SUM(input_tokens), 0) as input_tokens,
             COALESCE(SUM(output_tokens), 0) as output_tokens,
             COALESCE(SUM(cache_creation), 0) as cache_creation,
             COALESCE(SUM(cache_read), 0) as cache_read
      FROM usage_records
      \(scoped.whereSQL)
      GROUP BY model, source
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
      )
    }

    return TokMonSummary(total: total, bySource: bySource, byModel: byModel)
  }

  func trend(filter: TokMonQueryFilter, interval: String) throws -> [TokMonTrendBucket] {
    let scoped = scopedWhere(filter: filter)
    let format = interval == "day" ? "%Y-%m-%d" : "%Y-%m-%d %H:00"
    return try requiredDatabase.queryRows("""
      SELECT strftime('\(format)', created_at, 'localtime') as bucket,
             COALESCE(SUM(input_tokens), 0) as input_tokens,
             COALESCE(SUM(output_tokens), 0) as output_tokens,
             COALESCE(SUM(cache_creation), 0) as cache_creation,
             COALESCE(SUM(cache_read), 0) as cache_read,
             COUNT(*) as requests
      FROM usage_records
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
      )
    }
  }

  func heatmap(source: String?, model: String?) throws -> [TokMonHeatmapDay] {
    var whereSQL = "WHERE created_at >= datetime('now', ?)"
    var params: [TokMonSQLValue] = [.text("-365 days")]
    appendOptionalFilters(source: source, model: model, tablePrefix: nil, whereSQL: &whereSQL, params: &params)

    return try requiredDatabase.queryRows("""
      SELECT strftime('%Y-%m-%d', created_at, 'localtime') as day,
             COUNT(*) as requests,
             COALESCE(SUM(input_tokens), 0) as input_tokens,
             COALESCE(SUM(output_tokens), 0) as output_tokens,
             COALESCE(SUM(cache_creation), 0) as cache_creation,
             COALESCE(SUM(cache_read), 0) as cache_read
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
  }

  func models() throws -> [TokMonModelOption] {
    try requiredDatabase.queryRows("""
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
             u.model,
             u.input_tokens,
             u.output_tokens,
             u.cache_creation,
             u.cache_read,
             u.reasoning_tokens,
             datetime(u.created_at, 'localtime') as created_at
      FROM usage_records u
      \(scoped.whereSQL)
      ORDER BY u.created_at DESC
      LIMIT ? OFFSET ?
    """, params: rowParams) { row in
      TokMonRecordRow(
        source: row.string(0),
        sessionId: row.string(1),
        model: row.string(2),
        inputTokens: row.int(3),
        outputTokens: row.int(4),
        cacheCreation: row.int(5),
        cacheRead: row.int(6),
        reasoningTokens: row.int(7),
        createdAt: row.string(8),
      )
    }

    return TokMonRecordsPage(total: total, page: normalizedPage, limit: normalizedLimit, rows: rows)
  }

  func sessions(limit: Int) throws -> [TokMonUsageSession] {
    try requiredDatabase.queryRows("""
      SELECT session_id,
             source,
             model,
             COUNT(*) as requests,
             COALESCE(SUM(input_tokens), 0) as input_tokens,
             COALESCE(SUM(output_tokens), 0) as output_tokens,
             MIN(created_at) as first_at,
             MAX(created_at) as last_at
      FROM usage_records
      GROUP BY session_id, source
      ORDER BY last_at DESC
      LIMIT ?
    """, params: [.int(max(1, limit))]) { row in
      TokMonUsageSession(
        sessionId: row.string(0),
        source: row.string(1),
        model: row.string(2),
        requests: row.int(3),
        inputTokens: row.int(4),
        outputTokens: row.int(5),
        firstAt: row.string(6),
        lastAt: row.string(7),
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

  private func scopedWhere(filter: TokMonQueryFilter, tablePrefix: String? = nil) -> (whereSQL: String, params: [TokMonSQLValue]) {
    let createdColumn = column("created_at", tablePrefix: tablePrefix)
    var whereSQL = "WHERE datetime(\(createdColumn), 'localtime') BETWEEN datetime(?) AND datetime(?)"
    var params: [TokMonSQLValue] = [.text(filter.from), .text(filter.to)]
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
