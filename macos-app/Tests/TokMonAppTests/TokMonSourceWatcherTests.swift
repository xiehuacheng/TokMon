import Foundation
import Testing
@testable import TokMonApp

@Test func sourceWatcherStartsAndStopsWithoutCrashing() async throws {
  let tempDir = try makeTokMonTempDir()
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "claude-code": TokMonSourceConfig(path: tempDir.path),
    ]
  )
  let watcher = TokMonSourceWatcher(
    configProvider: { config },
    onChange: { _ in }
  )

  await watcher.start()
  await watcher.stop()
}

@Test func sourceWatcherFiltersMissingPaths() async throws {
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "claude-code": TokMonSourceConfig(path: "/nonexistent/path/for/tokmon-test"),
    ]
  )
  let watcher = TokMonSourceWatcher(
    configProvider: { config },
    onChange: { _ in }
  )

  await watcher.start()
  await watcher.stop()
}

@Test func sourceWatcherRestartUpdatesWatchedPaths() async throws {
  let firstDir = try makeTokMonTempDir()
  let secondDir = try makeTokMonTempDir()

  let firstConfig = TokMonConfig(
    port: 3388,
    sources: [
      "claude-code": TokMonSourceConfig(path: firstDir.path),
    ]
  )
  let secondConfig = TokMonConfig(
    port: 3388,
    sources: [
      "claude-code": TokMonSourceConfig(path: secondDir.path),
    ]
  )
  let provider = ConfigProvider(initial: firstConfig)
  let watcher = TokMonSourceWatcher(
    configProvider: { provider.config },
    onChange: { _ in }
  )

  await watcher.start()

  provider.update(secondConfig)
  await watcher.restart()

  await watcher.stop()
}

@Test func sourceWatcherDebouncesFileEvents() async throws {
  let tempDir = try makeTokMonTempDir()
  let config = TokMonConfig(
    port: 3388,
    sources: [
      "claude-code": TokMonSourceConfig(path: tempDir.path),
    ]
  )
  let expectation = Expectation()
  let watcher = TokMonSourceWatcher(
    configProvider: { config },
    debounceInterval: .milliseconds(50),
    onChange: { _ in
      Task {
        await expectation.fulfill()
      }
    }
  )

  await watcher.handleEvents(
    paths: [tempDir.appendingPathComponent("test.jsonl").path],
    flags: [FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)]
  )

  try await Task.sleep(for: .milliseconds(200))

  #expect(await expectation.isFulfilled)

  await watcher.stop()
}

private actor Expectation {
  private var fulfilled = false

  func fulfill() {
    fulfilled = true
  }

  var isFulfilled: Bool {
    fulfilled
  }
}

private final class ConfigProvider: @unchecked Sendable {
  private var stored: TokMonConfig

  init(initial: TokMonConfig) {
    stored = initial
  }

  var config: TokMonConfig { stored }

  func update(_ config: TokMonConfig) {
    stored = config
  }
}
