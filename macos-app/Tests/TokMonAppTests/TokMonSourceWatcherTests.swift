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
    onChange: { paths in
      Task {
        await expectation.fulfill(paths: paths)
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

@Test func sourceWatcherHandlesMustScanSubDirs() async throws {
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
    minimumScanInterval: .milliseconds(30),
    onChange: { paths in
      Task {
        await expectation.fulfill(paths: paths)
      }
    }
  )
  await watcher.start()

  let deepPath = tempDir.appendingPathComponent("2026/06/26/rollout.jsonl").path
  await watcher.handleEvents(
    paths: [deepPath],
    flags: [FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)]
  )

  try await Task.sleep(for: .milliseconds(200))

  #expect(await expectation.isFulfilled)
  let captured = await expectation.capturedPaths
  #expect(captured?.contains(tempDir.path) == true)

  await watcher.stop()
}

@Test func sourceWatcherHandlesKernelDropped() async throws {
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
    minimumScanInterval: .milliseconds(30),
    onChange: { paths in
      Task {
        await expectation.fulfill(paths: paths)
      }
    }
  )
  await watcher.start()

  let deepPath = tempDir.appendingPathComponent("nested/deep/file.jsonl").path
  await watcher.handleEvents(
    paths: [deepPath],
    flags: [FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped)]
  )

  try await Task.sleep(for: .milliseconds(200))

  #expect(await expectation.isFulfilled)
  let captured = await expectation.capturedPaths
  #expect(captured?.contains(tempDir.path) == true)

  await watcher.stop()
}

@Test func sourceWatcherAcceptsDirectoryEventsUnderWatchedSource() async throws {
  let tempDir = try makeTokMonTempDir()
  let subDir = tempDir.appendingPathComponent("2026/06/26", isDirectory: true)
  try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

  let config = TokMonConfig(
    port: 3388,
    sources: [
      "codex": TokMonSourceConfig(path: tempDir.path),
    ]
  )
  let expectation = Expectation()
  let watcher = TokMonSourceWatcher(
    configProvider: { config },
    debounceInterval: .milliseconds(50),
    minimumScanInterval: .milliseconds(30),
    onChange: { paths in
      Task {
        await expectation.fulfill(paths: paths)
      }
    }
  )
  await watcher.start()

  await watcher.handleEvents(
    paths: [subDir.path],
    flags: [FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)]
  )

  try await Task.sleep(for: .milliseconds(200))

  #expect(await expectation.isFulfilled)
  let captured = await expectation.capturedPaths
  #expect(captured?.contains(tempDir.path) == true)

  await watcher.stop()
}

@Test func sourceWatcherFiltersUnrelatedDirectoryEvents() async throws {
  let tempDir = try makeTokMonTempDir()
  let unrelatedDir = tempDir.appendingPathComponent("unrelated", isDirectory: true)
  try FileManager.default.createDirectory(at: unrelatedDir, withIntermediateDirectories: true)

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
    minimumScanInterval: .milliseconds(30),
    onChange: { _ in
      Task {
        await expectation.fulfill()
      }
    }
  )
  await watcher.start()

  await watcher.handleEvents(
    paths: ["/tmp/tokmon-unrelated-directory-event"],
    flags: [FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)]
  )

  try await Task.sleep(for: .milliseconds(100))

  #expect(await expectation.isFulfilled == false)

  await watcher.stop()
}

@Test func sourceWatcherSplitsCodexRootIntoSessionDirectories() async throws {
  let codexDir = try makeTokMonTempDir()
  let sessionsDir = codexDir.appendingPathComponent("sessions", isDirectory: true)
  let archivedDir = codexDir.appendingPathComponent("archived_sessions", isDirectory: true)
  try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: archivedDir, withIntermediateDirectories: true)

  let config = TokMonConfig(
    port: 3388,
    sources: [
      "codex": TokMonSourceConfig(path: codexDir.path),
    ]
  )
  let watcher = TokMonSourceWatcher(
    configProvider: { config },
    onChange: { _ in }
  )
  await watcher.start()

  let watched = await watcher.watchedPaths
  #expect(watched.contains(sessionsDir.path))
  #expect(watched.contains(archivedDir.path))
  #expect(watched.contains(codexDir.path) == false)

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
