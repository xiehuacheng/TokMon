import Foundation
import Testing
@testable import TokMonApp

@Test func menuBarPresentationFormatsIconOnlyAsNoTitle() {
  let snapshot = makeMenuBarSnapshot(totalTokens: 42_800, requests: 128, cost: 1.28)

  #expect(TokMonMenuBarPresentation.title(for: .iconOnly, snapshot: snapshot) == nil)
}

@Test func menuBarPresentationFormatsCoreMetrics() {
  let snapshot = makeMenuBarSnapshot(totalTokens: 42_800, requests: 128, cost: 1.28)

  #expect(TokMonMenuBarPresentation.title(for: .totalTokens, snapshot: snapshot) == "42.8K")
  #expect(TokMonMenuBarPresentation.title(for: .requests, snapshot: snapshot) == "128")
  #expect(TokMonMenuBarPresentation.title(for: .estimatedCost, snapshot: snapshot) == "$1.28")
}

@Test func menuBarPresentationUsesPlaceholderWhenSummaryIsMissing() {
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

  #expect(TokMonMenuBarPresentation.title(for: .totalTokens, snapshot: snapshot) == "-")
  #expect(TokMonMenuBarPresentation.title(for: .estimatedCost, snapshot: snapshot) == "-")
  #expect(TokMonMenuBarPresentation.title(for: .requests, snapshot: snapshot) == "-")
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
    menuBarDisplayMode: .estimatedCost,
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
