import Foundation

enum AgentMonProjectLocator {
  static func projectRoot() throws -> URL {
    let fileManager = FileManager.default
    var candidates: [URL] = []

    if let bundledRoot = bundledServerRoot(fileManager: fileManager) {
      return bundledRoot
    }

    if let explicitRoot = ProcessInfo.processInfo.environment["AGENTMON_PROJECT_ROOT"], !explicitRoot.isEmpty {
      candidates.append(URL(fileURLWithPath: explicitRoot))
    }

    candidates.append(URL(fileURLWithPath: fileManager.currentDirectoryPath))
    candidates.append(Bundle.main.bundleURL)

    for base in candidates {
      if let root = rootByWalkingUp(from: base, fileManager: fileManager) {
        return root
      }
    }

    throw AgentMonAppError(
      "Could not find the AgentMon project root. Set AGENTMON_PROJECT_ROOT to the repository path.",
    )
  }

  static func bundledNodeURL(projectRoot: URL) -> URL? {
    let nodeURL = projectRoot
      .deletingLastPathComponent()
      .appendingPathComponent("Node")
      .appendingPathComponent("bin")
      .appendingPathComponent("node")

    return FileManager.default.isExecutableFile(atPath: nodeURL.path) ? nodeURL : nil
  }

  static func appDataDir() throws -> URL {
    let fileManager = FileManager.default
    let supportRoot = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true,
    )
    let dataDir = supportRoot.appendingPathComponent("AgentMon", isDirectory: true)
    try fileManager.createDirectory(at: dataDir, withIntermediateDirectories: true)
    return dataDir
  }

  private static func bundledServerRoot(fileManager: FileManager) -> URL? {
    guard let resourcesURL = Bundle.main.resourceURL else { return nil }
    let serverRoot = resourcesURL.appendingPathComponent("AgentMonServer", isDirectory: true)
    return looksLikeAgentMonRoot(serverRoot, fileManager: fileManager) ? serverRoot : nil
  }

  private static func rootByWalkingUp(from startURL: URL, fileManager: FileManager) -> URL? {
    var current = startURL.standardizedFileURL

    for _ in 0..<8 {
      if looksLikeAgentMonRoot(current, fileManager: fileManager) {
        return current
      }

      let parent = current.deletingLastPathComponent()
      if parent.path == current.path { break }
      current = parent
    }

    return nil
  }

  private static func looksLikeAgentMonRoot(_ url: URL, fileManager: FileManager) -> Bool {
    let requiredPaths = [
      "src/index.ts",
      "public/index.html",
      "package.json",
    ]

    return requiredPaths.allSatisfy { relativePath in
      fileManager.fileExists(atPath: url.appendingPathComponent(relativePath).path)
    }
  }
}
