import SwiftUI

@MainActor
final class TokMonRuntime: ObservableObject {
  static let shared = TokMonRuntime()

  let stats: TokMonStatsStore
  @Published var statusPanelSessionBubbleY: CGFloat?

  private let settingsWindowController: TokMonSettingsWindowController?
  private var started = false
  private var sourceWatcher: TokMonSourceWatcher?

  init() {
    do {
      let engine = try Self.makeTokMonEngine()
      let engineActor = TokMonEngineActor(engine: engine)
      let statsStore = TokMonStatsStore(engineActor: engineActor)
      let watcher = TokMonSourceWatcher(
        configProvider: {
          (try? engine.configStore.loadConfig()) ?? TokMonConfig.default
        },
        onChange: { [weak statsStore, weak engineActor] paths in
          Task {
            let inserted = try? await engineActor?.scan(paths: paths)
            tokMonLog("TokMonSourceWatcher scanned \(inserted ?? 0) new records")
            await statsStore?.refresh()
          }
        }
      )
      let controller = TokMonSettingsWindowController(
        engineActor: engineActor,
        onSettingsSaved: { [weak watcher, weak statsStore] in
          Task {
            await watcher?.restart()
            await statsStore?.refreshWithScan()
          }
        }
      )
      stats = statsStore
      sourceWatcher = watcher
      settingsWindowController = controller
    } catch {
      tokMonLog("TokMon native TokMon engine failed to initialize: \(error.localizedDescription)")
      stats = TokMonStatsStore(startupError: error.localizedDescription)
      sourceWatcher = nil
      settingsWindowController = nil
    }
  }

  func start() {
    guard !started else { return }
    started = true
    tokMonLog("TokMon runtime using native TokMon engine")
    Task { [sourceWatcher] in
      await sourceWatcher?.start()
    }
    stats.startObserving()
    Task { [stats] in
      await stats.refreshWithScan()
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
