import Foundation
import CoreServices

actor TokMonSourceWatcher {
  private var stream: FSEventStreamRef?
  private var watchedPaths: [String] = []
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
    minimumScanInterval: Duration = .seconds(5),
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
    let paths = config.sources.values
      .map { expandedPath($0.path) }
      .filter { FileManager.default.fileExists(atPath: $0) }
    guard !paths.isEmpty else {
      tokMonLog("TokMonSourceWatcher: no valid source paths to watch")
      return
    }
    watchedPaths = paths
    tokMonLog("TokMonSourceWatcher: starting watch on \(paths)")

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
        paths as CFArray,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
        5.0,
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
    let relevantFlags = FSEventStreamEventFlags(
      kFSEventStreamEventFlagItemCreated
        | kFSEventStreamEventFlagItemModified
        | kFSEventStreamEventFlagItemRenamed
        | kFSEventStreamEventFlagItemRemoved
    )

    var changedPaths: [String] = []
    for (path, flag) in zip(paths, flags) {
      guard (flag & relevantFlags) != 0 else { continue }
      if (flag & irrelevantFlags) != 0 && (flag & relevantFlags) == 0 { continue }

      let filename = (path as NSString).lastPathComponent.lowercased()
      let ext = (path as NSString).pathExtension.lowercased()
      guard ext == "jsonl" || filename == "opencode.db" || filename.hasPrefix("opencode.db-") else {
        continue
      }
      changedPaths.append(path)
    }
    guard !changedPaths.isEmpty else { return }

    pendingChangeTask?.cancel()

    if let lastScan = lastScanTime,
       Date().timeIntervalSince(lastScan) >= minimumScanIntervalComponents {
      lastScanTime = Date()
      tokMonLog("TokMonSourceWatcher: triggering immediate scan after \(changedPaths.count) change(s)")
      onChange(changedPaths)
      return
    }

    pendingChangeTask = Task { [weak self] in
      try? await Task.sleep(for: self?.debounceInterval ?? .seconds(3))
      guard let self, !Task.isCancelled else { return }
      await self.setLastScanTime(Date())
      tokMonLog("TokMonSourceWatcher: triggering scan after \(changedPaths.count) change(s)")
      self.onChange(changedPaths)
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
