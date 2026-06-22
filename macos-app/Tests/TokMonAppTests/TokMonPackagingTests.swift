import Foundation
import Testing
@testable import TokMonApp

@Test func packageAndBuildScriptsUseTokMonNames() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let package = try String(contentsOf: packageDir.appendingPathComponent("Package.swift"), encoding: .utf8)
  let script = try String(contentsOf: packageDir.appendingPathComponent("scripts/build-app.sh"), encoding: .utf8)

  #expect(package.contains("name: \"TokMonMac\""))
  #expect(package.contains(".executable(name: \"TokMon\", targets: [\"TokMonApp\"])"))
  #expect(package.contains("name: \"TokMonApp\""))
  #expect(package.contains("path: \"Sources/TokMonApp\""))
  #expect(package.contains("name: \"TokMonAppTests\""))
  #expect(package.contains("dependencies: [\"TokMonApp\"]"))
  #expect(package.contains("path: \"Tests/TokMonAppTests\""))
  #expect(script.contains("APP_NAME=\"TokMon\""))
  #expect(script.contains("Assets/TokMon.icns"))
  #expect(!script.contains("APP_NAME=\"AgentMon\""))
}

@Test func readmeUsesCurrentTokMonScreenshots() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let repoRoot = packageDir.deletingLastPathComponent()
  let readme = try String(contentsOf: repoRoot.appendingPathComponent("README.md"), encoding: .utf8)

  #expect(readme.contains("docs/images/tokmon-sessions-list.png"))
  #expect(readme.contains("docs/images/tokmon-session-drilldown.png"))
  #expect(!readme.contains("docs/images/tokmon-status-tokens.png"))
  #expect(!readme.contains("docs/images/tokmon-status-sessions.png"))
  #expect(!readme.contains("docs/images/tokmon-status-popover.png"))
  #expect(FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent("docs/images/tokmon-sessions-list.png").path))
  #expect(FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent("docs/images/tokmon-session-drilldown.png").path))
}

@Test func infoPlistUsesTokMonBundleMetadata() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let plist = try String(contentsOf: packageDir.appendingPathComponent("Packaging/Info.plist"), encoding: .utf8)

  #expect(plist.contains("<string>TokMon</string>"))
  #expect(plist.contains("<string>TokMon.icns</string>"))
  #expect(plist.contains("<string>local.tokmon.app</string>"))
  #expect(plist.contains("<string>0.2.0</string>"))
  #expect(plist.contains("<string>3</string>"))
  #expect(!plist.contains("<string>AgentMon</string>"))
  #expect(!plist.contains("<string>AgentMon.icns</string>"))
}

@Test func projectLocatorDoesNotRequireWebDashboardFiles() throws {
  let root = try makeTokMonTempDir()
  let appRoot = root.appendingPathComponent("macos-app", isDirectory: true)
  let sourceDir = appRoot
    .appendingPathComponent("Sources", isDirectory: true)
    .appendingPathComponent("TokMonApp", isDirectory: true)
  try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
  try "// swift-tools-version: 6.0\n".write(
    to: appRoot.appendingPathComponent("Package.swift"),
    atomically: true,
    encoding: .utf8,
  )
  try "// main\n".write(to: sourceDir.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)

  #expect(TokMonProjectLocator.looksLikeTokMonRoot(root, fileManager: .default))
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

@Test func statusItemUsesCustomTokMonMenuBarIcon() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let sourcesDir = packageDir.appendingPathComponent("Sources").appendingPathComponent("TokMonApp")
  let main = try String(contentsOf: sourcesDir.appendingPathComponent("main.swift"), encoding: .utf8)
  let icon = try String(contentsOf: sourcesDir.appendingPathComponent("TokMonMenuBarIcon.swift"), encoding: .utf8)

  #expect(main.contains("TokMonMenuBarIcon.makeImage()"))
  #expect(main.contains("NSStatusItem.variableLength"))
  #expect(main.contains("monospacedDigitSystemFont(ofSize: 12, weight: .semibold)"))
  #expect(!main.contains("chart.line.uptrend.xyaxis"))
  #expect(icon.contains("rotate(byDegrees: 90)"))
  #expect(icon.contains("image.isTemplate = true"))
  #expect(!icon.contains("strokeCurve("))
  #expect(!icon.contains("curve(to:"))
}

@Test func statusItemUpdatesTitleFromMenuBarPresentation() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let main = try String(
    contentsOf: packageDir.appendingPathComponent("Sources/TokMonApp/main.swift"),
    encoding: .utf8,
  )

  #expect(main.contains("import Combine"))
  #expect(main.contains("private var cancellables = Set<AnyCancellable>()"))
  #expect(main.contains("TokMonMenuBarPresentation.title("))
  #expect(main.contains("statusItem.button?.title = title ?? \"\""))
  #expect(main.contains("statusItem.button?.imagePosition = title == nil ? .imageOnly : .imageLeft"))
}

