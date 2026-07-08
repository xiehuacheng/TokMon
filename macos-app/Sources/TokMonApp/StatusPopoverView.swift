import SwiftUI
import ScreenCaptureKit

struct StatusPopoverView: View {
  @EnvironmentObject private var runtime: TokMonRuntime
  @EnvironmentObject private var stats: TokMonStatsStore
  @State private var selectedPage = TokMonPopoverPage.overview
  @State private var selectedSeries = TokMonSeriesPresentation.total
  @State private var expandedRequestId: String?
  @State private var isTotalTokensExpanded = false
  @State private var refreshRotation: Double = 0
  @State private var sessionRowFrames: [String: CGRect] = [:]
  @State private var scrollViewBounds: CGRect = .zero
  @Namespace private var pageRailSelectionNamespace
  private let numberFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter
  }()

  var body: some View {
    ZStack(alignment: .topLeading) {
      VStack(alignment: .leading, spacing: 10) {
        pinnedHeader
        ScrollView(showsIndicators: false) {
          scrollingPageContent
            .padding(.horizontal, 11)
            .padding(.bottom, 11)
            .frame(maxWidth: .infinity, minHeight: statusPanelScrollContentHeight, alignment: .topLeading)
            .background(Color.clear)
            .contentShape(Rectangle())
        }
        .background {
          GeometryReader { proxy in
            Color.clear.preference(
              key: ScrollViewBoundsPreferenceKey.self,
              value: proxy.frame(in: .named(StatusPopoverCoordinateSpace.main))
            )
          }
        }
        .onPreferenceChange(ScrollViewBoundsPreferenceKey.self) { bounds in
          scrollViewBounds = bounds
        }
        .tokMonScrollEdgeFade(top: 8, bottom: 12)
      }
      .clipShape(StatusPanelContentMask())
      .background(alignment: .top) {
        StatusPanelShell()
      }
      .frame(width: statusPanelMainWidth, height: statusPanelHeight)
      .background {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
          .fill(Color.clear)
          .shadow(color: TokMonGlass.ambientShadow, radius: 20, x: 0, y: 10)
      }
      .background(Color.clear)
      .contentShape(Rectangle())
      .coordinateSpace(name: StatusPopoverCoordinateSpace.main)
      .padding(.leading, sessionBubbleWidth + sessionBubbleGutter)
      if selectedPage == .sessions, let selectedSessionBubbleY {
        selectedSessionDrilldown
          .offset(x: 0, y: selectedSessionBubbleY)
          .animation(TokMonMotion.gentleSpring, value: selectedSessionBubbleY)
      }
    }
    .padding([.bottom, .leading, .trailing], statusPanelShadowPadding)
    .frame(width: statusPanelContentWidth + statusPanelShadowPadding * 2, height: statusPanelHeight + statusPanelShadowPadding, alignment: .topLeading)
    .onChange(of: stats.snapshot.dashboardState?.activeSeries, initial: true) { _, activeSeries in
      selectedSeries = TokMonSeriesPresentation(rawValue: activeSeries ?? "total")
    }
    .onChange(of: selectedSessionBubbleY, initial: true) { _, _ in
      syncSessionBubbleHitSurface()
    }
    .onChange(of: selectedPage, initial: true) { _, _ in
      resetTransientUIState()
      syncSessionBubbleHitSurface()
    }
    .onChange(of: stats.snapshot.selectedUsageSession, initial: true) { _, _ in
      resetTransientUIState()
      syncSessionBubbleHitSurface()
    }
    .onAppear {
      stats.popoverDidAppear()
    }
    .onDisappear {
      runtime.statusPanelSessionBubbleY = nil
      resetTransientUIState()
    }
  }

  private func resetTransientUIState() {
    expandedRequestId = nil
    isTotalTokensExpanded = false
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
            .fill(.regularMaterial)
            .overlay {
              RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(TokMonGlass.danger.opacity(0.35), lineWidth: 1)
            }
            .shadow(color: TokMonGlass.ambientShadow, radius: 6, y: 2)
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
    case .quota:
      quotaPage
    }
  }

  private var pinnedHeader: some View {
    VStack(alignment: .leading, spacing: 10) {
      header
      SystemMenuPageRail(
        pages: availablePages,
        selectedPage: selectedPage,
        selectionNamespace: pageRailSelectionNamespace,
        onSelect: selectPage,
      )
      rangeControl
    }
    .padding(.horizontal, 11)
    .padding(.top, 11)
    .padding(.bottom, 2)
  }

  private var scrollingPageContent: some View {
    VStack(alignment: .leading, spacing: 10) {
      errorBanner
      currentPage
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 10) {
      ZStack {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(.regularMaterial)
          .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .strokeBorder(TokMonGlass.glassEdge, lineWidth: 1)
          }
          .shadow(color: TokMonGlass.ambientShadow, radius: 4, y: 2)
        Text("T")
          .font(.system(size: 17, weight: .black, design: .rounded))
          .foregroundStyle(.primary)
      }
      .frame(width: 30, height: 30)

      VStack(alignment: .leading, spacing: 3) {
        Text("TokMon")
          .font(.system(size: 14, weight: .heavy, design: .rounded))
          .foregroundStyle(.primary)
        Text(updatedLine)
          .font(.system(size: 12, weight: .semibold, design: .rounded))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer()

      HeaderIconButton(systemName: "arrow.clockwise", help: "Refresh Now", rotation: refreshRotation) {
        let targetRotation = refreshRotation + 360
        withAnimation(.easeInOut(duration: 0.5)) {
          refreshRotation = targetRotation
        }
        Task { await stats.refreshWithScan() }
      }
      HeaderIconButton(systemName: "camera", completedSystemName: "checkmark", help: "Copy Screenshot") {
        copyScreenshotToPasteboard()
      }

      HeaderIconButton(systemName: "gearshape", help: "TokMon Settings") {
        runtime.openSettings()
      }
      HeaderIconButton(systemName: "arrow.up.circle", help: "Check for Updates") {
        runtime.statusPanel?.orderOut(nil)
        runtime.stats.popoverDidDisappear()
        runtime.updater.checkForUpdates()
      }
      HeaderIconButton(systemName: "power", help: "Quit TokMon") {
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
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        Text("Waiting for TokMon settings...")
          .font(.system(size: 13, weight: .semibold, design: .rounded))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private var overviewPage: some View {
    VStack(alignment: .leading, spacing: 10) {
      TokMonHudMetricGrid(
        metrics: primaryMetrics,
        tokenDetails: secondaryMetrics,
        isTotalExpanded: isTotalTokensExpanded,
        onToggleTotalExpanded: toggleTotalTokensExpanded,
        onSelect: selectSeries,
      )
      TokMonQuotaMiniCard(snapshot: stats.kimiQuotaSnapshot) {
        withAnimation(TokMonMotion.softSnappySpring) {
          selectedPage = .quota
        }
      }
      TokMonHudTrendCard(
        title: "Trend",
        valueLabel: selectedSeries.label,
        points: trendPoints(for: selectedSeries.key),
        color: selectedSeries.tintColor,
      )
      TokMonHudActivityCard(
        days: stats.snapshot.heatmapDays,
        selectedSeries: selectedSeries.key,
        costRates: aggregateCostRates,
        colorForValue: { value, max in heatmapColor(value: value, maxValue: max, color: selectedSeries.tintColor) },
      )
      TokMonHudBreakdownCard(
        title: "Top Models",
        trailingTitle: selectedSeries.isCost ? "Cost" : selectedSeries.label,
        rows: modelRows,
      )
      TokMonHudBreakdownCard(
        title: "Sources",
        trailingTitle: selectedSeries.isCost ? "Cost" : selectedSeries.label,
        rows: sourceRows,
      )
    }
    .font(.system(size: 12, weight: .regular, design: .rounded))
    .padding(9)
    .hudCard()
  }

  private var requestsPage: some View {
    let rows = stats.snapshot.recordsPage?.rows ?? []
    let total = stats.snapshot.recordsPage?.total ?? 0

    return VStack(alignment: .leading, spacing: 9) {
      TokMonHudSectionHeader("Requests", trailing: total > 0 ? "Showing \(rows.count) of \(total)" : nil)
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
      TokMonHudSectionHeader("Sessions", trailing: sessions.isEmpty ? nil : "Latest \(sessions.count)")
      if sessions.isEmpty {
        emptyState("No usage sessions yet.")
      } else {
        ForEach(sessions) { session in
          SessionRowView(
            session: session,
            isSelected: stats.snapshot.selectedUsageSession?.id == session.id,
            costRates: costRates(forSession: session),
            projectName: sessionDisplayProjectName(for: session),
            firstPrompt: sessionDisplayFirstPrompt(for: session),
            sourceColor: colorForSource(session.source),
            formatCompact: formatChartValue,
            formatCost: formatCost,
            onSelect: {
              toggleUsageSessionSelection(session)
            },
          )
          .background {
            GeometryReader { proxy in
              Color.clear.preference(
                key: SessionRowFramePreferenceKey.self,
                value: [session.id: proxy.frame(in: .named(StatusPopoverCoordinateSpace.main))],
              )
            }
          }
        }
        if stats.canLoadMoreUsageSessions {
          LoadMoreButton(title: "Load More Sessions") {
            stats.loadMoreUsageSessions()
          }
        }
      }
    }
    .padding(9)
    .hudCard()
    .onPreferenceChange(SessionRowFramePreferenceKey.self) { frames in
      sessionRowFrames = frames
    }
  }

  private var quotaPage: some View {
    TokMonQuotaView(snapshot: stats.kimiQuotaSnapshot) {
      Task { await stats.refreshKimiQuota() }
    }
    .font(.system(size: 12, weight: .regular, design: .rounded))
  }

  @ViewBuilder
  private var selectedSessionDrilldown: some View {
    if let selection = stats.snapshot.selectedUsageSession {
      let rows = stats.snapshot.selectedSessionRecords
      let selectedSession = stats.snapshot.usageSessions.first { $0.id == selection.id }
      let projectName = sessionProjectName(for: selectedSession, fallbackSource: selection.source)
      let firstPrompt = sessionFirstPrompt(for: selectedSession, fallbackSessionId: selection.sessionId)

      VStack(alignment: .leading, spacing: 0) {
        SessionDrilldownHeader(
          projectName: projectName,
          firstPrompt: firstPrompt,
          onClose: {
            withAnimation(TokMonMotion.gentleSpring) {
              stats.clearSelectedUsageSession()
            }
          },
        )
        .padding(.bottom, 10)

        SessionDrilldownScrollShell {
          if rows.isEmpty {
            emptyState("No requests in this session for the selected range.")
          } else {
            VStack(alignment: .leading, spacing: 10) {
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
        }
      }
      .padding(14)
      .frame(width: sessionBubbleWidth, height: sessionBubbleMaxHeight, alignment: .topLeading)
      .background(alignment: .top) {
        ZStack {
          RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.clear)
            .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 9)
          StatusSessionBubbleShell()
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
      .transition(.tokMonPanelDrilldown)
    }
  }

  private var primaryMetrics: [TokMonHudMetric] {
    let totals = stats.snapshot.summary?.total
    return [
      TokMonHudMetric(series: .total, value: formatCompact(totals?.totalTokens), delta: metricDelta(for: .total), isSelected: selectedSeries.key == .total),
      TokMonHudMetric(series: .cost, value: formatCost(currentEstimatedCost), delta: metricDelta(for: .cost), isSelected: selectedSeries.key == .cost),
      TokMonHudMetric(series: .requests, value: formatCompact(totals?.totalRequests), delta: metricDelta(for: .requests), isSelected: selectedSeries.key == .requests),
      TokMonHudMetric(series: .cacheHitRate, value: formatPercent(totals?.cacheHitRate), delta: metricDelta(for: .cacheHitRate), isSelected: selectedSeries.key == .cacheHitRate),
    ]
  }

  private var secondaryMetrics: [TokMonHudMetric] {
    let totals = stats.snapshot.summary?.total
    return [
      TokMonHudMetric(series: .input, value: formatCompact(totals?.totalInput), delta: metricDelta(for: .input), isSelected: selectedSeries.key == .input),
      TokMonHudMetric(series: .output, value: formatCompact(totals?.totalOutput), delta: metricDelta(for: .output), isSelected: selectedSeries.key == .output),
      TokMonHudMetric(series: .cache, value: formatCompact(totals?.totalCacheCreation), delta: metricDelta(for: .cache), isSelected: selectedSeries.key == .cache),
      TokMonHudMetric(series: .cacheHit, value: formatCompact(totals?.totalCacheRead), delta: metricDelta(for: .cacheHit), isSelected: selectedSeries.key == .cacheHit),
    ]
  }

  private var modelRows: [TokMonHudBreakdownRow] {
    Array((stats.snapshot.summary?.byModel ?? [])
      .sorted { modelValue($0, for: selectedSeries.key) > modelValue($1, for: selectedSeries.key) }
      .prefix(4))
      .map { model in
        TokMonHudBreakdownRow(
          id: model.id,
          title: model.model,
          value: formatMetricValue(modelValue(model, for: selectedSeries.key)),
          color: colorForSource(model.source),
        )
      }
  }

  private var sourceRows: [TokMonHudBreakdownRow] {
    (stats.snapshot.summary?.bySource ?? [])
      .sorted { sourceValue($0, for: selectedSeries.key) > sourceValue($1, for: selectedSeries.key) }
      .map { source in
        TokMonHudBreakdownRow(
          id: source.id,
          title: labelForSource(source.source),
          value: formatMetricValue(sourceValue(source, for: selectedSeries.key)),
          color: colorForSource(source.source),
        )
      }
  }

  private func emptyState(_ message: String) -> some View {
    Text(message)
      .font(.system(size: 13, weight: .semibold, design: .rounded))
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
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
      return "now"
    }
    return updatedAt.formatted(date: .omitted, time: .standard)
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
      return "No prev"
    }

    let currentValue = summaryValue(current, for: seriesKey)
    let previousValue = summaryValue(previous, for: seriesKey)
    guard previousValue > 0 else {
      return currentValue > 0 ? "New vs prev" : "No prev"
    }

    let change = (currentValue - previousValue) / previousValue
    if abs(change) < 0.005 {
      return "No change vs prev"
    }
    let sign = change > 0 ? "+" : "-"
    return "\(sign)\(Int((abs(change) * 100).rounded()))% vs prev"
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

  private func copyScreenshotToPasteboard() {
    guard let window = runtime.statusPanel,
          let screen = window.screen else { return }

    Task {
      do {
        let content = try await SCShareableContent.current

        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
          tokMonLog("Screenshot: could not read screen number")
          return
        }
        let targetDisplayID = CGDirectDisplayID(screenNumber.uint32Value)
        guard let scDisplay = content.displays.first(where: { $0.displayID == targetDisplayID }) else {
          tokMonLog("Screenshot: could not find SCDisplay for screen \(targetDisplayID)")
          return
        }

        let filter = SCContentFilter(display: scDisplay, excludingApplications: [], exceptingWindows: [])
        let scale = window.backingScaleFactor
        let config = SCStreamConfiguration()
        config.width = Int(scDisplay.frame.width * scale)
        config.height = Int(scDisplay.frame.height * scale)
        config.showsCursor = false

        let cgImage = try await SCScreenshotManager.captureImage(
          contentFilter: filter,
          configuration: config
        )

        let mainDisplayHeight = CGDisplayBounds(CGMainDisplayID()).height
        let cropRect = statusPanelScreenshotCropRect(
          windowFrame: window.frame,
          displayFrame: scDisplay.frame,
          scale: scale,
          mainDisplayHeight: mainDisplayHeight
        )

        guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
          tokMonLog("Screenshot: cropping failed")
          return
        }

        let croppedSize = CGSize(width: cropRect.width / scale, height: cropRect.height / scale)
        let image = NSImage(cgImage: croppedCGImage, size: croppedSize)
        await MainActor.run {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.writeObjects([image])
        }
      } catch {
        tokMonLog("Screenshot failed: \(error.localizedDescription)")
      }
    }
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
    withAnimation(TokMonMotion.smoothSpring) {
      isTotalTokensExpanded.toggle()
    }
  }

  private var availablePages: [TokMonPopoverPage] {
    stats.usesNativeEngine ? TokMonPopoverPage.allCases : [.overview]
  }

  private var statusPanelScrollContentHeight: CGFloat {
    statusPanelHeight - 104
  }

  private var selectedSessionBubbleY: CGFloat? {
    guard let selection = stats.snapshot.selectedUsageSession,
          let rowFrame = sessionRowFrames[selection.id] else {
      return nil
    }

    let visibleBounds = scrollViewBounds.isEmpty
      ? CGRect(x: 0, y: 104, width: statusPanelMainWidth, height: statusPanelScrollContentHeight)
      : scrollViewBounds
    guard rowFrame.intersects(visibleBounds) else {
      return nil
    }

    let minimumY: CGFloat = 12
    let maximumY = max(minimumY, statusPanelHeight - sessionBubbleMaxHeight - 12)
    return min(max(rowFrame.minY - 6, minimumY), maximumY)
  }

  private func selectPage(_ page: TokMonPopoverPage) {
    withAnimation(TokMonMotion.softSnappySpring) {
      selectedPage = page
    }
  }

  private func jumpToSession(source: String, sessionId: String) {
    withAnimation(TokMonMotion.gentleSpring) {
      stats.selectUsageSession(source: source, sessionId: sessionId)
      selectedPage = .sessions
    }
  }

  private func toggleUsageSessionSelection(_ session: TokMonUsageSession) {
    withAnimation(TokMonMotion.gentleSpring) {
      if stats.snapshot.selectedUsageSession?.id == session.id {
        stats.clearSelectedUsageSession()
      } else {
        stats.selectUsageSession(source: session.source, sessionId: session.sessionId)
      }
    }
  }

  private func syncSessionBubbleHitSurface() {
    runtime.statusPanelSessionBubbleY = selectedPage == .sessions && stats.snapshot.selectedUsageSession != nil ? selectedSessionBubbleY : nil
  }

  private func sessionProjectName(for session: TokMonUsageSession?, fallbackSource: String) -> String {
    if let projectName = session?.projectName, !projectName.isEmpty {
      return projectName
    }
    if let title = session?.title, let split = splitTokMonSessionTitle(title) {
      return split.projectName
    }
    return labelForSource(fallbackSource)
  }

  private func sessionFirstPrompt(for session: TokMonUsageSession?, fallbackSessionId: String) -> String {
    if let firstPrompt = session?.firstPrompt, !firstPrompt.isEmpty {
      return firstPrompt
    }
    if let title = session?.title, let split = splitTokMonSessionTitle(title) {
      return split.firstPrompt
    }
    return fallbackSessionId
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

  private func sessionDisplayProjectName(for session: TokMonUsageSession) -> String {
    if let projectName = session.projectName, !projectName.isEmpty {
      return projectName
    }
    if let title = session.title, let split = splitTokMonSessionTitle(title) {
      return split.projectName
    }
    return labelForSource(session.source)
  }

  private func sessionDisplayFirstPrompt(for session: TokMonUsageSession) -> String {
    if let firstPrompt = session.firstPrompt, !firstPrompt.isEmpty {
      return firstPrompt
    }
    if let title = session.title, let split = splitTokMonSessionTitle(title) {
      return split.firstPrompt
    }
    return session.sessionId
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
    case "kimi-code":
      "Kimi Code"
    case "opencode":
      "OpenCode"
    case "qwen-code":
      "Qwen Code"
    default:
      source
    }
  }

  private func colorForSource(_ source: String) -> Color {
    switch source {
    case "claude-code":
      TokMonGlass.accent
    case "codex":
      TokMonGlass.codexTeal
    case "kimi-code":
      TokMonGlass.kimiPurple
    case "opencode":
      TokMonGlass.opencodeAmber
    case "qwen-code":
      TokMonGlass.danger
    default:
      .secondary
    }
  }

  private func heatmapColor(value: Double, maxValue: Double, color: Color) -> Color {
    guard maxValue > 0, value > 0 else {
      return Color.secondary.opacity(0.12)
    }
    let opacity = 0.22 + 0.58 * (value / maxValue)
    return color.opacity(opacity)
  }

  private func splitTokMonSessionTitle(_ title: String) -> (projectName: String, firstPrompt: String)? {
    let separator = " - "
    guard let range = title.range(of: separator) else {
      return nil
    }
    let projectName = String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    let firstPrompt = String(title[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !projectName.isEmpty, !firstPrompt.isEmpty else {
      return nil
    }
    return (projectName, firstPrompt)
  }
}

private enum TokMonPopoverPage: String, CaseIterable, Identifiable {
  case overview
  case requests
  case sessions
  case quota

  var id: String { rawValue }

  var title: String {
    switch self {
    case .overview:
      "Tokens"
    case .requests:
      "Requests"
    case .sessions:
      "Sessions"
    case .quota:
      "Quota"
    }
  }
}

private struct TokMonHudMetric: Identifiable {
  let series: TokMonSeriesPresentation
  let value: String
  let delta: String
  let isSelected: Bool

  var id: String { series.key.rawValue }
}

private struct TokMonHudBreakdownRow: Identifiable {
  let id: String
  let title: String
  let value: String
  let color: Color
}

private enum StatusPopoverCoordinateSpace {
  static let main = "StatusPopoverMain"
}

private struct SessionRowFramePreferenceKey: PreferenceKey {
  static let defaultValue: [String: CGRect] = [:]

  static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
    value.merge(nextValue(), uniquingKeysWith: { _, next in next })
  }
}

private struct ScrollViewBoundsPreferenceKey: PreferenceKey {
  static let defaultValue: CGRect = .zero

  static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
    value = nextValue()
  }
}

private struct StatusPanelShell: View {
  var body: some View {
    if #available(macOS 26.0, *) {
      shellShape
        .fill(.clear)
        .glassEffect(.regular, in: shellShape)
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    } else {
      shellShape
        .fill(.ultraThinMaterial)
        .overlay {
          shellShape.strokeBorder(TokMonGlass.glassEdge, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
  }

  private var shellShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: 30, style: .continuous)
  }
}

private struct StatusSessionBubbleShell: View {
  var body: some View {
    if #available(macOS 26.0, *) {
      shellShape
        .fill(.clear)
        .glassEffect(.regular, in: shellShape)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    } else {
      ZStack {
        shellShape
          .fill(Color.clear)
          .shadow(color: TokMonGlass.ambientShadow, radius: 20, x: 0, y: 10)
        shellShape
          .fill(.thinMaterial)
          .overlay {
            shellShape.strokeBorder(TokMonGlass.glassEdge, lineWidth: 1)
          }
      }
      .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
  }

  private var shellShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: 24, style: .continuous)
  }
}

