import SwiftUI

@MainActor
final class AgentMonRuntime: ObservableObject {
  static let shared = AgentMonRuntime()

  let server = AgentMonServer()
  let stats = AgentMonStatsStore()

  private var started = false

  func start() {
    guard !started else { return }
    started = true
    agentMonLog("AgentMon runtime starting service")
    server.start()
    stats.start(appURL: server.appURL)
  }

  func openDashboard() {
    start()
    NSWorkspace.shared.open(server.appURL)
  }

  func quit() {
    stats.stop()
    server.stop(waitUntilExit: true)
    NSApplication.shared.terminate(nil)
  }

  func stop() {
    stats.stop()
    server.stop(waitUntilExit: true)
  }
}
