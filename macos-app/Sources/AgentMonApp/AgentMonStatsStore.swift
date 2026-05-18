import Foundation

struct AgentMonStatsSnapshot: Sendable {
  var scanStatus: AgentMonScanStatus?
  var summary: TokMonSummary?
  var trendBuckets: [TokMonTrendBucket] = []
  var heatmapDays: [TokMonHeatmapDay] = []
  var recordsPage: TokMonRecordsPage?
  var usageSessions: [TokMonUsageSession] = []
  var selectedUsageSession: TokMonUsageSessionSelection?
  var selectedSessionRecords: [TokMonRecordRow] = []
  var dashboardState: TokMonDashboardState?
  var updatedAt: Date?

  static let empty = AgentMonStatsSnapshot()
}

struct TokMonUsageSessionSelection: Equatable, Sendable {
  let source: String
  let sessionId: String

  var id: String { "\(source):\(sessionId)" }
}

struct AgentMonScanStatus: Decodable, Equatable, Sendable {
  let running: Bool
  let phase: String
  let current: Int
  let total: Int
  let processed: Int
  let startedAt: String?
  let finishedAt: String?
  let error: String?
}

private struct ActivityRequest: Encodable {
  let name: String
  let ttlMs: Int
}

@MainActor
final class AgentMonStatsStore: ObservableObject {
  @Published private(set) var snapshot = AgentMonStatsSnapshot.empty
  @Published private(set) var isRefreshing = false
  @Published private(set) var errorMessage: String?

  private let nativeWorker: TokMonNativeStatsWorker?
  private var appURL: URL?
  private var timerTask: Task<Void, Never>?
  private var recordsLimit = 20
  private var usageSessionsLimit = 50
  private var selectedUsageSession: TokMonUsageSessionSelection?
  private let activityName = "status-popover"
  private let activityTtlMilliseconds = 10_000

  init(engine: TokMonEngine? = nil, nowProvider: @escaping @Sendable () -> Date = Date.init) {
    nativeWorker = engine.map { TokMonNativeStatsWorker(engine: $0, nowProvider: nowProvider) }
  }

  var usesNativeEngine: Bool {
    nativeWorker != nil
  }

  var canLoadMoreRecords: Bool {
    guard let recordsPage = snapshot.recordsPage else { return false }
    return usesNativeEngine && recordsPage.rows.count < recordsPage.total
  }

  var canLoadMoreUsageSessions: Bool {
    usesNativeEngine && !snapshot.usageSessions.isEmpty && snapshot.usageSessions.count >= usageSessionsLimit
  }

  func configure(appURL: URL) {
    self.appURL = appURL
  }

  func startObserving(appURL: URL? = nil) {
    if let appURL {
      self.appURL = appURL
    }
    if timerTask == nil {
      timerTask = Task { [weak self] in
        while !Task.isCancelled {
          guard let self else { return }
          try? await Task.sleep(nanoseconds: self.refreshDelay)
          await self.refresh()
        }
      }
    }
    requestRefresh()
  }

  func stopObserving() {
    timerTask?.cancel()
    timerTask = nil
    releaseActivity()
  }

  func refresh() async {
    isRefreshing = true
    defer { isRefreshing = false }

    do {
      if let nativeWorker {
        snapshot = try await nativeWorker.refresh(
          recordsLimit: recordsLimit,
          sessionsLimit: usageSessionsLimit,
          selectedSession: selectedUsageSession,
        )
      } else if let appURL {
        try await refreshHTTP(appURL: appURL)
      }
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
      snapshot = AgentMonStatsSnapshot(
        scanStatus: snapshot.scanStatus,
        summary: snapshot.summary,
        trendBuckets: snapshot.trendBuckets,
        heatmapDays: snapshot.heatmapDays,
        recordsPage: snapshot.recordsPage,
        usageSessions: snapshot.usageSessions,
        selectedUsageSession: snapshot.selectedUsageSession,
        selectedSessionRecords: snapshot.selectedSessionRecords,
        dashboardState: snapshot.dashboardState,
        updatedAt: snapshot.updatedAt,
      )
    }
  }

  func loadMoreRecords() {
    guard usesNativeEngine else { return }
    recordsLimit += 20
    requestRefresh()
  }

  func loadMoreUsageSessions() {
    guard usesNativeEngine else { return }
    usageSessionsLimit += 50
    requestRefresh()
  }

  func selectUsageSession(source: String, sessionId: String) {
    guard usesNativeEngine else { return }
    selectedUsageSession = TokMonUsageSessionSelection(source: source, sessionId: sessionId)
    requestRefresh()
  }

  func clearSelectedUsageSession() {
    guard usesNativeEngine else { return }
    selectedUsageSession = nil
    snapshot.selectedUsageSession = nil
    snapshot.selectedSessionRecords = []
  }

  private var refreshDelay: UInt64 {
    let milliseconds = max(snapshot.dashboardState?.refreshRate ?? 3000, 1000)
    return UInt64(milliseconds) * 1_000_000
  }