private struct StatusPanelContentMask: Shape {
  func path(in rect: CGRect) -> Path {
    RoundedRectangle(cornerRadius: 24, style: .continuous)
      .path(in: rect.insetBy(dx: 7, dy: 7))
  }
}

private struct SessionDrilldownScrollShell<Content: View>: View {
  @ViewBuilder let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    ScrollView(showsIndicators: true) {
      content
        .frame(
          maxWidth: sessionBubbleWidth - 28 - sessionBubbleScrollIndicatorReserve,
          minHeight: sessionBubbleScrollHeight,
          alignment: .topLeading,
        )
        .background(Color.clear)
        .contentShape(Rectangle())
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .frame(height: sessionBubbleScrollHeight, alignment: .topLeading)
    .background(Color.clear)
    .contentShape(Rectangle())
  }
}

private struct SessionDrilldownHeader: View {
  let projectName: String
  let firstPrompt: String
  let onClose: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 4) {
        Text(projectName)
          .font(.system(size: 15, weight: .heavy, design: .rounded))
          .lineLimit(2)
          .minimumScaleFactor(0.88)
        Text(firstPrompt)
          .font(.system(size: 12, weight: .semibold, design: .rounded))
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .truncationMode(.tail)
      }
      Spacer()
      Button(action: onClose) {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 15, weight: .semibold))
          .frame(width: 24, height: 24)
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .focusable(false)
      .foregroundStyle(.secondary)
      .help("Close session details")
    }
  }
}

