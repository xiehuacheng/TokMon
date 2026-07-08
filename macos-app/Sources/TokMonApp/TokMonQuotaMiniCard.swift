import SwiftUI

struct TokMonQuotaMiniCard: View {
  let snapshot: KimiQuotaSnapshot?
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("Kimi Quota")
            .font(.system(size: 12, weight: .heavy, design: .rounded))
          Spacer()
          Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
        }

        if let error = snapshot?.error, snapshot?.weekly == nil && snapshot?.fiveHour == nil {
          Text(errorLabel(error))
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(TokMonGlass.danger)
        } else {
          row(label: "Week", window: snapshot?.weekly)
          row(label: "5h", window: snapshot?.fiveHour)
        }
      }
      .padding(9)
      .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    .buttonStyle(.plain)
    .hudCard()
  }

  private func row(label: String, window: KimiQuotaWindow?) -> some View {
    HStack(spacing: 8) {
      Text(label)
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(.secondary)
        .frame(width: 32, alignment: .leading)
      GeometryReader { geo in
        RoundedRectangle(cornerRadius: 3, style: .continuous)
          .fill(.quaternary)
          .overlay(alignment: .leading) {
            if let window {
              RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color(for: window.percentUsed))
                .frame(width: geo.size.width * min(window.percentUsed / 100, 1))
            }
          }
      }
      .frame(height: 5)
      Text(window.map { "\(Int($0.percentUsed))%" } ?? "—")
        .font(.system(size: 11, weight: .heavy, design: .rounded))
        .foregroundStyle(window.map { color(for: $0.percentUsed) } ?? .secondary)
        .frame(width: 34, alignment: .trailing)
    }
  }

  private func errorLabel(_ error: KimiQuotaError) -> String {
    switch error {
    case .noAPIKey:
      return "+ Kimi Key"
    default:
      return "Quota unavailable"
    }
  }

  private func color(for percent: Double) -> Color {
    if percent >= 95 { return TokMonGlass.danger }
    if percent >= 80 { return .orange }
    return TokMonGlass.accent
  }
}
