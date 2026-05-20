import Foundation

struct TokMonSourceConfig: Codable, Equatable {
  var path: String
}

struct TokMonConfig: Codable, Equatable {
  var port: Int
  var sources: [String: TokMonSourceConfig]

  static let `default` = TokMonConfig(
    port: 3388,
    sources: [
      "claude-code": TokMonSourceConfig(path: "~/.claude/projects"),
      "codex": TokMonSourceConfig(path: "~/.codex/sessions"),
    ],
  )
}

struct TokMonCostRates: Codable, Equatable {
  var input: Double
  var output: Double
  var cacheCreate: Double
  var cacheRead: Double

  enum CodingKeys: String, CodingKey {
    case input
    case output
    case cacheCreate = "cache_create"
    case cacheRead = "cache_read"
  }

  static let zero = TokMonCostRates(input: 0, output: 0, cacheCreate: 0, cacheRead: 0)

  func normalized() -> TokMonCostRates {
    TokMonCostRates(
      input: max(0, input),
      output: max(0, output),
      cacheCreate: max(0, cacheCreate),
      cacheRead: max(0, cacheRead),
    )
  }

  func cost(inputTokens: Int, outputTokens: Int, cacheCreation: Int, cacheRead: Int) -> Double {
    Double(inputTokens) / 1_000_000 * input
      + Double(outputTokens) / 1_000_000 * output
      + Double(cacheCreation) / 1_000_000 * cacheCreate
      + Double(cacheRead) / 1_000_000 * self.cacheRead
  }
}

struct TokMonUIState: Codable, Equatable {
  var source: String
  var from: String
  var to: String
  var rangeLabel: String?
  var rangeHours: Int?
  var rangeDays: Int?
  var liveMode: Bool
  var rangeMode: String
  var interval: String
  var activeSeries: String
  var refreshRate: Int
  var costRates: TokMonCostRates
  var modelPricing: [String: TokMonCostRates] = [:]

  static let `default` = TokMonUIState(
    source: "",
    from: "",
    to: "",
    rangeLabel: TokMonRangePreset.thisWeek.label,
    rangeHours: nil,
    rangeDays: nil,
    liveMode: true,
    rangeMode: "round",
    interval: "day",
    activeSeries: "total",
    refreshRate: 3000,
    costRates: .zero,
    modelPricing: [:],
  )
}

enum TokMonRangePreset: String, CaseIterable, Identifiable, Sendable {
  case today
  case thisWeek
  case thisMonth
  case all

  init(label: String?) {
    switch label {
    case "today", "1H", "24H":
      self = .today
    case "thisWeek", "7D":
      self = .thisWeek
    case "thisMonth", "30D":
      self = .thisMonth
    case "all":
      self = .all
    default:
      self = .thisWeek
    }
  }

  var id: String { rawValue }
  var label: String { rawValue }

  var displayLabel: String {
    switch self {
    case .today:
      "Today"
    case .thisWeek:
      "This Week"
    case .thisMonth:
      "This Month"
    case .all:
      "All"
    }
  }

  var compactDisplayLabel: String {
    switch self {
    case .today:
      "Today"
    case .thisWeek:
      "Week"
    case .thisMonth:
      "Month"
    case .all:
      "All"
    }
  }

  var hours: Int? {
    nil
  }

  var days: Int? {
    nil
  }

  var interval: String {
    switch self {
    case .today:
      "hour"
    case .thisWeek, .thisMonth, .all:
      "day"
    }
  }
}

struct TokMonUsageRecord: Equatable {
  var source: String
  var sessionId: String
  var model: String
  var inputTokens: Int
  var outputTokens: Int
  var cacheCreation: Int
  var cacheRead: Int
  var reasoningTokens: Int
  var createdAt: String
}

struct TokMonSessionMetadata: Equatable {
  var id: String
  var source: String
  var title: String?
  var firstPrompt: String?
  var lastPrompt: String?
  var model: String?
  var startedAt: String?
  var lastActiveAt: String?
  var filePath: String?
  var projectPath: String?
}

struct TokMonScanState: Equatable {
  var offset: Int64
  var sessionId: String?
  var model: String?
  var lastUsageKey: String?
  var lastMtime: String? = nil

  static let empty = TokMonScanState(offset: 0, sessionId: nil, model: nil, lastUsageKey: nil, lastMtime: nil)
}

struct TokMonQueryFilter: Equatable {
  var from: String
  var to: String
  var source: String?
  var model: String?

  var hasTimeRange: Bool {
    !from.isEmpty && !to.isEmpty
  }
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