private struct GlassHoverModifier: ViewModifier {
  let cornerRadius: CGFloat
  let isSelected: Bool
  @State private var isHovered = false
  @State private var isPressed = false

  func body(content: Content) -> some View {
    content
      .background {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(isSelected
            ? (isPressed
                ? TokMonGlass.accentTilePress
                : isHovered
                  ? TokMonGlass.accentTileHover
                  : TokMonGlass.accentTileIdle)
            : isPressed ? TokMonGlass.cardRowPress : isHovered ? TokMonGlass.cardRowHover : TokMonGlass.cardRowIdle)
      }
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .strokeBorder(
            isSelected ? TokMonGlass.accent.opacity(isPressed ? 0.55 : 0.50) : TokMonGlass.cardBorder,
            lineWidth: 1)
      }
      .onHover { hovering in
        isHovered = hovering
      }
      .simultaneousGesture(
        DragGesture(minimumDistance: 0)
          .onChanged { _ in isPressed = true }
          .onEnded { _ in isPressed = false }
      )
  }
}

private extension View {
  func glassHover(cornerRadius: CGFloat = 16, isSelected: Bool = false) -> some View {
    modifier(GlassHoverModifier(cornerRadius: cornerRadius, isSelected: isSelected))
  }

  func glassCard(cornerRadius: CGFloat = 16) -> some View {
    modifier(GlassCardModifier(cornerRadius: cornerRadius))
  }
}

