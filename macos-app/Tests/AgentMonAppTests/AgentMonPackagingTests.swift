import Foundation
import Testing
@testable import AgentMonApp

@Test func projectLocatorDoesNotRequireWebDashboardFiles() throws {
  let root = try makeTokMonTempDir()
  let appRoot = root.appendingPathComponent("macos-app", isDirectory: true)
  let sourceDir = appRoot
    .appendingPathComponent("Sources", isDirectory: true)
    .appendingPathComponent("AgentMonApp", isDirectory: true)
  try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
  try "// swift-tools-version: 6.0\n".write(
    to: appRoot.appendingPathComponent("Package.swift"),
    atomically: true,
    encoding: .utf8,
  )
  try "// main\n".write(to: sourceDir.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)

  #expect(AgentMonProjectLocator.looksLikeAgentMonRoot(root, fileManager: .default))
}

@Test func buildScriptDoesNotBundleWebDashboardAssets() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let scriptURL = packageDir
    .appendingPathComponent("scripts")
    .appendingPathComponent("build-app.sh")
  let script = try String(contentsOf: scriptURL, encoding: .utf8)

  #expect(!script.contains("public"))
}

@Test func liquidGlassStyleUsesNativeControlsWithoutCustomLightOverlays() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let styleURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("TokMonGlassStyle.swift")
  let style = try String(contentsOf: styleURL, encoding: .utf8)

  #expect(style.contains("buttonStyle(.glass"))
  #expect(!style.contains("TimelineView(.animation"))
  #expect(!style.contains("minimumInterval"))
  #expect(!style.contains(".onContinuousHover"))
  #expect(!style.contains("hoverLocation"))
}

@Test func liquidGlassStyleUsesDarkTranslucentHudSurfaces() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let styleURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("TokMonGlassStyle.swift")
  let style = try String(contentsOf: styleURL, encoding: .utf8)

  #expect(style.contains("let baseOpacity = 0.18 + prominence * 0.06"))
  #expect(style.contains("let highlightOpacity = 0.05 + prominence * 0.045"))
  #expect(style.contains("Color.white.opacity(0.12"))
  #expect(!style.contains("TokMonLiquidBackdrop"))
  #expect(!style.contains("NSColor(red: 0.03"))
  #expect(!style.contains("let baseOpacity = 0.24 + prominence * 0.08"))
}

@Test func liquidGlassStyleUsesCalmerIcyPaletteAndSoftSelection() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let styleURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("TokMonGlassStyle.swift")
  let style = try String(contentsOf: styleURL, encoding: .utf8)

  #expect(style.contains("NSColor(red: 0.64, green: 0.82, blue: 1.0"))
  #expect(style.contains("NSColor(red: 0.58, green: 0.78, blue: 0.66"))
  #expect(style.contains("neutralTint = Color.white.opacity(0.86)"))
  #expect(style.contains("mutedTint = Color.white.opacity(0.52)"))
  #expect(style.contains("shape.fill(isSelected ? TokMonGlass.accent.opacity(0.24)"))
  #expect(!style.contains("TokMonGlass.accent.opacity(0.78)"))
}

@Test func statusPanelShellUsesSystemMenuTranslucency() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)

  #expect(view.contains(".fill(.regularMaterial)"))
  #expect(view.contains("Color.black.opacity(0.34)"))
  #expect(view.contains("Color.white.opacity(0.12)"))
  #expect(view.contains("LinearGradient("))
  #expect(!view.contains("Color.black.opacity(0.46)"))
  #expect(!view.contains("Color.black.opacity(0.08)"))
}

