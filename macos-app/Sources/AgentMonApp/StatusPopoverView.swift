import SwiftUI

struct StatusPopoverView: View {
  @EnvironmentObject private var runtime: AgentMonRuntime
  @EnvironmentObject private var stats: AgentMonStatsStore
  @State private var selectedPage = TokMonPopoverPage.overview
  @State private var selectedSeries = TokMonSeriesPresentation.total
  @State private var expandedRequestId: String?
  @State private var isTotalTokensExpanded = false
  private let numberFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter
  }()

  var body: some View {
    TokMonLiquidGlassScene {
      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: 10) {
          header
          errorBanner
          SystemMenuPageRail(
            pages: availablePages,
            selectedPage: selectedPage,
            onSelect: { selectedPage = $0 },
          )
          rangeControl
          currentPage
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 740, alignment: .topLeading)
        .background(Color.black.opacity(0.001))
        .contentShape(Rectangle())
      }
    }
    .background(alignment: .top) {
      StatusPanelShell()
    }
    .frame(width: 360, height: 740)
    .onChange(of: stats.snapshot.dashboardState?.activeSeries, initial: true) { _, activeSeries in
      selectedSeries = TokMonSeriesPresentation(rawValue: activeSeries ?? "total")
    }
  }

  @ViewBuilder
  private var errorBanner: some View {
    if let errorMessage = stats.errorMessage {
      Text(errorMessage)
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(TokMonGlass.danger)
        .lineLimit(2)
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.black.opacity(0.22))
            .overlay {
              RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(TokMonGlass.danger.opacity(0.32), lineWidth: 1)
            }
        }
    }
  }

  @ViewBuilder
  private var currentPage: some View {
    switch selectedPage {
    case .overview:
      overviewPage
    case .requests:
      requestsPage
    case .sessions:
      sessionsPage
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 10) {
      ZStack {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(Color.white.opacity(0.12))
          .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
          }
        Text("A")
          .font(.system(size: 17, weight: .black, design: .rounded))
          .foregroundStyle(TokMonGlass.neutralTint)
      }
      .frame(width: 30, height: 30)

      VStack(alignment: .leading, spacing: 3) {
        Text("AgentMon")
          .font(.system(size: 14, weight: .heavy, design: .rounded))
          .foregroundStyle(TokMonGlass.neutralTint)
        Text("\(serverLine) · \(updatedLine)")
          .font(.system(size: 12, weight: .semibold, design: .rounded))
          .foregroundStyle(TokMonGlass.mutedTint)
          .lineLimit(1)
      }

      Spacer()

      HeaderIconButton(systemName: "gearshape", help: "TokMon Settings") {
        runtime.openSettings()
      }
      HeaderIconButton(systemName: "power", help: "Quit AgentMon") {
        runtime.quit()
      }
    }
  }

  private var rangeControl: some View {
    Group {
      if let state = stats.snapshot.dashboardState, stats.usesNativeEngine {
        RangePresetControl(
          selectedLabel: TokMonRangePreset(label: state.rangeLabel).label,
          onSelect: selectRangePreset,
        )
      } else if let state = stats.snapshot.dashboardState {
        Text(state.rangeDisplay)
          .font(.system(size: 13, weight: .semibold, design: .rounded))
          .foregroundStyle(TokMonGlass.mutedTint)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        Text("Waiting for TokMon settings...")
          .font(.system(size: 13, weight: .semibold, design: .rounded))
          .foregroundStyle(TokMonGlass.mutedTint)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private var overviewPage: some View {
    VStack(alignment: .leading, spacing: 10) {
      AgentMonHudMetricGrid(
        metrics: primaryMetrics,
        tokenDetails: secondaryMetrics,
        isTotalExpanded: isTotalTokensExpanded,
        onToggleTotalExpanded: toggleTotalTokensExpanded,
        onSelect: selectSeries,
      )
      AgentMonHudTrendCard(
        title: "Trend",
        valueLabel: selectedSeries.label,
        points: trendPoints(for: selectedSeries.key),
        color: selectedSeries.tintColor,
      )
      AgentMonHudActivityCard(
        days: stats.snapshot.heatmapDays,
        selectedSeries: selectedSeries.key,
        colorForValue: heatmapColor,
      )
      AgentMonHudBreakdownCard(
        title: "Top Models",
        trailingTitle: selectedSeries.isCost ? "Cost" : selectedSeries.label,
        rows: modelRows,
      )
      AgentMonHudBreakdownCard(
        title: "Sources",
        trailingTitle: selectedSeries.isCost ? "Cost" : selectedSeries.label,
        rows: sourceRows,
      )
    }
    .font(.system(size: 12, weight: .regular, design: .rounded))
  }

  private var requestsPage: some View {
    let rows = stats.snapshot.recordsPage?.rows ?? []
    let total = stats.snapshot.recordsPage?.total ?? 0

    return VStack(alignment: .leading, spacing: 9) {
      AgentMonHudSectionHeader("Requests", trailing: total > 0 ? "Showing \(rows.count) of \(total)" : nil)
      if rows.isEmpty {
        emptyState("No requests in the selected range.")
      } else {
        ForEach(rows) { row in
          RequestRowView(
            row: row,
            isExpanded: expandedRequestId == row.id,
            costRates: costRates(forModel: row.model),
            sourceLabel: labelForSource(row.source),
            sourceColor: colorForSource(row.source),
            formatCompact: formatChartValue,
            formatCost: formatCost,
            onToggleDetails: {
              expandedRequestId = expandedRequestId == row.id ? nil : row.id
            },
            onJumpToSession: {
              jumpToSession(source: row.source, sessionId: row.sessionId)
            },
          )
        }
        if stats.canLoadMoreRecords {
          LoadMoreButton(title: "Load More Requests") {
            stats.loadMoreRecords()
          }
        }
      }
    }
    .padding(9)
    .hudCard()
  }

  private var sessionsPage: some View {
    let sessions = stats.snapshot.usageSessions

    return VStack(alignment: .leading, spacing: 9) {
      AgentMonHudSectionHeader("Sessions", trailing: sessions.isEmpty ? nil : "Latest \(sessions.count)")
      if sessions.isEmpty {
        emptyState("No usage sessions yet.")
      } else {
        ForEach(sessions) { session in
          SessionRowView(
            session: session,
            isSelected: stats.snapshot.selectedUsageSession?.id == session.id,
            costRates: costRates(forSession: session),
            sourceLabel: labelForSource(session.source),
            sourceColor: colorForSource(session.source),
            formatCompact: formatChartValue,
            formatCost: formatCost,
            onSelect: {
              stats.selectUsageSession(source: session.source, sessionId: session.sessionId)
            },
          )
        }
        if stats.canLoadMoreUsageSessions {
          LoadMoreButton(title: "Load More Sessions") {
            stats.loadMoreUsageSessions()
          }
        }
        selectedSessionDrilldown
      }
    }
    .padding(9)
    .hudCard()
  }

  @ViewBuilder
  private var selectedSessionDrilldown: some View {
    if let selection = stats.snapshot.selectedUsageSession {
      let rows = stats.snapshot.selectedSessionRecords
      let selectedSession = stats.snapshot.usageSessions.first { $0.id == selection.id }

      VStack(alignment: .leading, spacing: 10) {
        HStack {
          AgentMonHudSectionHeader("Session Requests", trailing: nil)
          Spacer()
          Button {
            stats.clearSelectedUsageSession()
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 15, weight: .semibold))
          }
          .buttonStyle(.plain)
          .focusable(false)
        }
        Text("\(labelForSource(selection.source)) · \(selectedSession?.title ?? selection.sessionId)")
          .font(.system(size: 12, weight: .semibold, design: .rounded))
          .foregroundStyle(TokMonGlass.mutedTint)
          .lineLimit(1)
          .truncationMode(.middle)

        if rows.isEmpty {
          emptyState("No requests in this session for the selected range.")
        } else {
          ForEach(rows) { row in
            RequestRowView(
              row: row,
              isExpanded: expandedRequestId == row.id,
              costRates: costRates(forModel: row.model),
              sourceLabel: labelForSource(row.source),
              sourceColor: colorForSource(row.source),
              formatCompact: formatChartValue,
              formatCost: formatCost,
              onToggleDetails: {
                expandedRequestId = expandedRequestId == row.id ? nil : row.id
              },
              onJumpToSession: nil,
            )
          }
        }
      }
      .padding(14)
      .hudInsetCard()
    }
  }

  private var primaryMetrics: [AgentMonHudMetric] {
    let totals = stats.snapshot.summary?.total
    return [
      AgentMonHudMetric(series: .total, value: formatCompact(totals?.totalTokens), delta: metricDelta(for: .total), isSelected: selectedSeries.key == .total),
      AgentMonHudMetric(series: .cost, value: formatCost(currentEstimatedCost), delta: metricDelta(for: .cost), isSelected: selectedSeries.key == .cost),
      AgentMonHudMetric(series: .requests, value: formatCompact(totals?.totalRequests), delta: metricDelta(for: .requests), isSelected: selectedSeries.key == .requests),
      AgentMonHudMetric(series: .cacheHitRate, value: formatPercent(totals?.cacheHitRate), delta: metricDelta(for: .cacheHitRate), isSelected: selectedSeries.key == .cacheHitRate),
    ]
  }

  private var secondaryMetrics: [AgentMonHudMetric] {
    let totals = stats.snapshot.summary?.total
    return [
      AgentMonHudMetric(series: .input, value: formatCompact(totals?.totalInput), delta: metricDelta(for: .input), isSelected: selectedSeries.key == .input),
      AgentMonHudMetric(series: .output, value: formatCompact(totals?.totalOutput), delta: metricDelta(for: .output), isSelected: selectedSeries.key == .output),
      AgentMonHudMetric(series: .cache, value: formatCompact(totals?.totalCacheCreation), delta: metricDelta(for: .cache), isSelected: selectedSeries.key == .cache),
      AgentMonHudMetric(series: .cacheHit, value: formatCompact(totals?.totalCacheRead), delta: metricDelta(for: .cacheHit), isSelected: selectedSeries.key == .cacheHit),
    ]
  }

  private var modelRows: [AgentMonHudBreakdownRow] {
    Array((stats.snapshot.summary?.byModel ?? [])
      .sorted { modelValue($0, for: selectedSeries.key) > modelValue($1, for: selectedSeries.key) }
      .prefix(4))
      .map { model in
        AgentMonHudBreakdownRow(
          id: model.id,
          title: model.model,
          subtitle: "\(model.requests) sessions",
          value: formatMetricValue(modelValue(model, for: selectedSeries.key)),
          color: colorForSource(model.source),
        )
      }
  }

  private var sourceRows: [AgentMonHudBreakdownRow] {
    (stats.snapshot.summary?.bySource ?? [])
      .sorted { sourceValue($0, for: selectedSeries.key) > sourceValue($1, for: selectedSeries.key) }
      .map { source in
        AgentMonHudBreakdownRow(
          id: source.id,
          title: labelForSource(source.source),
          subtitle: "\(source.requests) requests",
          value: formatMetricValue(sourceValue(source, for: selectedSeries.key)),
          color: colorForSource(source.source),
        )
      }
  }

  private func emptyState(_ message: String) -> some View {
    Text(message)
      .font(.system(size: 13, weight: .semibold, design: .rounded))
      .foregroundStyle(TokMonGlass.mutedTint)
      .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
  }

  private var serverLine: String {
    "Native TokMon"
  }

  private var currentEstimatedCost: Double? {
    guard let summary = stats.snapshot.summary else {
      return stats.snapshot.dashboardState?.estimatedCost
    }
    if !modelPricing.isEmpty {
      return summary.estimatedCost(modelPricing: modelPricing)
    }
    return summary.estimatedCost(costRates: fallbackCostRates)
  }

  private var updatedLine: String {
    guard let updatedAt = stats.snapshot.updatedAt else {
      return "updated now"
    }
    return "Updated \(updatedAt.formatted(date: .omitted, time: .standard))"
  }

  private func format(_ value: Int?) -> String {
    guard let value else { return "-" }
    return numberFormatter.string(from: NSNumber(value: value)) ?? String(value)
  }

  private func formatCompact(_ value: Int?) -> String {
    guard let value else { return "-" }
    return formatChartValue(Double(value))
  }

  private func formatCost(_ value: Double?) -> String {
    guard let value else { return "-" }
    if value >= 1000 { return "$" + String(format: "%.1fK", value / 1000) }
    if value >= 1 { return "$" + String(format: "%.2f", value) }
    if value >= 0.01 { return "$" + String(format: "%.3f", value) }
    return "$" + String(format: "%.4f", value)
  }

  private func formatMetricValue(_ value: Double?) -> String {
    if selectedSeries.isPercent {
      return formatPercent(value)
    }
    return selectedSeries.isCost ? formatCost(value) : formatChartValue(value)
  }

  private func formatPercent(_ value: Double?) -> String {
    guard let value else { return "-" }
    return String(format: "%.1f%%", value * 100)
  }

  private func metricDelta(for seriesKey: TokMonSeriesKey) -> String {
    guard let current = stats.snapshot.summary,
          let previous = stats.snapshot.previousSummary else {
      return "No previous period"
    }

    let currentValue = summaryValue(current, for: seriesKey)
    let previousValue = summaryValue(previous, for: seriesKey)
    guard previousValue > 0 else {
      return currentValue > 0 ? "New vs previous" : "No previous period"
    }

    let change = (currentValue - previousValue) / previousValue
    if abs(change) < 0.005 {
      return "No change vs previous"
    }
    let sign = change > 0 ? "+" : "-"
    return "\(sign)\(Int((abs(change) * 100).rounded()))% vs previous"
  }

  private func summaryValue(_ summary: TokMonSummary, for seriesKey: TokMonSeriesKey) -> Double {
    switch seriesKey {
    case .cost:
      if !modelPricing.isEmpty {
        return summary.estimatedCost(modelPricing: modelPricing)
      }
      return summary.estimatedCost(costRates: fallbackCostRates)
    default:
      return summary.total.value(for: seriesKey, costRates: fallbackCostRates)
    }
  }

  private func formatChartValue(_ value: Double?) -> String {
    guard let value else { return "-" }
    if value >= 1_000_000_000 { return String(format: "%.1fB", value / 1_000_000_000) }
    if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1fK", value / 1_000) }
    return format(Int(value.rounded()))
  }

  private func selectSeries(_ series: TokMonSeriesPresentation) {
    selectedSeries = series
  }

  private func selectRangePreset(_ preset: TokMonRangePreset) {
    Task {
      await stats.updateDashboardRange(preset.label)
    }
  }

  private func toggleTotalTokensExpanded() {
    withAnimation(.interactiveSpring(response: 0.48, dampingFraction: 0.82, blendDuration: 0.16)) {
      isTotalTokensExpanded.toggle()
    }
  }

  private var availablePages: [TokMonPopoverPage] {
    stats.usesNativeEngine ? TokMonPopoverPage.allCases : [.overview]
  }

  private func jumpToSession(source: String, sessionId: String) {
    stats.selectUsageSession(source: source, sessionId: sessionId)
    selectedPage = .sessions
  }

  private func trendPoints(for seriesKey: TokMonSeriesKey) -> [TokMonTrendPoint] {
    let costRates = aggregateCostRates
    return stats.snapshot.trendBuckets.map { bucket in
      TokMonTrendPoint(
        id: "\(seriesKey.rawValue):\(bucket.bucket)",
        label: bucket.bucket,
        value: bucket.value(for: seriesKey, costRates: costRates),
      )
    }
  }

  private var modelPricing: [String: TokMonCostRates] {
    stats.snapshot.dashboardState?.modelPricing ?? [:]
  }

  private var fallbackCostRates: TokMonCostRates {
    stats.snapshot.dashboardState?.costRates ?? .zero
  }

  private var aggregateCostRates: TokMonCostRates {
    guard let summary = stats.snapshot.summary, !modelPricing.isEmpty else {
      return fallbackCostRates
    }
    return weightedAverageRates(byModel: summary.byModel, modelPricing: modelPricing)
  }

  private func costRates(forModel model: String) -> TokMonCostRates {
    guard !modelPricing.isEmpty else {
      return fallbackCostRates
    }
    return modelPricing[model] ?? .zero
  }

  private func costRates(forSession session: TokMonUsageSession) -> TokMonCostRates {
    guard !modelPricing.isEmpty else {
      return fallbackCostRates
    }
    if session.model != "Mixed" {
      return modelPricing[session.model] ?? .zero
    }
    return aggregateCostRates
  }

  private func sourceValue(_ source: TokMonSourceTotals, for seriesKey: TokMonSeriesKey) -> Double {
    guard seriesKey == .cost, !modelPricing.isEmpty else {
      return source.value(for: seriesKey, costRates: fallbackCostRates)
    }
    return (stats.snapshot.summary?.byModel ?? [])
      .filter { $0.source == source.source }
      .reduce(0) { sum, model in sum + modelValue(model, for: .cost) }
  }

  private func modelValue(_ model: TokMonModelTotals, for seriesKey: TokMonSeriesKey) -> Double {
    model.value(for: seriesKey, costRates: costRates(forModel: model.model))
  }

  private func weightedAverageRates(
    byModel: [TokMonModelTotals],
    modelPricing: [String: TokMonCostRates],
  ) -> TokMonCostRates {
    var totalInput = 0
    var totalOutput = 0
    var totalCacheCreation = 0
    var totalCacheRead = 0
    var inputCost = 0.0
    var outputCost = 0.0
    var cacheCreationCost = 0.0
    var cacheReadCost = 0.0

    for model in byModel {
      guard let rates = modelPricing[model.model] else { continue }
      totalInput += model.inputTokens
      totalOutput += model.outputTokens
      totalCacheCreation += model.cacheCreation
      totalCacheRead += model.cacheRead
      inputCost += Double(model.inputTokens) / 1_000_000 * rates.input
      outputCost += Double(model.outputTokens) / 1_000_000 * rates.output
      cacheCreationCost += Double(model.cacheCreation) / 1_000_000 * rates.cacheCreate
      cacheReadCost += Double(model.cacheRead) / 1_000_000 * rates.cacheRead
    }

    return TokMonCostRates(
      input: totalInput == 0 ? 0 : inputCost / Double(totalInput) * 1_000_000,
      output: totalOutput == 0 ? 0 : outputCost / Double(totalOutput) * 1_000_000,
      cacheCreate: totalCacheCreation == 0 ? 0 : cacheCreationCost / Double(totalCacheCreation) * 1_000_000,
      cacheRead: totalCacheRead == 0 ? 0 : cacheReadCost / Double(totalCacheRead) * 1_000_000,
    )
  }

  private func labelForSource(_ source: String) -> String {
    switch source {
    case "claude-code":
      "Claude Code"
    case "codex":
      "Codex"
    default:
      source
    }
  }

  private func colorForSource(_ source: String) -> Color {
    switch source {
    case "claude-code":
      TokMonGlass.warning
    case "codex":
      TokMonGlass.accent
    default:
      TokMonGlass.mutedTint
    }
  }

  private func heatmapColor(value: Double, maxValue: Double) -> Color {
    guard maxValue > 0, value > 0 else {
      return Color.white.opacity(0.08)
    }
    let opacity = 0.30 + 0.55 * (value / maxValue)
    return TokMonGlass.success.opacity(opacity)
  }
}

