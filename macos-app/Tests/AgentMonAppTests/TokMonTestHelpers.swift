import Foundation

func makeTokMonTempDir() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("AgentMonTokMonTests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}
