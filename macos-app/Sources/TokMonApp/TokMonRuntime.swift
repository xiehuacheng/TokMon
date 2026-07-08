import SwiftUI

@MainActor
final class TokMonRuntime: ObservableObject {
  static let shared = TokMonRuntime()

  let stats: TokMonStatsStore
  let updater = TokMonUpdater.shared
  @Published var statusPanelSessionBubbleY: CGFloat?
  weak var statusPanel: NSPanel?

  private var settingsWindowController: TokMonSettingsWindowController?
  private let engineActor: TokMonEngineActor?
  private var started = false
  private var sourceWatcher: TokMonSourceWatcher?
  private var fileWatcher: TokMonFileWatcher?
  private var windowPresentationCount = 0
  private var settingsWindowPresentationActive = false

  init() {
    do {
      let engine = try Self.makeTokMonEngine()
      let engineActor = TokMonEngineActor(engine: engine)
      let statsStore = TokMonStatsStore(engineActor: engineActor, configStore: engine.configStore)

      let onScan: @Sendable ([String]) -> Void = { [weak statsStore, weak engineActor] paths in
        Task {
          let inserted = (try? await engineActor?.scan(paths: paths)) ?? 0
          tokMonLog("TokMon scanned \(inserted) new records from \(paths)")
          guard inserted > 0 else { return }
          await statsStore?.refresh()
        }
      }

      let watcher = TokMonSourceWatcher(
        configProvider: {
          (try? engine.configStore.loadConfig()) ?? TokMonConfig.default
        },
        onChange: onScan
      )
      let watcherForFileEvents = TokMonFileWatcher(onChange: onScan)
      engine.scanner.fileWatcher = watcherForFileEvents

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
      self.engineActor = engineActor
      sourceWatcher = watcher
      fileWatcher = watcherForFileEvents
      settingsWindowController = controller
      settingsWindowController?.onWindowClosed = { [weak self] in
        if self?.settingsWindowPresentationActive == true {
          self?.settingsWindowPresentationActive = false
          self?.endWindowPresentation()
        }
      }
    } catch {
      tokMonLog("TokMon native TokMon engine failed to initialize: \(error.localizedDescription)")
      stats = TokMonStatsStore(startupError: error.localizedDescription)
      engineActor = nil
      sourceWatcher = nil
      fileWatcher = nil
      settingsWindowController = nil
    }
  }

  func start() {
    guard !started else { return }
    started = true
    tokMonLog("TokMon runtime using native TokMon engine")
    stats.startObserving()
    Task { [sourceWatcher, engineActor, stats] in
      try? await engineActor?.migrateLegacyKimiAPIKeyIfNeeded()
      await Self.migrateScannerVersion(
        engineActor: engineActor,
        defaults: UserDefaults.standard,
        currentVersion: TokMonScanner.scannerVersion
      )
      await sourceWatcher?.start()
      await stats.refreshWithScan()
    }
  }

  nonisolated internal static func migrateScannerVersion(
    engineActor: TokMonEngineActor?,
    defaults: UserDefaults,
    currentVersion: Int
  ) async {
    let storedVersion = defaults.object(forKey: "tokmonScannerVersion") as? Int
    if let storedVersion, storedVersion < currentVersion, let engineActor {
      do {
        tokMonLog("TokMon migrating scanner version \(storedVersion) -> \(currentVersion), rebuilding database")
        _ = try await engineActor.rebuildAndRescan()
        defaults.set(currentVersion, forKey: "tokmonScannerVersion")
      } catch {
        tokMonLog("TokMon scanner version migration rebuild failed: \(error.localizedDescription)")
      }
    } else if storedVersion == nil {
      defaults.set(currentVersion, forKey: "tokmonScannerVersion")
    }
  }

  func openSettings() {
    let wasVisible = settingsWindowController?.isWindowVisible == true
    if !wasVisible {
      settingsWindowPresentationActive = true
      beginWindowPresentation()
    }
    settingsWindowController?.show()
  }

  func isSettingsWindowEvent(_ event: NSEvent) -> Bool {
    settingsWindowController?.containsEvent(event) == true
  }

  func beginWindowPresentation() {
    let wasActive = NSApplication.shared.isActive
    let policyResult = NSApplication.shared.setActivationPolicy(.regular)
    windowPresentationCount += 1
    tokMonLog("TokMon beginWindowPresentation: wasActive=\(wasActive), policyResult=\(policyResult), count=\(windowPresentationCount)")
  }

  func endWindowPresentation() {
    windowPresentationCount = max(0, windowPresentationCount - 1)
    if windowPresentationCount == 0 {
      NSApplication.shared.setActivationPolicy(.accessory)
    }
    tokMonLog("TokMon endWindowPresentation: count=\(windowPresentationCount), isActive=\(NSApplication.shared.isActive)")
  }

  func quit() {
    stats.stopObserving()
    Task { [fileWatcher] in
      await fileWatcher?.stop()
    }
    NSApplication.shared.terminate(nil)
  }

  func stop() {
    stats.stopObserving()
    Task { [fileWatcher] in
      await fileWatcher?.stop()
    }
  }

  private static func makeTokMonEngine() throws -> TokMonEngine {
    let dataDir = try TokMonProjectLocator.appDataDir()
    let configStore = TokMonConfigStore(dataDir: dataDir)
    let database = try TokMonDatabase(appDataDir: dataDir)
    return TokMonEngine(configStore: configStore, database: database)
  }
}
