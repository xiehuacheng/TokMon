import SwiftUI

enum TokMonValueFormatter {
  static func formatCompact(_ value: Double?) -> String {
    guard let value else { return "-" }
    if value >= 1_000_000_000 { return String(format: "%.1fB", value / 1_000_000_000) }
    if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1fK", value / 1_000) }
    return String(Int(value.rounded()))
  }

  static func formatCompact(_ value: Int?) -> String {
    guard let value else { return "-" }
    return formatCompact(Double(value))
  }

  static func formatCost(_ value: Double?) -> String {
    guard let value else { return "-" }
    if value >= 1000 { return "$" + String(format: "%.1fK", value / 1000) }
    if value >= 1 { return "$" + String(format: "%.2f", value) }
    if value >= 0.01 { return "$" + String(format: "%.3f", value) }
    return "$" + String(format: "%.4f", value)
  }
}

func quotaColor(for percent: Double) -> Color {
  if percent >= 95 { return TokMonGlass.danger }
  if percent >= 80 { return .orange }
  return TokMonGlass.accent
}