private struct GlassCardModifier: ViewModifier {
  let cornerRadius: CGFloat
  @State private var isHovered = false
  @State private var isPressed = false

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    content
      .background {
        shape.fill(isPressed ? TokMonGlass.cardRowPress : isHovered ? TokMonGlass.cardRowHover : TokMonGlass.cardRowIdle)
      }
      .clipShape(shape)
      .overlay {
        shape.strokeBorder(TokMonGlass.cardBorder, lineWidth: 1)
      }
      .background {
        shape
          .fill(Color.clear)
          .shadow(color: TokMonGlass.ambientShadow, radius: 6, x: 0, y: 2)
      }
      .onHover { isHovered = $0 }
      .simultaneousGesture(
        DragGesture(minimumDistance: 0)
          .onChanged { _ in isPressed = true }
          .onEnded { _ in isPressed = false }
      )
  }
}

private struct GlassRowButtonStyle: ButtonStyle {
  let cornerRadius: CGFloat
  let isSelected: Bool
  @State private var isHovered = false

  func makeBody(configuration: Configuration) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    configuration.label
      .background {
        shape.fill(isSelected
          ? (configuration.isPressed
              ? TokMonGlass.accentTilePress
              : isHovered
                ? TokMonGlass.accentTileHover
                : TokMonGlass.accentTileIdle)
          : configuration.isPressed ? TokMonGlass.cardRowPress : isHovered ? TokMonGlass.cardRowHover : TokMonGlass.cardRowIdle)
      }
      .clipShape(shape)
      .overlay {
        shape.strokeBorder(
          isSelected ? TokMonGlass.accent.opacity(configuration.isPressed ? 0.60 : 0.55) : TokMonGlass.cardBorder,
          lineWidth: 1)
      }
      .background {
        shape
          .fill(Color.clear)
          .shadow(color: TokMonGlass.ambientShadow, radius: 6, x: 0, y: 2)
      }
      .onHover { isHovered = $0 }
  }
}

