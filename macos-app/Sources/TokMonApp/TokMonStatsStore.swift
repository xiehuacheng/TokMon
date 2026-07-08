import Foundation

struct TokMonStatsSnapshot: Sendable {
  var scanStatus: TokMonScanStatus?
  var summary: TokMonSummary?
  var previousSummary: TokMonSummary?
  var trendBuckets: [TokMonTrendBucket] = []
  var heatmapDays: [TokMonHeatmapDay] = []
  var yearHeatmapDays: [TokMonHeatmapDay] = []
  var recordsPage: TokMonRecordsPage?
  var usageSessions: [TokMonUsageSession] = []
  var selectedUsageSession: TokMonUsageSessionSelection?
  var selectedSessionRecords: [TokMonRecordRow] = []
  var dashboardState: TokMonDashboardState?
  var updatedAt: Date?

  static let empty = TokMonStatsSnapshot()
}

struct TokMonUsageSessionSelection: Equatable, Sendable {
  let source: String
  let sessionId: String

  var id: String { "\(source):\(sessionId)" }
}

struct TokMonScanStatus: Decodable, Equatable, Sendable {
  let running: Bool
  let phase: String
  let current: Int
  let total: Int
  let processed: Int
  let startedAt: String?
  let finishedAt: String?
  let error: String?
}

@MainActor
final class TokMonStatsStore: ObservableObject {
  @Published private(set) var snapshot = TokMonStatsSnapshot.empty
  @Published private(set) var isRefreshing = false
  @Published private(set) var errorMessage: String?
  @Published private(set) var kimiQuotaSnapshot: KimiQuotaSnapshot?
  private var isUpdatingDashboardRange = false

  private let nativeEngineActor: TokMonEngineActor?
  private let defaultRecordsLimit = 20
  private let defaultUsageSessionsLimit = 50
  private var recordsLimit = 20
  private var usageSessionsLimit = 50
  private var selectedUsageSession: TokMonUsageSessionSelection?

  private var isPopoverVisible = false
  private var quotaRefreshTask: Task<Void, Never>?
  private var lastRefreshedDataVersion: UInt64 = 0

  init(engine: TokMonEngine? = nil, nowProvider: @escaping @Sendable () -> Date = Date.init) {
    nativeEngineActor = engine.map { TokMonEngineActor(engine: $0) }
    self.nowProvider = nowProvider
  }

  init(engineActor: TokMonEngineActor, nowProvider: @escaping @Sendable () -> Date = Date.init) {
    nativeEngineActor = engineActor
    self.nowProvider = nowProvider
  }

  init(startupError: String, nowProvider: @escaping @Sendable () -> Date = Date.init) {
    nativeEngineActor = nil
    self.nowProvider = nowProvider
    errorMessage = startupError
  }

  private let nowProvider: @Sendable () -> Date

  var usesNativeEngine: Bool {
    nativeEngineActor != nil
  }

  var canLoadMoreRecords: Bool {
    guard let recordsPage = snapshot.recordsPage else { return false }
    return usesNativeEngine && recordsPage.rows.count < recordsPage.total
  }

  var canLoadMoreUsageSessions: Bool {
    usesNativeEngine && !snapshot.usageSessions.isEmpty && snapshot.usageSessions.count >= usageSessionsLimit
  }

  /// Retained for API compatibility. TokMon is now event-driven, so there is
  /// no periodic polling timer to start.
  func startObserving() {}

  private func shouldRefresh() async -> Bool {
    guard let nativeEngineActor else { return false }
    let currentVersion = await nativeEngineActor.databaseDataVersion()
    let isFirstRefresh = lastRefreshedDataVersion == 0
    guard isFirstRefresh || isPopoverVisible || currentVersion != lastRefreshedDataVersion else {
      return false
    }
    lastRefreshedDataVersion = currentVersion
    return true
  }

  func popoverDidAppear() {
    isPopoverVisible = true
    requestRefresh()
    startQuotaRefreshTask()
  }

  func popoverDidDisappear() {
    isPopoverVisible = false
    recordsLimit = defaultRecordsLimit
    usageSessionsLimit = defaultUsageSessionsLimit
    clearSelectedUsageSession()
    stopQuotaRefreshTask()
  }

  /// Retained for API compatibility. TokMon is now event-driven, so there is
  /// no periodic polling timer to stop.
  func stopObserving() {}

  func refresh() async {
    guard await shouldRefresh() else { return }
    await refresh(scan: false)
  }

  func refreshWithScan() async {
    guard let nativeEngineActor else { return }
    lastRefreshedDataVersion = await nativeEngineActor.databaseDataVersion()
    await refresh(scan: true)
  }

