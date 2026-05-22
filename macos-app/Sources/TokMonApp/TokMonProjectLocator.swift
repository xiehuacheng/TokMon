import Foundation

enum TokMonProjectLocator {
  static func projectRoot() throws -> URL {
    let fileManager = FileManager.default
    var candidates: [URL] = []

    if let explicitRoot = ProcessInfo.processInfo.environment["TOKMON_PROJECT_ROOT"], !explicitRoot.isEmpty {
      candidates.append(URL(fileURLWithPath: explicitRoot))
    }

    candidates.append(URL(fileURLWithPath: fileManager.currentDirectoryPath))
    candidates.append(Bundle.main.bundleURL)

    for base in candidates {
      if let root = rootByWalkingUp(from: base, fileManager: fileManager) {
        return root
      }
    }

    throw TokMonAppError(
      "Could not find the TokMon project root. Set TOKMON_PROJECT_ROOT to the repository path.",
    )
  }

  static func appDataDir() throws -> URL {
    let fileManager = FileManager.default
    let supportRoot = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true,
    )
    return try appDataDir(in: supportRoot, fileManager: fileManager)
  }

  static func appDataDir(in supportRoot: URL, fileManager: FileManager = .default) throws -> URL {
    let dataDir = supportRoot.appendingPathComponent("TokMon", isDirectory: true)
    let legacyDir = supportRoot.appendingPathComponent("AgentMon", isDirectory: true)

    if fileManager.fileExists(atPath: dataDir.path) {
      try migrateLegacyDatabaseFile(in: dataDir, fileManager: fileManager)
      return dataDir
    }

    if fileManager.fileExists(atPath: legacyDir.path) {
      do {
        try fileManager.moveItem(at: legacyDir, to: dataDir)
      } catch {
        throw TokMonAppError("Could not migrate AgentMon data to TokMon: \(error.localizedDescription)")
      }
      try migrateLegacyDatabaseFile(in: dataDir, fileManager: fileManager)
      return dataDir
    }

    try fileManager.createDirectory(at: dataDir, withIntermediateDirectories: true)
    return dataDir
  }

  private static func migrateLegacyDatabaseFile(in dataDir: URL, fileManager: FileManager) throws {
    try migrateLegacyDatabaseComponent(
      from: dataDir.appendingPathComponent("agentmon.db"),
      to: dataDir.appendingPathComponent("tokmon.db"),
      fileManager: fileManager,
    )
    try migrateLegacyDatabaseComponent(
      from: dataDir.appendingPathComponent("agentmon.db-wal"),
      to: dataDir.appendingPathComponent("tokmon.db-wal"),
      fileManager: fileManager,
    )
    try migrateLegacyDatabaseComponent(
      from: dataDir.appendingPathComponent("agentmon.db-shm"),
      to: dataDir.appendingPathComponent("tokmon.db-shm"),
      fileManager: fileManager,
    )
  }

  private static func migrateLegacyDatabaseComponent(from legacyURL: URL, to tokMonURL: URL, fileManager: FileManager) throws {
    guard fileManager.fileExists(atPath: legacyURL.path),
          !fileManager.fileExists(atPath: tokMonURL.path) else {
      return
    }
    try fileManager.moveItem(at: legacyURL, to: tokMonURL)
  }

  private static func rootByWalkingUp(from startURL: URL, fileManager: FileManager) -> URL? {
    var current = startURL.standardizedFileURL

    for _ in 0..<8 {
      if looksLikeTokMonRoot(current, fileManager: fileManager) {
        return current
      }

      let parent = current.deletingLastPathComponent()
      if parent.path == current.path { break }
      current = parent
    }

    return nil
  }

  static func looksLikeTokMonRoot(_ url: URL, fileManager: FileManager) -> Bool {
    let requiredPaths = [
      "macos-app/Package.swift",
      "macos-app/Sources/TokMonApp/main.swift",
    ]

    return requiredPaths.allSatisfy { relativePath in
      fileManager.fileExists(atPath: url.appendingPathComponent(relativePath).path)
    }
  }
}