private enum TokMonPopoverPage: String, CaseIterable, Identifiable {
  case overview
  case requests
  case sessions

  var id: String { rawValue }

  var title: String {
    switch self {
    case .overview:
      "Tokens"
    case .requests:
      "Requests"
    case .sessions:
      "Sessions"
    }
  }
}

private struct AgentMonHudMetric: Identifiable {
  let series: TokMonSeriesPresentation
  let value: String
  let delta: String
  let isSelected: Bool

  var id: String { series.key.rawValue }
}

private struct AgentMonHudBreakdownRow: Identifiable {
  let id: String
  let title: String
  let subtitle: String
  let value: String
  let color: Color
}

private struct StatusPanelShell: View {
  var body: some View {
    shellShape
      .fill(.regularMaterial)
      .overlay { shellShape.fill(Color.black.opacity(0.34)) }
      .overlay {
        shellShape.fill(
          LinearGradient(
            colors: [
              Color.white.opacity(0.10),
              Color.white.opacity(0.025),
              Color.black.opacity(0.12),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing,
          )
        )
      }
      .overlay {
        shellShape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
      }
      .shadow(color: Color.black.opacity(0.24), radius: 22, y: 10)
      .allowsHitTesting(false)
  }

  private var shellShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: 30, style: .continuous)
  }
}

