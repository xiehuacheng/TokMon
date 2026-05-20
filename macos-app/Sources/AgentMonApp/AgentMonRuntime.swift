import SwiftUI

@MainActor
final class AgentMonRuntime: ObservableObject {
  static let shared = AgentMonRuntime()

  let stats: AgentMonStatsStore

  private let settingsWindowController: TokMonSettingsWindowController?
  private var started = false

  init() {
    do {
      let engine = try Self.makeTokMonEngine()
      let engineActor = TokMonEngineActor(engine: engine)
      stats = AgentMonStatsStore(engineActor: engineActor)
      settingsWindowController = TokMonSettingsWindowController(engineActor: engineActor)
    } catch {
      agentMonLog("AgentMon native TokMon engine failed to initialize: \(error.localizedDescription)")
      stats = AgentMonStatsStore(startupError: error.localizedDescription)
      settingsWindowController = nil
    }
  }

  func start() {
    guard !started else { return }
    started = true
    agentMonLog("AgentMon runtime using native TokMon engine")
  }

  func openSettings() {
    settingsWindowController?.show()
  }

  func quit() {
    stats.stopObserving()
    NSApplication.shared.terminate(nil)
  }

  func stop() {
    stats.stopObserving()
  }

  private static func makeTokMonEngine() throws -> TokMonEngine {
    let dataDir = try AgentMonProjectLocator.appDataDir()
    let configStore = TokMonConfigStore(dataDir: dataDir)
    let database = try TokMonDatabase(appDataDir: dataDir)
    return TokMonEngine(configStore: configStore, database: database)
  }
}