@Test func statusPopoverMatchesSystemMenuHudMockupStructure() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)

  #expect(view.contains("SystemMenuPageRail("))
  #expect(view.contains("PrimaryMetricTile("))
  #expect(view.contains("AgentMonHudMetricGrid("))
  #expect(view.contains("AgentMonHudTrendCard("))
  #expect(view.contains("AgentMonHudActivityCard("))
  #expect(view.contains("AgentMonHudBreakdownCard("))
  #expect(view.contains("AgentMonHudSectionHeader("))
  #expect(view.contains("HeaderIconButton(systemName: \"gearshape\""))
  #expect(view.contains("HeaderIconButton(systemName: \"power\""))
  #expect(view.contains("columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 2)"))
  #expect(view.contains("MetricDelta"))
  #expect(view.contains("TokMonGlass.hudCardFill"))
  #expect(!view.contains(".pickerStyle(.segmented)"))
}

@Test func statusPopoverMergesTrendPageIntoTokensOverview() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)

  #expect(view.contains("case .overview:"))
  #expect(view.contains("\"Tokens\""))
  #expect(view.contains("AgentMonHudMetricGrid("))
  #expect(!view.contains("case trends"))
  #expect(!view.contains("trendsPage"))
  #expect(!view.contains("[.overview, .trends]"))
}

@Test func statusPopoverMatchesPrototypeRangeMetricAndActivityDetails() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)

  #expect(view.contains("private let prototypeRangePresets: [TokMonRangePreset] = [.today, .thisWeek, .thisMonth, .all]"))
  #expect(view.contains("ForEach(prototypeRangePresets)"))
  #expect(!view.contains("ForEach(TokMonRangePreset.allCases)"))
  #expect(view.contains("AgentMonHudMetric(series: .total"))
  #expect(view.contains("delta: metricDelta(for: .total"))
  #expect(view.contains("delta: metricDelta(for: .cost"))
  #expect(view.contains("delta: metricDelta(for: .requests"))
  #expect(view.contains("delta: metricDelta(for: .cacheHitRate"))
  #expect(view.contains("TokMonHeatmapLayout(days: days)"))
  #expect(view.contains("ForEach(layout.weeks)"))
  #expect(view.contains("ForEach(0..<7, id: \\.self)"))
  #expect(view.contains(".frame(width: cellSize, height: cellSize)"))
  #expect(view.contains("HeatmapMonthAxis("))
  #expect(view.contains("HeatmapWeekdayAxis("))
  #expect(view.contains("TrendYAxisLabels("))
  #expect(view.contains("TrendXAxisLabels("))
  #expect(!view.contains("YearHeatmapPopover"))
  #expect(!view.contains("showsYearHeatmap"))
  #expect(!view.contains(".popover(isPresented:"))
}

@Test func statusPopoverExpandsTotalTokensCardForTokenDetails() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)

  #expect(view.contains("@State private var isTotalTokensExpanded = false"))
  #expect(view.contains("tokenDetails: secondaryMetrics"))
  #expect(view.contains("TotalTokensMetricTile("))
  #expect(view.contains("TokenDetailMiniMetric("))
  #expect(view.contains("CompactMetricTile("))
  #expect(view.contains("hideDelta: true"))
  #expect(view.contains("withAnimation(.interactiveSpring"))
  #expect(view.contains("systemName: isExpanded ? \"chevron.left\" : \"chevron.right\""))
}

@Test func totalTokensNumberDoesNotResizeBetweenCollapsedAndExpandedStates() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)
  let valueText = view
    .components(separatedBy: "private struct MetricValueText: View")
    .dropFirst()
    .first?
    .components(separatedBy: "private struct AgentMonHudTrendCard")
    .first ?? ""

  #expect(view.contains("MetricValueText("))
  #expect(view.contains("private struct MetricValueText: View"))
  #expect(valueText.contains(".font(.system(size: 20, weight: .black, design: .rounded).monospacedDigit())"))
  #expect(valueText.contains(".fixedSize(horizontal: true, vertical: false)"))
  #expect(valueText.contains(".frame(height: 24, alignment: .leading)"))
  #expect(valueText.contains(".frame(minWidth: 76, alignment: .leading)"))
  #expect(!view.contains(".font(.system(size: 26, weight: .black, design: .rounded).monospacedDigit())"))
  #expect(!view.contains(".font(.system(size: 24, weight: .black, design: .rounded).monospacedDigit())"))
  #expect(valueText.contains("transaction.animation = nil"))
  #expect(!valueText.contains("minimumScaleFactor"))
}