private struct HeaderIconButton: View {
  let systemName: String
  let help: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(TokMonGlass.neutralTint)
        .frame(width: 28, height: 28)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    .buttonStyle(.plain)
    .focusable(false)
    .help(help)
    .background {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color.white.opacity(0.07))
        .overlay {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        }
    }
  }
}

private struct SystemMenuPageRail: View {
  let pages: [TokMonPopoverPage]
  let selectedPage: TokMonPopoverPage
  let onSelect: (TokMonPopoverPage) -> Void

  var body: some View {
    HStack(spacing: 3) {
      ForEach(pages) { page in
        Button {
          onSelect(page)
        } label: {
          Text(page.title)
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 26)
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .foregroundStyle(selectedPage == page ? TokMonGlass.neutralTint : TokMonGlass.mutedTint)
        .background {
          RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(selectedPage == page ? TokMonGlass.accent.opacity(0.18) : Color.clear)
            .overlay {
              RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(selectedPage == page ? TokMonGlass.accent.opacity(0.26) : Color.clear, lineWidth: 1)
            }
        }
      }
    }
    .padding(3)
    .background {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(TokMonGlass.hudRailFill)
        .overlay {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(TokMonGlass.hudCardStroke, lineWidth: 1)
        }
    }
  }
}

private struct RangePresetControl: View {
  let selectedLabel: String
  let onSelect: (TokMonRangePreset) -> Void
  private let prototypeRangePresets: [TokMonRangePreset] = [.today, .thisWeek, .thisMonth, .all]

