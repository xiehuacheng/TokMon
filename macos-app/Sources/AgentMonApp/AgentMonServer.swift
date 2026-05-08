import Foundation
import Darwin

enum AgentMonServerPhase: Equatable {
  case idle
  case starting
  case running(attachedToExistingServer: Bool)
  case failed(String)

  var isRunning: Bool {
    if case .running = self { return true }
    return false
  }
}

@MainActor
final class AgentMonServer: ObservableObject {
  @Published private(set) var phase: AgentMonServerPhase = .idle
  @Published private(set) var detail = "Preparing AgentMon..."
  @Published private(set) var logOutput = ""

  let appURL = URL(string: "http://127.0.0.1:3388")!

  private var process: Process?
  private var outputPipe: Pipe?
  private var startTask: Task<Void, Never>?
  private var isStopping = false

  func start() {
    if startTask != nil || phase.isRunning { return }

    startTask = Task { [weak self] in
      await self?.startServer()
    }
  }

  func restart() {
    startTask?.cancel()
    startTask = nil
    stop(waitUntilExit: true)
    detail = "Restarting AgentMon server..."
    start()
  }

  func stop(waitUntilExit: Bool = false) {
    startTask?.cancel()
    startTask = nil

    guard let process, process.isRunning else {
      self.process = nil
      phase = .idle
      detail = "AgentMon server stopped."
      return
    }

    isStopping = true
    detail = "Stopping AgentMon server..."
    process.terminate()

    if waitUntilExit {
      let deadline = Date().addingTimeInterval(2)
      while process.isRunning && Date() < deadline {
        usleep(100_000)
      }
      if process.isRunning {
        kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
      }
      cleanupServerProcess()
      phase = .idle
      detail = "AgentMon server stopped."
      isStopping = false
      return
    }

    Task { [weak self, process] in
      try? await Task.sleep(nanoseconds: 2_000_000_000)
      if process.isRunning {
        kill(process.processIdentifier, SIGKILL)
      }
      await MainActor.run {
        self?.phase = .idle
        self?.detail = "AgentMon server stopped."
        self?.isStopping = false
      }
    }
  }

  private func startServer() async {
    agentMonLog("AgentMon service start requested")
    phase = .starting
    detail = "Checking local service port..."

    if await isHealthy() {
      phase = .running(attachedToExistingServer: true)
      detail = "Connected to existing AgentMon server."
      agentMonLog("AgentMon connected to existing server at \(appURL.absoluteString)")
      startTask = nil
      return
    }

    do {
      let projectRoot = try AgentMonProjectLocator.projectRoot()
      let dataDir = try AgentMonProjectLocator.appDataDir()
      detail = "Starting AgentMon..."
      agentMonLog("AgentMon server root: \(projectRoot.path)")
      agentMonLog("AgentMon data dir: \(dataDir.path)")
      process = try launchServer(projectRoot: projectRoot, dataDir: dataDir)
    } catch {
      fail("Unable to launch AgentMon: \(error.localizedDescription)")
      return
    }

    do {
      try await waitForHealth(timeoutSeconds: 15)
      phase = .running(attachedToExistingServer: false)
      detail = "AgentMon is running."
    } catch {
      stop()
      fail(error.localizedDescription)
    }

    startTask = nil
  }

  private func launchServer(projectRoot: URL, dataDir: URL) throws -> Process {
    let process = Process()
    let nodeURL = try nodeExecutableURL(projectRoot: projectRoot)
    agentMonLog("AgentMon using node: \(nodeURL.path)")
    process.executableURL = nodeURL
    process.arguments = ["--import", "tsx/esm", "src/index.ts"]
    process.currentDirectoryURL = projectRoot
    process.environment = launchEnvironment(projectRoot: projectRoot, dataDir: dataDir)

    let pipe = Pipe()
    outputPipe = pipe
    process.standardOutput = pipe
    process.standardError = pipe
    pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
      agentMonLog(text.trimmingCharacters(in: .newlines))
      Task { @MainActor in
        self?.appendLog(text)
      }
    }

    process.terminationHandler = { [weak self] terminatedProcess in
      Task { @MainActor in
        self?.handleServerExit(terminatedProcess)
      }
    }

