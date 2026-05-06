import Foundation

func agentMonLog(_ message: String) {
  let line = "\(Date()) \(message)\n"
  let url = URL(fileURLWithPath: "/tmp/agentmon-macos.log")

  if let data = line.data(using: .utf8) {
    if FileManager.default.fileExists(atPath: url.path),
       let handle = try? FileHandle(forWritingTo: url) {
      _ = try? handle.seekToEnd()
      try? handle.write(contentsOf: data)
      try? handle.close()
    } else {
      try? data.write(to: url)
    }
  }

  print(message)
}
