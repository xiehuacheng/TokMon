import SwiftUI

struct TokMonQuotaView: View {
  let accounts: [KimiAPIKeyAccount]
  let snapshots: [String: KimiQuotaSnapshot]
  let selectedAccountID: String?
  let isLoading: Bool
  let onRefresh: () -> Void
  let onSelectAccount: (String?) -> Void
  let onAddKey: (String, String) -> Void
  let onRemoveKey: (String) -> Void
  let onRenameKey: (String, String) -> Void
  let onUpdateEndDate: (String, String, Date) -> Void

  @State private var isAdding = false
  @State private var newKeyInput: String = ""
  @State private var newKeyLabel: String = ""
  @State private var editingAccountID: String? = nil
  @State private var editLabel: String = ""
  @State private var refreshRotation: Double = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Kimi Quota")
          .font(.system(size: 13, weight: .heavy, design: .rounded))
        Spacer()
        Button {
          withAnimation(TokMonMotion.gentleSpring) {
            isAdding.toggle()
            if !isAdding {
              clearAddFields()
            }
          }
        } label: {
          Image(systemName: "plus")
            .font(.system(size: 12, weight: .bold))
            .requestActionButton()
        }
        .buttonStyle(PressScaleButtonStyle())
        .focusable(false)
        .focusEffectDisabled()

        Button {
          withAnimation(.easeInOut(duration: 0.5)) {
            refreshRotation += 360
          }
          onRefresh()
        } label: {
          Image(systemName: "arrow.clockwise")
            .font(.system(size: 12, weight: .bold))
            .rotationEffect(.degrees(refreshRotation))
            .requestActionButton()
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
      }

      if isAdding {
        addKeyCard
          .transition(.move(edge: .top).combined(with: .opacity))
      }

      if accounts.isEmpty && !isAdding {
        Text("No keys configured. Tap + to add one.")
          .font(.system(size: 12, weight: .medium, design: .rounded))
          .foregroundStyle(.secondary)
      }

