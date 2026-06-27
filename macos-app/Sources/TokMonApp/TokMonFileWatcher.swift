import Foundation
import Dispatch

/// Watches individual files using a kernel-level vnode monitor (`DispatchSource`).
///
/// macOS FSEvents does not reliably deliver events for append-only files that are
/// kept open by the writer (Codex writes its live `rollout-*.jsonl` this way).
/// A per-file `DispatchSource` using `EVFILT_VNODE` catches those appends as they
/// happen, while still being event-driven rather than polled.
actor TokMonFileWatcher {
  private var monitors: [String: FileMonitor] = [:]
  private let onChange: @Sendable ([String]) -> Void
  private let debounce: Duration

  init(
    debounce: Duration = .seconds(1),
    onChange: @escaping @Sendable ([String]) -> Void
  ) {
    self.debounce = debounce
    self.onChange = onChange
  }

  /// Start watching `path` if it exists and is not already being watched.
  func watch(path: String) {
    guard monitors[path] == nil else { return }
    guard FileManager.default.fileExists(atPath: path) else { return }

    guard let monitor = FileMonitor(
      path: path,
      debounce: debounce,
      onChange: { [weak self] in
        Task { [weak self] in
          await self?.notifyChange(for: path)
        }
      }
    ) else {
      return
    }
    monitors[path] = monitor
  }

  /// Stop watching `path`.
  func unwatch(path: String) {
    monitors.removeValue(forKey: path)?.stop()
  }

  /// Stop watching all files.
  func stop() {
    monitors.values.forEach { $0.stop() }
    monitors.removeAll()
  }

  private func notifyChange(for path: String) {
    onChange([path])
  }
}

private final class FileMonitor: @unchecked Sendable {
  private let path: String
  private let fd: Int32
  private let source: DispatchSourceFileSystemObject
  private var pendingTask: Task<Void, Never>?

  init?(
    path: String,
    debounce: Duration,
    onChange: @escaping @Sendable () -> Void
  ) {
    self.path = path
    let fd = open(path, O_EVTONLY)
    guard fd >= 0 else { return nil }
    self.fd = fd

    self.source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fd,
      eventMask: [.write, .extend, .rename, .revoke, .delete],
      queue: DispatchQueue.global(qos: .background)
    )

    source.setEventHandler { [weak self] in
      guard let self else { return }
      self.pendingTask?.cancel()
      self.pendingTask = Task {
        try? await Task.sleep(for: debounce)
        guard !Task.isCancelled else { return }
        onChange()
      }
    }

    source.setCancelHandler { [weak self] in
      self?.pendingTask?.cancel()
      close(fd)
    }

    source.resume()
  }

  deinit {
    stop()
  }

  func stop() {
    source.cancel()
  }
}