  var body: some View {
    HStack(spacing: 3) {
      ForEach(prototypeRangePresets) { preset in
        Button {
          onSelect(preset)
        } label: {
          Text(preset.compactDisplayLabel)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .frame(maxWidth: .infinity, minHeight: 22)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .foregroundStyle(selectedLabel == preset.label ? TokMonGlass.neutralTint : TokMonGlass.mutedTint)
        .tokMonSelectionPill(isSelected: selectedLabel == preset.label, cornerRadius: 10)
        .help("Show \(preset.displayLabel)")
      }
    }
  }
}

private struct AgentMonHudMetricGrid: View {
  let metrics: [AgentMonHudMetric]
  let tokenDetails: [AgentMonHudMetric]
  let isTotalExpanded: Bool
  let onToggleTotalExpanded: () -> Void
  let onSelect: (TokMonSeriesPresentation) -> Void

  var body: some View {
    let totalMetric = metrics.first { $0.series.key == .total }
    let supportingMetrics = metrics.filter { $0.series.key != .total }

    VStack(spacing: 7) {
      if isTotalExpanded {
        if let totalMetric {
          TotalTokensMetricTile(
            metric: totalMetric,
            tokenDetails: tokenDetails,
            isExpanded: isTotalExpanded,
            onToggleExpanded: onToggleTotalExpanded,
            onSelect: onSelect,
          )
          HStack(spacing: 7) {
            ForEach(supportingMetrics) { metric in
              CompactMetricTile(metric: metric, hideDelta: true, onSelect: onSelect)
            }
          }
          .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity),
          ))
        }
      } else {
        LazyVGrid(
          columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 2),
          alignment: .leading,
          spacing: 7,
        ) {
          ForEach(metrics) { metric in
            if metric.series.key == .total {
              TotalTokensMetricTile(
                metric: metric,
                tokenDetails: tokenDetails,
                isExpanded: false,
                onToggleExpanded: onToggleTotalExpanded,
                onSelect: onSelect,
              )
            } else {
              PrimaryMetricTile(metric: metric, hideDelta: false, onSelect: onSelect)
            }
          }
        }
        .transition(.asymmetric(
          insertion: .scale(scale: 0.98).combined(with: .opacity),
          removal: .scale(scale: 0.98).combined(with: .opacity),
        ))
      }
    }
  }
}

private struct PrimaryMetricTile: View {
  let metric: AgentMonHudMetric
  var hideDelta = false
  let onSelect: (TokMonSeriesPresentation) -> Void

  var body: some View {
    Button {
      onSelect(metric.series)
    } label: {
      VStack(alignment: .leading, spacing: 7) {
        HStack {
          Text(metric.series.label.uppercased())
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(TokMonGlass.mutedTint)
            .lineLimit(1)
          Spacer(minLength: 0)
          Text(metric.series.icon)
            .font(.system(size: 12, weight: .black, design: .rounded))
            .foregroundStyle(metric.isSelected ? TokMonGlass.accent : TokMonGlass.mutedTint)
        }
        MetricValueText(value: metric.value, isSelected: metric.isSelected)
        if !hideDelta {
          MetricDelta(metric.delta)
        }
      }
      .padding(9)
      .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
      .hudCard(isSelected: metric.isSelected)
      .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .buttonStyle(.plain)
    .focusable(false)
  }
}

private struct TotalTokensMetricTile: View {
  let metric: AgentMonHudMetric
  let tokenDetails: [AgentMonHudMetric]
  let isExpanded: Bool
  let onToggleExpanded: () -> Void
  let onSelect: (TokMonSeriesPresentation) -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Button {
        onSelect(metric.series)
      } label: {
        VStack(alignment: .leading, spacing: 7) {
          HStack(spacing: 6) {
            Text(metric.series.label.uppercased())
              .font(.system(size: 11, weight: .heavy, design: .rounded))
              .foregroundStyle(TokMonGlass.mutedTint)
              .lineLimit(1)
            Text(metric.series.icon)
              .font(.system(size: 12, weight: .black, design: .rounded))
              .foregroundStyle(metric.isSelected ? TokMonGlass.accent : TokMonGlass.mutedTint)
          }
          MetricValueText(value: metric.value, isSelected: metric.isSelected)
          MetricDelta(metric.delta)
        }
        .frame(minWidth: 76, maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .focusable(false)

      if isExpanded {
        LazyVGrid(
          columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2),
          alignment: .leading,
          spacing: 6,
        ) {
          ForEach(tokenDetails) { detail in
            TokenDetailMiniMetric(metric: detail)
          }
        }
        .frame(width: 152)
        .transition(.asymmetric(
          insertion: .move(edge: .trailing).combined(with: .opacity),
          removal: .move(edge: .trailing).combined(with: .opacity),
        ))
      }

      Button {
        onToggleExpanded()
      } label: {
        Image(systemName: isExpanded ? "chevron.left" : "chevron.right")
          .font(.system(size: 11, weight: .black))
          .foregroundStyle(TokMonGlass.neutralTint)
          .frame(width: 24, height: 24)
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .focusable(false)
      .background {
        Circle()
          .fill(Color.white.opacity(0.075))
          .overlay { Circle().strokeBorder(Color.white.opacity(0.11), lineWidth: 1) }
      }
      .help(isExpanded ? "Hide token details" : "Show token details")
    }
    .padding(9)
    .frame(maxWidth: .infinity, minHeight: isExpanded ? 80 : 66, alignment: .topLeading)
    .hudCard(isSelected: metric.isSelected)
    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}

private struct TokenDetailMiniMetric: View {
  let metric: AgentMonHudMetric

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(metric.series.compactLabel)
        .font(.system(size: 9, weight: .heavy, design: .rounded))
        .foregroundStyle(TokMonGlass.mutedTint)
        .lineLimit(1)
      Text(metric.value)
        .font(.system(size: 12, weight: .black, design: .rounded).monospacedDigit())
        .foregroundStyle(TokMonGlass.neutralTint.opacity(0.88))
        .lineLimit(1)
    }
    .padding(.horizontal, 7)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color.white.opacity(0.045))
        .overlay {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        }
    }
  }
}

