import SwiftUI

struct TokMonQuotaView: View {
  let snapshot: KimiQuotaSnapshot?
  let onRefresh: () -> Void
  let onOpenSettings: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Kimi Quota")
          .font(.system(size: 13, weight: .heavy, design: .rounded))
        Spacer()
        Button(action: onRefresh) {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.plain)
      }

      if let error = snapshot?.error {
        errorView(error)
      }

      if let weekly = snapshot?.weekly {
        quotaCard(title: "Weekly", window: weekly)
      }

      if let fiveHour = snapshot?.fiveHour {
        quotaCard(title: "5-Hour", window: fiveHour)
      }

      if snapshot?.weekly == nil && snapshot?.fiveHour == nil {
        Text("No quota data available.")
          .font(.system(size: 12, weight: .medium, design: .rounded))
          .foregroundStyle(.secondary)
      }

      if let fetchedAt = snapshot?.fetchedAt {
        Text("Updated \(fetchedAt.formatted(date: .omitted, time: .shortened))")
          .font(.system(size: 10, weight: .medium, design: .rounded))
          .foregroundStyle(.secondary)
      }
    }
    .padding(9)
    .hudCard()
  }

  private func quotaCard(title: String, window: KimiQuotaWindow) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(title)
          .font(.system(size: 12, weight: .semibold, design: .rounded))
        Spacer()
        Text("\(Int(window.percentUsed))%")
          .font(.system(size: 12, weight: .heavy, design: .rounded))
          .foregroundStyle(color(for: window.percentUsed))
      }
      GeometryReader { geo in
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(.quaternary)
          .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
              .fill(color(for: window.percentUsed))
              .frame(width: geo.size.width * min(window.percentUsed / 100, 1))
          }
      }
      .frame(height: 6)
      HStack {
        Text("\(Int(window.used)) / \(Int(window.limit))")
          .font(.system(size: 11, weight: .medium, design: .rounded))
          .foregroundStyle(.secondary)
        Spacer()
        if let countdown = window.countdown {
          Text("Resets in \(countdown)")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  @ViewBuilder
  private func errorView(_ error: KimiQuotaError) -> some View {
    if error == .noAPIKey {
      VStack(alignment: .leading, spacing: 6) {
        Text("Add your Kimi Code API key in Settings.")
          .font(.system(size: 12, weight: .semibold, design: .rounded))
          .foregroundStyle(TokMonGlass.danger)
          .lineLimit(2)
        Button("Open Settings") {
          onOpenSettings()
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .controlSize(.small)
      }
    } else {
      Text(errorMessage(error))
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(TokMonGlass.danger)
        .lineLimit(2)
    }
  }

  private func errorMessage(_ error: KimiQuotaError) -> String {
    switch error {
    case .invalidKey:
      "Invalid API key. Make sure it is a Kimi Code key (sk-kimi-xxx)."
    case .endpointNotFound:
      "Kimi quota endpoint not found. The API may have changed."
    case .rateLimited:
      "Rate limited. Please retry later."
    case .network, .decoding:
      "Could not load quota. Check your network."
    case .noAPIKey:
      "Add your Kimi Code API key in Settings."
    }
  }

  private func color(for percent: Double) -> Color {
    if percent >= 95 { return TokMonGlass.danger }
    if percent >= 80 { return .orange }
    return TokMonGlass.accent
  }
}