  func estimatedCost(modelPricing: [String: TokMonCostRates]) -> Double {
    byModel.reduce(0) { sum, model in
      guard let rates = modelPricing[model.model] else {
        return sum
      }
      return sum + model.value(for: .cost, costRates: rates)
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
    totalInput + totalOutput + totalCacheRead
  }

  var cacheHitRate: Double {
    cacheHitRatio(inputTokens: totalInput, cacheRead: totalCacheRead)
  }

  func value(for series: TokMonSeriesKey, costRates: TokMonCostRates) -> Double {
    switch series {
    case .total:
      Double(totalTokens)
    case .requests:
      Double(totalRequests)
    case .input:
      Double(totalInput)
    case .output:
      Double(totalOutput)
    case .cache:
      Double(totalCacheCreation)
    case .cacheHit:
      Double(totalCacheRead)
    case .cacheHitRate:
      cacheHitRate
    case .cost:
      costRates.cost(
        inputTokens: totalInput,
        outputTokens: totalOutput,
        cacheCreation: totalCacheCreation,
        cacheRead: totalCacheRead,
      )
    }
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
    inputTokens + outputTokens + cacheRead
  }

  var cacheHitRate: Double {
    cacheHitRatio(inputTokens: inputTokens, cacheRead: cacheRead)
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
    case .cacheHitRate:
      cacheHitRate
    case .cost:
      costRates.cost(
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        cacheCreation: cacheCreation,
        cacheRead: cacheRead,
      )
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
    inputTokens + outputTokens + cacheRead
  }

  var cacheHitRate: Double {
    cacheHitRatio(inputTokens: inputTokens, cacheRead: cacheRead)
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
    case .cacheHitRate:
      cacheHitRate
    case .cost:
      costRates.cost(
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        cacheCreation: cacheCreation,
        cacheRead: cacheRead,
      )
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

  var cacheHitRate: Double {
    cacheHitRatio(inputTokens: inputTokens, cacheRead: cacheRead)
  }

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
      Double(inputTokens + outputTokens + cacheRead)
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
    case .cacheHitRate:
      cacheHitRate
    case .cost:
      costRates.cost(
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        cacheCreation: cacheCreation,
        cacheRead: cacheRead,
      )
    }
  }
}

struct TokMonHeatmapDay: Equatable, Identifiable {
  var day: String
  var requests: Int
  var inputTokens: Int
  var outputTokens: Int
  var cacheCreation: Int
  var cacheRead: Int
  var id: String { day }
}

struct TokMonModelOption: Equatable, Identifiable {
  var model: String
  var lastUsed: String
  var id: String { model }
}

struct TokMonRecordRow: Equatable, Identifiable {
  var id: String { "\(source):\(sessionId):\(createdAt):\(inputTokens):\(outputTokens)" }
  var source: String
  var sessionId: String
  var model: String
  var inputTokens: Int
  var outputTokens: Int
  var cacheCreation: Int
  var cacheRead: Int
  var reasoningTokens: Int
  var createdAt: String
}

struct TokMonRecordsPage: Equatable {
  var total: Int
  var page: Int
  var limit: Int
  var rows: [TokMonRecordRow]
}

struct TokMonUsageSession: Equatable, Identifiable {
  var id: String { "\(source):\(sessionId)" }
  var sessionId: String
  var source: String
  var title: String?
  var model: String
  var requests: Int
  var inputTokens: Int
  var outputTokens: Int
  var cacheCreation: Int
  var cacheRead: Int
  var firstAt: String
  var lastAt: String
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
    case .cacheHitRate:
      "cacheHitRate"
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
  case cacheHitRate
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
    case "cacheHitRate":
      self = .cacheHitRate
    case "cost":
      self = .cost
    default:
      self = .total
    }
  }
}

private func cacheHitRatio(inputTokens: Int, cacheRead: Int) -> Double {
  let denominator = inputTokens + cacheRead
  guard denominator > 0 else {
    return 0
  }
  return Double(cacheRead) / Double(denominator)
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
  let modelPricing: [String: TokMonCostRates]
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
    case modelPricing
    case updatedAt
  }

  init(
    source: String,
    from: String,
    to: String,
    interval: String,
    liveMode: Bool,
    rangeMode: String,
    rangeLabel: String?,
    rangeHours: Int?,
    rangeDays: Int?,
    refreshRate: Int,
    activeSeries: String,
    estimatedCost: Double,
    costRates: TokMonCostRates,
    modelPricing: [String: TokMonCostRates] = [:],
    updatedAt: String,
  ) {
    self.source = source
    self.from = from
    self.to = to
    self.interval = interval
    self.liveMode = liveMode
    self.rangeMode = rangeMode
    self.rangeLabel = rangeLabel
    self.rangeHours = rangeHours
    self.rangeDays = rangeDays
    self.refreshRate = refreshRate
    self.activeSeries = activeSeries
    self.estimatedCost = estimatedCost
    self.costRates = costRates
    self.modelPricing = modelPricing
    self.updatedAt = updatedAt
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
    modelPricing = try container.decodeIfPresent([String: TokMonCostRates].self, forKey: .modelPricing) ?? [:]
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

enum TokMonTrendInterval {
  case hour
  case day

  init(_ rawValue: String) {
    self = rawValue == "hour" ? .hour : .day
  }
}
