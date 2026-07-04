import Foundation

func JSONLine(_ value: [String: Any]) throws -> String {
  let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
  return String(decoding: data, as: UTF8.self) + "\n"
}

func writeJSONL(_ values: [[String: Any]], to url: URL) throws {
  let content = try values.map(JSONLine).joined(separator: "\n") + "\n"
  try content.write(to: url, atomically: true, encoding: .utf8)
}

func makeTokMonTempDir() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("TokMonTokMonTests-\(UUID().uuidString)", isDirectory: true)
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