  private func refresh(scan: Bool) async {
    guard !isRefreshing, !isUpdatingDashboardRange else {
      return
    }
    isRefreshing = true
    defer { isRefreshing = false }

    do {
      if let nativeEngineActor {
        if scan {
          snapshot = try await nativeEngineActor.refreshStats(
            now: nowProvider(),
            recordsLimit: recordsLimit,
            sessionsLimit: usageSessionsLimit,
            selectedSession: selectedUsageSession,
          )
        } else {
          snapshot = try await nativeEngineActor.refreshStatsWithoutScan(
            now: nowProvider(),
            recordsLimit: recordsLimit,
            sessionsLimit: usageSessionsLimit,
            selectedSession: selectedUsageSession,
          )
        }
      }
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
      snapshot = TokMonStatsSnapshot(
        scanStatus: snapshot.scanStatus,
        summary: snapshot.summary,
        previousSummary: snapshot.previousSummary,
        trendBuckets: snapshot.trendBuckets,
        heatmapDays: snapshot.heatmapDays,
        yearHeatmapDays: snapshot.yearHeatmapDays,
        recordsPage: snapshot.recordsPage,
        usageSessions: snapshot.usageSessions,
        selectedUsageSession: snapshot.selectedUsageSession,
        selectedSessionRecords: snapshot.selectedSessionRecords,
        dashboardState: snapshot.dashboardState,
        updatedAt: snapshot.updatedAt,
      )
    }
  }

