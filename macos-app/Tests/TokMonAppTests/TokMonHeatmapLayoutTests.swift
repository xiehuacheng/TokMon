import Foundation
import Testing
@testable import TokMonApp

@Test func heatmapLayoutCreatesWeekColumnsWithMonthAndWeekdayLabels() {
  let days = [
    TokMonHeatmapDay(day: "2026-01-29", requests: 0, inputTokens: 0, outputTokens: 0, cacheCreation: 0, cacheRead: 0),
    TokMonHeatmapDay(day: "2026-01-30", requests: 1, inputTokens: 10, outputTokens: 0, cacheCreation: 0, cacheRead: 0),
    TokMonHeatmapDay(day: "2026-01-31", requests: 0, inputTokens: 0, outputTokens: 0, cacheCreation: 0, cacheRead: 0),
    TokMonHeatmapDay(day: "2026-02-01", requests: 2, inputTokens: 20, outputTokens: 0, cacheCreation: 0, cacheRead: 0),
    TokMonHeatmapDay(day: "2026-02-02", requests: 0, inputTokens: 0, outputTokens: 0, cacheCreation: 0, cacheRead: 0),
  ]

  let layout = TokMonHeatmapLayout(days: days)

  #expect(layout.weekdayLabels.map(\.label) == ["Mon", "Wed", "Fri", "Sun"])
  #expect(layout.weekdayLabels.map(\.weekdayIndex) == [0, 2, 4, 6])
  #expect(layout.weeks.count == 2)
  #expect(layout.weeks.allSatisfy { $0.cells.count == 7 })
  #expect(layout.weeks[0].cells[3]?.day == "2026-01-29")
  #expect(layout.weeks[0].cells[6]?.day == "2026-02-01")
  #expect(layout.weeks[1].cells[0]?.day == "2026-02-02")
  #expect(layout.monthLabels.map(\.label).contains("Feb"))
  #expect(layout.monthLabels.first { $0.label == "Feb" }?.weekIndex == 0)
}

@Test func heatmapLayoutMetricsFillAvailablePopoverWidth() {
  let metrics = TokMonHeatmapLayout.metrics(
    availableWidth: 320,
    weekCount: 29,
    labelWidth: 30,
    minimumCellSize: 3,
    maximumCellSize: 10,
  )

  #expect(metrics.cellSize >= 9)
  #expect(metrics.cellSize <= 10)
  #expect(metrics.labelWidth == 30)
  #expect(metrics.usedWidth > 300)
  #expect(metrics.usedWidth <= 320)
}

@Test func heatmapLayoutAvoidsDateFormatterInRedrawHotPath() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let layoutURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("TokMonHeatmapLayout.swift")
  let source = try String(contentsOf: layoutURL, encoding: .utf8)

  #expect(!source.contains("DateFormatter"))
}

@Test func heatmapValueDescriptorFollowsSelectedSeries() {
  let day = TokMonHeatmapDay(
    day: "2026-05-14",
    requests: 3,
    inputTokens: 1200,
    outputTokens: 240,
    cacheCreation: 90,
    cacheRead: 600,
  )
  let costRates = TokMonCostRates(input: 3, output: 15, cacheCreate: 3.75, cacheRead: 0.3)

  #expect(TokMonHeatmapValueDescriptor(day: day, series: .requests, costRates: costRates).helpText == "2026-05-14: 3 Requests")
  #expect(TokMonHeatmapValueDescriptor(day: day, series: .input, costRates: costRates).helpText == "2026-05-14: 1.2K Input")
  #expect(TokMonHeatmapValueDescriptor(day: day, series: .output, costRates: costRates).helpText == "2026-05-14: 240 Output")
  #expect(TokMonHeatmapValueDescriptor(day: day, series: .cache, costRates: costRates).helpText == "2026-05-14: 90 Cache Created")
  #expect(TokMonHeatmapValueDescriptor(day: day, series: .cacheHit, costRates: costRates).helpText == "2026-05-14: 600 Cache Hit")
  #expect(TokMonHeatmapValueDescriptor(day: day, series: .cacheHitRate, costRates: costRates).helpText == "2026-05-14: 33.3% Hit Rate")
  #expect(TokMonHeatmapValueDescriptor(day: day, series: .total, costRates: costRates).helpText == "2026-05-14: 2.0K Total Tokens")
  #expect(TokMonHeatmapValueDescriptor(day: day, series: .cost, costRates: costRates).helpText == "2026-05-14: $0.0077 Cost")
}