private struct CompactMetricTile: View {
  let metric: AgentMonHudMetric
  let hideDelta: Bool
  let onSelect: (TokMonSeriesPresentation) -> Void

  var body: some View {
    Button {
      onSelect(metric.series)
    } label: {
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Text(metric.series.compactLabel.uppercased())
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .foregroundStyle(TokMonGlass.mutedTint)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
          Spacer(minLength: 0)
          Text(metric.series.icon)
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundStyle(metric.isSelected ? TokMonGlass.accent : TokMonGlass.mutedTint)
        }
        Text(metric.value)
          .font(.system(size: 15, weight: .black, design: .rounded).monospacedDigit())
          .foregroundStyle(metric.isSelected ? TokMonGlass.accent : TokMonGlass.neutralTint)
          .lineLimit(1)
          .minimumScaleFactor(0.62)
        if !hideDelta {
          MetricDelta(metric.delta)
        }
      }
      .padding(9)
      .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
      .hudCard(isSelected: metric.isSelected)
      .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .buttonStyle(.plain)
    .focusable(false)
  }
}

private struct MetricDelta: View {
  let text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    Text(text)
      .font(.system(size: 13, weight: .bold, design: .rounded))
      .foregroundStyle(TokMonGlass.mutedTint)
      .lineLimit(1)
      .minimumScaleFactor(0.72)
  }
}

private struct MetricValueText: View {
  let value: String
  let isSelected: Bool

  var body: some View {
    Text(value)
      .font(.system(size: 20, weight: .black, design: .rounded).monospacedDigit())
      .foregroundStyle(isSelected ? TokMonGlass.accent : TokMonGlass.neutralTint)
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
      .frame(minWidth: 76, alignment: .leading)
      .frame(height: 24, alignment: .leading)
      .transaction { transaction in
        transaction.animation = nil
      }
  }
}

private struct AgentMonHudTrendCard: View {
  let title: String
  let valueLabel: String
  let points: [TokMonTrendPoint]
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      AgentMonHudSectionHeader(title, trailing: valueLabel)
      TrendLineChart(points: points, color: color)
        .frame(height: 60)
    }
    .padding(10)
    .hudCard()
  }
}

private struct AgentMonHudActivityCard: View {
  let days: [TokMonHeatmapDay]
  let selectedSeries: TokMonSeriesKey
  let colorForValue: (Double, Double) -> Color

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      AgentMonHudSectionHeader("Activity", trailing: days.isEmpty ? nil : "\(days.count)D")

      if days.isEmpty {
        Text("No recent activity.")
          .font(.system(size: 13, weight: .semibold, design: .rounded))
          .foregroundStyle(TokMonGlass.mutedTint)
          .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
      } else {
        RecentActivityGrid(days: days, selectedSeries: selectedSeries, colorForValue: colorForValue)
      }
    }
    .padding(10)
    .hudCard()
  }
}

private struct AgentMonHudBreakdownCard: View {
  let title: String
  let trailingTitle: String
  let rows: [AgentMonHudBreakdownRow]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      AgentMonHudSectionHeader(title, trailing: trailingTitle)
      if rows.isEmpty {
        Text("No usage in the selected range.")
          .font(.system(size: 13, weight: .semibold, design: .rounded))
          .foregroundStyle(TokMonGlass.mutedTint)
          .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
      } else {
        VStack(spacing: 0) {
          ForEach(rows) { row in
            HStack(spacing: 14) {
              Circle()
                .fill(row.color)
                .frame(width: 8, height: 8)
              VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                  .font(.system(size: 13, weight: .heavy, design: .rounded))
                  .foregroundStyle(TokMonGlass.neutralTint)
                  .lineLimit(1)
                  .truncationMode(.middle)
                Text(row.subtitle)
                  .font(.system(size: 11, weight: .bold, design: .rounded))
                  .foregroundStyle(TokMonGlass.mutedTint)
                  .lineLimit(1)
              }
              Spacer(minLength: 12)
              Text(row.value)
                .font(.system(size: 12, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(TokMonGlass.neutralTint.opacity(0.82))
                .lineLimit(1)
            }
            .padding(.vertical, 7)
            if row.id != rows.last?.id {
              Divider().overlay(Color.white.opacity(0.08))
            }
          }
        }
      }
    }
    .padding(10)
    .hudCard()
  }
}

private struct AgentMonHudSectionHeader: View {
  let title: String
  let trailing: String?

  init(_ title: String, trailing: String?) {
    self.title = title
    self.trailing = trailing
  }

  var body: some View {
    HStack {
      Text(title)
        .font(.system(size: 14, weight: .heavy, design: .rounded))
        .foregroundStyle(TokMonGlass.neutralTint.opacity(0.84))
      Spacer()
      if let trailing {
        Text(trailing)
          .font(.system(size: 12, weight: .heavy, design: .rounded))
          .foregroundStyle(TokMonGlass.neutralTint.opacity(0.78))
          .lineLimit(1)
      }
    }
  }
}

private struct RecentActivityGrid: View {
  let days: [TokMonHeatmapDay]
  let selectedSeries: TokMonSeriesKey
  let colorForValue: (Double, Double) -> Color