@Test func settingsWindowIncludesMenuBarDisplayPicker() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let settings = try String(
    contentsOf: packageDir.appendingPathComponent("Sources/TokMonApp/TokMonSettingsWindow.swift"),
    encoding: .utf8,
  )

  #expect(settings.contains("SettingsSection(\"Menu Bar\")"))
  #expect(settings.contains("Picker(\"Menu Bar Display\", selection: $store.draft.menuBarDisplayMode)"))
  #expect(settings.contains("ForEach(TokMonMenuBarDisplayMode.allCases)"))
}

@Test func userFacingTextUsesTokMonName() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let sourcesDir = packageDir.appendingPathComponent("Sources/TokMonApp")
  let popover = try String(contentsOf: sourcesDir.appendingPathComponent("StatusPopoverView.swift"), encoding: .utf8)
  let settings = try String(contentsOf: sourcesDir.appendingPathComponent("TokMonSettingsWindow.swift"), encoding: .utf8)
  let runtime = try String(contentsOf: sourcesDir.appendingPathComponent("TokMonRuntime.swift"), encoding: .utf8)

  #expect(popover.contains("Text(\"TokMon\")"))
  #expect(popover.contains("Text(\"T\")"))
  #expect(popover.contains("help: \"Quit TokMon\""))
  #expect(settings.contains("Text(\"TokMon Settings\")"))
  #expect(settings.contains("Text(\"TokenMonitor\")"))
  #expect(runtime.contains("TokMon native TokMon engine failed to initialize"))
  #expect(!popover.contains("Text(\"A\")"))
  #expect(!popover.contains("Text(\"AgentMon\")"))
  #expect(!settings.contains("Text(\"Native token monitoring\")"))
}

@Test func liquidGlassStyleUsesNativeControlsWithoutCustomLightOverlays() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let styleURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("TokMonGlassStyle.swift")
  let style = try String(contentsOf: styleURL, encoding: .utf8)

  #expect(style.contains("buttonStyle(.glass"))
  #expect(!style.contains("TimelineView(.animation"))
  #expect(!style.contains("minimumInterval"))
  #expect(!style.contains(".onContinuousHover"))
  #expect(!style.contains("hoverLocation"))
}

@Test func liquidGlassStyleUsesLightTranslucentHudSurfaces() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let styleURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("TokMonGlassStyle.swift")
  let style = try String(contentsOf: styleURL, encoding: .utf8)

  #expect(style.contains(".glassEffect"))
  #expect(!style.contains("struct TokMonGlassSurface"))
  #expect(!style.contains("func tokMonShell"))
  #expect(!style.contains("func tokMonCard"))
  #expect(!style.contains("func tokMonControl"))
  #expect(!style.contains("TokMonLiquidBackdrop"))
  #expect(!style.contains("NSColor(red: 0.03"))
  #expect(!style.contains("Color.black.opacity(baseOpacity)"))
  #expect(!style.contains("let baseOpacity = 0.16 + prominence * 0.06"))
  #expect(!style.contains("Color.white.opacity(baseOpacity)"))
}

@Test func liquidGlassStyleUsesCalmerIcyPaletteAndSoftSelection() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let styleURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("TokMonGlassStyle.swift")
  let style = try String(contentsOf: styleURL, encoding: .utf8)

  #expect(style.contains("NSColor(red: 0.482, green: 0.380, blue: 1.0"))
  #expect(style.contains("NSColor(red: 1.0, green: 0.176, blue: 0.573"))
  #expect(!style.contains("TokMonGlass.accent.opacity(0.78)"))
}

@Test func statusPanelShellUsesLightLiquidGlassTranslucency() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)

  #expect(view.contains(".fill(.ultraThinMaterial)"))
  #expect(view.contains("TokMonGlass.glassEdge"))
  #expect(!view.contains("Color.black.opacity(0.34)"))
  #expect(!view.contains(".preferredColorScheme(.dark)"))
}

@Test func statusPopoverMatchesSystemMenuHudMockupStructure() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)

  #expect(view.contains("SystemMenuPageRail("))
  #expect(view.contains("PrimaryMetricTile("))
  #expect(view.contains("TokMonHudMetricGrid("))
  #expect(view.contains("TokMonHudTrendCard("))
  #expect(view.contains("TokMonHudActivityCard("))
  #expect(view.contains("TokMonHudBreakdownCard("))
  #expect(view.contains("TokMonHudSectionHeader("))
  #expect(view.contains("HeaderIconButton(systemName: \"gearshape\""))
  #expect(view.contains("HeaderIconButton(systemName: \"power\""))
  #expect(view.contains("columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 2)"))
  #expect(view.contains("MetricDelta"))
  #expect(view.contains(".thinMaterial"))
  #expect(!view.contains(".pickerStyle(.segmented)"))
}

