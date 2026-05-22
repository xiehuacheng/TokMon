import Foundation
import Testing
@testable import TokMonApp

@Test func projectLocatorMigratesLegacyAgentMonSupportDirectory() throws {
  let supportRoot = try makeTokMonTempDir()
  let legacyDir = supportRoot.appendingPathComponent("AgentMon", isDirectory: true)
  try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
  try "legacy".write(to: legacyDir.appendingPathComponent("tokmon-ui-state.json"), atomically: true, encoding: .utf8)
  try Data("db".utf8).write(to: legacyDir.appendingPathComponent("agentmon.db"))

  let dataDir = try TokMonProjectLocator.appDataDir(in: supportRoot, fileManager: .default)

  #expect(dataDir.lastPathComponent == "TokMon")
  #expect(!FileManager.default.fileExists(atPath: legacyDir.path))
  #expect(FileManager.default.fileExists(atPath: dataDir.appendingPathComponent("tokmon-ui-state.json").path))
  #expect(FileManager.default.fileExists(atPath: dataDir.appendingPathComponent("tokmon.db").path))
  #expect(!FileManager.default.fileExists(atPath: dataDir.appendingPathComponent("agentmon.db").path))
}

@Test func projectLocatorMigratesLegacyAgentMonDatabaseSidecars() throws {
  let supportRoot = try makeTokMonTempDir()
  let legacyDir = supportRoot.appendingPathComponent("AgentMon", isDirectory: true)
  try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
  try Data("db".utf8).write(to: legacyDir.appendingPathComponent("agentmon.db"))
  try Data("wal".utf8).write(to: legacyDir.appendingPathComponent("agentmon.db-wal"))
  try Data("shm".utf8).write(to: legacyDir.appendingPathComponent("agentmon.db-shm"))

  let dataDir = try TokMonProjectLocator.appDataDir(in: supportRoot, fileManager: .default)

  #expect(FileManager.default.fileExists(atPath: dataDir.appendingPathComponent("tokmon.db").path))
  #expect(FileManager.default.fileExists(atPath: dataDir.appendingPathComponent("tokmon.db-wal").path))
  #expect(FileManager.default.fileExists(atPath: dataDir.appendingPathComponent("tokmon.db-shm").path))
  #expect(!FileManager.default.fileExists(atPath: dataDir.appendingPathComponent("agentmon.db-wal").path))
  #expect(!FileManager.default.fileExists(atPath: dataDir.appendingPathComponent("agentmon.db-shm").path))
}

@Test func projectLocatorDoesNotOverwriteExistingTokMonSupportDirectory() throws {
  let supportRoot = try makeTokMonTempDir()
  let legacyDir = supportRoot.appendingPathComponent("AgentMon", isDirectory: true)
  let tokMonDir = supportRoot.appendingPathComponent("TokMon", isDirectory: true)
  try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: tokMonDir, withIntermediateDirectories: true)
  try "legacy".write(to: legacyDir.appendingPathComponent("tokmon-ui-state.json"), atomically: true, encoding: .utf8)
  try "current".write(to: tokMonDir.appendingPathComponent("tokmon-ui-state.json"), atomically: true, encoding: .utf8)

  let dataDir = try TokMonProjectLocator.appDataDir(in: supportRoot, fileManager: .default)

  let currentText = try String(contentsOf: dataDir.appendingPathComponent("tokmon-ui-state.json"), encoding: .utf8)
  #expect(dataDir == tokMonDir)
  #expect(currentText == "current")
  #expect(FileManager.default.fileExists(atPath: legacyDir.path))
}