private struct HeaderIconButtonStyle: ButtonStyle {
  let isHovered: Bool
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(Color.white.opacity(configuration.isPressed ? 0.35 : isHovered ? 0.22 : 0.0))
          .allowsHitTesting(false)
      }
      .animation(.easeInOut(duration: 0.12), value: isHovered)
      .animation(.easeInOut(duration: 0.08), value: configuration.isPressed)
  }
}

private struct HeaderIconButton: View {
  let systemName: String
  let completedSystemName: String?
  let help: String
  var rotation: Double = 0
  let action: () -> Void
  @State private var isHovered = false
  @State private var isCompleted = false

  init(
    systemName: String,
    completedSystemName: String? = nil,
    help: String,
    rotation: Double = 0,
    action: @escaping () -> Void
  ) {
    self.systemName = systemName
    self.completedSystemName = completedSystemName
    self.help = help
    self.rotation = rotation
    self.action = action
  }

  var body: some View {
    Button(action: {
      if completedSystemName != nil {
        isCompleted = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
          isCompleted = false
        }
      }
      action()
    }) {
      ZStack {
        buttonBackground
        Image(systemName: effectiveIconName)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(.primary)
          .rotationEffect(.degrees(rotation))
      }
      .frame(width: 28, height: 28)
      .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    .buttonStyle(HeaderIconButtonStyle(isHovered: isHovered))
    .focusable(false)
    .help(help)
    .onHover { isHovered = $0 }
  }