      ForEach(accounts) { account in
        accountCard(account)
      }
    }
    .padding(9)
    .hudCard()
    .focusEffectDisabled()
  }

  private var addKeyCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Add Key")
          .font(.system(size: 12, weight: .heavy, design: .rounded))
        Spacer()
        Button {
          withAnimation(TokMonMotion.gentleSpring) {
            isAdding = false
            clearAddFields()
          }
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 10, weight: .bold))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
      }

      SecureField("sk-kimi-xxx", text: $newKeyInput)
        .quotaTextField()

      HStack(spacing: 8) {
        TextField("Label", text: $newKeyLabel)
          .quotaTextField()
        Button {
          let label = newKeyLabel.isEmpty ? "Kimi Key" : newKeyLabel
          onAddKey(newKeyInput, label)
          clearAddFields()
          isAdding = false
        } label: {
          Text("Add")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .requestActionButton()
        }
        .buttonStyle(.plain)
        .disabled(newKeyInput.isEmpty)
        .focusable(false)
        .focusEffectDisabled()
      }
    }
    .padding(10)
    .hudCard(background: TokMonGlass.cardBackgroundInner)
  }

  private func accountCard(_ account: KimiAPIKeyAccount) -> some View {
    let isSelected = selectedAccountID == account.id
    let snapshot = snapshots[account.id]

    return VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Button {
          onSelectAccount(isSelected ? nil : account.id)
        } label: {
          Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isSelected ? TokMonGlass.accent : .secondary)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()

        if editingAccountID == account.id {
          TextField("Label", text: $editLabel)
            .quotaTextField(width: 120)
        } else {
          Text(account.label)
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .lineLimit(1)
        }

        Spacer()

        if editingAccountID == account.id {
          Button {
            onRenameKey(account.id, editLabel)
            editingAccountID = nil
          } label: {
            Image(systemName: "checkmark")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(TokMonGlass.accent)
          }
          .buttonStyle(.plain)
          .focusable(false)
          .focusEffectDisabled()
          Button {
            editingAccountID = nil
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 12, weight: .semibold))
          }
          .buttonStyle(.plain)
          .focusable(false)
          .focusEffectDisabled()
        } else {
          Button {
            editLabel = account.label
            editingAccountID = account.id
          } label: {
            Image(systemName: "pencil")
              .font(.system(size: 12, weight: .semibold))
          }
          .buttonStyle(.plain)
          .focusable(false)
          .focusEffectDisabled()
          Button {
            onRemoveKey(account.id)
          } label: {
            Image(systemName: "trash")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(TokMonGlass.danger)
          }
          .buttonStyle(.plain)
          .focusable(false)
          .focusEffectDisabled()
        }
      }
      .frame(height: 22)

      accountQuotaContent(snapshot: snapshot, account: account)
    }
    .padding(10)
    .hudCard(background: TokMonGlass.cardBackgroundInner, isSelected: isSelected)
  }

  @ViewBuilder
  private func accountQuotaContent(snapshot: KimiQuotaSnapshot?, account: KimiAPIKeyAccount) -> some View {
    if let snapshot {
      if let error = snapshot.error, error != .noAPIKey {
        Text(errorMessage(error))
          .font(.system(size: 11, weight: .semibold, design: .rounded))
          .foregroundStyle(TokMonGlass.danger)
          .lineLimit(2)
      }

      if let weekly = snapshot.weekly {
        quotaCard(title: "Weekly", window: weekly, account: account)
      }

      if let fiveHour = snapshot.fiveHour {
        quotaCard(title: "5-Hour", window: fiveHour, account: account)
      }

      if snapshot.weekly == nil && snapshot.fiveHour == nil && snapshot.error == nil {
        Text("No quota data available.")
          .font(.system(size: 11, weight: .medium, design: .rounded))
          .foregroundStyle(.secondary)
      }

      if let fetchedAt = snapshot.fetchedAt {
        Text("Updated \(fetchedAt.formatted(date: .omitted, time: .shortened))")
          .font(.system(size: 10, weight: .medium, design: .rounded))
          .foregroundStyle(.secondary)
      }
    } else if isLoading {
      ProgressView()
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      Text("No quota data available.")
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
    }
  }

  private func quotaCard(title: String, window: KimiQuotaWindow, account: KimiAPIKeyAccount) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(title)
          .font(.system(size: 11, weight: .semibold, design: .rounded))
        Spacer()
        Text("\(Int(window.percentUsed))%")
          .font(.system(size: 11, weight: .heavy, design: .rounded))
          .foregroundStyle(quotaColor(for: window.percentUsed))
      }
      GeometryReader { geo in
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(.quaternary)
          .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
              .fill(quotaColor(for: window.percentUsed))
              .frame(width: geo.size.width * min(window.percentUsed / 100, 1))
          }
      }
      .frame(height: 6)
      HStack(spacing: 6) {
        if let footerText = footerText(for: window) {
          Text(footerText)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
        } else {
          ManualEndDatePicker {
            onUpdateEndDate(account.id, title, $0)
          }
        }
        Spacer()
      }
    }
  }

  private func resetDateText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "MM/dd HH:mm"
    return formatter.string(from: date)
  }

  private func footerText(for window: KimiQuotaWindow) -> String? {
    guard let resetAt = window.resetAt ?? window.endAt else {
      return window.countdown.map { "Resets in \($0)" }
    }
    let timeText = resetDateText(resetAt)
    guard let countdown = window.countdown else {
      return "Resets \(timeText)"
    }
    return "Resets in \(countdown) (\(timeText))"
  }

  private func clearAddFields() {
    newKeyInput = ""
    newKeyLabel = ""
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
      "Add your Kimi Code API key above."
    }
  }

}

private struct PressScaleButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
      .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
  }
}

private struct ManualEndDatePicker: View {
  let onCommit: (Date) -> Void
  @State private var date = Date()

  var body: some View {
    DatePicker("End date", selection: $date, displayedComponents: [.date, .hourAndMinute])
      .datePickerStyle(.field)
      .labelsHidden()
      .frame(maxWidth: 110)
      .onChange(of: date) { _, newDate in
        onCommit(newDate)
      }
  }
}

private extension View {
  func quotaTextField(width: CGFloat? = nil) -> some View {
    textFieldStyle(.plain)
      .font(.system(size: 12, weight: .semibold, design: .rounded))
      .foregroundStyle(.primary)
      .padding(.horizontal, 10)
      .frame(minWidth: width, maxWidth: width == nil ? .infinity : width, minHeight: 28)
      .background {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .fill(.regularMaterial)
          .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
              .strokeBorder(TokMonGlass.glassEdge, lineWidth: 1)
          }
      }
  }
}
