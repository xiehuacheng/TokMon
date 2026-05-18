import SwiftUI

@MainActor
final class AgentMonRuntime: ObservableObject {
  static let shared = AgentMonRuntime()

  let server = AgentMonServer()
  let stats: AgentMonStatsStore
  let usesNativeTokMonEngine: Bool

  private let nativeEngineActor: TokMonEngineActor?
  private let settingsWindowController: TokMonSettingsWindowController?
  private var started = false

  init() {
    if let engine = try? Self.makeTokMonEngine() {
      let engineActor = TokMonEngineActor(engine: engine)
      nativeEngineActor = engineActor
      stats = AgentMonStatsStore(engineActor: engineActor)
      usesNativeTokMonEngine = true
      settingsWindowController = TokMonSettingsWindowController(engineActor: engineActor)
    } else {
      nativeEngineActor = nil
      stats = AgentMonStatsStore()
      usesNativeTokMonEngine = false
      settingsWindowController = nil
    }
  }

  func start() {
    guard !started else { return }
    started = true
    if usesNativeTokMonEngine {
      agentMonLog("AgentMon runtime using native TokMon engine")
    } else {
      agentMonLog("AgentMon runtime starting service")
      server.start()
      stats.configure(appURL: server.appURL)
    }
  }

  func openDashboard() {
    start()
    guard !usesNativeTokMonEngine else { return }
    NSWorkspace.shared.open(server.appURL)
  }

  func openSettings() {
    settingsWindowController?.show()
  }

  func quit() {
    stats.stopObserving()
    if !usesNativeTokMonEngine {
      server.stop(waitUntilExit: true)
    }
    NSApplication.shared.terminate(nil)
  }

  func stop() {
    stats.stopObserving()
    if !usesNativeTokMonEngine {
      server.stop(waitUntilExit: true)
    }
  }

  private static func makeTokMonEngine() throws -> TokMonEngine {
    let dataDir = try AgentMonProjectLocator.appDataDir()
    let configStore = TokMonConfigStore(dataDir: dataDir)
    let database = try TokMonDatabase(appDataDir: dataDir)
    return TokMonEngine(configStore: configStore, database: database)
  }
}