  private func refreshHTTP(appURL: URL) async throws {
    try await renewActivity(appURL: appURL)
    _ = try? await triggerTokMonScan(appURL: appURL)

    async let scanStatus = fetchScanStatus(appURL: appURL)
    async let dashboardState = fetchDashboardState(appURL: appURL)

    let resolvedScanStatus = try await scanStatus
    let resolvedDashboardState = try await dashboardState
    async let summary = fetchTokMonSummary(appURL: appURL, dashboardState: resolvedDashboardState)
    async let trend = fetchTokMonTrend(appURL: appURL, dashboardState: resolvedDashboardState)
    let resolvedSummary = try await summary
    let resolvedTrend = try await trend

    snapshot = AgentMonStatsSnapshot(
      scanStatus: resolvedScanStatus,
      summary: resolvedSummary,
      trendBuckets: TokMonStatsSnapshotBuilder.fillTrendBuckets(resolvedTrend, dashboardState: resolvedDashboardState),
      heatmapDays: snapshot.heatmapDays,
      recordsPage: snapshot.recordsPage,
      usageSessions: snapshot.usageSessions,
      selectedUsageSession: snapshot.selectedUsageSession,
      selectedSessionRecords: snapshot.selectedSessionRecords,
      dashboardState: resolvedDashboardState,
      updatedAt: Date(),
    )
  }

  private func requestRefresh() {
    Task { [weak self] in
      await self?.refresh()
    }
  }

  private func releaseActivity() {
    guard nativeWorker == nil, let appURL else { return }
    Task.detached { [activityName] in
      var request = URLRequest(url: appURL.appendingPathComponent("api/activity/\(activityName)"))
      request.httpMethod = "DELETE"
      request.timeoutInterval = 1.5
      _ = try? await URLSession.shared.data(for: request)
    }
  }

  private nonisolated func renewActivity(appURL: URL) async throws {
    var request = URLRequest(url: appURL.appendingPathComponent("api/activity"))
    request.httpMethod = "POST"
    request.timeoutInterval = 1.5
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(ActivityRequest(name: activityName, ttlMs: activityTtlMilliseconds))

    let (_, response) = try await URLSession.shared.data(for: request)
    try validate(response: response, url: request.url ?? appURL)
  }

  private nonisolated func triggerTokMonScan(appURL: URL) async throws {
    let url = appURL.appendingPathComponent("api/tokmon/scan")
    let (data, response) = try await URLSession.shared.data(from: url)
    try validate(response: response, url: url)
    _ = data
  }

  private nonisolated func fetchScanStatus(appURL: URL) async throws -> AgentMonScanStatus {
    let url = appURL.appendingPathComponent("api/scan-status")
    let (data, response) = try await URLSession.shared.data(from: url)
    try validate(response: response, url: url)
    return try JSONDecoder().decode(AgentMonScanStatus.self, from: data)
  }

  private nonisolated func fetchDashboardState(appURL: URL) async throws -> TokMonDashboardState {
    let url = appURL.appendingPathComponent("api/tokmon/dashboard-state")
    let (data, response) = try await URLSession.shared.data(from: url)
    try validate(response: response, url: url)
    return try JSONDecoder().decode(TokMonDashboardState.self, from: data)
  }

  private nonisolated func fetchTokMonSummary(appURL: URL, dashboardState: TokMonDashboardState) async throws -> TokMonSummary {
    let url = try makeTokMonURL(appURL: appURL, endpoint: "summary", dashboardState: dashboardState, includeInterval: false)
    let (data, response) = try await URLSession.shared.data(from: url)
    try validate(response: response, url: url)
    return try JSONDecoder().decode(TokMonSummary.self, from: data)
  }

  private nonisolated func fetchTokMonTrend(appURL: URL, dashboardState: TokMonDashboardState) async throws -> [TokMonTrendBucket] {
    let url = try makeTokMonURL(appURL: appURL, endpoint: "trend", dashboardState: dashboardState, includeInterval: true)
    let (data, response) = try await URLSession.shared.data(from: url)
    try validate(response: response, url: url)
    return try JSONDecoder().decode([TokMonTrendBucket].self, from: data)
  }

  private nonisolated func makeTokMonURL(
    appURL: URL,
    endpoint: String,
    dashboardState: TokMonDashboardState,
    includeInterval: Bool,
  ) throws -> URL {
    var components = URLComponents(url: appURL.appendingPathComponent("api/tokmon/\(endpoint)"), resolvingAgainstBaseURL: false)
    var queryItems = [
      URLQueryItem(name: "from", value: dashboardState.from),
      URLQueryItem(name: "to", value: dashboardState.to),
    ]

    if includeInterval {
      queryItems.append(URLQueryItem(name: "interval", value: dashboardState.interval))
    }

    if !dashboardState.source.isEmpty {
      queryItems.append(URLQueryItem(name: "source", value: dashboardState.source))
    }

    components?.queryItems = queryItems

    guard let url = components?.url else {
      throw AgentMonAppError("Could not build TokMon \(endpoint) URL.")
    }

    return url
  }

