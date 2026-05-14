import Foundation

struct AgentMonStatsSnapshot {
  var scanStatus: AgentMonScanStatus?
  var summary: TokMonSummary?
  var trendBuckets: [TokMonTrendBucket] = []
  var dashboardState: TokMonDashboardState?
  var updatedAt: Date?

  static let empty = AgentMonStatsSnapshot()
}

struct AgentMonScanStatus: Decodable {
  let running: Bool
  let phase: String
  let current: Int
  let total: Int
  let processed: Int
  let startedAt: String?
  let finishedAt: String?
  let error: String?
}

struct TokMonSummary: Decodable {
  let total: TokMonTotals
  let bySource: [TokMonSourceTotals]
  let byModel: [TokMonModelTotals]

  func estimatedCost(costRates: TokMonCostRates) -> Double {
    byModel.reduce(0) { sum, model in
      sum + model.value(for: .cost, costRates: costRates)
    }
  }
}

struct TokMonTotals: Decodable {
  let totalRequests: Int
  let totalInput: Int
  let totalOutput: Int
  let totalCacheCreation: Int
  let totalCacheRead: Int
  let totalReasoning: Int

  enum CodingKeys: String, CodingKey {
    case totalRequests = "total_requests"
    case totalInput = "total_input"
    case totalOutput = "total_output"
    case totalCacheCreation = "total_cache_creation"
    case totalCacheRead = "total_cache_read"
    case totalReasoning = "total_reasoning"
  }

  var totalTokens: Int {
    totalInput + totalOutput
  }
}

struct TokMonSourceTotals: Decodable, Identifiable {
  let source: String
  let requests: Int
  let inputTokens: Int
  let outputTokens: Int
  let cacheCreation: Int
  let cacheRead: Int

  var id: String { source }

  enum CodingKeys: String, CodingKey {
    case source
    case requests
    case inputTokens = "input_tokens"
    case outputTokens = "output_tokens"
    case cacheCreation = "cache_creation"
    case cacheRead = "cache_read"
  }

  var totalTokens: Int {
    inputTokens + outputTokens
  }

  func value(for series: TokMonSeriesKey, costRates: TokMonCostRates) -> Double {
    switch series {
    case .total:
      Double(totalTokens)
    case .requests:
      Double(requests)
    case .input:
      Double(inputTokens)
    case .output:
      Double(outputTokens)
    case .cache:
      Double(cacheCreation)
    case .cacheHit:
      Double(cacheRead)
    case .cost:
      Double(inputTokens) / 1_000_000 * costRates.input
        + Double(outputTokens) / 1_000_000 * costRates.output
        + Double(cacheCreation) / 1_000_000 * costRates.cacheCreate
        + Double(cacheRead) / 1_000_000 * costRates.cacheRead
    }
  }
}

struct TokMonModelTotals: Decodable, Identifiable {
  let model: String
  let source: String
  let requests: Int
  let inputTokens: Int
  let outputTokens: Int
  let cacheCreation: Int
  let cacheRead: Int

  var id: String { "\(source):\(model)" }

  enum CodingKeys: String, CodingKey {
    case model
    case source
    case requests
    case inputTokens = "input_tokens"
    case outputTokens = "output_tokens"
    case cacheCreation = "cache_creation"
    case cacheRead = "cache_read"
  }

  var totalTokens: Int {
    inputTokens + outputTokens
  }

  func value(for series: TokMonSeriesKey, costRates: TokMonCostRates) -> Double {
    switch series {
    case .total:
      Double(totalTokens)
    case .requests:
      Double(requests)
    case .input:
      Double(inputTokens)
    case .output:
      Double(outputTokens)
    case .cache:
      Double(cacheCreation)
    case .cacheHit:
      Double(cacheRead)
    case .cost:
      Double(inputTokens) / 1_000_000 * costRates.input
        + Double(outputTokens) / 1_000_000 * costRates.output
        + Double(cacheCreation) / 1_000_000 * costRates.cacheCreate
        + Double(cacheRead) / 1_000_000 * costRates.cacheRead
    }
  }
}

struct TokMonTrendBucket: Decodable {
  let bucket: String
  let inputTokens: Int
  let outputTokens: Int
  let cacheCreation: Int
  let cacheRead: Int
  let requests: Int

  init(
    bucket: String,
    inputTokens: Int = 0,
    outputTokens: Int = 0,
    cacheCreation: Int = 0,
    cacheRead: Int = 0,
    requests: Int = 0,
  ) {
    self.bucket = bucket
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens
    self.cacheCreation = cacheCreation
    self.cacheRead = cacheRead
    self.requests = requests
  }

  enum CodingKeys: String, CodingKey {
    case bucket
    case inputTokens = "input_tokens"
    case outputTokens = "output_tokens"
    case cacheCreation = "cache_creation"
    case cacheRead = "cache_read"
    case requests
  }

  func value(for series: TokMonSeriesKey, costRates: TokMonCostRates) -> Double {
    switch series {
    case .total:
      Double(inputTokens + outputTokens)
    case .requests:
      Double(requests)
    case .input:
      Double(inputTokens)
    case .output:
      Double(outputTokens)
    case .cache:
      Double(cacheCreation)
    case .cacheHit:
      Double(cacheRead)
    case .cost:
      Double(inputTokens) / 1_000_000 * costRates.input
        + Double(outputTokens) / 1_000_000 * costRates.output
        + Double(cacheCreation) / 1_000_000 * costRates.cacheCreate
        + Double(cacheRead) / 1_000_000 * costRates.cacheRead
    }
  }
}