@Test func statusPopoverMergesTrendPageIntoTokensOverview() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)

  #expect(view.contains("case .overview:"))
  #expect(view.contains("\"Tokens\""))
  #expect(view.contains("TokMonHudMetricGrid("))
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
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)

  #expect(view.contains("private let prototypeRangePresets: [TokMonRangePreset] = [.today, .thisWeek, .thisMonth, .all]"))
  #expect(view.contains("ForEach(prototypeRangePresets)"))
  #expect(!view.contains("ForEach(TokMonRangePreset.allCases)"))
  #expect(view.contains("TokMonHudMetric(series: .total"))
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

@Test func statusPopoverUsesDistinctSourceColors() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)
  let colorFunction = view
    .components(separatedBy: "private func colorForSource(_ source: String) -> Color")
    .dropFirst()
    .first?
    .components(separatedBy: "private func heatmapColor")
    .first ?? ""

  #expect(colorFunction.contains("case \"claude-code\":\n      TokMonGlass.accent"))
  #expect(colorFunction.contains("case \"codex\":\n      TokMonGlass.success"))
  #expect(colorFunction.contains("case \"opencode\":\n      TokMonGlass.warning"))
  #expect(colorFunction.contains("case \"qwen-code\":\n      TokMonGlass.danger"))
  #expect(!colorFunction.contains("case \"qwen-code\":\n      TokMonGlass.warning"))
}

@Test func statusPopoverExpandsTotalTokensCardForTokenDetails() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)

  #expect(view.contains("@State private var isTotalTokensExpanded = false"))
  #expect(view.contains("tokenDetails: secondaryMetrics"))
  #expect(view.contains("TotalTokensMetricTile("))
  #expect(view.contains("TokenDetailMiniMetric("))
  #expect(view.contains("CompactMetricTile("))
  #expect(view.contains("hideDelta: true"))
  #expect(view.contains("withAnimation(TokMonMotion.smoothSpring)"))
  #expect(view.contains("systemName: isExpanded ? \"chevron.left\" : \"chevron.right\""))
}

@Test func statusPopoverUsesCentralSmoothMotionTokens() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let motionURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("TokMonMotion.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)
  let motion = try String(contentsOf: motionURL, encoding: .utf8)

  #expect(motion.contains("enum TokMonMotion"))
  #expect(motion.contains("static let smoothSpring = Animation.spring(response: 0.42, dampingFraction: 0.88, blendDuration: 0.08)"))
  #expect(motion.contains("static let gentleSpring = Animation.spring(response: 0.50, dampingFraction: 0.90, blendDuration: 0.12)"))
  #expect(motion.contains("static let softSnappySpring = Animation.spring(response: 0.32, dampingFraction: 0.86, blendDuration: 0.06)"))
  #expect(view.contains("withAnimation(TokMonMotion.smoothSpring)"))
  #expect(view.contains("withAnimation(TokMonMotion.softSnappySpring)"))
  #expect(view.contains("withAnimation(TokMonMotion.gentleSpring)"))
  #expect(view.contains(".animation(TokMonMotion.smoothSpring, value: isTotalExpanded)"))
  #expect(view.contains(".animation(TokMonMotion.gentleSpring, value: selectedSessionBubbleY)"))
  #expect(view.contains(".transition(.tokMonPanelDrilldown)"))
  #expect(!view.contains("withAnimation(.interactiveSpring"))
}

@Test func totalTokensNumberDoesNotResizeBetweenCollapsedAndExpandedStates() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)
  let valueText = view
    .components(separatedBy: "private struct MetricValueText: View")
    .dropFirst()
    .first?
    .components(separatedBy: "private struct TokMonHudTrendCard")
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

@Test func totalTokensCollapsedComparisonKeepsFullMetricWidth() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)
  let totalTile = view
    .components(separatedBy: "private struct TotalTokensMetricTile: View")
    .dropFirst()
    .first?
    .components(separatedBy: "private struct TokenDetailMiniMetric: View")
    .first ?? ""
  let collapsedBody = totalTile
    .components(separatedBy: "private var collapsedBody: some View")
    .dropFirst()
    .first?
    .components(separatedBy: "private var expandedBody: some View")
    .first ?? ""

  #expect(totalTile.contains("if isExpanded {\n        expandedBody\n      } else {\n        collapsedBody\n      }"))
  #expect(collapsedBody.contains("ZStack(alignment: .topTrailing)"))
  #expect(collapsedBody.contains("metricSummary\n          .frame(maxWidth: .infinity, alignment: .leading)"))
  #expect(totalTile.contains("MetricDelta(metric.delta)"))
  #expect(!collapsedBody.contains("HStack(alignment: .top, spacing: 10)"))
}