@Test func statusPopoverKeepsTotalTokensSingleWidthUntilExpanded() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)

  #expect(view.contains("ForEach(metrics) { metric in\n            if metric.series.key == .total {"))
  #expect(view.contains("TotalTokensMetricTile(\n                metric: metric,"))
  #expect(view.contains("isExpanded: false"))
  #expect(view.contains("} else {\n              PrimaryMetricTile("))
  #expect(view.contains("if isTotalExpanded {\n        if let totalMetric {"))
  #expect(view.contains("} else {\n        LazyVGrid("))
  #expect(view.contains("TotalTokensMetricTile("))
  #expect(!view.contains("if let totalMetric {\n        TotalTokensMetricTile("))
}

@Test func requestRowsUseTwoLineTokenChipGrid() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)

  #expect(view.contains("RequestTokenChipGrid("))
  #expect(view.contains("columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)"))
  #expect(view.contains("TokenChipData(label: \"In\""))
  #expect(view.contains("TokenChipData(label: \"Out\""))
  #expect(view.contains("TokenChipData(label: \"Cache\""))
  #expect(view.contains("TokenChipData(label: \"$\""))
  #expect(!view.contains("HStack(spacing: 14) {\n        TokenChip(label: \"In\""))
}

@Test func statusPopoverKeepsUpdatedTimeOnlyInHeader() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)

  #expect(view.contains("\\(serverLine) · \\(updatedLine)"))
  #expect(!view.contains("private var footer: some View"))
  #expect(!view.contains("footer"))
}

@Test func nativeRangePresetSourcesOnlyExposeSupportedDashboardRanges() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let sourcesDir = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
  let sourceFiles = [
    "TokMonModels.swift",
    "AgentMonStatsStore.swift",
    "StatusPopoverView.swift",
    "TokMonConfigStore.swift",
  ]
  let source = try sourceFiles
    .map { try String(contentsOf: sourcesDir.appendingPathComponent($0), encoding: .utf8) }
    .joined(separator: "\n")

  #expect(source.contains("case today"))
  #expect(source.contains("case thisWeek"))
  #expect(source.contains("case thisMonth"))
  #expect(source.contains("case all"))
  #expect(!source.contains("case yesterday"))
  #expect(!source.contains("case thisYear"))
  #expect(!source.contains("\"yesterday\""))
  #expect(!source.contains("\"thisYear\""))
  #expect(!source.contains("\"Yesterday\""))
  #expect(!source.contains("\"This Year\""))
  #expect(!source.contains("\"Yday\""))
  #expect(!source.contains("\"Year\""))
  #expect(!source.contains("\"90D\""))
}

@Test func statusPopoverMetricDeltaUsesPreviousSummaryInsteadOfTrendBuckets() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)

  #expect(view.contains("stats.snapshot.previousSummary"))
  #expect(!view.contains("buckets.dropLast().last"))
}

@Test func statusPopoverUsesPrototypeScaledTypographyAndControls() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)

  #expect(view.contains("VStack(alignment: .leading, spacing: 10)"))
  #expect(view.contains(".frame(width: 30, height: 30)"))
  #expect(view.contains(".frame(width: 28, height: 28)"))
  #expect(view.contains(".font(.system(size: 14, weight: .heavy, design: .rounded))"))
  #expect(view.contains(".font(.system(size: 20, weight: .black, design: .rounded).monospacedDigit())"))
  #expect(view.contains(".frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)"))
  #expect(view.contains(".frame(maxWidth: .infinity, minHeight: 26)"))
  #expect(view.contains(".frame(maxWidth: .infinity, minHeight: 22)"))
  #expect(view.contains(".frame(height: 60)"))
}