struct TokMonTrendPoint: Identifiable {
  let id: String
  let label: String
  let value: Double
}

enum TokMonSeriesKey {
  var rawValue: String {
    switch self {
    case .total:
      "total"
    case .requests:
      "reqs"
    case .input:
      "input"
    case .output:
      "output"
    case .cache:
      "cache"
    case .cacheHit:
      "cacheHit"
    case .cost:
      "cost"
    }
  }

  case total
  case requests
  case input
  case output
  case cache
  case cacheHit
  case cost

  init(_ rawValue: String) {
    switch rawValue {
    case "reqs":
      self = .requests
    case "input":
      self = .input
    case "output":
      self = .output
    case "cache":
      self = .cache
    case "cacheHit":
      self = .cacheHit
    case "cost":
      self = .cost
    default:
      self = .total
    }
  }
}

struct TokMonCostRates: Decodable {
  let input: Double
  let output: Double
  let cacheCreate: Double
  let cacheRead: Double

  enum CodingKeys: String, CodingKey {
    case input
    case output
    case cacheCreate = "cache_create"
    case cacheRead = "cache_read"
  }

  static let zero = TokMonCostRates(input: 0, output: 0, cacheCreate: 0, cacheRead: 0)
}

struct TokMonDashboardState: Decodable {
  let source: String
  let from: String
  let to: String
  let interval: String
  let liveMode: Bool
  let rangeMode: String
  let rangeLabel: String?
  let rangeHours: Int?
  let rangeDays: Int?
  let refreshRate: Int
  let activeSeries: String
  let estimatedCost: Double
  let costRates: TokMonCostRates
  let updatedAt: String

  enum CodingKeys: String, CodingKey {
    case source
    case from
    case to
    case interval
    case liveMode
    case rangeMode
    case rangeLabel
    case rangeHours
    case rangeDays
    case refreshRate
    case activeSeries
    case estimatedCost
    case costRates
    case updatedAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
    from = try container.decodeIfPresent(String.self, forKey: .from) ?? ""
    to = try container.decodeIfPresent(String.self, forKey: .to) ?? ""
    interval = try container.decodeIfPresent(String.self, forKey: .interval) ?? "day"
    liveMode = try container.decodeIfPresent(Bool.self, forKey: .liveMode) ?? true
    rangeMode = try container.decodeIfPresent(String.self, forKey: .rangeMode) ?? "exact"
    rangeLabel = try container.decodeIfPresent(String.self, forKey: .rangeLabel)
    rangeHours = try container.decodeIfPresent(Int.self, forKey: .rangeHours)
    rangeDays = try container.decodeIfPresent(Int.self, forKey: .rangeDays)
    refreshRate = try container.decodeIfPresent(Int.self, forKey: .refreshRate) ?? 3000
    activeSeries = try container.decodeIfPresent(String.self, forKey: .activeSeries) ?? "total"
    estimatedCost = try container.decodeIfPresent(Double.self, forKey: .estimatedCost) ?? 0
    costRates = try container.decodeIfPresent(TokMonCostRates.self, forKey: .costRates) ?? .zero
    updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
  }

  var sourceLabel: String {
    switch source {
    case "":
      "All Sources"
    case "claude-code":
      "Claude Code"
    case "codex":
      "Codex"
    default:
      source
    }
  }

  var rangeDisplay: String {
    if let rangeLabel, !rangeLabel.isEmpty {
      return rangeLabel
    }
    return "\(from.dropLast(3)) - \(to.dropLast(3))"
  }

  var rangeModeLabel: String {
    rangeMode == "round" ? "Round" : "Exact"
  }
}

private struct ActivityRequest: Encodable {
  let name: String
  let ttlMs: Int
}

enum TokMonTrendInterval {
  case hour
  case day

  init(_ rawValue: String) {
    self = rawValue == "hour" ? .hour : .day
  }
}

@MainActor
final class AgentMonStatsStore: ObservableObject {
  @Published private(set) var snapshot = AgentMonStatsSnapshot.empty
  @Published private(set) var isRefreshing = false
  @Published private(set) var errorMessage: String?

  private var appURL: URL?
  private var timerTask: Task<Void, Never>?
  private let refreshIntervalSeconds = 3
  private let activityName = "status-popover"
  private let activityTtlMilliseconds = 10_000

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
          try? await Task.sleep(nanoseconds: UInt64(self?.refreshIntervalSeconds ?? 3) * 1_000_000_000)
          await self?.refresh()
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
    guard let appURL else { return }

    isRefreshing = true
    defer { isRefreshing = false }

    do {
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
        trendBuckets: fillTrendBuckets(resolvedTrend, dashboardState: resolvedDashboardState),
        dashboardState: resolvedDashboardState,
        updatedAt: Date(),
      )
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
      snapshot = AgentMonStatsSnapshot(
        scanStatus: snapshot.scanStatus,
        summary: snapshot.summary,
        trendBuckets: snapshot.trendBuckets,
        dashboardState: snapshot.dashboardState,
        updatedAt: snapshot.updatedAt,
      )
    }
  }

  private func requestRefresh() {
    Task { [weak self] in
      await self?.refresh()
    }
  }

  private func releaseActivity() {
    guard let appURL else { return }
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

  private nonisolated func fillTrendBuckets(
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

  private nonisolated func trendBucketKey(for date: Date, interval: TokMonTrendInterval) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = interval == .day ? "yyyy-MM-dd" : "yyyy-MM-dd HH:00"
    return formatter.string(from: date)
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