@Test func totalTokensComparisonTextMatchesOtherMetricCards() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)
  let totalTile = view
    .components(separatedBy: "private struct TotalTokensMetricTile: View")
    .dropFirst()
    .first?
    .components(separatedBy: "private struct TokenDetailMiniMetric: View")
    .first ?? ""
  let primaryTile = view
    .components(separatedBy: "private struct PrimaryMetricTile: View")
    .dropFirst()
    .first?
    .components(separatedBy: "private struct TotalTokensMetricTile: View")
    .first ?? ""
  let metricDelta = view
    .components(separatedBy: "private struct MetricDelta: View")
    .dropFirst()
    .first?
    .components(separatedBy: "private struct MetricValueText: View")
    .first ?? ""

  #expect(totalTile.contains("MetricDelta(metric.delta)"))
  #expect(primaryTile.contains("MetricDelta(metric.delta)"))
  #expect(metricDelta.contains(".font(.system(size: 13, weight: .bold, design: .rounded))"))
  #expect(!totalTile.contains("MetricDelta(metric.delta, size:"))
  #expect(!metricDelta.contains("init(_ text: String, size:"))
  #expect(!metricDelta.contains("var size: CGFloat"))
  #expect(!metricDelta.contains("minimumScaleFactor"))
}

@Test func statusPopoverKeepsTotalTokensSingleWidthUntilExpanded() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
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

@Test func statusPopoverGivesTokensPageSameOuterBreathingRoomAsRecordsPages() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)
  let overview = view
    .components(separatedBy: "private var overviewPage: some View")
    .dropFirst()
    .first?
    .components(separatedBy: "private var requestsPage: some View")
    .first ?? ""

  #expect(overview.contains(".padding(9)"))
  #expect(overview.contains(".hudCard()"))
  #expect(overview.contains("TokMonHudMetricGrid("))
  #expect(overview.contains("TokMonHudActivityCard("))
}

@Test func requestRowsUseTwoLineTokenChipGrid() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)

  #expect(view.contains("RequestTokenChipGrid("))
  #expect(view.contains("columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)"))
  #expect(view.contains("TokenChipData(label: \"In\""))
  #expect(view.contains("TokenChipData(label: \"Out\""))
  #expect(view.contains("TokenChipData(label: \"Cache\""))
  #expect(view.contains("TokenChipData(label: \"Cost\""))
  #expect(view.contains("Text(isExpanded ? \"Hide\" : \"Details\")"))
  #expect(view.contains("Text(\"Jump\")"))
  #expect(view.contains(".frame(width: 78, alignment: .leading)"))
  #expect(view.contains(".truncationMode(.middle)"))
  #expect(view.contains(".contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))"))
  #expect(view.contains(".frame(minWidth: 76, minHeight: 26)"))
  #expect(!view.contains("Button(isExpanded ? \"Hide\" : \"Details\")"))
  #expect(!view.contains("Button(\"Jump\", action: onJumpToSession)"))
  #expect(!view.contains("HStack(spacing: 14) {\n        TokenChip(label: \"In\""))
}

@Test func statusPopoverSmallButtonsUseFullVisualHitAreas() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)
  let requestButtonModifier = view
    .components(separatedBy: "func requestActionButton() -> some View")
    .dropFirst()
    .first?
    .components(separatedBy: "func sessionDrilldownActionButton() -> some View")
    .first ?? ""
  let sessionButtonModifier = view
    .components(separatedBy: "func sessionDrilldownActionButton() -> some View")
    .dropFirst()
    .first?
    .components(separatedBy: "private func shortTimestamp")
    .first ?? ""
  let sessionHeader = view
    .components(separatedBy: "private struct SessionDrilldownHeader: View")
    .dropFirst()
    .first?
    .components(separatedBy: "private struct HeaderIconButton: View")
    .first ?? ""
  let headerIconButton = view
    .components(separatedBy: "private struct HeaderIconButton: View")
    .dropFirst()
    .first?
    .components(separatedBy: "private struct SystemMenuPageRail: View")
    .first ?? ""

  #expect(requestButtonModifier.contains(".padding(.horizontal, 12)\n      .frame(minWidth: 76, minHeight: 26)\n      .background"))
  #expect(requestButtonModifier.contains("}\n      .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))"))
  #expect(!requestButtonModifier.contains("buttonStyle(.plain)"))
  #expect(!requestButtonModifier.contains(".focusable(false)"))
  #expect(!requestButtonModifier.contains(".contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))\n      .foregroundStyle"))
  #expect(sessionButtonModifier.contains(".padding(.horizontal, 10)\n      .frame(minWidth: 76, minHeight: 24)\n      .background"))
  #expect(sessionButtonModifier.contains("}\n      .contentShape(Capsule())"))
  #expect(!sessionButtonModifier.contains(".contentShape(Rectangle())\n      .foregroundStyle"))
  #expect(sessionHeader.contains(".frame(width: 24, height: 24)\n          .contentShape(Circle())"))
  #expect(headerIconButton.contains(".frame(width: 28, height: 28)\n        .background"))
  #expect(headerIconButton.contains("}\n        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))"))
  #expect(!headerIconButton.contains(".help(help)\n    .background"))
}

