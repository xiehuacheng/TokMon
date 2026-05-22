import Foundation

enum TokMonMenuBarPresentation {
  static func title(
    for mode: TokMonMenuBarDisplayMode,
    snapshot: TokMonStatsSnapshot,
  ) -> String? {
    guard mode != .iconOnly else {
      return nil
    }
    guard let summary = snapshot.summary else {
      return "-"
    }

    switch mode {
    case .iconOnly:
      return nil
    case .totalTokens:
      return formatCompact(Double(summary.total.totalTokens))
    case .estimatedCost:
      return formatCost(estimatedCost(for: summary, snapshot: snapshot))
    case .requests:
      return formatCompact(Double(summary.total.totalRequests))
    }
  }

  static func accessibilityLabel(
    for mode: TokMonMenuBarDisplayMode,
    snapshot: TokMonStatsSnapshot,
  ) -> String {
    guard let title = title(for: mode, snapshot: snapshot), !title.isEmpty else {
      return "TokMon"
    }
    return "TokMon \(mode.displayLabel) \(title)"
  }

  private static func estimatedCost(
    for summary: TokMonSummary,
    snapshot: TokMonStatsSnapshot,
  ) -> Double {
    let modelPricing = snapshot.dashboardState?.modelPricing ?? [:]
    if !modelPricing.isEmpty {
      return summary.estimatedCost(modelPricing: modelPricing)
    }
    return summary.estimatedCost(costRates: snapshot.dashboardState?.costRates ?? .zero)
  }

  private static func formatCompact(_ value: Double) -> String {
    if value >= 1_000_000_000 { return String(format: "%.1fB", value / 1_000_000_000) }
    if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1fK", value / 1_000) }

    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: Int(value.rounded()))) ?? String(Int(value.rounded()))
  }

  private static func formatCost(_ value: Double) -> String {
    if value >= 1000 { return "$" + String(format: "%.1fK", value / 1000) }
    if value >= 1 { return "$" + String(format: "%.2f", value) }
    if value >= 0.01 { return "$" + String(format: "%.3f", value) }
    return "$" + String(format: "%.4f", value)
  }
}
