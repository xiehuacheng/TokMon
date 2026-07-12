import Foundation

enum TokMonMenuBarPresentation {
  static func title(
    for items: TokMonMenuBarItems,
    snapshot: TokMonStatsSnapshot,
    kimiQuotaSnapshot: KimiQuotaSnapshot? = nil,
  ) -> String? {
    guard !items.isEmpty else {
      return nil
    }
    guard let summary = snapshot.summary else {
      return nil
    }

    let quota = kimiQuotaSnapshot ?? snapshot.kimiQuotaSnapshot
    var parts: [String] = []
    if items.totalTokens {
      parts.append(TokMonValueFormatter.formatCompact(Double(summary.total.totalTokens)))
    }
    if items.estimatedCost {
      parts.append(TokMonValueFormatter.formatCost(estimatedCost(for: summary, snapshot: snapshot)))
    }
    if items.requests {
      parts.append(TokMonValueFormatter.formatCompact(Double(summary.total.totalRequests)))
    }
    if items.cacheHitRate {
      parts.append(formatCacheHitRate(summary.total.cacheHitRate))
    }
    let showLegacyWeekly = items.kimiQuota && !items.kimiWeeklyQuota && !items.kimiFiveHourQuota
    if items.kimiWeeklyQuota || showLegacyWeekly {
      if let weekly = quota?.weekly {
        parts.append("7d \(Int(weekly.percentUsed))%")
      }
    }
    if items.kimiFiveHourQuota {
      if let fiveHour = quota?.fiveHour {
        parts.append("5h \(Int(fiveHour.percentUsed))%")
      }
    }

    let result = parts.filter { !$0.isEmpty }.joined(separator: " · ")
    return result.isEmpty ? nil : result
  }

  static func accessibilityLabel(
    for items: TokMonMenuBarItems,
    snapshot: TokMonStatsSnapshot,
    kimiQuotaSnapshot: KimiQuotaSnapshot? = nil,
  ) -> String {
    guard let title = title(for: items, snapshot: snapshot, kimiQuotaSnapshot: kimiQuotaSnapshot), !title.isEmpty else {
      return "TokMon"
    }
    return "TokMon \(title)"
  }

  private static func formatCacheHitRate(_ value: Double?) -> String {
    guard let value else {
      return "-"
    }
    return String(format: "%.1f%%", value * 100)
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

}