  private var effectiveIconName: String {
    if isCompleted, let completedSystemName {
      return completedSystemName
    }
    return systemName
  }

  private var buttonBackground: some View {
    Group {
      if #available(macOS 26.0, *) {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(.clear)
          .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      } else {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(.regularMaterial)
          .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .strokeBorder(TokMonGlass.glassEdge, lineWidth: 1)
          }
          .shadow(color: TokMonGlass.ambientShadow, radius: 4, y: 2)
      }
    }
  }
}

private struct GlassButtonStyle: ButtonStyle {
  let cornerRadius: CGFloat
  let isSelected: Bool
  @State private var isHovered = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
      .background {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(isSelected
            ? (configuration.isPressed
                ? TokMonGlass.accentTilePress
                : isHovered
                  ? TokMonGlass.accentTileHover
                  : TokMonGlass.accentTileIdle)
            : configuration.isPressed
              ? TokMonGlass.cardBackgroundInnerPress
              : isHovered
                ? TokMonGlass.cardBackgroundInnerHover
                : TokMonGlass.cardBackgroundInner)
      }
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .strokeBorder(
            isSelected ? TokMonGlass.accent.opacity(configuration.isPressed ? 0.55 : 0.50) : TokMonGlass.cardBorder,
            lineWidth: 1)
      }
      .background {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(Color.clear)
          .shadow(color: TokMonGlass.ambientShadow, radius: 10, x: 0, y: 4)
      }
      .onHover { hovering in
        isHovered = hovering
      }
  }
}

private struct SystemMenuPageRail: View {
  let pages: [TokMonPopoverPage]
  let selectedPage: TokMonPopoverPage
  let selectionNamespace: Namespace.ID
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
        .buttonStyle(GlassButtonStyle(cornerRadius: 11, isSelected: false))
        .focusable(false)
        .foregroundStyle(selectedPage == page ? .primary : .secondary)
        .background {
          if selectedPage == page {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
              .fill(TokMonGlass.accent.opacity(0.28))
              .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                  .strokeBorder(TokMonGlass.accent.opacity(0.45), lineWidth: 1)
              }
              .matchedGeometryEffect(id: "pageRailSelection", in: selectionNamespace)
          }
        }
      }
    }
    .padding(3)
    .background {
      if #available(macOS 26.0, *) {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(.clear)
          .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      } else {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(.thinMaterial)
          .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
              .strokeBorder(TokMonGlass.cardBorder, lineWidth: 1)
          }
          .shadow(color: TokMonGlass.ambientShadow, radius: 6, y: 2)
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
                .buttonStyle(GlassButtonStyle(cornerRadius: 10, isSelected: false))
        .focusable(false)
        .foregroundStyle(selectedLabel == preset.label ? .primary : .secondary)
        .tokMonSelectionPill(isSelected: selectedLabel == preset.label, cornerRadius: 10)
        .help("Show \(preset.displayLabel)")
      }
    }
  }
}

private struct TokMonHudMetricGrid: View {
  let metrics: [TokMonHudMetric]
  let tokenDetails: [TokMonHudMetric]
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
          .transition(.tokMonSupportingMetrics)
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
        .transition(.tokMonMetricGrid)
      }
    }
    .animation(TokMonMotion.smoothSpring, value: isTotalExpanded)
  }
}

private struct PrimaryMetricTile: View {
  let metric: TokMonHudMetric
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
            .foregroundStyle(.secondary)
            .lineLimit(1)
          Spacer(minLength: 0)
          Text(metric.series.icon)
            .font(.system(size: 12, weight: .black, design: .rounded))
            .foregroundStyle(metric.isSelected ? TokMonGlass.accent : .secondary)
        }
        MetricValueText(value: metric.value, isSelected: metric.isSelected)
        if !hideDelta {
          MetricDelta(metric.delta)
        }
      }
      .padding(9)
      .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
      .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .buttonStyle(GlassButtonStyle(cornerRadius: 16, isSelected: metric.isSelected))
    .focusable(false)
  }
}

private struct TotalTokensMetricTile: View {
  let metric: TokMonHudMetric
  let tokenDetails: [TokMonHudMetric]
  let isExpanded: Bool
  let onToggleExpanded: () -> Void
  let onSelect: (TokMonSeriesPresentation) -> Void

  var body: some View {
    Group {
      if isExpanded {
        expandedBody
      } else {
        collapsedBody
      }
    }
    .padding(9)
    .frame(maxWidth: .infinity, minHeight: isExpanded ? 80 : 66, alignment: .topLeading)
    .glassHover(cornerRadius: 16, isSelected: metric.isSelected)
    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private var collapsedBody: some View {
    ZStack(alignment: .topTrailing) {
      Button {
        onSelect(metric.series)
      } label: {
        metricSummary
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .focusable(false)

      expandButton
    }
  }

  private var expandedBody: some View {
    HStack(alignment: .top, spacing: 10) {
      Button {
        onSelect(metric.series)
      } label: {
        metricSummary
          .frame(minWidth: 76, maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .focusable(false)

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
      .transition(.tokMonTokenDetailGrid)

      expandButton
    }
  }

  private var metricSummary: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 6) {
        Text(metric.series.label.uppercased())
          .font(.system(size: 11, weight: .heavy, design: .rounded))
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Text(metric.series.icon)
          .font(.system(size: 12, weight: .black, design: .rounded))
          .foregroundStyle(metric.isSelected ? TokMonGlass.accent : .secondary)
        if !isExpanded {
          Spacer(minLength: 30)
        }
      }
      MetricValueText(value: metric.value, isSelected: metric.isSelected)
      MetricDelta(metric.delta)
    }
  }

  private var expandButton: some View {
    Button {
      onToggleExpanded()
    } label: {
      Image(systemName: isExpanded ? "chevron.left" : "chevron.right")
        .font(.system(size: 11, weight: .black))
        .foregroundStyle(.primary)
        .frame(width: 24, height: 24)
        .background {
          Circle()
            .fill(.regularMaterial)
            .overlay { Circle().strokeBorder(TokMonGlass.glassEdge, lineWidth: 1) }
            .shadow(color: TokMonGlass.ambientShadow, radius: 3, y: 1)
        }
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .focusable(false)
    .help(isExpanded ? "Hide token details" : "Show token details")
  }
}

private struct TokenDetailMiniMetric: View {
  let metric: TokMonHudMetric

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(metric.series.compactLabel)
        .font(.system(size: 9, weight: .heavy, design: .rounded))
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Text(metric.value)
        .font(.system(size: 12, weight: .black, design: .rounded).monospacedDigit())
        .foregroundStyle(.primary.opacity(0.88))
        .lineLimit(1)
    }
    .padding(.horizontal, 7)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(.regularMaterial)
        .overlay {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(TokMonGlass.glassEdge, lineWidth: 1)
        }
    }
  }
}