    try process.run()
    return process
  }

  private func nodeExecutableURL(projectRoot: URL) throws -> URL {
    if let bundledNodeURL = AgentMonProjectLocator.bundledNodeURL(projectRoot: projectRoot) {
      if nodeCanLoadProjectModules(bundledNodeURL, projectRoot: projectRoot) {
        return bundledNodeURL
      }

      throw AgentMonAppError(
        "Bundled Node cannot load AgentMon's native modules. Rebuild the standalone app with matching dependencies.",
      )
    }

    let fileManager = FileManager.default
    let environment = ProcessInfo.processInfo.environment
    let pathEntries = (environment["PATH"] ?? "")
      .split(separator: ":")
      .map(String.init)

    let home = fileManager.homeDirectoryForCurrentUser
    let staticCandidates = [
      "/opt/homebrew/bin/node",
      "/usr/local/bin/node",
      "/usr/bin/node",
    ]

    var candidates = nvmNodeCandidates(home: home)
    candidates.append(contentsOf: pathEntries.map { URL(fileURLWithPath: $0).appendingPathComponent("node").path })
    candidates.append(contentsOf: staticCandidates)

    let executableCandidates = unique(candidates).filter {
      fileManager.isExecutableFile(atPath: $0)
    }

    for path in executableCandidates {
      let nodeURL = URL(fileURLWithPath: path)
      if nodeCanLoadProjectModules(nodeURL, projectRoot: projectRoot) {
        return nodeURL
      }
    }

    if !executableCandidates.isEmpty {
      throw AgentMonAppError(
        "Found node, but none of the candidates can load this project's native better-sqlite3 module. Run npm rebuild with the Node version you want AgentMon to use.",
      )
    }

    throw AgentMonAppError("Could not find node. Install Node.js or add it to PATH before launching AgentMon.")
  }

  private func unique(_ paths: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []

    for path in paths {
      guard !seen.contains(path) else { continue }
      seen.insert(path)
      result.append(path)
    }

    return result
  }

  private func nodeCanLoadProjectModules(_ nodeURL: URL, projectRoot: URL) -> Bool {
    let process = Process()
    process.executableURL = nodeURL
    process.arguments = [
      "-e",
      "const Database = require('better-sqlite3'); const db = new Database(':memory:'); db.close();",
    ]
    process.currentDirectoryURL = projectRoot
    process.environment = launchEnvironment(projectRoot: projectRoot, dataDir: nil)
    process.standardOutput = Pipe()
    process.standardError = Pipe()

    do {
      try process.run()
      process.waitUntilExit()
      return process.terminationStatus == 0
    } catch {
      return false
    }
  }

  private func nvmNodeCandidates(home: URL) -> [String] {
    let versionsRoot = home
      .appendingPathComponent(".nvm")
      .appendingPathComponent("versions")
      .appendingPathComponent("node")

    guard let entries = try? FileManager.default.contentsOfDirectory(
      at: versionsRoot,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles],
    ) else {
      return []
    }

    return entries
      .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
      .map { $0.appendingPathComponent("bin/node").path }
  }

  private func launchEnvironment(projectRoot: URL, dataDir: URL?) -> [String: String] {
    var environment = ProcessInfo.processInfo.environment
    let existingPath = environment["PATH"] ?? ""
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    var commonNodePaths: [String] = []

    if let bundledNodeURL = AgentMonProjectLocator.bundledNodeURL(projectRoot: projectRoot) {
      commonNodePaths.append(bundledNodeURL.deletingLastPathComponent().path)
    }

    commonNodePaths.append(contentsOf: [
      "/opt/homebrew/bin",
      "/usr/local/bin",
      "/usr/bin",
      projectRoot.appendingPathComponent("node_modules/.bin").path,
    ])

    commonNodePaths.append(contentsOf: nvmNodeCandidates(home: URL(fileURLWithPath: home)).map {
      URL(fileURLWithPath: $0).deletingLastPathComponent().path
    })

    environment["PATH"] = (commonNodePaths + [existingPath])
      .filter { !$0.isEmpty }
      .joined(separator: ":")
    if let dataDir {
      environment["AGENTMON_DATA_DIR"] = dataDir.path
    }
    environment.removeValue(forKey: "FORCE_COLOR")
    return environment
  }

  private func isHealthy() async -> Bool {
    var request = URLRequest(url: appURL.appendingPathComponent("api/scan-status"))
    request.timeoutInterval = 1.5

    do {
      let (_, response) = try await URLSession.shared.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else { return false }
      return (200..<500).contains(httpResponse.statusCode)
    } catch {
      return false
    }
  }

  private func waitForHealth(timeoutSeconds: TimeInterval) async throws {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while Date() < deadline {
      if Task.isCancelled { return }
      if await isHealthy() { return }
      try await Task.sleep(nanoseconds: 250_000_000)
    }
    throw AgentMonAppError("Timed out waiting for AgentMon at \(appURL.absoluteString).")
  }

  private func appendLog(_ text: String) {
    logOutput += text
    if logOutput.count > 6000 {
      logOutput = String(logOutput.suffix(6000))
    }
  }

  private func handleServerExit(_ terminatedProcess: Process) {
    guard process === terminatedProcess else { return }
    cleanupServerProcess()

    if isStopping {
      phase = .idle
      detail = "AgentMon server stopped."
      isStopping = false
      return
    }

    if !phase.isRunning { return }

    let code = terminatedProcess.terminationStatus
    fail("AgentMon server exited with code \(code).")
  }

  private func cleanupServerProcess() {
    outputPipe?.fileHandleForReading.readabilityHandler = nil
    outputPipe = nil
    process = nil
  }

  private func fail(_ message: String) {
    agentMonLog("AgentMon service error: \(message)")
    phase = .failed(message)
    detail = message
    startTask = nil
  }
}

struct AgentMonAppError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? {
    message
  }
}