  var body: some View {
    let layout = TokMonHeatmapLayout(days: days)
    let maxValue = days.map { dayValue($0, series: selectedSeries) }.max() ?? 0
    GeometryReader { proxy in
      let metrics = TokMonHeatmapLayout.metrics(
        availableWidth: proxy.size.width,
        weekCount: layout.weeks.count,
        labelWidth: 30,
        minimumCellSize: 6,
        maximumCellSize: 14,
      )
      let cellSize = metrics.cellSize
      VStack(alignment: .leading, spacing: 4) {
        HeatmapMonthAxis(layout: layout, metrics: metrics)
        HStack(alignment: .top, spacing: 5) {
          HeatmapWeekdayAxis(labels: layout.weekdayLabels, cellSize: cellSize, gap: metrics.gap)
          HStack(alignment: .top, spacing: metrics.gap) {
            ForEach(layout.weeks) { week in
              VStack(spacing: metrics.gap) {
                ForEach(0..<7, id: \.self) { weekdayIndex in
                  let day = week.cells[weekdayIndex]
                  RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(day.map { colorForValue(dayValue($0, series: selectedSeries), maxValue) } ?? Color.white.opacity(0.045))
                    .frame(width: cellSize, height: cellSize)
                    .help(day.map { "\($0.day): \($0.requests) requests" } ?? "No activity")
                }
              }
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(height: 118)
  }

  private func dayValue(_ day: TokMonHeatmapDay, series: TokMonSeriesKey) -> Double {
    switch series {
    case .total:
      return Double(day.inputTokens + day.outputTokens + day.cacheRead)
    case .requests:
      return Double(day.requests)
    case .input:
      return Double(day.inputTokens)
    case .output:
      return Double(day.outputTokens)
    case .cache:
      return Double(day.cacheCreation)
    case .cacheHit:
      return Double(day.cacheRead)
    case .cacheHitRate:
      let denominator = day.inputTokens + day.cacheRead
      guard denominator > 0 else { return 0 }
      return Double(day.cacheRead) / Double(denominator)
    case .cost:
      return Double(day.inputTokens + day.outputTokens + day.cacheCreation + day.cacheRead)
    }
  }
}

private struct HeatmapMonthAxis: View {
  let layout: TokMonHeatmapLayout
  let metrics: TokMonHeatmapLayout.Metrics

  var body: some View {
    ZStack(alignment: .leading) {
      Color.clear.frame(height: 12)
      ForEach(layout.monthLabels) { month in
        Text(month.label)
          .font(.system(size: 9, weight: .bold, design: .rounded))
          .foregroundStyle(TokMonGlass.mutedTint)
          .offset(x: metrics.labelWidth + CGFloat(month.weekIndex) * (metrics.cellSize + metrics.gap))
      }
    }
    .frame(width: metrics.usedWidth, height: 12, alignment: .leading)
  }
}

private struct HeatmapWeekdayAxis: View {
  let labels: [TokMonHeatmapLayout.WeekdayLabel]
  let cellSize: CGFloat
  let gap: CGFloat

  var body: some View {
    ZStack(alignment: .topLeading) {
      Color.clear.frame(width: 18, height: cellSize * 7 + gap * 6)
      ForEach(labels) { label in
        Text(label.label)
          .font(.system(size: 8, weight: .bold, design: .rounded))
          .foregroundStyle(TokMonGlass.mutedTint)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
          .offset(y: CGFloat(label.weekdayIndex) * (cellSize + gap) - 1)
      }
    }
    .frame(width: 26, height: cellSize * 7 + gap * 6, alignment: .topLeading)
  }
}

private struct TrendLineChart: View {
  let points: [TokMonTrendPoint]
  let color: Color

  var body: some View {
    GeometryReader { proxy in
      let yAxisWidth: CGFloat = 36
      let xAxisHeight: CGFloat = 14
      let chartRect = CGRect(
        x: yAxisWidth,
        y: 0,
        width: max(proxy.size.width - yAxisWidth, 1),
        height: max(proxy.size.height - xAxisHeight, 1),
      )
      let scale = TrendChartScale(points: points)
      let chartPoints = normalizedPoints(in: chartRect.size, scale: scale)
      VStack(spacing: 2) {
        HStack(spacing: 4) {
          TrendYAxisLabels(scale: scale, height: chartRect.height, formatValue: formatAxisValue)
            .frame(width: yAxisWidth, height: chartRect.height)
          ZStack {
            ChartGrid(horizontalLines: 3, verticalLines: 6)
              .stroke(Color.white.opacity(0.08), lineWidth: 1)
            if chartPoints.count > 1 {
              smoothedTrendFill(points: chartPoints, size: chartRect.size)
                .fill(
                  LinearGradient(
                    colors: [color.opacity(0.22), TokMonGlass.success.opacity(0.12), Color.clear],
                    startPoint: .leading,
                    endPoint: .trailing,
                  )
                )
              smoothedTrendPath(points: chartPoints)
                .stroke(color.opacity(0.42), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
          }
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        TrendXAxisLabels(points: points, leadingPadding: yAxisWidth + 4)
          .frame(height: xAxisHeight)
      }
    }
  }

  private func normalizedPoints(in size: CGSize, scale: TrendChartScale) -> [CGPoint] {
    guard !points.isEmpty else { return [] }
    let horizontalInset: CGFloat = 4
    let drawableWidth = max(size.width - horizontalInset * 2, 1)
    let step = points.count > 1 ? drawableWidth / CGFloat(points.count - 1) : 0
    return points.enumerated().map { index, point in
      let x = horizontalInset + CGFloat(index) * step
      let normalized = scale.normalized(point.value)
      let y = size.height - CGFloat(normalized) * max(size.height - 12, 1) - 6
      return CGPoint(x: x, y: y)
    }
  }

  private func formatAxisValue(_ value: Double) -> String {
    if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1fK", value / 1_000) }
    return String(format: "%.0f", value)
  }

  private func smoothedTrendPath(points: [CGPoint]) -> Path {
    Path { path in
      guard let first = points.first else { return }
      path.move(to: first)
      addSmoothedCurve(to: &path, points: points)
    }
  }

  private func smoothedTrendFill(points: [CGPoint], size: CGSize) -> Path {
    Path { path in
      guard let first = points.first, let last = points.last else { return }
      path.move(to: CGPoint(x: first.x, y: size.height))
      path.addLine(to: first)
      addSmoothedCurve(to: &path, points: points)
      path.addLine(to: CGPoint(x: last.x, y: size.height))
      path.closeSubpath()
    }
  }

  private func addSmoothedCurve(to path: inout Path, points: [CGPoint]) {
    guard points.count > 1 else { return }

    for index in 0..<(points.count - 1) {
      let current = points[index]
      let next = points[index + 1]
      let previous = index > 0 ? points[index - 1] : current
      let following = index + 2 < points.count ? points[index + 2] : next
      let tension: CGFloat = 0.18
      let rawFirstControl = CGPoint(
        x: current.x + (next.x - previous.x) * tension,
        y: current.y + (next.y - previous.y) * tension,
      )
      let rawSecondControl = CGPoint(
        x: next.x - (following.x - current.x) * tension,
        y: next.y - (following.y - current.y) * tension,
      )
      let firstControl = boundedControlPoint(rawFirstControl, from: current, to: next)
      let secondControl = boundedControlPoint(rawSecondControl, from: current, to: next)

      path.addCurve(to: next, control1: firstControl, control2: secondControl)
    }
  }

  private func boundedControlPoint(_ point: CGPoint, from current: CGPoint, to next: CGPoint) -> CGPoint {
    CGPoint(
      x: clamp(point.x, min(current.x, next.x), max(current.x, next.x)),
      y: clamp(point.y, min(current.y, next.y), max(current.y, next.y)),
    )
  }

  private func clamp(_ value: CGFloat, _ lowerBound: CGFloat, _ upperBound: CGFloat) -> CGFloat {
    min(max(value, lowerBound), upperBound)
  }
}

private struct TrendChartScale {
  let minValue: Double
  let maxValue: Double
  let range: Double

  init(points: [TokMonTrendPoint]) {
    let values = points.map(\.value)
    let rawMin = min(values.min() ?? 0, 0)
    let rawMax = values.max() ?? 0
    minValue = rawMin
    maxValue = rawMax
    range = max(rawMax - rawMin, 1)
  }

  func normalized(_ value: Double) -> Double {
    (value - minValue) / range
  }
}

private struct TrendYAxisLabels: View {
  let scale: TrendChartScale
  let height: CGFloat
  let formatValue: (Double) -> String

  var body: some View {
    VStack(alignment: .trailing) {
      Text(formatValue(scale.maxValue))
      Spacer()
      Text(formatValue((scale.maxValue + scale.minValue) / 2))
      Spacer()
      Text(formatValue(scale.minValue))
    }
    .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
    .foregroundStyle(TokMonGlass.mutedTint)
    .frame(height: height)
  }
}

private struct TrendXAxisLabels: View {
  let points: [TokMonTrendPoint]
  let leadingPadding: CGFloat

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        ForEach(axisTickIndices, id: \.self) { index in
          Text(shortAxisLabel(points[index].label))
            .frame(width: 46, alignment: index == axisTickIndices.last ? .trailing : .center)
            .offset(x: tickOffset(index: index, width: proxy.size.width))
        }
      }
    }
    .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
    .foregroundStyle(TokMonGlass.mutedTint)
    .lineLimit(1)
    .padding(.leading, leadingPadding)
  }

  private var axisTickIndices: [Int] {
    guard points.count > 1 else { return points.isEmpty ? [] : [0] }
    let desiredTickCount = min(points.count, 5)
    return (0..<desiredTickCount).map { tick in
      Int((Double(points.count - 1) * Double(tick) / Double(desiredTickCount - 1)).rounded())
    }.reduce(into: []) { result, index in
      if result.last != index {
        result.append(index)
      }
    }
  }

  private var isSingleHourlyDay: Bool {
    let dayLabels = Set(points.compactMap { point -> String? in
      guard point.label.count >= 10 else { return nil }
      return String(point.label.prefix(10))
    })
    return dayLabels.count == 1 && points.contains { $0.label.count >= 16 }
  }

  private func tickOffset(index: Int, width: CGFloat) -> CGFloat {
    guard points.count > 1 else { return 0 }
    let labelWidth: CGFloat = 46
    let drawableWidth = max(width - labelWidth, 1)
    let progress = CGFloat(index) / CGFloat(points.count - 1)
    return drawableWidth * progress
  }

  private func shortAxisLabel(_ label: String?) -> String {
    guard let label else { return "" }
    if label.count >= 16 {
      let timeStart = label.index(label.startIndex, offsetBy: 11)
      let timeEnd = label.index(label.startIndex, offsetBy: 16)
      if isSingleHourlyDay {
        return String(label[timeStart..<timeEnd])
      }
      let start = label.index(label.startIndex, offsetBy: 5)
      let end = label.index(label.startIndex, offsetBy: 16)
      return String(label[start..<end])
    }
    if label.count >= 10 {
      let start = label.index(label.startIndex, offsetBy: 5)
      return String(label[start...])
    }
    return label
  }
}

private struct ChartGrid: Shape {
  let horizontalLines: Int
  let verticalLines: Int

  func path(in rect: CGRect) -> Path {
    var path = Path()
    for index in 1...horizontalLines {
      let y = rect.minY + rect.height * CGFloat(index) / CGFloat(horizontalLines + 1)
      path.move(to: CGPoint(x: rect.minX, y: y))
      path.addLine(to: CGPoint(x: rect.maxX, y: y))
    }
    for index in 1...verticalLines {
      let x = rect.minX + rect.width * CGFloat(index) / CGFloat(verticalLines + 1)
      path.move(to: CGPoint(x: x, y: rect.minY))
      path.addLine(to: CGPoint(x: x, y: rect.maxY))
    }
    return path
  }
}

private struct RequestRowView: View {
  let row: TokMonRecordRow
  let isExpanded: Bool
  let costRates: TokMonCostRates
  let sourceLabel: String
  let sourceColor: Color
  let formatCompact: (Double?) -> String
  let formatCost: (Double?) -> String
  let onToggleDetails: () -> Void
  let onJumpToSession: (() -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(row.model)
          .font(.system(size: 14, weight: .heavy, design: .rounded))
          .lineLimit(1)
        Spacer()
        Text(shortTimestamp(row.createdAt))
          .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
          .foregroundStyle(TokMonGlass.mutedTint)
      }
      HStack(spacing: 10) {
        Text(sourceLabel)
          .font(.system(size: 12, weight: .bold, design: .rounded))
          .foregroundStyle(sourceColor)
        Text(row.sessionId)
          .font(.system(size: 12, weight: .medium, design: .monospaced))
          .foregroundStyle(TokMonGlass.mutedTint)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      HStack(alignment: .bottom, spacing: 10) {
        RequestTokenChipGrid(
          chips: [
            TokenChipData(label: "In", value: formatCompact(Double(row.inputTokens))),
            TokenChipData(label: "Out", value: formatCompact(Double(row.outputTokens))),
            TokenChipData(label: "Cache", value: formatCompact(Double(row.cacheCreation + row.cacheRead))),
            TokenChipData(label: "$", value: formatCost(cost)),
          ],
        )
        VStack(alignment: .trailing, spacing: 5) {
          Button(isExpanded ? "Hide" : "Details") {
            onToggleDetails()
          }
          .buttonStyle(.plain)
          .foregroundStyle(TokMonGlass.mutedTint)
          if let onJumpToSession {
            Button("Jump", action: onJumpToSession)
              .buttonStyle(.plain)
              .foregroundStyle(TokMonGlass.mutedTint)
          }
        }
        .font(.system(size: 11, weight: .bold, design: .rounded))
      }
      if isExpanded {
        VStack(alignment: .leading, spacing: 3) {
          DetailLine(label: "Created", value: row.createdAt)
          DetailLine(label: "Session", value: row.sessionId)
          DetailLine(label: "Cache Created", value: formatCompact(Double(row.cacheCreation)))
          DetailLine(label: "Cache Read", value: formatCompact(Double(row.cacheRead)))
          DetailLine(label: "Reasoning", value: formatCompact(Double(row.reasoningTokens)))
        }
      }
    }
    .padding(14)
    .hudInsetCard()
  }

  private var cost: Double {
    costRates.cost(
      inputTokens: row.inputTokens,
      outputTokens: row.outputTokens,
      cacheCreation: row.cacheCreation,
      cacheRead: row.cacheRead,
    )
  }
}

private struct TokenChipData: Identifiable {
  let label: String
  let value: String

  var id: String { label }
}

private struct RequestTokenChipGrid: View {
  let chips: [TokenChipData]

  var body: some View {
    LazyVGrid(
      columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
      alignment: .leading,
      spacing: 5,
    ) {
      ForEach(chips) { chip in
        TokenChip(label: chip.label, value: chip.value)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct SessionRowView: View {
  let session: TokMonUsageSession
  let isSelected: Bool
  let costRates: TokMonCostRates
  let sourceLabel: String
  let sourceColor: Color
  let formatCompact: (Double?) -> String
  let formatCost: (Double?) -> String
  let onSelect: () -> Void

  var body: some View {
    Button(action: onSelect) {
      HStack(spacing: 12) {
        Circle()
          .fill(sourceColor)
          .frame(width: 8, height: 8)
        VStack(alignment: .leading, spacing: 4) {
          Text(session.title ?? session.sessionId)
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .lineLimit(1)
            .truncationMode(.middle)
          Text("\(sourceLabel) · \(session.model) · \(session.requests) req")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(TokMonGlass.mutedTint)
            .lineLimit(1)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 4) {
          Text(formatCompact(Double(session.inputTokens + session.outputTokens + session.cacheRead)))
            .font(.system(size: 13, weight: .heavy, design: .rounded).monospacedDigit())
          Text(formatCost(cost))
            .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(TokMonGlass.mutedTint)
        }
      }
      .padding(14)
      .hudInsetCard(isSelected: isSelected)
    }
    .buttonStyle(.plain)
    .focusable(false)
  }

  private var cost: Double {
    costRates.cost(
      inputTokens: session.inputTokens,
      outputTokens: session.outputTokens,
      cacheCreation: session.cacheCreation,
      cacheRead: session.cacheRead,
    )
  }
}

private struct DetailLine: View {
  let label: String
  let value: String

  var body: some View {
    HStack {
      Text(label)
        .foregroundStyle(TokMonGlass.mutedTint)
      Spacer()
      Text(value)
        .lineLimit(1)
        .truncationMode(.middle)
    }
    .font(.system(size: 12, weight: .semibold, design: .rounded))
  }
}

private struct TokenChip: View {
  let label: String
  let value: String

  var body: some View {
    HStack(spacing: 4) {
      Text(label)
        .foregroundStyle(TokMonGlass.mutedTint)
      Text(value)
        .foregroundStyle(TokMonGlass.neutralTint)
    }
    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
    .lineLimit(1)
  }
}

private struct LoadMoreButton: View {
  let title: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(title, systemImage: "plus.circle")
        .font(.system(size: 13, weight: .bold, design: .rounded))
        .frame(maxWidth: .infinity)
    }
    .tokMonGlassButton()
    .focusable(false)
  }
}

private struct HudCardModifier: ViewModifier {
  var isSelected = false

  func body(content: Content) -> some View {
    content
      .background {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(TokMonGlass.hudCardFill)
          .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
              .fill(
                LinearGradient(
                  colors: [Color.white.opacity(0.05), Color.clear],
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing,
                )
              )
          }
          .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
              .strokeBorder(isSelected ? TokMonGlass.accent.opacity(0.42) : TokMonGlass.hudCardStroke, lineWidth: 1)
          }
      }
  }
}

private struct HudInsetCardModifier: ViewModifier {
  var isSelected = false

  func body(content: Content) -> some View {
    content
      .background {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(Color.black.opacity(0.14))
          .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
              .strokeBorder(isSelected ? TokMonGlass.accent.opacity(0.36) : Color.white.opacity(0.08), lineWidth: 1)
          }
      }
  }
}

private extension View {
  func hudCard(isSelected: Bool = false) -> some View {
    modifier(HudCardModifier(isSelected: isSelected))
  }

  func hudInsetCard(isSelected: Bool = false) -> some View {
    modifier(HudInsetCardModifier(isSelected: isSelected))
  }
}

private func shortTimestamp(_ value: String) -> String {
  if value.count >= 16 {
    let start = value.index(value.startIndex, offsetBy: 5)
    let end = value.index(value.startIndex, offsetBy: 16)
    return String(value[start..<end])
  }
  return value
}

private struct TokMonSeriesPresentation {
  let key: TokMonSeriesKey
  let label: String
  let icon: String
  let isCost: Bool
  let isPercent: Bool

  init(rawValue: String) {
    self.init(key: TokMonSeriesKey(rawValue))
  }

  init(key: TokMonSeriesKey) {
    self.key = key
    switch key {
    case .requests:
      label = "Requests"
      icon = "#"
      isCost = false
      isPercent = false
    case .input:
      label = "Input Tokens"
      icon = "→"
      isCost = false
      isPercent = false
    case .output:
      label = "Output Tokens"
      icon = "←"
      isCost = false
      isPercent = false
    case .cache:
      label = "Cache Created"
      icon = "◆"
      isCost = false
      isPercent = false
    case .cacheHit:
      label = "Cache Hit"
      icon = "✦"
      isCost = false
      isPercent = false
    case .cacheHitRate:
      label = "Hit Rate"
      icon = "%"
      isCost = false
      isPercent = true
    case .cost:
      label = "Est. Cost"
      icon = "$"
      isCost = true
      isPercent = false
    case .total:
      label = "Total Tokens"
      icon = "Σ"
      isCost = false
      isPercent = false
    }
  }

  static let total = TokMonSeriesPresentation(key: .total)
  static let requests = TokMonSeriesPresentation(key: .requests)
  static let input = TokMonSeriesPresentation(key: .input)
  static let output = TokMonSeriesPresentation(key: .output)
  static let cache = TokMonSeriesPresentation(key: .cache)
  static let cacheHit = TokMonSeriesPresentation(key: .cacheHit)
  static let cacheHitRate = TokMonSeriesPresentation(key: .cacheHitRate)
  static let cost = TokMonSeriesPresentation(key: .cost)

  var compactLabel: String {
    switch key {
    case .input:
      "Input"
    case .output:
      "Output"
    case .cache:
      "Cache New"
    case .cacheHit:
      "Cache Hit"
    case .cacheHitRate:
      "Hit Rate"
    case .cost:
      "Cost"
    case .requests:
      "Requests"
    case .total:
      "Total"
    }
  }

  var tintColor: Color {
    switch key {
    case .cacheHitRate, .cost:
      TokMonGlass.success
    case .cache, .cacheHit:
      TokMonGlass.warning
    default:
      TokMonGlass.accent
    }
  }
}