@Test func statusPopoverPlacesSessionBubbleOutsideMainPanel() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let mainURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("main.swift")
  let layoutURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("StatusPanelLayout.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)
  let main = try String(contentsOf: mainURL, encoding: .utf8)
  let layout = try String(contentsOf: layoutURL, encoding: .utf8)

  #expect(view.contains("let heatmapLabelWidth: CGFloat = 31"))
  #expect(!view.contains(".frame(width: cellSize + metrics.gap"))
  #expect(layout.contains("let statusPanelMainWidth: CGFloat = 342"))
  #expect(layout.contains("let statusPanelHeight: CGFloat = 690"))
  #expect(layout.contains("let sessionBubbleWidth: CGFloat = 276"))
  #expect(layout.contains("let sessionBubbleGutter: CGFloat = 14"))
  #expect(layout.contains("let sessionBubbleScrollHeight: CGFloat = 332"))
  #expect(layout.contains("let sessionBubbleMaxHeight: CGFloat = 430"))
  #expect(layout.contains("let statusPanelContentWidth = statusPanelMainWidth + sessionBubbleWidth + sessionBubbleGutter"))
  #expect(view.contains(".frame(width: statusPanelMainWidth, height: statusPanelHeight)"))
  #expect(view.contains(".frame(width: statusPanelContentWidth, height: statusPanelHeight, alignment: .topLeading)"))
  #expect(view.contains(".padding(.leading, sessionBubbleWidth + sessionBubbleGutter)"))
  #expect(view.contains(".offset(x: 0, y: selectedSessionBubbleY)"))
  #expect(!view.contains(".offset(x: 0, y: 42)"))
  #expect(!view.contains(".offset(x: 8, y: 42)"))
  #expect(main.contains("NSSize(width: statusPanelContentWidth, height: statusPanelHeight)"))
  #expect(main.contains("let panelSize = NSSize(width: statusPanelContentWidth, height: statusPanelHeight)"))
  #expect(main.contains("let mainPanelWidth: CGFloat = statusPanelMainWidth"))
  #expect(main.contains("let preferredMainX = buttonFrameInScreen.midX - mainPanelWidth / 2"))
}

@Test func statusPopoverBreakdownRowsReserveSubtitleSpaceForNames() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)

  #expect(!view.contains("subtitle: selectedSeries.label"))
  #expect(!view.contains("let subtitle: String"))
  #expect(!view.contains("Text(row.subtitle)"))
  #expect(view.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
  #expect(!view.contains("subtitle: \"\\(model.requests) sessions\""))
  #expect(!view.contains("subtitle: \"\\(source.requests) requests\""))
}

@Test func settingsWindowSavesAndCloses() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("TokMonSettingsWindow.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)

  #expect(view.contains("Button(\"Save and Close\")"))
  #expect(view.contains("onSaveAndClose()"))
  #expect(!view.contains("Button(\"Save\")"))
}

@Test func statusPopoverKeepsUpdatedTimeOnlyInHeader() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
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
    .appendingPathComponent("TokMonApp")
  let sourceFiles = [
    "TokMonModels.swift",
    "TokMonStatsStore.swift",
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
    .appendingPathComponent("TokMonApp")
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
    .appendingPathComponent("TokMonApp")
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
    .appendingPathComponent("TokMonApp")
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
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let queryURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("TokMonQueryStore.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)
  let query = try String(contentsOf: queryURL, encoding: .utf8)
  let weekdayAxisStart = try #require(view.range(of: "private struct HeatmapWeekdayAxis: View")?.lowerBound)
  let weekdayAxisEnd = try #require(view.range(of: "private struct TrendLineChart: View")?.lowerBound)
  let weekdayAxis = String(view[weekdayAxisStart..<weekdayAxisEnd])

  #expect(query.contains("days: Int = 112"))
  #expect(view.contains("selectedSeries.key"))
  #expect(view.contains("maximumCellSize: 14"))
  #expect(view.contains("let heatmapLabelWidth: CGFloat = 31"))
  #expect(weekdayAxis.contains("ForEach(0..<7, id: \\.self)"))
  #expect(weekdayAxis.contains(".frame(width: 26, height: cellSize, alignment: .leading)"))
  #expect(!weekdayAxis.contains(".offset(y: CGFloat(label.weekdayIndex) * (cellSize + gap) - 1)"))
  #expect(weekdayAxis.contains(".lineLimit(1)"))
  #expect(weekdayAxis.contains(".minimumScaleFactor(0.75)"))
  #expect(view.contains(".frame(height: 124)"))
}

@Test func statusPopoverTrendAxisUsesDenseLabelsAndTodayTimeOnly() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
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
    .appendingPathComponent("TokMonApp")
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
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("TokMonSettingsWindow.swift")
  let settings = try String(contentsOf: settingsURL, encoding: .utf8)

  #expect(settings.contains("SettingsWindowShell()"))
  #expect(settings.contains(".fill(.ultraThinMaterial)"))
  #expect(settings.contains(".thinMaterial"))
  #expect(settings.contains(".regularMaterial"))
  #expect(!settings.contains(".preferredColorScheme(.dark)"))
  #expect(settings.contains(".font(.system(size: 15, weight: .heavy, design: .rounded))"))
}

