import Foundation
import CoreServices

actor TokMonSourceWatcher {
  private var stream: FSEventStreamRef?
  private(set) var watchedPaths: [String] = []
  private let onChange: @Sendable ([String]) -> Void
  private let configProvider: @Sendable () -> TokMonConfig
  private var pendingChangeTask: Task<Void, Never>?
  private let debounceInterval: Duration
  private let minimumScanInterval: Duration
  private var lastScanTime: Date?
  private var retainedContext: Unmanaged<TokMonSourceWatcherContext>?
  private let fsEventQueue = DispatchQueue(
    label: "com.tokmon.fsevents",
    qos: .background,
    attributes: [],
    autoreleaseFrequency: .workItem
  )

  init(
    configProvider: @escaping @Sendable () -> TokMonConfig,
    debounceInterval: Duration = .seconds(3),
    minimumScanInterval: Duration = .seconds(3),
    onChange: @escaping @Sendable ([String]) -> Void
  ) {
    self.configProvider = configProvider
    self.debounceInterval = debounceInterval
    self.minimumScanInterval = minimumScanInterval
    self.onChange = onChange
  }

  func start() {
    stop()
    let config = configProvider()
    let watchPaths = config.sources
      .sorted { $0.key < $1.key }
      .flatMap { sourceKey, source in
        expandedWatchPaths(for: sourceKey, path: source.path)
      }
      .filter { FileManager.default.fileExists(atPath: $0) }
    guard !watchPaths.isEmpty else {
      tokMonLog("TokMonSourceWatcher: no valid source paths to watch")
      return
    }
    watchedPaths = watchPaths
    tokMonLog("TokMonSourceWatcher: starting watch on \(watchPaths)")

    let context = TokMonSourceWatcherContext(watcher: self)
    let retained = Unmanaged.passRetained(context)
    retainedContext = retained

    var fsContext = FSEventStreamContext(
      version: 0,
      info: retained.toOpaque(),
      retain: nil,
      release: nil,
      copyDescription: nil
    )

    let callback: FSEventStreamCallback = { _, clientCallBackInfo, numEvents, eventPaths, eventFlags, _ in
      guard let info = clientCallBackInfo else { return }
      guard let watcher = Unmanaged<TokMonSourceWatcherContext>.fromOpaque(info).takeUnretainedValue().watcher else { return }

      let cfArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
      var pathArray: [String] = []
      for index in 0..<CFArrayGetCount(cfArray) {
        let rawValue = CFArrayGetValueAtIndex(cfArray, index)
        let cfString = Unmanaged<CFString>.fromOpaque(rawValue!).takeUnretainedValue()
        pathArray.append(cfString as String)
      }
      var flagArray: [FSEventStreamEventFlags] = []
      for index in 0..<numEvents {
        flagArray.append(eventFlags[index])
      }

      Task {
        await watcher.handleEvents(paths: pathArray, flags: flagArray)
      }
    }

    let streamRef = withUnsafeMutablePointer(to: &fsContext) { contextPtr in
      FSEventStreamCreate(
        kCFAllocatorDefault,
        callback,
        contextPtr,
        watchPaths as CFArray,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
        1.0,
        FSEventStreamCreateFlags(
          kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagUseCFTypes
            | kFSEventStreamCreateFlagWatchRoot
        )
      )
    }

    guard let streamRef else {
      retained.release()
      retainedContext = nil
      tokMonLog("TokMonSourceWatcher: failed to create FSEventStream")
      return
    }

    stream = streamRef
    FSEventStreamSetDispatchQueue(streamRef, fsEventQueue)
    FSEventStreamStart(streamRef)
  }

  func stop() {
    if let stream {
      FSEventStreamStop(stream)
      FSEventStreamInvalidate(stream)
      FSEventStreamRelease(stream)
    }
    stream = nil
    watchedPaths = []
    pendingChangeTask?.cancel()
    pendingChangeTask = nil
    retainedContext?.release()
    retainedContext = nil
  }

  func restart() {
    tokMonLog("TokMonSourceWatcher: restarting due to config change")
    start()
  }

  package func handleEvents(
    paths: [String],
    flags: [FSEventStreamEventFlags]
  ) {
    let irrelevantFlags = FSEventStreamEventFlags(
      kFSEventStreamEventFlagItemFinderInfoMod
        | kFSEventStreamEventFlagItemInodeMetaMod
        | kFSEventStreamEventFlagItemXattrMod
        | kFSEventStreamEventFlagItemChangeOwner
    )
    let coarseFlags = FSEventStreamEventFlags(
      kFSEventStreamEventFlagMustScanSubDirs
        | kFSEventStreamEventFlagKernelDropped
        | kFSEventStreamEventFlagUserDropped
    )
    let relevantFlags = coarseFlags
      | FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)
      | FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)
      | FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed)
      | FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved)

    var changedPaths = Set<String>()
    for (path, flag) in zip(paths, flags) {
      guard (flag & relevantFlags) != 0 else { continue }
      if (flag & irrelevantFlags) != 0 && (flag & relevantFlags) == 0 { continue }

      // FSEvents may coalesce events for deep directories into MustScanSubDirs
      // or KernelDropped. Treat those as "something changed under this root".
      if (flag & coarseFlags) != 0 {
        if let root = watchedRoot(containing: path) {
          changedPaths.insert(root)
        }
        continue
      }

      let filename = (path as NSString).lastPathComponent.lowercased()
      let ext = (path as NSString).pathExtension.lowercased()
      guard ext == "jsonl" || filename == "opencode.db" || filename.hasPrefix("opencode.db-") else {
        // A directory-level event under a watched root (without coarse flags)
        // should still trigger a scan of that root.
        if let root = watchedRoot(containing: path), isDirectory(path) {
          changedPaths.insert(root)
        }
        continue
      }
      changedPaths.insert(path)
    }
    guard !changedPaths.isEmpty else { return }

    pendingChangeTask?.cancel()

    let changedArray = Array(changedPaths)
    if let lastScan = lastScanTime,
       Date().timeIntervalSince(lastScan) >= minimumScanIntervalComponents {
      lastScanTime = Date()
      tokMonLog("TokMonSourceWatcher: triggering immediate scan after \(changedArray.count) change(s)")
      onChange(changedArray)
      return
    }

    pendingChangeTask = Task { [weak self] in
      try? await Task.sleep(for: self?.debounceInterval ?? .seconds(3))
      guard let self, !Task.isCancelled else { return }
      await self.setLastScanTime(Date())
      tokMonLog("TokMonSourceWatcher: triggering scan after \(changedArray.count) change(s)")
      self.onChange(changedArray)
    }
  }

  private func setLastScanTime(_ date: Date) {
    lastScanTime = date
  }

  private var minimumScanIntervalComponents: TimeInterval {
    var seconds: Double = 0
    seconds += Double(minimumScanInterval.components.seconds)
    seconds += Double(minimumScanInterval.components.attoseconds) / 1e18
    return seconds
  }

  private func expandedWatchPaths(for sourceKey: String, path: String) -> [String] {
    let expanded = expandedPath(path)
    guard sourceKey == "codex" else {
      return [expanded]
    }

    let url = URL(fileURLWithPath: expanded)
    var watchPaths: [String] = []
    let sessionsDir = url.appendingPathComponent("sessions", isDirectory: true)
    if FileManager.default.fileExists(atPath: sessionsDir.path) {
      watchPaths.append(sessionsDir.path)
    }
    let archivedDir = url.appendingPathComponent("archived_sessions", isDirectory: true)
    if FileManager.default.fileExists(atPath: archivedDir.path) {
      watchPaths.append(archivedDir.path)
    }
    if watchPaths.isEmpty {
      watchPaths.append(expanded)
    }
    return watchPaths
  }

  private func watchedRoot(containing path: String) -> String? {
    watchedPaths
      .filter { path == $0 || path.hasPrefix($0 + "/") }
      .max(by: { $0.count < $1.count })
  }

  private func isDirectory(_ path: String) -> Bool {
    var isDir: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
  }
}

private final class TokMonSourceWatcherContext {
  weak var watcher: TokMonSourceWatcher?

  init(watcher: TokMonSourceWatcher) {
    self.watcher = watcher
  }
}

private func expandedPath(_ path: String) -> String {
  if path == "~" {
    return FileManager.default.homeDirectoryForCurrentUser.path
  }
  if path.hasPrefix("~/") {
    return FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(String(path.dropFirst(2)))
      .path
  }
  return path
}