private struct CompactMetricTile: View {
  let metric: TokMonHudMetric
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
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
          Spacer(minLength: 0)
          Text(metric.series.icon)
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundStyle(metric.isSelected ? TokMonGlass.accent : .secondary)
        }
        Text(metric.value)
          .font(.system(size: 15, weight: .black, design: .rounded).monospacedDigit())
          .foregroundStyle(metric.isSelected ? TokMonGlass.accent : .primary)
          .lineLimit(1)
          .minimumScaleFactor(0.62)
        if !hideDelta {
          MetricDelta(metric.delta)
        }
      }
      .padding(9)
      .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
      .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .buttonStyle(GlassButtonStyle(cornerRadius: 16, isSelected: metric.isSelected))
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
      .foregroundStyle(.secondary)
      .lineLimit(1)
  }
}

private struct MetricValueText: View {
  let value: String
  let isSelected: Bool

  var body: some View {
    Text(value)
      .font(.system(size: 20, weight: .black, design: .rounded).monospacedDigit())
      .foregroundStyle(isSelected ? TokMonGlass.accent : .primary)
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
      .frame(minWidth: 76, alignment: .leading)
      .frame(height: 24, alignment: .leading)
      .transaction { transaction in
        transaction.animation = nil
      }
  }
}

private struct TokMonHudTrendCard: View {
  let title: String
  let valueLabel: String
  let points: [TokMonTrendPoint]
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      TokMonHudSectionHeader(title, trailing: valueLabel)
      TrendLineChart(points: points, color: color)
        .frame(height: 60)
    }
    .padding(10)
    .hudCard(background: TokMonGlass.cardBackgroundInner)
  }
}

private struct TokMonHudActivityCard: View {
  let days: [TokMonHeatmapDay]
  let selectedSeries: TokMonSeriesKey
  let costRates: TokMonCostRates
  let colorForValue: (Double, Double) -> Color

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      TokMonHudSectionHeader("Activity", trailing: days.isEmpty ? nil : "\(days.count)D")

      if days.isEmpty {
        Text("No recent activity.")
          .font(.system(size: 13, weight: .semibold, design: .rounded))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
      } else {
        RecentActivityGrid(
          days: days,
          selectedSeries: selectedSeries,
          costRates: costRates,
          colorForValue: colorForValue,
        )
      }
    }
    .padding(10)
    .hudCard(background: TokMonGlass.cardBackgroundInner)
  }
}

private struct TokMonHudBreakdownCard: View {
  let title: String
  let trailingTitle: String
  let rows: [TokMonHudBreakdownRow]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      TokMonHudSectionHeader(title, trailing: trailingTitle)
      if rows.isEmpty {
        Text("No usage in the selected range.")
          .font(.system(size: 13, weight: .semibold, design: .rounded))
          .foregroundStyle(.secondary)
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
                  .foregroundStyle(.primary)
                  .lineLimit(1)
                  .truncationMode(.middle)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              Spacer(minLength: 12)
              Text(row.value)
                .font(.system(size: 12, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary.opacity(0.82))
                .lineLimit(1)
            }
            .padding(.vertical, 7)
            if row.id != rows.last?.id {
              Divider().overlay(Color.secondary.opacity(0.20))
            }
          }
        }
      }
    }
    .padding(10)
    .hudCard(background: TokMonGlass.cardBackgroundInner)
  }
}

private struct TokMonHudSectionHeader: View {
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
        .foregroundStyle(.primary.opacity(0.84))
      Spacer()
      if let trailing {
        Text(trailing)
          .font(.system(size: 12, weight: .heavy, design: .rounded))
          .foregroundStyle(.primary.opacity(0.78))
          .lineLimit(1)
      }
    }
  }
}

private struct RecentActivityGrid: View {
  let days: [TokMonHeatmapDay]
  let selectedSeries: TokMonSeriesKey
  let costRates: TokMonCostRates
  let colorForValue: (Double, Double) -> Color

