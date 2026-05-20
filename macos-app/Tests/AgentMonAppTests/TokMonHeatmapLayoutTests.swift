import Foundation
import Testing
@testable import AgentMonApp

@Test func heatmapLayoutCreatesWeekColumnsWithMonthAndWeekdayLabels() {
  let days = [
    TokMonHeatmapDay(day: "2026-01-29", requests: 0, inputTokens: 0, outputTokens: 0, cacheCreation: 0, cacheRead: 0),
    TokMonHeatmapDay(day: "2026-01-30", requests: 1, inputTokens: 10, outputTokens: 0, cacheCreation: 0, cacheRead: 0),
    TokMonHeatmapDay(day: "2026-01-31", requests: 0, inputTokens: 0, outputTokens: 0, cacheCreation: 0, cacheRead: 0),
    TokMonHeatmapDay(day: "2026-02-01", requests: 2, inputTokens: 20, outputTokens: 0, cacheCreation: 0, cacheRead: 0),
    TokMonHeatmapDay(day: "2026-02-02", requests: 0, inputTokens: 0, outputTokens: 0, cacheCreation: 0, cacheRead: 0),
  ]

  let layout = TokMonHeatmapLayout(days: days)

  #expect(layout.weekdayLabels.map(\.label) == ["Mon", "Wed", "Fri"])
  #expect(layout.weekdayLabels.map(\.weekdayIndex) == [1, 3, 5])
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
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("TokMonHeatmapLayout.swift")
  let source = try String(contentsOf: layoutURL, encoding: .utf8)

  #expect(!source.contains("DateFormatter"))
}
