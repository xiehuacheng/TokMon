import Foundation
import ServiceManagement

@MainActor
final class TokMonSettingsStore: ObservableObject {
  @Published var draft = TokMonSettingsDraft()
  @Published private(set) var statusMessage = ""
  @Published private(set) var errorMessage: String?
  @Published private(set) var isBusy = false

  private let engineActor: TokMonEngineActor

  init(engine: TokMonEngine) {
    engineActor = TokMonEngineActor(engine: engine)
  }

  init(engineActor: TokMonEngineActor) {
    self.engineActor = engineActor
  }

  func load() async throws {
    do {
      draft = try await engineActor.loadSettingsDraft()
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
      throw error
    }
  }

  func save() async throws {
    try await runBusyAction {
      try await engineActor.saveSettings(draft: draft)
    }
    applyLaunchAtLogin(draft.launchAtLogin)
    if errorMessage == nil {
      statusMessage = "Settings saved."
    }
  }

  private func applyLaunchAtLogin(_ enabled: Bool) {
    let service = SMAppService.mainApp
    do {
      if enabled {
        if service.status != .enabled {
          try service.register()
        }
      } else {
        if service.status == .enabled {
          try service.unregister()
        }
      }
    } catch {
      errorMessage = "Could not change login item: \(error.localizedDescription)"
    }
  }

  func scanNow() async throws {
    try await runBusyAction {
      let inserted = try await engineActor.scan()
      statusMessage = inserted == 1 ? "Scanned 1 record." : "Scanned \(inserted) records."
    }
  }

  func rebuildAndRescan() async throws {
    try await runBusyAction {
      let inserted = try await engineActor.rebuildAndRescan()
      statusMessage = inserted == 1 ? "Rebuilt database and scanned 1 record." : "Rebuilt database and scanned \(inserted) records."
    }
  }

  private func runBusyAction(_ action: () async throws -> Void) async rethrows {
    isBusy = true
    defer { isBusy = false }
    do {
      try await action()
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
      throw error
    }
  }
}

struct TokMonSettingsDraft: Equatable {
  var claudePath = TokMonConfig.default.sources["claude-code"]?.path ?? "~/.claude/projects"
  var codexPath = TokMonConfig.default.sources["codex"]?.path ?? "~/.codex/sessions"
  var kimiCodePath = TokMonConfig.default.sources["kimi-code"]?.path ?? "~/.kimi-code"
  var openCodePath = TokMonConfig.default.sources["opencode"]?.path ?? "~/.local/share/opencode"
  var qwenCodePath = TokMonConfig.default.sources["qwen-code"]?.path ?? "~/.qwen/projects"
  var source = TokMonUIState.default.source
  var rangeLabel = TokMonUIState.default.rangeLabel ?? "7D"
  var liveMode = TokMonUIState.default.liveMode
  var interval = TokMonUIState.default.interval
  var activeSeries = TokMonUIState.default.activeSeries
  var menuBarDisplayItems = TokMonUIState.default.menuBarDisplayItems
  var refreshRate = TokMonUIState.default.refreshRate
  var inputRate = TokMonUIState.default.costRates.input
  var outputRate = TokMonUIState.default.costRates.output
  var cacheCreateRate = TokMonUIState.default.costRates.cacheCreate
  var cacheReadRate = TokMonUIState.default.costRates.cacheRead
  var modelPricing = TokMonUIState.default.modelPricing
  var kimiQuotaRefreshInterval: Int = TokMonUIState.default.kimiQuotaRefreshInterval
  var launchAtLogin: Bool = TokMonUIState.default.launchAtLogin
  var availableModels: [TokMonModelOption] = []
}

enum TokMonSettingsError: LocalizedError {
  case noReadableSourcePaths
  case noUsageLogsFound

  var errorDescription: String? {
    switch self {
    case .noReadableSourcePaths:
      "No configured TokMon source paths are readable. Rebuild was not started."
    case .noUsageLogsFound:
      "No TokMon usage logs were found in the configured source paths. Rebuild was not started."
    }
  }
}
