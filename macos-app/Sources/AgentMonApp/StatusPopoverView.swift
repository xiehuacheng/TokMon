import SwiftUI

struct StatusPopoverView: View {
  @EnvironmentObject private var runtime: AgentMonRuntime
  @EnvironmentObject private var server: AgentMonServer
  @EnvironmentObject private var stats: AgentMonStatsStore
  @State private var selectedSeries = TokMonSeriesPresentation(rawValue: "total")

  private let numberFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter
  }()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        header

        if let errorMessage = stats.errorMessage {
          Text(errorMessage)
            .font(.caption)
            .foregroundStyle(TokMonMetricColor.red.swiftUIColor)
            .lineLimit(2)
        }

        dashboardStatePanel
        metricsGrid
        trendPanel
        scanStatus
        sourceBreakdown
        modelBreakdown
        footer
      }
      .padding(16)
    }
    .frame(width: 360, height: 500)
    .onChange(of: stats.snapshot.dashboardState?.activeSeries, initial: true) { _, activeSeries in
      selectedSeries = TokMonSeriesPresentation(rawValue: activeSeries ?? "total")
    }
  }

  private var header: some View {
    HStack(alignment: .center) {
      VStack(alignment: .leading, spacing: 3) {
        Text("AgentMon")
          .font(.headline)
        Text(serverLine)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if !runtime.usesNativeTokMonEngine {
        Button {
          runtime.openDashboard()
        } label: {
          Image(systemName: "safari")
            .font(.system(size: 14, weight: .semibold))
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("Open Dashboard")
      }

      Button {
        runtime.quit()
      } label: {
        Image(systemName: "power")
          .font(.system(size: 14, weight: .semibold))
          .frame(width: 24, height: 24)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .focusable(false)
      .help("Quit AgentMon")

      if !runtime.usesNativeTokMonEngine {
        Button {
          server.restart()
        } label: {
          Label("Restart Dashboard Service", systemImage: server.phase == .starting ? "arrow.triangle.2.circlepath.circle" : "arrow.clockwise")
            .labelStyle(.iconOnly)
            .font(.system(size: 14, weight: .semibold))
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(server.phase == .starting)
        .accessibilityLabel("Restart Dashboard Service")
        .help("Restart Dashboard Service")
      }
    }
  }

  private var metricsGrid: some View {
    let totals = stats.snapshot.summary?.total

    return LazyVGrid(
      columns: [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
      ],
      alignment: .leading,
      spacing: 6,
    ) {
      MetricTile(
        series: .total,
        value: formatCompact(totals?.totalTokens),
        isSelected: selectedSeries.key == .total,
        onSelect: selectSeries,
      )
      MetricTile(
        series: .requests,
        value: formatCompact(totals?.totalRequests),
        isSelected: selectedSeries.key == .requests,
        onSelect: selectSeries,
      )
      MetricTile(
        series: .input,
        value: formatCompact(totals?.totalInput),
        isSelected: selectedSeries.key == .input,
        onSelect: selectSeries,
      )
      MetricTile(
        series: .output,
        value: formatCompact(totals?.totalOutput),
        isSelected: selectedSeries.key == .output,
        onSelect: selectSeries,
      )
      MetricTile(
        series: .cache,
        value: formatCompact(totals?.totalCacheCreation),
        isSelected: selectedSeries.key == .cache,
        onSelect: selectSeries,
      )
      MetricTile(
        series: .cacheHit,
        value: formatCompact(totals?.totalCacheRead),
        isSelected: selectedSeries.key == .cacheHit,
        onSelect: selectSeries,
      )
      MetricTile(
        series: .cost,
        value: formatCost(currentEstimatedCost),
        isSelected: selectedSeries.key == .cost,
        onSelect: selectSeries,
      )
    }
  }

  private var dashboardStatePanel: some View {
    Group {
      if let state = stats.snapshot.dashboardState {
        VStack(spacing: 6) {
          HStack(spacing: 6) {
            StatePill(label: "Range", value: state.rangeDisplay)
            StatePill(label: "Source", value: state.sourceLabel)
          }
          HStack(spacing: 6) {
            StatePill(label: "Mode", value: "\(state.liveMode ? "Live" : "Fixed") · \(state.interval.capitalized)")
            StatePill(label: "Time", value: state.rangeModeLabel)
          }
        }
      } else {
        Text("Waiting for dashboard settings...")
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(8)
    .background(Color(nsColor: .controlBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  private var scanStatus: some View {
    return VStack(alignment: .leading, spacing: 8) {
      SectionTitle("Scan")

      if let scanStatus = stats.snapshot.scanStatus {
        HStack {
          Circle()
            .fill(scanStatus.running ? TokMonMetricColor.accent.swiftUIColor : TokMonMetricColor.green.swiftUIColor)
            .frame(width: 8, height: 8)
          Text(scanStatus.phase)
            .font(.caption)
            .lineLimit(1)
          Spacer()
          Text(scanStatus.running ? "\(scanStatus.current)/\(scanStatus.total)" : "Idle")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }

        if scanStatus.running, scanStatus.total > 0 {
          ProgressView(value: Double(scanStatus.current), total: Double(scanStatus.total))
        }

        if let error = scanStatus.error, !error.isEmpty {
          Text(error)
            .font(.caption2)
            .foregroundStyle(TokMonMetricColor.red.swiftUIColor)
            .lineLimit(2)
        }
      } else {
        Text("Waiting for scan status...")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var trendPanel: some View {
    let trendPoints = trendPoints(for: selectedSeries.key)

    return VStack(alignment: .leading, spacing: 8) {
      HStack {
        SectionTitle("Trend")
        Spacer()
        Text(selectedSeries.label)
          .font(.caption2)
          .foregroundStyle(selectedSeries.color.swiftUIColor)
      }

      if trendPoints.isEmpty {
        Text("No trend data in the selected range.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        TrendLineChart(
          points: trendPoints,
          color: selectedSeries.color.swiftUIColor,
          valueFormatter: selectedSeries.isCost ? formatCost : formatChartValue,
        )
        .frame(maxWidth: .infinity, minHeight: 132, maxHeight: 132)
      }
    }
    .padding(10)
    .background(Color(nsColor: .controlBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  private var sourceBreakdown: some View {
    let costRates = stats.snapshot.dashboardState?.costRates ?? .zero
    let selectedKey = selectedSeries.key

    return VStack(alignment: .leading, spacing: 8) {
      SectionTitle("Sources")

      let sources = stats.snapshot.summary?.bySource ?? []
      if sources.isEmpty {
        Text("No usage in the selected range.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        ForEach(sources.sorted { $0.value(for: selectedKey, costRates: costRates) > $1.value(for: selectedKey, costRates: costRates) }) { source in
          HStack {
            Text(labelForSource(source.source))
              .font(.caption)
              .foregroundStyle(colorForSource(source.source))
            Spacer()
            Text(formatMetricValue(source.value(for: selectedKey, costRates: costRates)))
              .font(.caption.monospacedDigit())
              .foregroundStyle(.primary)
          }
        }
      }
    }
  }

  private var modelBreakdown: some View {
    let costRates = stats.snapshot.dashboardState?.costRates ?? .zero
    let selectedKey = selectedSeries.key

    return VStack(alignment: .leading, spacing: 8) {
      SectionTitle("Top Models")

      let models = Array((stats.snapshot.summary?.byModel ?? [])
        .sorted { $0.value(for: selectedKey, costRates: costRates) > $1.value(for: selectedKey, costRates: costRates) }
        .prefix(4))

      if models.isEmpty {
        Text("No model activity yet.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        ForEach(models) { model in
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(model.model)
                .font(.caption)
                .lineLimit(1)
              Text(labelForSource(model.source))
                .font(.caption2)
                .foregroundStyle(colorForSource(model.source))
            }
            Spacer()
            Text(formatMetricValue(model.value(for: selectedKey, costRates: costRates)))
              .font(.caption.monospacedDigit())
              .foregroundStyle(.primary)
          }
        }
      }
    }
  }

  private var footer: some View {
    Text(updatedLine)
      .font(.caption2)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, 2)
  }

  private var serverLine: String {
    if runtime.usesNativeTokMonEngine {
      return "Native TokMon"
    }

    switch server.phase {
    case .idle:
      return "Ready"
    case .starting:
      return "Starting local server"
    case .running(let attached):
      return attached ? "Connected to existing server" : "Local server running"
    case .failed:
      return "Server failed"
    }
  }

  private var currentEstimatedCost: Double? {
    guard
      let summary = stats.snapshot.summary,
      let costRates = stats.snapshot.dashboardState?.costRates
    else {
      return stats.snapshot.dashboardState?.estimatedCost
    }

    return summary.estimatedCost(costRates: costRates)
  }

  private var updatedLine: String {
    guard let updatedAt = stats.snapshot.updatedAt else {
      return "Not refreshed yet"
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
    selectedSeries.isCost ? formatCost(value) : formatChartValue(value)
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

  private func trendPoints(for seriesKey: TokMonSeriesKey) -> [TokMonTrendPoint] {
    let costRates = stats.snapshot.dashboardState?.costRates ?? .zero
    return stats.snapshot.trendBuckets.map { bucket in
      TokMonTrendPoint(
        id: "\(seriesKey.rawValue):\(bucket.bucket)",
        label: bucket.bucket,
        value: bucket.value(for: seriesKey, costRates: costRates),
      )
    }
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
      TokMonMetricColor.orange.swiftUIColor
    case "codex":
      TokMonMetricColor.accent.swiftUIColor
    default:
      TokMonMetricColor.purple.swiftUIColor
    }
  }
}

private struct MetricTile: View {
  let series: TokMonSeriesPresentation
  let value: String
  let isSelected: Bool
  let onSelect: (TokMonSeriesPresentation) -> Void

  var body: some View {
    Button {
      onSelect(series)
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
          Text(series.icon)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(series.color.swiftUIColor)
          Text(series.label)
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
        }
        Text(value)
          .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
          .foregroundStyle(series.color.swiftUIColor)
          .lineLimit(1)
          .minimumScaleFactor(0.62)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 7)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(Color(nsColor: .controlBackgroundColor))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .stroke(isSelected ? series.color.swiftUIColor : Color.clear, lineWidth: 1.5)
      )
      .contentShape(RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .focusable(false)
  }
}

private struct StatePill: View {
  let label: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label.uppercased())
        .font(.system(size: 8, weight: .semibold, design: .rounded))
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Text(value)
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.primary)
        .lineLimit(1)
        .truncationMode(.middle)
        .minimumScaleFactor(0.75)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct TrendLineChart: View {
  let points: [TokMonTrendPoint]
  let color: Color
  let valueFormatter: (Double?) -> String

  var body: some View {
    let values = points.map(\.value)
    let maxValue = values.max() ?? 0
    let minValue = values.min() ?? 0
    let hasVariation = maxValue > minValue

    GeometryReader { proxy in
      let size = proxy.size
      let yAxisWidth: CGFloat = 44
      let trailingInset: CGFloat = 2
      let xAxisHeight: CGFloat = 22
      let plotRect = CGRect(
        x: yAxisWidth,
        y: 0,
        width: max(size.width - yAxisWidth - trailingInset, 1),
        height: max(size.height - xAxisHeight, 1),
      )
      let chartPoints = pathPoints(in: plotRect.size, minValue: minValue, maxValue: maxValue, hasVariation: hasVariation)
        .map { CGPoint(x: $0.x + plotRect.minX, y: $0.y + plotRect.minY) }
      let xAxisRect = CGRect(
        x: plotRect.minX,
        y: plotRect.maxY,
        width: plotRect.width,
        height: xAxisHeight,
      )

      ZStack {
        RoundedRectangle(cornerRadius: 6)
          .fill(Color(nsColor: .windowBackgroundColor).opacity(0.35))

        ChartGrid(horizontalLines: 3, verticalLines: 4)
          .stroke(Color.secondary.opacity(0.16), style: StrokeStyle(lineWidth: 0.7, dash: [3, 4]))
          .frame(width: plotRect.width, height: plotRect.height)
          .position(x: plotRect.midX, y: plotRect.midY)

        ChartYAxisLabels(
          minValue: minValue,
          maxValue: maxValue,
          formatter: valueFormatter,
          horizontalLines: 3,
        )
        .frame(width: yAxisWidth - 8, height: plotRect.height)
        .position(x: (yAxisWidth - 8) / 2, y: plotRect.midY)

        Path { path in
          guard !chartPoints.isEmpty else { return }
          path.move(to: chartPoints[0])
          if chartPoints.count == 2 {
            path.addLine(to: chartPoints[1])
          } else {
            for index in 0..<(chartPoints.count - 1) {
              let previous = chartPoints[max(index - 1, 0)]
              let current = chartPoints[index]
              let next = chartPoints[index + 1]
              let nextNext = chartPoints[min(index + 2, chartPoints.count - 1)]
              let controlScale: CGFloat = 0.18
              let rawControl1 = CGPoint(
                x: current.x + (next.x - previous.x) * controlScale,
                y: current.y + (next.y - previous.y) * controlScale,
              )
              let rawControl2 = CGPoint(
                x: next.x - (nextNext.x - current.x) * controlScale,
                y: next.y - (nextNext.y - current.y) * controlScale,
              )
              let control1 = boundedControlPoint(rawControl1, from: current, to: next)
              let control2 = boundedControlPoint(rawControl2, from: current, to: next)
              path.addCurve(to: next, control1: control1, control2: control2)
            }
          }
        }
        .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

        if let lastPoint = chartPoints.last {
          Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .position(lastPoint)
        }

        ChartXAxisLabels(ticks: xAxisTicks)
          .frame(width: xAxisRect.width, height: xAxisRect.height)
          .position(x: xAxisRect.midX, y: xAxisRect.midY)
      }
    }
    .frame(maxWidth: .infinity)
  }

  private var xAxisTicks: [(index: Int, label: String, alignment: Alignment)] {
    guard !points.isEmpty else { return [] }
    let maxTicks = min(points.count, 5)
    let indexes: [Int]

    if maxTicks == 1 {
      indexes = [0]
    } else {
      indexes = (0..<maxTicks).reduce(into: []) { result, tick in
        let rawIndex = Double(tick) * Double(points.count - 1) / Double(maxTicks - 1)
        let index = Int(rawIndex.rounded())
        if result.last != index {
          result.append(index)
        }
      }
    }

    return indexes.enumerated().map { position, index in
      let alignment: Alignment
      if position == 0 {
        alignment = .leading
      } else if position == indexes.count - 1 {
        alignment = .trailing
      } else {
        alignment = .center
      }

      return (index, compactXAxisLabel(points[index].label), alignment)
    }
  }

  private func compactXAxisLabel(_ label: String) -> String {
    if let hourRange = label.range(of: #" \d{2}:00$"#, options: .regularExpression) {
      return String(label[hourRange].dropFirst())
    }

    if label.count >= 10 {
      let start = label.index(label.startIndex, offsetBy: 5)
      let end = label.index(label.startIndex, offsetBy: 10)
      return String(label[start..<end])
    }

    return label
  }

  private func pathPoints(in size: CGSize, minValue: Double, maxValue: Double, hasVariation: Bool) -> [CGPoint] {
    guard !points.isEmpty, size.width > 0, size.height > 0 else { return [] }
    let horizontalStep = points.count > 1 ? size.width / CGFloat(points.count - 1) : 0
    let verticalPadding: CGFloat = 3
    let drawableHeight = max(size.height - verticalPadding * 2, 1)

    return points.enumerated().map { index, point in
      let x = points.count > 1 ? CGFloat(index) * horizontalStep : size.width / 2
      let normalized = hasVariation ? (point.value - minValue) / (maxValue - minValue) : 0.5
      let y = verticalPadding + CGFloat(1 - normalized) * drawableHeight
      return CGPoint(x: x, y: y)
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

private struct ChartGrid: Shape {
  let horizontalLines: Int
  let verticalLines: Int

  func path(in rect: CGRect) -> Path {
    var path = Path()

    if horizontalLines > 0 {
      for index in 1...horizontalLines {
        let y = rect.minY + rect.height * CGFloat(index) / CGFloat(horizontalLines + 1)
        path.move(to: CGPoint(x: rect.minX, y: y))
        path.addLine(to: CGPoint(x: rect.maxX, y: y))
      }
    }

    if verticalLines > 0 {
      for index in 1...verticalLines {
        let x = rect.minX + rect.width * CGFloat(index) / CGFloat(verticalLines + 1)
        path.move(to: CGPoint(x: x, y: rect.minY))
        path.addLine(to: CGPoint(x: x, y: rect.maxY))
      }
    }

    return path
  }
}

private struct ChartYAxisLabels: View {
  let minValue: Double
  let maxValue: Double
  let formatter: (Double?) -> String
  let horizontalLines: Int

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .topTrailing) {
        ForEach(labelTicks, id: \.offset) { tick in
          Text(formatter(tick.value))
            .font(.system(size: 8, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .position(x: proxy.size.width / 2, y: proxy.size.height * tick.offset)
        }
      }
    }
  }

  private var labelTicks: [(offset: CGFloat, value: Double)] {
    let count = max(horizontalLines + 2, 2)
    let range = maxValue - minValue

    return (0..<count).map { index in
      let fraction = Double(index) / Double(count - 1)
      let offset = CGFloat(fraction)
      let value = maxValue - range * fraction
      return (offset, value)
    }
  }
}

private struct ChartXAxisLabels: View {
  let ticks: [(index: Int, label: String, alignment: Alignment)]

  var body: some View {
    HStack(spacing: 0) {
      ForEach(ticks, id: \.index) { tick in
        Text(tick.label)
          .font(.system(size: 8, weight: .medium, design: .monospaced))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .frame(maxWidth: .infinity, alignment: tick.alignment)
      }
    }
    .padding(.top, 5)
  }
}

private struct TokMonSeriesPresentation {
  let key: TokMonSeriesKey
  let label: String
  let icon: String
  let color: TokMonMetricColor
  let isCost: Bool

  init(rawValue: String) {
    self.init(key: TokMonSeriesKey(rawValue))
  }

  init(key: TokMonSeriesKey) {
    self.key = key
    switch key {
    case .requests:
      label = "Requests"
      icon = "⚡"
      color = .green
      isCost = false
    case .input:
      label = "Input Tokens"
      icon = "→"
      color = .purple
      isCost = false
    case .output:
      label = "Output Tokens"
      icon = "←"
      color = .pink
      isCost = false
    case .cache:
      label = "Cache Created"
      icon = "◆"
      color = .orange
      isCost = false
    case .cacheHit:
      label = "Cache Hit"
      icon = "✦"
      color = .red
      isCost = false
    case .cost:
      label = "Est. Cost"
      icon = "$"
      color = .teal
      isCost = true
    case .total:
      label = "Total Tokens"
      icon = "∑"
      color = .accent
      isCost = false
    }
  }

  static let total = TokMonSeriesPresentation(key: .total)
  static let requests = TokMonSeriesPresentation(key: .requests)
  static let input = TokMonSeriesPresentation(key: .input)
  static let output = TokMonSeriesPresentation(key: .output)
  static let cache = TokMonSeriesPresentation(key: .cache)
  static let cacheHit = TokMonSeriesPresentation(key: .cacheHit)
  static let cost = TokMonSeriesPresentation(key: .cost)
}

private enum TokMonMetricColor {
  case accent
  case green
  case orange
  case pink
  case purple
  case red
  case teal

  var swiftUIColor: Color {
    Color(nsColor: nsColor)
  }

  private var nsColor: NSColor {
    switch self {
    case .accent:
      NSColor(red: 0x58 / 255, green: 0xa6 / 255, blue: 0xff / 255, alpha: 1)
    case .green:
      NSColor(red: 0x3f / 255, green: 0xb9 / 255, blue: 0x50 / 255, alpha: 1)
    case .orange:
      NSColor(red: 0xd2 / 255, green: 0x99 / 255, blue: 0x22 / 255, alpha: 1)
    case .pink:
      NSColor(red: 0xf7 / 255, green: 0x78 / 255, blue: 0xba / 255, alpha: 1)
    case .purple:
      NSColor(red: 0xbc / 255, green: 0x8c / 255, blue: 0xff / 255, alpha: 1)
    case .red:
      NSColor(red: 0xf8 / 255, green: 0x51 / 255, blue: 0x49 / 255, alpha: 1)
    case .teal:
      NSColor(red: 0x2d / 255, green: 0xd4 / 255, blue: 0xbf / 255, alpha: 1)
    }
  }
}

private struct InfoRow: View {
  let label: String
  let value: String

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(width: 44, alignment: .leading)
      Text(value)
        .font(.caption.monospacedDigit())
        .lineLimit(1)
        .truncationMode(.middle)
      Spacer(minLength: 0)
    }
  }
}

private struct SectionTitle: View {
  let title: String

  init(_ title: String) {
    self.title = title
  }

  var body: some View {
    Text(title.uppercased())
      .font(.caption2.weight(.semibold))
      .foregroundStyle(.secondary)
  }
}