@Test func statsObservationAvoidsDuplicateImmediateRefreshWhenPanelOpens() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let storeURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("TokMonStatsStore.swift")
  let mainURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
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
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("TokMonStatsStore.swift")
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
    .appendingPathComponent("TokMonApp")
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
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("main.swift")
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let main = try String(contentsOf: mainURL, encoding: .utf8)
  let view = try String(contentsOf: viewURL, encoding: .utf8)

  #expect(main.contains("NSSize(width: statusPanelContentWidth, height: statusPanelHeight)"))
  #expect(main.contains("let panelSize = NSSize(width: statusPanelContentWidth, height: statusPanelHeight)"))
  #expect(main.contains("let y = screenFrame.maxY - panelSize.height"))
  #expect(!main.contains("let y = buttonFrameInScreen.minY - panelSize.height"))
  #expect(view.contains(".frame(width: statusPanelContentWidth, height: statusPanelHeight, alignment: .topLeading)"))
  #expect(view.contains(".frame(width: statusPanelMainWidth, height: statusPanelHeight)"))
  #expect(view.contains(".padding(11)"))
}

@Test func statusPopoverRemovesInnerEdgeBufferAndKeepsOpenCodeDisplayName() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let modelsURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("TokMonModels.swift")
  let settingsURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("TokMonSettingsWindow.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)
  let models = try String(contentsOf: modelsURL, encoding: .utf8)
  let settings = try String(contentsOf: settingsURL, encoding: .utf8)

  #expect(!view.contains("StatusPanelEdgeBuffer()"))
  #expect(!view.contains("private struct StatusPanelEdgeBuffer: View"))
  #expect(!view.contains("""
  RoundedRectangle(cornerRadius: 24, style: .continuous)
      .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
  """))
  #expect(view.contains("\"OpenCode\""))
  #expect(models.contains("\"OpenCode\""))
  #expect(settings.contains("(\"opencode\", \"OpenCode\")"))
  #expect(settings.contains("(\"qwen-code\", \"Qwen Code\")"))
  #expect(settings.contains("FieldRow(\"OpenCode\")"))
  #expect(settings.contains("FieldRow(\"Qwen Code\")"))
}

@Test func statusPopoverScrollViewCatchesWheelEventsAcrossTransparentGaps() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)

  #expect(view.contains(".frame(maxWidth: .infinity, minHeight: statusPanelScrollContentHeight, alignment: .topLeading)"))
  #expect(view.contains(".contentShape(Rectangle())"))
  #expect(view.contains("Color.clear"))
}

@Test func statusPopoverVisiblePanelsConsumeClicksAcrossTransparentGaps() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)
  let rootBody = view
    .components(separatedBy: "var body: some View")
    .dropFirst()
    .first?
    .components(separatedBy: "@ViewBuilder")
    .first ?? ""
  let mainShell = view
    .components(separatedBy: "private struct StatusPanelShell: View")
    .dropFirst()
    .first?
    .components(separatedBy: "private struct StatusSessionBubbleShell: View")
    .first ?? ""
  let sessionShell = view
    .components(separatedBy: "private struct StatusSessionBubbleShell: View")
    .dropFirst()
    .first?
    .components(separatedBy: "private struct StatusPanelContentMask: Shape")
    .first ?? ""

  #expect(rootBody.contains(".background(Color.clear)"))
  #expect(rootBody.contains(".contentShape(Rectangle())"))
  #expect(mainShell.contains(".contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))"))
  #expect(!mainShell.contains(".allowsHitTesting(false)"))
  #expect(sessionShell.contains(".contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))"))
  #expect(!sessionShell.contains(".allowsHitTesting(false)"))
}

@Test func statusPopoverClipsScrollingContentInsidePanelEdge() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)

  #expect(view.contains("StatusPanelContentMask()"))
  #expect(view.contains("private struct StatusPanelContentMask: Shape"))
  #expect(view.contains(".clipShape(StatusPanelContentMask())"))
  #expect(!view.contains("StatusPanelEdgeBuffer()\n            .padding(7)"))
}

@Test func sessionDrilldownUsesMainPanelGlassAndSelectedRowPosition() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)

  #expect(view.contains("@State private var sessionRowFrames: [String: CGRect] = [:]"))
  #expect(view.contains("private var selectedSessionBubbleY: CGFloat"))
  #expect(view.contains("private struct SessionRowFramePreferenceKey: PreferenceKey"))
  #expect(view.contains(".coordinateSpace(name: StatusPopoverCoordinateSpace.main)"))
  #expect(view.contains(".onPreferenceChange(SessionRowFramePreferenceKey.self)"))
  #expect(view.contains("proxy.frame(in: .named(StatusPopoverCoordinateSpace.main))"))
  #expect(view.contains("StatusSessionBubbleShell()"))
  #expect(view.contains("private struct StatusSessionBubbleShell: View"))
  #expect(view.contains(".fill(.ultraThinMaterial)"))
  #expect(view.contains("TokMonGlass.glassEdge"))
  #expect(!view.contains("Color.black.opacity(0.34)"))
  #expect(!view.contains(".frame(width: sessionBubbleWidth, alignment: .topLeading)\n      .hudCard()"))
}

@Test func sessionDrilldownCapturesWheelEventsAcrossWholeBubble() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let layoutURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("StatusPanelLayout.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)
  let layout = try String(contentsOf: layoutURL, encoding: .utf8)

  #expect(view.contains("private struct SessionDrilldownHeader: View"))
  #expect(view.contains("xmark.circle.fill"))
  #expect(view.contains(".lineLimit(2)"))
  #expect(view.contains(".frame(width: sessionBubbleWidth, height: sessionBubbleMaxHeight, alignment: .topLeading)"))
  #expect(view.contains(".padding(14)"))
  #expect(view.contains("Text(isExpanded ? \"Hide\" : \"Details\")"))
  #expect(view.contains("Text(\"Jump\")"))
  #expect(view.contains(".requestActionButton()"))
  #expect(view.contains("SessionDrilldownScrollShell {"))
  #expect(view.contains("private struct SessionDrilldownScrollShell<Content: View>: View"))
  #expect(view.contains("ScrollView(showsIndicators: true)"))
  #expect(layout.contains("let sessionBubbleScrollIndicatorReserve: CGFloat = 8"))
  #expect(view.contains("maxWidth: sessionBubbleWidth - 28 - sessionBubbleScrollIndicatorReserve"))
  #expect(view.contains("minHeight: sessionBubbleScrollHeight"))
  #expect(view.contains(".frame(maxWidth: .infinity, alignment: .topLeading)"))
  #expect(view.contains(".frame(height: sessionBubbleScrollHeight, alignment: .topLeading)"))
  #expect(view.contains(".background(Color.clear)"))
  #expect(view.contains(".contentShape(Rectangle())"))
  #expect(!view.contains(".frame(width: sessionBubbleWidth, height: sessionBubbleScrollHeight, alignment: .topLeading)"))
  #expect(!view.contains("content\n        .padding(14)"))
}

@Test func statusPopoverKeepsHeaderPinnedOutsideScrollingContent() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)

  #expect(view.contains("pinnedHeader"))
  #expect(view.contains("scrollingPageContent"))
  #expect(view.contains("private var pinnedHeader: some View"))
  #expect(view.contains("private var scrollingPageContent: some View"))
  #expect(view.contains("ScrollView(showsIndicators: false) {\n            scrollingPageContent"))
  #expect(!view.contains("ScrollView(showsIndicators: false) {\n            VStack(alignment: .leading, spacing: 10) {\n              header"))
}

@Test func statusPopoverPageRailSlidesSelectionBetweenPages() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("StatusPopoverView.swift")
  let view = try String(contentsOf: viewURL, encoding: .utf8)

  #expect(view.contains("@Namespace private var pageRailSelectionNamespace"))
  #expect(view.contains("selectionNamespace: pageRailSelectionNamespace"))
  #expect(view.contains("let selectionNamespace: Namespace.ID"))
  #expect(view.contains(".matchedGeometryEffect(id: \"pageRailSelection\", in: selectionNamespace)"))
  #expect(view.contains("withAnimation(TokMonMotion.softSnappySpring)"))
  #expect(!view.contains(".fill(selectedPage == page ? TokMonGlass.accent.opacity(0.18) : Color.clear)"))
}

@Test func trendChartUsesSmoothedCurveInsteadOfStraightSegments() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let viewURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
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
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("main.swift")
  let main = try String(contentsOf: mainURL, encoding: .utf8)

  #expect(!main.contains("NSPopover()"))
  #expect(main.contains("TokMonStatusPanel("))
  #expect(main.contains("styleMask: [.borderless]"))
  #expect(main.contains("panel.isOpaque = false"))
  #expect(main.contains("panel.backgroundColor = .clear"))
  #expect(main.contains("panel.hasShadow = false"))
  #expect(main.contains("panel.level = .statusBar"))
  #expect(main.contains("TokMonStatusPanel"))
  #expect(main.contains("override var canBecomeKey: Bool { true }"))
  #expect(!main.contains("func windowDidResignKey"))
  #expect(main.contains("closeStatusPanel"))
  #expect(main.contains("showStatusPanel"))
}

@Test func statusPanelAnimatesOpenAndCloseAtWindowLevel() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let mainURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("main.swift")
  let main = try String(contentsOf: mainURL, encoding: .utf8)

  #expect(main.contains("private let statusPanelAnimationDuration: TimeInterval = 0.18"))
  #expect(main.contains("private let statusPanelAnimationOffset: CGFloat = 10"))
  #expect(main.contains("private var isClosingStatusPanel = false"))
  #expect(main.contains("animateStatusPanelOpen(panel, targetFrame: panelFrame)"))
  #expect(main.contains("animateStatusPanelClose(panel)"))
  #expect(main.contains("private func animateStatusPanelOpen(_ panel: NSPanel, targetFrame: NSRect)"))
  #expect(main.contains("private func animateStatusPanelClose(_ panel: NSPanel)"))
  #expect(main.contains("NSAnimationContext.runAnimationGroup"))
  #expect(main.contains("context.duration = statusPanelAnimationDuration"))
  #expect(main.contains("context.timingFunction = CAMediaTimingFunction(name: .easeOut)"))
  #expect(main.contains("panel.animator().alphaValue = 1"))
  #expect(main.contains("panel.animator().setFrameOrigin(targetFrame.origin)"))
  #expect(main.contains("panel.animator().alphaValue = 0"))
  #expect(main.contains("panel.animator().setFrameOrigin(closingFrame.origin)"))
  #expect(!main.contains("statusPanel?.orderOut(nil)"))
}

@Test func statusPanelOutsideClickMonitorIgnoresOnlyVisiblePanelSurfaces() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let mainURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("main.swift")
  let main = try String(contentsOf: mainURL, encoding: .utf8)

  #expect(main.contains("private var localClickMonitor: Any?"))
  #expect(main.contains("private func shouldCloseStatusPanel(for event: NSEvent) -> Bool"))
  #expect(main.contains("private func handleLocalMouseDown(_ event: NSEvent) -> NSEvent?"))
  #expect(main.contains("guard let statusPanel else"))
  #expect(main.contains("return !isPointInsideVisibleStatusPanel(NSEvent.mouseLocation, statusPanel: statusPanel)"))
  #expect(main.contains("private func isPointInsideVisibleStatusPanel(_ point: NSPoint, statusPanel: NSPanel) -> Bool"))
  #expect(main.contains("var mainFrame = statusPanel.frame"))
  #expect(main.contains("mainFrame.origin.x += sessionBubbleWidth + sessionBubbleGutter"))
  #expect(main.contains("mainFrame.size.width = statusPanelMainWidth"))
  #expect(main.contains("mainFrame.insetBy(dx: -2, dy: -2).contains(point)"))
  #expect(main.contains("guard let sessionBubbleY = runtime.statusPanelSessionBubbleY else"))
  #expect(main.contains("var bubbleFrame = statusPanel.frame"))
  #expect(main.contains("bubbleFrame.origin.y = statusPanel.frame.maxY - sessionBubbleY - sessionBubbleMaxHeight"))
  #expect(main.contains("bubbleFrame.size.width = sessionBubbleWidth"))
  #expect(main.contains("bubbleFrame.size.height = sessionBubbleMaxHeight"))
  #expect(main.contains("guard self?.shouldCloseStatusPanel(for: event) == true else"))
  #expect(main.contains("localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown])"))
  #expect(main.contains("self?.handleLocalMouseDown(event) ?? event"))
  #expect(main.contains("return isStatusPanelEvent ? nil : event"))
  #expect(!main.contains("statusPanel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)"))
  #expect(!main.contains("NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in"))
}

@Test func statusPopoverPublishesVisibleSessionBubbleYForPanelHitTesting() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let sourcesDir = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
  let runtime = try String(contentsOf: sourcesDir.appendingPathComponent("TokMonRuntime.swift"), encoding: .utf8)
  let view = try String(contentsOf: sourcesDir.appendingPathComponent("StatusPopoverView.swift"), encoding: .utf8)

  #expect(runtime.contains("@Published var statusPanelSessionBubbleY: CGFloat?"))
  #expect(view.contains(".onChange(of: selectedSessionBubbleY, initial: true)"))
  #expect(view.contains(".onChange(of: selectedPage, initial: true)"))
  #expect(view.contains(".onChange(of: stats.snapshot.selectedUsageSession, initial: true)"))
  #expect(view.contains(".onDisappear {\n      runtime.statusPanelSessionBubbleY = nil\n    }"))
  #expect(view.contains("private func syncSessionBubbleHitSurface()"))
  #expect(view.contains("runtime.statusPanelSessionBubbleY = selectedPage == .sessions && stats.snapshot.selectedUsageSession != nil ? selectedSessionBubbleY : nil"))
}

@Test func statusPanelOpeningAvoidsImmediateCloseOnActivationChanges() throws {
  let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let mainURL = packageDir
    .appendingPathComponent("Sources")
    .appendingPathComponent("TokMonApp")
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
    .appendingPathComponent("TokMonApp")
    .appendingPathComponent("main.swift")
  let main = try String(contentsOf: mainURL, encoding: .utf8)

  #expect(main.contains("window.isOpaque = false"))
  #expect(main.contains("window.backgroundColor = .clear"))
  #expect(main.contains("view.layer?.backgroundColor = NSColor.clear.cgColor"))
}
