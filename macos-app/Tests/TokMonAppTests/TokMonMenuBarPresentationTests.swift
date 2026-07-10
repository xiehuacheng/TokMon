import Foundation
import Testing
@testable import TokMonApp

@Test func menuBarPresentationFormatsEmptyItemsAsNoTitle() {
  let snapshot = makeMenuBarSnapshot(totalTokens: 42_800, requests: 128, cost: 1.28)

  #expect(TokMonMenuBarPresentation.title(for: .empty, snapshot: snapshot) == nil)
}

@Test func menuBarPresentationFormatsCoreMetrics() {
  let snapshot = makeMenuBarSnapshot(totalTokens: 42_800, requests: 128, cost: 1.28)

  #expect(TokMonMenuBarPresentation.title(for: TokMonMenuBarItems(totalTokens: true), snapshot: snapshot) == "42.8K")
  #expect(TokMonMenuBarPresentation.title(for: TokMonMenuBarItems(requests: true), snapshot: snapshot) == "128")
  #expect(TokMonMenuBarPresentation.title(for: TokMonMenuBarItems(estimatedCost: true), snapshot: snapshot) == "$1.28")
}

@Test func menuBarPresentationConcatenatesMultipleItems() {
  let snapshot = makeMenuBarSnapshot(totalTokens: 42_800, requests: 128, cost: 1.28)

  let items = TokMonMenuBarItems(totalTokens: true, requests: true)
  #expect(TokMonMenuBarPresentation.title(for: items, snapshot: snapshot) == "42.8K · 128")
}

@Test func menuBarPresentationShowsKimiWeeklyQuota() {
  var snapshot = makeMenuBarSnapshot(totalTokens: 42_800, requests: 128, cost: 1.28)
  snapshot.kimiQuotaSnapshot = KimiQuotaSnapshot(
    weekly: KimiQuotaWindow(label: "Weekly", used: 42, limit: 100, remaining: 58, percentUsed: 42, resetAt: nil, countdown: nil),
    fiveHour: nil,
    fetchedAt: nil,
    error: nil
  )

  #expect(TokMonMenuBarPresentation.title(for: TokMonMenuBarItems(kimiWeeklyQuota: true), snapshot: snapshot) == "7d 42%")
}

@Test func menuBarPresentationShowsKimiFiveHourQuota() {
  var snapshot = makeMenuBarSnapshot(totalTokens: 42_800, requests: 128, cost: 1.28)
  snapshot.kimiQuotaSnapshot = KimiQuotaSnapshot(
    weekly: nil,
    fiveHour: KimiQuotaWindow(label: "5-Hour", used: 17, limit: 100, remaining: 83, percentUsed: 17, resetAt: nil, countdown: nil),
    fetchedAt: nil,
    error: nil
  )

  #expect(TokMonMenuBarPresentation.title(for: TokMonMenuBarItems(kimiFiveHourQuota: true), snapshot: snapshot) == "5h 17%")
}

@Test func menuBarPresentationShowsBothKimiQuotaWindows() {
  var snapshot = makeMenuBarSnapshot(totalTokens: 42_800, requests: 128, cost: 1.28)
  snapshot.kimiQuotaSnapshot = KimiQuotaSnapshot(
    weekly: KimiQuotaWindow(label: "Weekly", used: 42, limit: 100, remaining: 58, percentUsed: 42, resetAt: nil, countdown: nil),
    fiveHour: KimiQuotaWindow(label: "5-Hour", used: 17, limit: 100, remaining: 83, percentUsed: 17, resetAt: nil, countdown: nil),
    fetchedAt: nil,
    error: nil
  )

  let items = TokMonMenuBarItems(kimiWeeklyQuota: true, kimiFiveHourQuota: true)
  #expect(TokMonMenuBarPresentation.title(for: items, snapshot: snapshot) == "7d 42% · 5h 17%")
}

