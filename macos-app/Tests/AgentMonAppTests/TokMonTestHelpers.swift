import Foundation

func makeTokMonTempDir() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("AgentMonTokMonTests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

func makeLocalDate(_ value: String) -> Date {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = .current
  formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
  return formatter.date(from: value)!
}
