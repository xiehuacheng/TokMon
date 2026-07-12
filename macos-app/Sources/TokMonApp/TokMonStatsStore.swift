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
  var kimiQuotaSnapshot: KimiQuotaSnapshot? = nil

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
  @Published private(set) var isRefreshingQuota = false
  @Published private(set) var kimiAPIKeyAccounts: [KimiAPIKeyAccount] = []
  @Published private(set) var selectedKimiAPIKeyID: String? = nil
  @Published private(set) var kimiQuotaSnapshots: [String: KimiQuotaSnapshot] = [:]
  private var isUpdatingDashboardRange = false

  private let nativeEngineActor: TokMonEngineActor?
  private let configStore: TokMonConfigStore?
  private let defaultRecordsLimit = 20
  private let defaultUsageSessionsLimit = 50
  private var recordsLimit = 20
  private var usageSessionsLimit = 50
  private var selectedUsageSession: TokMonUsageSessionSelection?

  private var isPopoverVisible = false
  private var isQuotaPageVisible = false
  private var quotaRefreshTask: Task<Void, Never>?
  private var lastRefreshedDataVersion: UInt64 = 0

  init(engine: TokMonEngine? = nil, configStore: TokMonConfigStore? = nil, nowProvider: @escaping @Sendable () -> Date = Date.init) {
    nativeEngineActor = engine.map { TokMonEngineActor(engine: $0) }
    self.configStore = configStore
    self.nowProvider = nowProvider
    loadKimiState()
  }

  init(engineActor: TokMonEngineActor, configStore: TokMonConfigStore? = nil, nowProvider: @escaping @Sendable () -> Date = Date.init) {
    nativeEngineActor = engineActor
    self.configStore = configStore
    self.nowProvider = nowProvider
    loadKimiState()
  }

  init(startupError: String, configStore: TokMonConfigStore? = nil, nowProvider: @escaping @Sendable () -> Date = Date.init) {
    nativeEngineActor = nil
    self.configStore = configStore
    self.nowProvider = nowProvider
    loadKimiState()
    errorMessage = startupError
  }

  private let nowProvider: @Sendable () -> Date

  private func loadKimiState() {
    guard let configStore else { return }
    let uiState = (try? configStore.loadUIState()) ?? TokMonUIState.default
    self.kimiAPIKeyAccounts = uiState.kimiAPIKeyAccounts
    self.selectedKimiAPIKeyID = uiState.selectedKimiAPIKeyID
    var snapshots: [String: KimiQuotaSnapshot] = [:]
    for account in uiState.kimiAPIKeyAccounts {
      snapshots[account.id] = configStore.loadKimiQuotaSnapshot(keyID: account.id)
    }
    self.kimiQuotaSnapshots = snapshots
    publishKimiQuotaSnapshot()
    syncQuotaRefreshTask()
  }

  private func publishKimiQuotaSnapshot() {
    let snapshot: KimiQuotaSnapshot
    if let selectedID = selectedKimiAPIKeyID, let cached = kimiQuotaSnapshots[selectedID] {
      snapshot = cached
    } else {
      snapshot = KimiQuotaSnapshot(weekly: nil, fiveHour: nil, fetchedAt: nil, error: .noAPIKey)
    }
    if self.kimiQuotaSnapshot != snapshot {
      self.kimiQuotaSnapshot = snapshot
    }
  }

  private func saveSelectedKimiAPIKeyID(_ id: String?) {
    guard let configStore else { return }
    var uiState = (try? configStore.loadUIState()) ?? TokMonUIState.default
    uiState.selectedKimiAPIKeyID = id
    try? configStore.saveUIState(uiState)
  }

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
    return true
  }

  func popoverDidAppear() {
    isPopoverVisible = true
    requestRefresh()
    syncQuotaRefreshTask()
  }

  func popoverDidDisappear() {
    isPopoverVisible = false
    recordsLimit = defaultRecordsLimit
    usageSessionsLimit = defaultUsageSessionsLimit
    clearSelectedUsageSession()
    syncQuotaRefreshTask()
  }

  func setQuotaPageVisible(_ visible: Bool) {
    isQuotaPageVisible = visible
    syncQuotaRefreshTask()
  }

  /// Retained for API compatibility. TokMon is now event-driven, so there is
  /// no periodic polling timer to stop.
  func stopObserving() {}

  func refresh() async {
    guard await shouldRefresh() else { return }
    await refresh(scan: false)
  }

  func refreshWithScan() async {
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
        snapshot.kimiQuotaSnapshot = self.kimiQuotaSnapshot
        lastRefreshedDataVersion = await nativeEngineActor.databaseDataVersion()
      }
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
      var preserved = snapshot
      preserved.kimiQuotaSnapshot = self.kimiQuotaSnapshot
      snapshot = preserved
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
      snapshot.kimiQuotaSnapshot = self.kimiQuotaSnapshot
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
      snapshot.kimiQuotaSnapshot = self.kimiQuotaSnapshot
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func updateDashboardCustomRange(from: String, to: String) async {
    guard let nativeEngineActor else { return }
    guard !isUpdatingDashboardRange else { return }

    isUpdatingDashboardRange = true
    defer { isUpdatingDashboardRange = false }
    do {
      snapshot = try await nativeEngineActor.updateDashboardCustomRangeAndRefreshRangeStats(
        from: from,
        to: to,
        preserving: snapshot,
        now: nowProvider(),
      )
      snapshot.kimiQuotaSnapshot = self.kimiQuotaSnapshot
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

  func selectKimiAPIKey(id: String?) {
    selectedKimiAPIKeyID = id
    saveSelectedKimiAPIKeyID(id)
    publishKimiQuotaSnapshot()
    if let id, kimiQuotaSnapshots[id] == nil {
      Task { @MainActor [weak self] in
        await self?.refreshKimiQuota()
      }
    }
  }

  func addKimiAPIKey(_ key: String, label: String) async throws {
    guard let nativeEngineActor else { return }
    _ = try await nativeEngineActor.addKimiAPIKey(key, label: label)
    loadKimiState()
    await refreshKimiQuota()
  }

  func removeKimiAPIKey(id: String) async throws {
    guard let nativeEngineActor else { return }
    try await nativeEngineActor.removeKimiAPIKey(id: id)
    kimiQuotaSnapshots.removeValue(forKey: id)
    loadKimiState()
  }

  func renameKimiAPIKey(id: String, newLabel: String) async throws {
    guard let nativeEngineActor else { return }
    try await nativeEngineActor.renameKimiAPIKey(id: id, newLabel: newLabel)
    loadKimiState()
  }

  func refreshKimiQuota() async {
    guard let nativeEngineActor, !kimiAPIKeyAccounts.isEmpty else {
      tokMonLog("Kimi quota refresh: skipped, no engine or accounts")
      publishKimiQuotaSnapshot()
      return
    }
    tokMonLog("Kimi quota refresh: starting for \(kimiAPIKeyAccounts.count) account(s)")
    var apiKeys: [String: String] = [:]
    for account in kimiAPIKeyAccounts {
      apiKeys[account.id] = await nativeEngineActor.loadKimiAPIKey(id: account.id)
      tokMonLog("Kimi quota refresh: account \(account.id) key loaded? \(apiKeys[account.id] != nil)")
    }
    isRefreshingQuota = true
    defer { isRefreshingQuota = false }
    let newSnapshots = await nativeEngineActor.refreshAllKimiQuotas(apiKeys: apiKeys)
    for (id, snapshot) in newSnapshots {
      let weekly = snapshot.weekly.map { "\(Int($0.used))/\(Int($0.limit))" } ?? "nil"
      let fiveHour = snapshot.fiveHour.map { "\(Int($0.used))/\(Int($0.limit))" } ?? "nil"
      tokMonLog("Kimi quota refresh: account \(id) weekly=(\(weekly)) fiveHour=(\(fiveHour)) error=\(String(describing: snapshot.error))")
      if let existing = kimiQuotaSnapshots[id], snapshot.weekly == nil, snapshot.fiveHour == nil {
        // Fetch failed but we have cached data: preserve the cached windows and
        // surface the error/fetchedAt so the UI can show that refresh failed.
        var updated = existing
        updated.error = snapshot.error
        updated.fetchedAt = snapshot.fetchedAt ?? nowProvider()
        kimiQuotaSnapshots[id] = updated
      } else {
        kimiQuotaSnapshots[id] = snapshot
        if snapshot.weekly != nil || snapshot.fiveHour != nil {
          try? configStore?.saveKimiQuotaSnapshot(snapshot, keyID: id)
        }
      }
    }
    publishKimiQuotaSnapshot()
  }

  var effectiveKimiQuotaSnapshots: [String: KimiQuotaSnapshot] {
    var result = kimiQuotaSnapshots
    for account in kimiAPIKeyAccounts {
      guard var snapshot = result[account.id] else { continue }
      var changed = false
      if var weekly = snapshot.weekly, weekly.endAt == nil, let manual = account.weeklyEndAt {
        weekly.endAt = manual
        snapshot.weekly = weekly
        changed = true
      }
      if var fiveHour = snapshot.fiveHour, fiveHour.endAt == nil, let manual = account.fiveHourEndAt {
        fiveHour.endAt = manual
        snapshot.fiveHour = fiveHour
        changed = true
      }
      if changed {
        result[account.id] = snapshot
      }
    }
    return result
  }

  func updateKimiAPIKeyEndDate(id: String, title: String, date: Date) async {
    guard let nativeEngineActor else { return }
    let weekly: Date? = title == "Weekly" ? date : nil
    let fiveHour: Date? = title == "5-Hour" ? date : nil
    try? await nativeEngineActor.updateKimiAPIKeyEndDates(id: id, weekly: weekly, fiveHour: fiveHour)
    loadKimiState()
  }

  private func syncQuotaRefreshTask() {
    quotaRefreshTask?.cancel()
    quotaRefreshTask = nil
    guard let nativeEngineActor, !kimiAPIKeyAccounts.isEmpty else { return }

    quotaRefreshTask = Task { [weak self, weak nativeEngineActor] in
      @MainActor
      func refreshOnce() async -> Bool {
        guard let self, nativeEngineActor != nil else { return false }
        await self.refreshKimiQuota()
        return true
      }
      guard await refreshOnce() else { return }
      while !Task.isCancelled {
        guard let nativeEngineActor else { break }
        let interval = (try? await nativeEngineActor.loadKimiQuotaRefreshInterval()) ?? 5
        guard interval > 0 else { break }
        try? await Task.sleep(for: .seconds(interval * 60))
        guard !Task.isCancelled, await refreshOnce() else { break }
      }
    }
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
      let key = bucketFormatter.string(from: current)
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
      menuBarDisplayItems: uiState.menuBarDisplayItems,
      estimatedCost: 0,
      costRates: uiState.costRates,
      modelPricing: uiState.modelPricing,
      updatedAt: isoTimestamp(now),
    )
  }

  static func previousFilter(from dashboardState: TokMonDashboardState) -> TokMonQueryFilter? {
    let preset = TokMonRangePreset(label: dashboardState.rangeLabel)
    guard preset != .all,
          preset != .custom,
          let range = previousRange(for: preset, from: dashboardState.from, to: dashboardState.to) else {
      return nil
    }
    return TokMonQueryFilter(
      from: range.from,
      to: range.to,
      sources: dashboardState.source,
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
    case .custom:
      if !uiState.from.isEmpty, !uiState.to.isEmpty {
        return (uiState.from, uiState.to)
      }
      let weekdayIndex = (calendar.component(.weekday, from: today) + 5) % 7
      let start = calendar.date(byAdding: .day, value: -weekdayIndex, to: today) ?? today
      return (formattedDashboardBoundary(start, seconds: 0), currentEnd)
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
    case .all, .custom:
      return nil
    }

    let value = preset == .thisWeek ? -7 : -1
    guard let previousFrom = calendar.date(byAdding: component, value: value, to: currentFrom),
          let previousTo = calendar.date(byAdding: component, value: value, to: currentTo) else {
      return nil
    }
    return (formattedTimestamp(previousFrom), formattedTimestamp(previousTo))
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