@Test func statusPopoverUsesDenseHeatmapCellsAndCompactCards() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)

  #expect(view.contains("TokMonHeatmapLayout.metrics("))
  #expect(view.contains("maximumCellSize: 14"))
  #expect(view.contains(".frame(width: cellSize, height: cellSize)"))
  #expect(view.contains(".padding(9)"))
  #expect(view.contains("RoundedRectangle(cornerRadius: 16, style: .continuous)"))
  #expect(!view.contains(".frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)"))
}

@Test func statusPopoverHeatmapUsesLargerCellsAndNonWrappingWeekdayAxis() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let queryURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("TokMonQueryStore.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)
  let query = try String(contentsOf: queryURL, encoding: .utf8)

  #expect(query.contains("days: Int = 140"))
  #expect(view.contains("selectedSeries.key"))
  #expect(view.contains("maximumCellSize: 14"))
  #expect(view.contains("labelWidth: 30"))
  #expect(view.contains(".frame(width: 26"))
  #expect(view.contains(".lineLimit(1)"))
  #expect(view.contains(".minimumScaleFactor(0.75)"))
  #expect(view.contains(".frame(height: 118)"))
}

@Test func statusPopoverTrendAxisUsesDenseLabelsAndTodayTimeOnly() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)

  #expect(view.contains("ChartGrid(horizontalLines: 3, verticalLines: 6)"))
  #expect(view.contains("axisTickIndices"))
  #expect(view.contains("isSingleHourlyDay"))
  #expect(view.contains("return String(label[timeStart..<timeEnd])"))
  #expect(view.contains("let horizontalInset: CGFloat = 4"))
  #expect(view.contains("max(size.width - horizontalInset * 2, 1)"))
}

@Test func settingsWindowOnlyExposesNativeMaintenanceActions() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let settingsURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("TokMonSettingsWindow.swift")
  let settings = try String(contentsOf: settingsURL, encoding: .utf8)

  #expect(!settings.contains("SettingsSection(\"Defaults\")"))
  #expect(!settings.contains("FieldRow(\"Range\")"))
  #expect(!settings.contains("FieldRow(\"Metric\")"))
  #expect(!settings.contains("private let metrics"))
  #expect(settings.contains("SettingsSection(\"Maintenance\")"))
  #expect(settings.contains("Button(\"Scan Now\")"))
  #expect(settings.contains("Button(\"Rebuild Database\")"))
}

@Test func settingsWindowUsesPopoverHudGlassStyling() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let settingsURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("TokMonSettingsWindow.swift")
  let settings = try String(contentsOf: settingsURL, encoding: .utf8)

  #expect(settings.contains("SettingsWindowShell()"))
  #expect(settings.contains("TokMonGlass.hudCardFill"))
  #expect(settings.contains("TokMonGlass.hudCardStroke"))
  #expect(settings.contains(".preferredColorScheme(.dark)"))
  #expect(settings.contains(".font(.system(size: 15, weight: .heavy, design: .rounded))"))
}

@Test func statsObservationAvoidsDuplicateImmediateRefreshWhenPanelOpens() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let storeURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("AgentMonStatsStore.swift")
  let mainURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("main.swift")
  let store = try String(contentsOf: storeURL, encoding: .utf8)
  let main = try String(contentsOf: mainURL, encoding: .utf8)

  let observingSetup = store.components(separatedBy: "func stopObserving()").first ?? store
  #expect(!observingSetup.contains("requestRefresh()"))
  #expect(main.contains("await runtime.stats.refresh()"))
}