  private nonisolated func validate(response: URLResponse, url: URL) throws {
    guard let httpResponse = response as? HTTPURLResponse else {
      throw AgentMonAppError("No HTTP response from \(url.absoluteString).")
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      throw AgentMonAppError("\(url.path) returned HTTP \(httpResponse.statusCode).")
    }
  }
}

private actor TokMonNativeStatsWorker {
  private let engine: TokMonEngine
  private let nowProvider: @Sendable () -> Date

  init(engine: TokMonEngine, nowProvider: @escaping @Sendable () -> Date) {
    self.engine = engine
    self.nowProvider = nowProvider
  }

  func refresh(
    recordsLimit: Int,
    sessionsLimit: Int,
    selectedSession: TokMonUsageSessionSelection?,
  ) throws -> AgentMonStatsSnapshot {
    let now = nowProvider()
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
}

enum TokMonStatsSnapshotBuilder {
  static func fillTrendBuckets(
    _ buckets: [TokMonTrendBucket],
    dashboardState: TokMonDashboardState,
  ) -> [TokMonTrendBucket] {
    let interval = TokMonTrendInterval(dashboardState.interval)
    let calendar = Calendar.current
    let lookup = Dictionary(uniqueKeysWithValues: buckets.map { ($0.bucket, $0) })
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

    guard
      let rawStart = formatter.date(from: dashboardState.from),
      let rawEnd = formatter.date(from: dashboardState.to)
    else {
      return buckets
    }

    let start: Date
    let end: Date
    let stepComponent: Calendar.Component

    switch interval {
    case .day:
      start = calendar.startOfDay(for: rawStart)
      end = calendar.startOfDay(for: rawEnd)
      stepComponent = .day
    case .hour:
      start = calendar.dateInterval(of: .hour, for: rawStart)?.start ?? rawStart
      end = calendar.dateInterval(of: .hour, for: rawEnd)?.start ?? rawEnd
      stepComponent = .hour
    }

    var current = start
    var result: [TokMonTrendBucket] = []

    while current <= end {
      let key = trendBucketKey(for: current, interval: interval)
      result.append(lookup[key] ?? TokMonTrendBucket(bucket: key))
      guard let next = calendar.date(byAdding: stepComponent, value: 1, to: current) else { break }
      current = next
    }

    return result
  }

  static func currentDashboardState(from uiState: TokMonUIState, now: Date) -> TokMonDashboardState {
    let range = resolvedRange(for: uiState, now: now)
    return TokMonDashboardState(
      source: uiState.source,
      from: range.from,
      to: range.to,
      interval: uiState.interval,
      liveMode: uiState.liveMode,
      rangeMode: uiState.rangeMode,
      rangeLabel: uiState.rangeLabel,
      rangeHours: uiState.rangeHours,
      rangeDays: uiState.rangeDays,
      refreshRate: uiState.refreshRate,
      activeSeries: uiState.activeSeries,
      estimatedCost: 0,
      costRates: uiState.costRates,
      updatedAt: isoTimestamp(now),
    )
  }

  static func formattedTimestamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.string(from: date)
  }

  private static func resolvedRange(for uiState: TokMonUIState, now: Date) -> (from: String, to: String) {
    if !uiState.liveMode {
      return (
        uiState.from.isEmpty ? "2000-01-01 00:00:00" : uiState.from,
        uiState.to.isEmpty ? "2099-12-31 23:59:59" : uiState.to
      )
    }

    guard uiState.liveMode, uiState.rangeHours != nil || uiState.rangeDays != nil else {
      return ("2000-01-01 00:00:00", "2099-12-31 23:59:59")
    }

    let calendar = Calendar.current
    let from: Date
    if let rangeHours = uiState.rangeHours {
      if uiState.rangeMode == "round" {
        let roundedNow = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        from = calendar.date(byAdding: .hour, value: -rangeHours + 1, to: roundedNow) ?? now
      } else {
        from = calendar.date(byAdding: .hour, value: -rangeHours, to: now) ?? now
      }
    } else if let rangeDays = uiState.rangeDays {
      if uiState.rangeMode == "round" {
        let today = calendar.startOfDay(for: now)
        from = calendar.date(byAdding: .day, value: -rangeDays + 1, to: today) ?? now
      } else {
        from = calendar.date(byAdding: .day, value: -rangeDays, to: now) ?? now
      }
    } else {
      from = now
    }

    return (formattedDashboardBoundary(from, seconds: 0), formattedDashboardBoundary(now, seconds: 59))
  }

  private static func trendBucketKey(for date: Date, interval: TokMonTrendInterval) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = interval == .day ? "yyyy-MM-dd" : "yyyy-MM-dd HH:00"
    return formatter.string(from: date)
  }

  private static func formattedDashboardBoundary(_ date: Date, seconds: Int) -> String {
    var calendar = Calendar.current
    calendar.timeZone = .current
    let adjusted = calendar.date(
      bySettingHour: calendar.component(.hour, from: date),
      minute: calendar.component(.minute, from: date),
      second: seconds,
      of: date,
    ) ?? date

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.string(from: adjusted)
  }

  private static func isoTimestamp(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
  }
}
