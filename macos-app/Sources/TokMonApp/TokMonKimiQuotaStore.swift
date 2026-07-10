import Foundation

actor TokMonKimiQuotaStore {
  private let baseURL: String
  private let urlSession: URLSession

  init(baseURL: String = "https://api.kimi.com/coding/v1", urlSession: URLSession = URLSession(configuration: .ephemeral)) {
    self.baseURL = baseURL
    self.urlSession = urlSession
  }

  func fetchQuota(apiKey: String) async -> KimiQuotaSnapshot {
    guard !apiKey.isEmpty else {
      return KimiQuotaSnapshot(weekly: nil, fiveHour: nil, fetchedAt: nil, error: .noAPIKey)
    }
    do {
      let snapshot = try await performFetch(apiKey: apiKey)
      return snapshot
    } catch let error as KimiQuotaError {
      return KimiQuotaSnapshot(weekly: nil, fiveHour: nil, fetchedAt: nil, error: error)
    } catch {
      return KimiQuotaSnapshot(weekly: nil, fiveHour: nil, fetchedAt: nil, error: .network)
    }
  }

  private func performFetch(apiKey: String) async throws -> KimiQuotaSnapshot {
    do {
      let data = try await fetchData(apiKey: apiKey, path: "/usages")
      return try parseUsagePayload(data, fetchedAt: Date())
    } catch KimiQuotaError.endpointNotFound {
      let data = try await fetchData(apiKey: apiKey, path: "/usage")
      return try parseUsagePayload(data, fetchedAt: Date())
    }
  }

  private func fetchData(apiKey: String, path: String) async throws -> Data {
    guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else {
      throw KimiQuotaError.network
    }
    var request = URLRequest(url: url)
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("KimiCLI/1.6", forHTTPHeaderField: "User-Agent")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let (data, response) = try await urlSession.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw KimiQuotaError.network
    }

    switch httpResponse.statusCode {
    case 200:
      return data
    case 404:
      throw KimiQuotaError.endpointNotFound
    case 401, 403:
      throw KimiQuotaError.invalidKey
    case 429:
      throw KimiQuotaError.rateLimited
    default:
      throw KimiQuotaError.network
    }
  }

  func parseForTests(json: Data, fetchedAt: Date = Date()) throws -> KimiQuotaSnapshot {
    try parseUsagePayload(json, fetchedAt: fetchedAt)
  }
}

// MARK: - Parsing

private func parseDate(_ string: String) -> Date? {
  let isoFormatter = ISO8601DateFormatter()
  isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  let isoFormatterNoFraction = ISO8601DateFormatter()
  isoFormatterNoFraction.formatOptions = [.withInternetDateTime]
  return isoFormatter.date(from: string) ?? isoFormatterNoFraction.date(from: string)
}

private func parseNumber(_ value: Any?) -> Double? {
  if let num = value as? NSNumber { return num.doubleValue }
  if let str = value as? String, let d = Double(str) { return d }
  return nil
}

private func parseUsagePayload(_ data: Data, fetchedAt: Date) throws -> KimiQuotaSnapshot {
  guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
    throw KimiQuotaError.decoding
  }

  var weekly: KimiQuotaWindow?
  var fiveHour: KimiQuotaWindow?

  if let dataList = json["data"] as? [[String: Any]] {
    for item in dataList {
      let modelName = (item["model_name"] as? String)?.lowercased() ?? ""
      if modelName == "all" {
        weekly = makeWindow(from: item, label: "Weekly Usage", now: fetchedAt) ?? weekly
      }
    }
  }

  if let usage = json["usage"] as? [String: Any] {
    weekly = makeWindow(from: usage, label: "Weekly Usage", now: fetchedAt) ?? weekly
  }

  if let limits = json["limits"] as? [[String: Any]] {
    for item in limits {
      let detail = (item["detail"] as? [String: Any]) ?? item
      let windowMeta = item["window"] as? [String: Any]
      if fiveHour == nil, isFiveHourWindow(windowMeta),
         let window = makeWindow(from: detail, windowMeta: windowMeta, label: "5-Hour Limit", now: fetchedAt) {
        fiveHour = window
      }
    }
  }

  guard weekly != nil || fiveHour != nil else {
    throw KimiQuotaError.decoding
  }

  return KimiQuotaSnapshot(weekly: weekly, fiveHour: fiveHour, fetchedAt: fetchedAt, error: nil)
}

private func isFiveHourWindow(_ window: [String: Any]?) -> Bool {
  guard let window else { return false }
  guard let duration = parseNumber(window["duration"]) else { return false }
  let timeUnit = (window["timeUnit"] as? String)?.uppercased() ?? ""
  return duration == 300 && timeUnit.contains("MINUTE")
}

private func makeWindow(from dict: [String: Any], windowMeta: [String: Any]? = nil, label: String, now: Date) -> KimiQuotaWindow? {
  guard let limit = parseNumber(dict["limit"] ?? dict["limit_amount"]) else { return nil }

  let used: Double
  if let usedValue = parseNumber(dict["used"] ?? dict["used_amount"]) {
    used = usedValue
  } else if let remaining = parseNumber(dict["remaining"]) {
    used = max(0, limit - remaining)
  } else {
    return nil
  }

  let explicitEnd = endDate(from: dict, windowMeta: windowMeta)
  let resetAt = resetDate(from: dict, now: now) ?? explicitEnd
  let endAt = explicitEnd ?? resetAt
  let countdown = resetAt.map { countdownString(from: now, to: $0) }

  return KimiQuotaWindow(
    label: label,
    used: used,
    limit: limit,
    remaining: max(0, limit - used),
    percentUsed: limit > 0 ? (used / limit) * 100 : 0,
    resetAt: resetAt,
    endAt: endAt,
    countdown: countdown
  )
}

private func resetDate(from dict: [String: Any], now: Date) -> Date? {
  if let resetTime = dict["resetTime"] as? String ?? dict["reset_at"] as? String ?? dict["reset_time"] as? String {
    return parseDate(resetTime)
  }
  if let resetIn = parseNumber(dict["reset_in"]) {
    return now.addingTimeInterval(resetIn)
  }
  return nil
}

private func endDate(from dict: [String: Any], windowMeta: [String: Any]?) -> Date? {
  if let endTime = dict["end_at"] as? String ?? dict["end_time"] as? String ?? dict["endTime"] as? String {
    return parseDate(endTime)
  }
  if let endTime = windowMeta?["end"] as? String {
    return parseDate(endTime)
  }
  return nil
}

private func countdownString(from now: Date, to resetAt: Date) -> String {
  let diff = resetAt.timeIntervalSince(now)
  guard diff > 0 else { return "0m" }
  let hours = Int(diff) / 3600
  let minutes = (Int(diff) % 3600) / 60
  if hours > 0 {
    return "\(hours)h \(minutes)m"
  }
  return "\(minutes)m"
}