@Test func statsObservationScansAndRefreshesAllDataForTimerTicks() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let storeURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("AgentMonStatsStore.swift")
  let store = try String(contentsOf: storeURL, encoding: .utf8)

  let observingSetup = store.components(separatedBy: "func stopObserving()").first ?? store
  #expect(observingSetup.contains("await self.refresh()"))
  #expect(!observingSetup.contains("await self.refreshCurrentRange()"))
  #expect(store.contains("func refreshCurrentRange() async"))
  #expect(store.contains("nativeEngineActor.refreshStats("))
}

@Test func statusPanelShellSticksToTopWithoutPointerArrow() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)

  #expect(!view.contains("PointerShape"))
  #expect(!view.contains(".padding(.top, 20)"))
  #expect(!view.contains("private struct PointerShape"))
}

@Test func statusPanelUsesCompactMockupLikeCanvas() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let mainURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("main.swift")
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let main = try String(contentsOf: mainURL, encoding: .utf8)
  let view = try String(contentsOf: viewURL, encoding: .utf8)

  #expect(main.contains("NSSize(width: 360, height: 740)"))
  #expect(main.contains("let panelSize = NSSize(width: 360, height: 740)"))
  #expect(main.contains("let y = screenFrame.maxY - panelSize.height"))
  #expect(!main.contains("let y = buttonFrameInScreen.minY - panelSize.height"))
  #expect(view.contains(".frame(width: 360, height: 740)"))
  #expect(view.contains(".padding(11)"))
}

@Test func statusPopoverScrollViewCatchesWheelEventsAcrossTransparentGaps() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)

  #expect(view.contains(".frame(maxWidth: .infinity, minHeight: 740, alignment: .topLeading)"))
  #expect(view.contains(".contentShape(Rectangle())"))
  #expect(view.contains("Color.black.opacity(0.001)"))
}

@Test func trendChartUsesSmoothedCurveInsteadOfStraightSegments() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)

  #expect(view.contains("smoothedTrendPath(points:"))
  #expect(view.contains("smoothedTrendFill(points:"))
  #expect(view.contains("path.addCurve(to:"))
  #expect(!view.contains("path.addLine(to: point)"))
}

@Test func statusPanelUsesTransparentBorderlessWindowInsteadOfNSPopover() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let mainURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("main.swift")
  let main = try String(contentsOf: mainURL, encoding: .utf8)

  #expect(!main.contains("NSPopover()"))
  #expect(main.contains("AgentMonStatusPanel("))
  #expect(main.contains("styleMask: [.borderless]"))
  #expect(main.contains("panel.isOpaque = false"))
  #expect(main.contains("panel.backgroundColor = .clear"))
  #expect(main.contains("panel.hasShadow = false"))
  #expect(main.contains("panel.level = .statusBar"))
  #expect(main.contains("AgentMonStatusPanel"))
  #expect(main.contains("override var canBecomeKey: Bool { true }"))
  #expect(!main.contains("func windowDidResignKey"))
  #expect(main.contains("closeStatusPanel"))
  #expect(main.contains("showStatusPanel"))
}

@Test func statusPanelOpeningAvoidsImmediateCloseOnActivationChanges() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let mainURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("main.swift")
  let main = try String(contentsOf: mainURL, encoding: .utf8)

  #expect(main.contains("panel.hidesOnDeactivate = false"))
  #expect(main.contains("panel.orderFrontRegardless()"))
  #expect(main.contains("panel.makeKeyAndOrderFront(nil)"))
  #expect(main.contains("DispatchQueue.main.async { [weak self] in"))
  #expect(!main.contains("NSApplication.shared.activate(ignoringOtherApps: true)"))
}

@Test func statusPanelContentKeepsTransparentHostingLayers() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let mainURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("AgentMonApp")
    .appendingPathComponent("main.swift")
  let main = try String(contentsOf: mainURL, encoding: .utf8)

  #expect(main.contains("window.isOpaque = false"))
  #expect(main.contains("window.backgroundColor = .clear"))
  #expect(main.contains("view.layer?.backgroundColor = NSColor.clear.cgColor"))
}
