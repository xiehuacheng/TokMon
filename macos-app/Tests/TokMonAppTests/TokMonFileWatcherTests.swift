import Foundation
import Testing
@testable import TokMonApp

@Test func fileWatcherNotifiesOnAppend() async throws {
  let tempDir = try makeTokMonTempDir()
  let fileURL = tempDir.appendingPathComponent("live.jsonl")
  FileManager.default.createFile(atPath: fileURL.path, contents: Data())

  let expectation = Expectation()
  let watcher = TokMonFileWatcher(
    debounce: .milliseconds(100),
    onChange: { paths in
      Task {
        await expectation.fulfill(paths: paths)
      }
    }
  )

  await watcher.watch(path: fileURL.path)

  let handle = try FileHandle(forWritingTo: fileURL)
  try handle.write(contentsOf: "{\"event\":1}\n".data(using: .utf8)!)
  try handle.seekToEnd()
  try handle.write(contentsOf: "{\"event\":2}\n".data(using: .utf8)!)
  try handle.close()

  try await Task.sleep(for: .milliseconds(400))

  #expect(await expectation.isFulfilled)
  let captured = await expectation.capturedPaths
  #expect(captured?.contains(fileURL.path) == true)

  await watcher.stop()
}

@Test func fileWatcherDoesNotNotifyAfterUnwatch() async throws {
  let tempDir = try makeTokMonTempDir()
  let fileURL = tempDir.appendingPathComponent("live.jsonl")
  FileManager.default.createFile(atPath: fileURL.path, contents: Data())

  let expectation = Expectation()
  let watcher = TokMonFileWatcher(
    debounce: .milliseconds(100),
    onChange: { _ in
      Task {
        await expectation.fulfill()
      }
    }
  )

  await watcher.watch(path: fileURL.path)
  await watcher.unwatch(path: fileURL.path)

  let handle = try FileHandle(forWritingTo: fileURL)
  try handle.write(contentsOf: "{\"event\":1}\n".data(using: .utf8)!)
  try handle.close()

  try await Task.sleep(for: .milliseconds(300))

  #expect(await expectation.isFulfilled == false)

  await watcher.stop()
}

@Test func fileWatcherIgnoresMissingFiles() async throws {
  let expectation = Expectation()
  let watcher = TokMonFileWatcher(
    debounce: .milliseconds(100),
    onChange: { _ in
      Task {
        await expectation.fulfill()
      }
    }
  )

  await watcher.watch(path: "/nonexistent/tokmon-file.jsonl")

  #expect(await expectation.isFulfilled == false)

  await watcher.stop()
}

private actor Expectation {
  private var fulfilled = false
  private var lastPaths: [String]?

  func fulfill(paths: [String] = []) {
    fulfilled = true
    lastPaths = paths
  }

  var isFulfilled: Bool {
    fulfilled
  }

  var capturedPaths: [String]? {
    lastPaths
  }
}
