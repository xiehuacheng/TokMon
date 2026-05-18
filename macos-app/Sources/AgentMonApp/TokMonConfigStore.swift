import Foundation

final class TokMonConfigStore {
  private let dataDir: URL
  private let fileManager: FileManager

  init(dataDir: URL, fileManager: FileManager = .default) {
    self.dataDir = dataDir
    self.fileManager = fileManager
  }

  func loadConfig() throws -> TokMonConfig {
    let url = configURL
    guard fileManager.fileExists(atPath: url.path) else {
      return .default
    }
    let data = try Data(contentsOf: url)
    return normalizedConfig(from: data) ?? .default
  }

  func saveConfig(_ config: TokMonConfig) throws {
    try write(config, to: configURL)
  }

  func loadUIState() throws -> TokMonUIState {
    let url = uiStateURL
    if fileManager.fileExists(atPath: url.path) {
      let data = try Data(contentsOf: url)
      return normalizedUIState(from: data) ?? .default
    }

    let legacyURL = legacyDashboardStateURL
    guard fileManager.fileExists(atPath: legacyURL.path) else {
      return .default
    }

    let legacyData = try Data(contentsOf: legacyURL)
    let legacyState = normalizedUIState(from: legacyData) ?? .default
    try saveUIState(legacyState)
    return legacyState
  }

  func saveUIState(_ state: TokMonUIState) throws {
    try write(state, to: uiStateURL)
  }

  func expandUserPath(_ path: String) -> String {
    guard path == "~" || path.hasPrefix("~/") else {
      return path
    }

    let home = fileManager.homeDirectoryForCurrentUser.path
    if path == "~" {
      return home
    }
    return home + String(path.dropFirst())
  }

  private var configURL: URL {
    dataDir.appendingPathComponent("tokmon.config.json")
  }

  private var uiStateURL: URL {
    dataDir.appendingPathComponent("tokmon-ui-state.json")
  }

  private var legacyDashboardStateURL: URL {
    dataDir.appendingPathComponent("tokmon-dashboard-state.json")
  }

  private func normalizedConfig(from data: Data) -> TokMonConfig? {
    guard let object = jsonObject(from: data) else {
      return nil
    }

    var sources = TokMonConfig.default.sources
    if let rawSources = object["sources"] as? [String: Any] {
      for (name, value) in rawSources {
        guard
          let sourceObject = value as? [String: Any],
          let path = sourceObject["path"] as? String,
          !path.isEmpty
        else {
          continue
        }
        sources[name] = TokMonSourceConfig(path: path)
      }
    }

    return TokMonConfig(
      port: intValue(object["port"]) ?? TokMonConfig.default.port,
      sources: sources,
    )
  }

  private func normalizedUIState(from data: Data) -> TokMonUIState? {
    guard let object = jsonObject(from: data) else {
      return nil
    }

    let defaults = TokMonUIState.default
    return TokMonUIState(
      source: stringValue(object["source"]) ?? defaults.source,
      rangeLabel: optionalStringValue(object["rangeLabel"], default: defaults.rangeLabel),
      rangeHours: optionalIntValue(object["rangeHours"], default: defaults.rangeHours),
      rangeDays: optionalIntValue(object["rangeDays"], default: defaults.rangeDays),
      liveMode: boolValue(object["liveMode"]) ?? defaults.liveMode,
      rangeMode: stringValue(object["rangeMode"]) ?? defaults.rangeMode,
      interval: stringValue(object["interval"]) ?? defaults.interval,
      activeSeries: stringValue(object["activeSeries"]) ?? defaults.activeSeries,
      refreshRate: intValue(object["refreshRate"]) ?? defaults.refreshRate,
      costRates: normalizedCostRates(from: object["costRates"]),
    )
  }

  private func normalizedCostRates(from rawValue: Any?) -> TokMonCostRates {
    guard let object = rawValue as? [String: Any] else {
      return TokMonUIState.default.costRates
    }

    return TokMonCostRates(
      input: doubleValue(object["input"]) ?? TokMonUIState.default.costRates.input,
      output: doubleValue(object["output"]) ?? TokMonUIState.default.costRates.output,
      cacheCreate: doubleValue(object["cache_create"]) ?? TokMonUIState.default.costRates.cacheCreate,
      cacheRead: doubleValue(object["cache_read"]) ?? TokMonUIState.default.costRates.cacheRead,
    )
  }

  private func jsonObject(from data: Data) -> [String: Any]? {
    (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }

  private func optionalStringValue(_ value: Any?, default defaultValue: String?) -> String? {
    guard let value else {
      return defaultValue
    }
    if value is NSNull {
      return nil
    }
    return stringValue(value) ?? defaultValue
  }

  private func optionalIntValue(_ value: Any?, default defaultValue: Int?) -> Int? {
    guard let value else {
      return defaultValue
    }
    if value is NSNull {
      return nil
    }
    return intValue(value) ?? defaultValue
  }

  private func stringValue(_ value: Any?) -> String? {
    value as? String
  }

  private func boolValue(_ value: Any?) -> Bool? {
    value as? Bool
  }

  private func intValue(_ value: Any?) -> Int? {
    if value is Bool {
      return nil
    }
    guard let number = value as? NSNumber else {
      return nil
    }
    return number.intValue
  }

  private func doubleValue(_ value: Any?) -> Double? {
    if value is Bool {
      return nil
    }
    guard let number = value as? NSNumber else {
      return nil
    }
    return number.doubleValue
  }

  private func write<T: Encodable>(_ value: T, to url: URL) throws {
    try fileManager.createDirectory(at: dataDir, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var data = try encoder.encode(value)
    data.append(0x0A)
    try data.write(to: url, options: .atomic)
  }
}
