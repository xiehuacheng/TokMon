import Foundation

enum TokMonMenuBarPresentation {
  static func title(
    for items: TokMonMenuBarItems,
    snapshot: TokMonStatsSnapshot,
  ) -> String? {
    guard !items.isEmpty else {
      return nil
    }
    guard let summary = snapshot.summary else {
      return nil
    }

    var parts: [String] = []
    if items.totalTokens {
      parts.append(formatCompact(Double(summary.total.totalTokens)))
    }
    if items.estimatedCost {
      parts.append(formatCost(estimatedCost(for: summary, snapshot: snapshot)))
    }
    if items.requests {
      parts.append(formatCompact(Double(summary.total.totalRequests)))
    }
    if items.kimiQuota {
      if let weekly = snapshot.kimiQuotaSnapshot?.weekly {
        parts.append("K\(Int(weekly.percentUsed))%")
      } else {
        parts.append("K-")
      }
    }

    let result = parts.filter { !$0.isEmpty }.joined(separator: " · ")
    return result.isEmpty ? nil : result
  }

  static func accessibilityLabel(
    for items: TokMonMenuBarItems,
    snapshot: TokMonStatsSnapshot,
  ) -> String {
    guard let title = title(for: items, snapshot: snapshot), !title.isEmpty else {
      return "TokMon"
    }
    return "TokMon \(title)"
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
