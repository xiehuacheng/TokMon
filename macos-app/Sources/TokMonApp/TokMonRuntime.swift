import SwiftUI

@MainActor
final class TokMonRuntime: ObservableObject {
  static let shared = TokMonRuntime()

  let stats: TokMonStatsStore
  @Published var statusPanelSessionBubbleY: CGFloat?

  private let settingsWindowController: TokMonSettingsWindowController?
  private var started = false

  init() {
    do {
      let engine = try Self.makeTokMonEngine()
      let engineActor = TokMonEngineActor(engine: engine)
      stats = TokMonStatsStore(engineActor: engineActor)
      settingsWindowController = TokMonSettingsWindowController(engineActor: engineActor)
    } catch {
      tokMonLog("TokMon native TokMon engine failed to initialize: \(error.localizedDescription)")
      stats = TokMonStatsStore(startupError: error.localizedDescription)
      settingsWindowController = nil
    }
  }

  func start() {
    guard !started else { return }
    started = true
    tokMonLog("TokMon runtime using native TokMon engine")
    stats.startObserving()
    Task { [stats] in
      await stats.refresh()
    }
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
    let dataDir = try TokMonProjectLocator.appDataDir()
    let configStore = TokMonConfigStore(dataDir: dataDir)
    let database = try TokMonDatabase(appDataDir: dataDir)
    return TokMonEngine(configStore: configStore, database: database)
  }
}