@Test func menuBarPresentationBackwardCompatibleWithLegacyKimiQuota() {
  var snapshot = makeMenuBarSnapshot(totalTokens: 42_800, requests: 128, cost: 1.28)
  snapshot.kimiQuotaSnapshot = KimiQuotaSnapshot(
    weekly: KimiQuotaWindow(label: "Weekly", used: 50, limit: 100, remaining: 50, percentUsed: 50, resetAt: nil, countdown: nil),
    fiveHour: nil,
    fetchedAt: nil,
    error: nil
  )

  #expect(TokMonMenuBarPresentation.title(for: TokMonMenuBarItems(kimiQuota: true), snapshot: snapshot) == "7d 50%")
}

@Test func menuBarPresentationOmitsKimiQuotaWhenMissing() {
  let snapshot = makeMenuBarSnapshot(totalTokens: 42_800, requests: 128, cost: 1.28)

  #expect(TokMonMenuBarPresentation.title(for: TokMonMenuBarItems(kimiWeeklyQuota: true), snapshot: snapshot) == nil)
  #expect(TokMonMenuBarPresentation.title(for: TokMonMenuBarItems(kimiFiveHourQuota: true), snapshot: snapshot) == nil)
}

@Test func menuBarPresentationReturnsNilWhenSummaryIsMissing() {
  let snapshot = TokMonStatsSnapshot(
    scanStatus: nil,
    summary: nil,
    previousSummary: nil,
    trendBuckets: [],
    heatmapDays: [],
    yearHeatmapDays: [],
    recordsPage: nil,
    usageSessions: [],
    selectedUsageSession: nil,
    selectedSessionRecords: [],
    dashboardState: nil,
    updatedAt: nil,
  )

  #expect(TokMonMenuBarPresentation.title(for: TokMonMenuBarItems(totalTokens: true), snapshot: snapshot) == nil)
  #expect(TokMonMenuBarPresentation.title(for: TokMonMenuBarItems(estimatedCost: true), snapshot: snapshot) == nil)
  #expect(TokMonMenuBarPresentation.title(for: TokMonMenuBarItems(requests: true), snapshot: snapshot) == nil)
}

private func makeMenuBarSnapshot(totalTokens: Int, requests: Int, cost: Double) -> TokMonStatsSnapshot {
  let input = totalTokens
  let rates = TokMonCostRates(input: cost * 1_000_000 / Double(max(input, 1)), output: 0, cacheCreate: 0, cacheRead: 0)
  let summary = TokMonSummary(
    total: TokMonTotals(
      totalRequests: requests,
      totalInput: input,
      totalOutput: 0,
      totalCacheCreation: 0,
      totalCacheRead: 0,
      totalReasoning: 0,
    ),
    bySource: [],
    byModel: [
      TokMonModelTotals(
        model: "gpt-test",
        source: "codex",
        requests: requests,
        inputTokens: input,
        outputTokens: 0,
        cacheCreation: 0,
        cacheRead: 0,
      ),
    ],
  )
  let dashboardState = TokMonDashboardState(
    source: "",
    from: "",
    to: "",
    interval: "day",
    liveMode: true,
    rangeMode: "round",
    rangeLabel: "thisWeek",
    rangeHours: nil,
    rangeDays: nil,
    refreshRate: 3000,
    activeSeries: "total",
    menuBarDisplayItems: TokMonMenuBarItems(estimatedCost: true),
    estimatedCost: cost,
    costRates: rates,
    modelPricing: [:],
    updatedAt: "2026-05-22 12:00:00",
  )
  return TokMonStatsSnapshot(
    scanStatus: nil,
    summary: summary,
    previousSummary: nil,
    trendBuckets: [],
    heatmapDays: [],
    yearHeatmapDays: [],
    recordsPage: nil,
    usageSessions: [],
    selectedUsageSession: nil,
    selectedSessionRecords: [],
    dashboardState: dashboardState,
    updatedAt: nil,
  )
}