  var body: some View {
    let layout = TokMonHeatmapLayout(days: days)
    let maxValue = days.map { TokMonHeatmapValueDescriptor(day: $0, series: selectedSeries, costRates: costRates).value }.max() ?? 0
    GeometryReader { proxy in
      let heatmapLabelWidth: CGFloat = 31
      let metrics = TokMonHeatmapLayout.metrics(
        availableWidth: proxy.size.width,
        weekCount: layout.weeks.count,
        labelWidth: heatmapLabelWidth,
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
                  ZStack {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                      .fill(day.map { colorForValue(
                        TokMonHeatmapValueDescriptor(day: $0, series: selectedSeries, costRates: costRates).value,
                        maxValue,
                      ) } ?? Color.secondary.opacity(0.12))
                  }
                  .frame(width: cellSize, height: cellSize)
                  .contentShape(Rectangle())
                  .help(day.map {
                    TokMonHeatmapValueDescriptor(day: $0, series: selectedSeries, costRates: costRates).helpText
                  } ?? "No activity")
                }
              }
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(height: 124)
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
          .foregroundStyle(.secondary)
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
    VStack(alignment: .leading, spacing: gap) {
      ForEach(0..<7, id: \.self) { weekdayIndex in
        if let label = labels.first(where: { $0.weekdayIndex == weekdayIndex }) {
          Text(label.label)
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(width: 26, height: cellSize, alignment: .leading)
        } else {
          Color.clear
            .frame(width: 26, height: cellSize)
        }
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
              .stroke(Color.secondary.opacity(0.20), lineWidth: 1)
            if chartPoints.count > 1 {
              smoothedTrendFill(points: chartPoints, size: chartRect.size)
                .fill(
                  LinearGradient(
                    colors: [color.opacity(0.22), color.opacity(0.08), Color.clear],
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
    .foregroundStyle(.secondary)
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
    .foregroundStyle(.secondary)
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
          .foregroundStyle(.secondary)
      }
      HStack(spacing: 10) {
        Text(sourceLabel)
          .font(.system(size: 12, weight: .bold, design: .rounded))
          .foregroundStyle(sourceColor)
          .lineLimit(1)
          .truncationMode(.middle)
          .frame(width: 78, alignment: .leading)
        Text(sessionDisplayLabel)
          .font(.system(size: 12, weight: .semibold, design: .rounded))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      HStack(alignment: .bottom, spacing: 10) {
        RequestTokenChipGrid(
          chips: [
            TokenChipData(label: "In", value: formatCompact(Double(row.inputTokens))),
            TokenChipData(label: "Out", value: formatCompact(Double(row.outputTokens))),
            TokenChipData(label: "Cache", value: formatCompact(Double(row.cacheCreation + row.cacheRead))),
            TokenChipData(label: "Cost", value: formatCost(cost)),
          ],
        )
        VStack(alignment: .trailing, spacing: 5) {
          Button {
            onToggleDetails()
          } label: {
            Text(isExpanded ? "Hide" : "Details")
              .requestActionButton()
          }
          .buttonStyle(.plain)
          .focusable(false)
          if let onJumpToSession {
            Button(action: onJumpToSession) {
              Text("Jump")
                .requestActionButton()
            }
            .buttonStyle(.plain)
            .focusable(false)
          }
        }
        .font(.system(size: 11, weight: .bold, design: .rounded))
      }
      if isExpanded {
        VStack(alignment: .leading, spacing: 3) {
          DetailLine(label: "Created", value: row.createdAt)
          DetailLine(label: "Session", value: sessionDisplayLabel)
          DetailLine(label: "Cache Created", value: formatCompact(Double(row.cacheCreation)))
          DetailLine(label: "Cache Read", value: formatCompact(Double(row.cacheRead)))
          DetailLine(label: "Reasoning", value: formatCompact(Double(row.reasoningTokens)))
        }
      }
    }
    .padding(14)
    .glassCard(cornerRadius: 14)
  }

  private var cost: Double {
    costRates.cost(
      inputTokens: row.inputTokens,
      outputTokens: row.outputTokens,
      cacheCreation: row.cacheCreation,
      cacheRead: row.cacheRead,
    )
  }

  private var sessionDisplayLabel: String {
    row.sessionTitle ?? row.sessionId
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
  let projectName: String
  let firstPrompt: String
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
          Text(projectName)
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .lineLimit(1)
            .truncationMode(.middle)
          Text(firstPrompt)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .truncationMode(.tail)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 4) {
          Text(formatCompact(Double(session.inputTokens + session.outputTokens + session.cacheRead)))
            .font(.system(size: 13, weight: .heavy, design: .rounded).monospacedDigit())
          Text(formatCost(cost))
            .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }
      .padding(14)
      .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(GlassRowButtonStyle(cornerRadius: 14, isSelected: isSelected))
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
        .foregroundStyle(.secondary)
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
        .foregroundStyle(.secondary)
      Text(value)
        .foregroundStyle(.primary)
    }
    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
    .lineLimit(1)
    .frame(height: 22, alignment: .leading)
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
    .buttonStyle(GlassButtonStyle(cornerRadius: 16, isSelected: false))
    .focusable(false)
  }
}

struct HudCardModifier: ViewModifier {
  var background: Color = TokMonGlass.cardBackgroundOuter
  var isSelected = false

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
    let cardBackground: Color = isSelected
      ? TokMonGlass.accent.opacity(0.12)
      : Color.clear

    content
      .background {
        ZStack {
          shape.fill(background)
          shape.fill(cardBackground)
        }
      }
      .clipShape(shape)
      .overlay {
        shape.strokeBorder(isSelected ? TokMonGlass.accent.opacity(0.50) : TokMonGlass.cardBorder, lineWidth: 1)
      }
      .background {
        shape
          .fill(Color.clear)
          .shadow(color: TokMonGlass.ambientShadow, radius: 10, x: 0, y: 4)
      }
  }
}

extension View {
  func hudCard(background: Color = TokMonGlass.cardBackgroundOuter, isSelected: Bool = false) -> some View {
    modifier(HudCardModifier(background: background, isSelected: isSelected))
  }
}

private extension View {
  func requestActionButton() -> some View {
    foregroundStyle(.primary.opacity(0.86))
      .padding(.horizontal, 12)
      .frame(minWidth: 76, minHeight: 26)
      .background {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(.regularMaterial)
          .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .strokeBorder(TokMonGlass.glassEdge, lineWidth: 1)
          }
          .shadow(color: TokMonGlass.ambientShadow, radius: 4, y: 2)
      }
      .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
    case .cost, .cacheHitRate, .cacheHit:
      TokMonGlass.success
    case .cache:
      TokMonGlass.warning
    case .requests:
      TokMonGlass.accent
    default:
      TokMonGlass.accent
    }
  }
}