  func refreshCurrentRange() async {
    guard let nativeEngineActor, !isRefreshing, !isUpdatingDashboardRange else {
      return
    }
    isRefreshing = true
    defer { isRefreshing = false }

    do {
      snapshot = try await nativeEngineActor.refreshRangeStats(
        preserving: snapshot,
        now: nowProvider(),
      )
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func loadMoreRecords() {
    guard usesNativeEngine else { return }
    recordsLimit += 20
    requestRefresh()
  }

  func loadMoreUsageSessions() {
    guard usesNativeEngine else { return }
    usageSessionsLimit += 50
    requestRefresh()
  }

  func updateDashboardRange(_ label: String) async {
    guard let nativeEngineActor else { return }
    guard !isUpdatingDashboardRange else { return }

    isUpdatingDashboardRange = true
    defer { isUpdatingDashboardRange = false }
    do {
      snapshot = try await nativeEngineActor.updateDashboardRangeAndRefreshRangeStats(
        label: label,
        preserving: snapshot,
        now: nowProvider(),
      )
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func selectUsageSession(source: String, sessionId: String) {
    guard usesNativeEngine else { return }
    selectedUsageSession = TokMonUsageSessionSelection(source: source, sessionId: sessionId)
    snapshot.selectedUsageSession = selectedUsageSession
    snapshot.selectedSessionRecords = []
    requestSelectedUsageSessionRecords()
  }

  func clearSelectedUsageSession() {
    guard usesNativeEngine else { return }
    selectedUsageSession = nil
    snapshot.selectedUsageSession = nil
    snapshot.selectedSessionRecords = []
  }

  private func requestRefresh() {
    Task { [weak self] in
      await self?.refresh()
    }
  }

  private func requestSelectedUsageSessionRecords() {
    guard let nativeEngineActor, let selectedUsageSession else { return }
    let currentSnapshot = snapshot
    Task { [weak self] in
      do {
        let records = try await nativeEngineActor.selectedUsageSessionRecords(
          preserving: currentSnapshot,
          selectedSession: selectedUsageSession,
          now: self?.nowProvider() ?? Date(),
        )
        await MainActor.run {
          guard self?.selectedUsageSession == selectedUsageSession else { return }
          self?.snapshot.selectedSessionRecords = records
          self?.errorMessage = nil
        }
      } catch {
        await MainActor.run {
          self?.errorMessage = error.localizedDescription
        }
      }
    }
  }

  func refreshKimiQuota() async {
    guard let nativeEngineActor else { return }
    kimiQuotaSnapshot = await nativeEngineActor.refreshKimiQuota()
  }

  private func startQuotaRefreshTask() {
    stopQuotaRefreshTask()
    guard isPopoverVisible, let nativeEngineActor else { return }

    quotaRefreshTask = Task { [weak self] in
      await self?.refreshKimiQuota()
      while !Task.isCancelled {
        let interval = (try? await nativeEngineActor.loadKimiQuotaRefreshInterval()) ?? 5
        guard interval > 0 else { break }
        try? await Task.sleep(for: .seconds(interval * 60))
        guard !Task.isCancelled else { break }
        await self?.refreshKimiQuota()
      }
    }
  }

  private func stopQuotaRefreshTask() {
    quotaRefreshTask?.cancel()
    quotaRefreshTask = nil
  }
}

enum TokMonStatsSnapshotBuilder {
  static func fillTrendBuckets(
    _ buckets: [TokMonTrendBucket],
    dashboardState: TokMonDashboardState,
  ) -> [TokMonTrendBucket] {
    let interval = TokMonTrendInterval(dashboardState.interval)
    let calendar = Calendar.current
    let lookup = Dictionary(uniqueKeysWithValues: buckets.map { ($0.bucket, $0) })
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let bucketFormatter = DateFormatter()
    bucketFormatter.locale = Locale(identifier: "en_US_POSIX")
    bucketFormatter.timeZone = .current
    bucketFormatter.dateFormat = interval == .day ? "yyyy-MM-dd" : "yyyy-MM-dd HH:00"

    let rawStart: Date?
    let rawEnd: Date?
    if dashboardState.rangeLabel == TokMonRangePreset.all.label {
      rawStart = buckets.first.flatMap { bucketFormatter.date(from: $0.bucket) }
      rawEnd = buckets.last.flatMap { bucketFormatter.date(from: $0.bucket) }
    } else {
      rawStart = formatter.date(from: dashboardState.from)
      rawEnd = formatter.date(from: dashboardState.to)
    }

    guard let rawStart, let rawEnd else {
      return buckets
    }

    let start: Date
    let end: Date
    let stepComponent: Calendar.Component

    switch interval {
    case .day:
      start = calendar.startOfDay(for: rawStart)
      end = calendar.startOfDay(for: rawEnd)
      stepComponent = .day
    case .hour:
      start = calendar.dateInterval(of: .hour, for: rawStart)?.start ?? rawStart
      end = calendar.dateInterval(of: .hour, for: rawEnd)?.start ?? rawEnd
      stepComponent = .hour
    }

    var current = start
    var result: [TokMonTrendBucket] = []

    while current <= end {
      let key = trendBucketKey(for: current, interval: interval)
      result.append(lookup[key] ?? TokMonTrendBucket(bucket: key))
      guard let next = calendar.date(byAdding: stepComponent, value: 1, to: current) else { break }
      current = next
    }

    return result
  }

  static func currentDashboardState(from uiState: TokMonUIState, now: Date) -> TokMonDashboardState {
    let preset = TokMonRangePreset(label: uiState.rangeLabel)
    let range = resolvedRange(for: preset, uiState: uiState, now: now)
    return TokMonDashboardState(
      source: uiState.source,
      from: range.from,
      to: range.to,
      interval: preset.interval,
      liveMode: true,
      rangeMode: "round",
      rangeLabel: preset.label,
      rangeHours: preset.hours,
      rangeDays: preset.days,
      refreshRate: uiState.refreshRate,
      activeSeries: uiState.activeSeries,
      menuBarDisplayMode: uiState.menuBarDisplayMode,
      estimatedCost: 0,
      costRates: uiState.costRates,
      modelPricing: uiState.modelPricing,
      updatedAt: isoTimestamp(now),
    )
  }

  static func previousFilter(from dashboardState: TokMonDashboardState) -> TokMonQueryFilter? {
    let preset = TokMonRangePreset(label: dashboardState.rangeLabel)
    guard preset != .all,
          let range = previousRange(for: preset, from: dashboardState.from, to: dashboardState.to) else {
      return nil
    }
    return TokMonQueryFilter(
      from: range.from,
      to: range.to,
      source: dashboardState.source.isEmpty ? nil : dashboardState.source,
      model: nil,
    )
  }

  static func formattedTimestamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.string(from: date)
  }

  private static func resolvedRange(
    for preset: TokMonRangePreset,
    uiState: TokMonUIState,
    now: Date,
  ) -> (from: String, to: String) {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: now)
    let currentEnd = formattedDashboardBoundary(now, seconds: 59)

    switch preset {
    case .today:
      return (formattedDashboardBoundary(today, seconds: 0), currentEnd)
    case .thisWeek:
      let weekdayIndex = (calendar.component(.weekday, from: today) + 5) % 7
      let start = calendar.date(byAdding: .day, value: -weekdayIndex, to: today) ?? today
      return (formattedDashboardBoundary(start, seconds: 0), currentEnd)
    case .thisMonth:
      let start = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
      return (formattedDashboardBoundary(start, seconds: 0), currentEnd)
    case .all:
      return ("0001-01-01 00:00:00", "9999-12-31 23:59:59")
    }
  }

  private static func previousRange(
    for preset: TokMonRangePreset,
    from: String,
    to: String,
  ) -> (from: String, to: String)? {
    guard let currentFrom = parseDashboardBoundary(from),
          let currentTo = parseDashboardBoundary(to) else {
      return nil
    }

    let calendar = Calendar.current
    let component: Calendar.Component
    switch preset {
    case .today:
      component = .day
    case .thisWeek:
      component = .day
    case .thisMonth:
      component = .month
    case .all:
      return nil
    }

    let value = preset == .thisWeek ? -7 : -1
    guard let previousFrom = calendar.date(byAdding: component, value: value, to: currentFrom),
          let previousTo = calendar.date(byAdding: component, value: value, to: currentTo) else {
      return nil
    }
    return (formattedTimestamp(previousFrom), formattedTimestamp(previousTo))
  }

  private static func trendBucketKey(for date: Date, interval: TokMonTrendInterval) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = interval == .day ? "yyyy-MM-dd" : "yyyy-MM-dd HH:00"
    return formatter.string(from: date)
  }

  private static func formattedDashboardBoundary(_ date: Date, seconds: Int) -> String {
    var calendar = Calendar.current
    calendar.timeZone = .current
    let adjusted = calendar.date(
      bySettingHour: calendar.component(.hour, from: date),
      minute: calendar.component(.minute, from: date),
      second: seconds,
      of: date,
    ) ?? date

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.string(from: adjusted)
  }

  private static func parseDashboardBoundary(_ value: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.date(from: value)
  }

  private static func isoTimestamp(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
  }
}
