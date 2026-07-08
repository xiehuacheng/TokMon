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
    guard fileManager.fileExists(atPath: url.path) else {
      return .default
    }

    let data = try Data(contentsOf: url)
    return normalizedUIState(from: data) ?? .default
  }

  func saveUIState(_ state: TokMonUIState) throws {
    try write(state, to: uiStateURL)
  }

  func loadLastKimiQuotaSnapshot() -> KimiQuotaSnapshot? {
    let url = lastKimiQuotaSnapshotURL
    guard fileManager.fileExists(atPath: url.path) else {
      return nil
    }
    guard let data = try? Data(contentsOf: url) else {
      return nil
    }
    return try? JSONDecoder().decode(KimiQuotaSnapshot.self, from: data)
  }

  func saveLastKimiQuotaSnapshot(_ snapshot: KimiQuotaSnapshot) throws {
    try write(snapshot, to: lastKimiQuotaSnapshotURL)
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

  private var lastKimiQuotaSnapshotURL: URL {
    dataDir.appendingPathComponent("tokmon-kimi-quota.json")
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
    let preset = TokMonRangePreset(label: optionalStringValue(object["rangeLabel"], default: defaults.rangeLabel))
    return TokMonUIState(
      source: stringValue(object["source"]) ?? defaults.source,
      from: stringValue(object["from"]) ?? defaults.from,
      to: stringValue(object["to"]) ?? defaults.to,
      rangeLabel: preset.label,
      rangeHours: preset.hours,
      rangeDays: preset.days,
      liveMode: true,
      rangeMode: "round",
      interval: preset.interval,
      activeSeries: stringValue(object["activeSeries"]) ?? defaults.activeSeries,
      menuBarDisplayItems: normalizedMenuBarDisplayItems(from: object),
      refreshRate: intValue(object["refreshRate"]) ?? defaults.refreshRate,
      kimiQuotaRefreshInterval: intValue(object["kimiQuotaRefreshInterval"]) ?? defaults.kimiQuotaRefreshInterval,
      costRates: normalizedCostRates(from: object["costRates"]),
      modelPricing: normalizedModelPricing(from: object["modelPricing"]),
    )
  }

  private func normalizedMenuBarDisplayItems(from object: [String: Any]) -> TokMonMenuBarItems {
    if let items = object["menuBarDisplayItems"] as? [String: Any] {
      return TokMonMenuBarItems(
        totalTokens: boolValue(items["totalTokens"]) ?? false,
        estimatedCost: boolValue(items["estimatedCost"]) ?? false,
        requests: boolValue(items["requests"]) ?? false,
        kimiQuota: boolValue(items["kimiQuota"]) ?? false
      )
    }
    if let legacyMode = stringValue(object["menuBarDisplayMode"]) {
      return TokMonMenuBarItems(legacyMode: legacyMode)
    }
    return TokMonUIState.default.menuBarDisplayItems
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

  private func normalizedModelPricing(from rawValue: Any?) -> [String: TokMonCostRates] {
    guard let object = rawValue as? [String: Any] else {
      return TokMonUIState.default.modelPricing
    }

    return object.reduce(into: [:]) { result, item in
      guard !item.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return
      }
      result[item.key] = normalizedCostRates(from: item.value)
    }
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

  private func optionalIntValue(in object: [String: Any], key: String, default defaultValue: Int?) -> Int? {
    guard let value = object[key] else {
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
    guard let number = value as? NSNumber else {
      return nil
    }
    if isJSONBoolean(number) {
      return nil
    }
    return number.intValue
  }

  private func doubleValue(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber else {
      return nil
    }
    if isJSONBoolean(number) {
      return nil
    }
    return number.doubleValue
  }

  private func isJSONBoolean(_ value: NSNumber) -> Bool {
    CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID()
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
