import SwiftUI

struct TokMonQuotaView: View {
  let accounts: [KimiAPIKeyAccount]
  let snapshots: [String: KimiQuotaSnapshot]
  let selectedAccountID: String?
  let isLoading: Bool
  let onRefresh: () -> Void
  let onSelectAccount: (String) -> Void
  let onAddKey: (String, String) -> Void
  let onRemoveKey: (String) -> Void
  let onRenameKey: (String, String) -> Void

  @State private var isAdding = false
  @State private var newKeyInput: String = ""
  @State private var newKeyLabel: String = ""
  @State private var editingAccountID: String? = nil
  @State private var editLabel: String = ""

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
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()

        Button(action: onRefresh) {
          Image(systemName: "arrow.clockwise")
            .font(.system(size: 12, weight: .bold))
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
        if isSelected {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(TokMonGlass.accent)
        }

        if editingAccountID == account.id {
          TextField("Label", text: $editLabel)
            .quotaTextField(width: 120)
          Button {
            onRenameKey(account.id, editLabel)
            editingAccountID = nil
          } label: {
            Text("Save")
              .font(.system(size: 11, weight: .semibold, design: .rounded))
              .requestActionButton()
          }
          .buttonStyle(.plain)
          .focusable(false)
          .focusEffectDisabled()
          Button {
            editingAccountID = nil
          } label: {
            Text("Cancel")
              .font(.system(size: 11, weight: .semibold, design: .rounded))
              .requestActionButton()
          }
          .buttonStyle(.plain)
          .focusable(false)
          .focusEffectDisabled()
        } else {
          Text(account.label)
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .lineLimit(1)
          Spacer()
          Button {
            editLabel = account.label
            editingAccountID = account.id
          } label: {
            Image(systemName: "pencil")
              .font(.system(size: 11, weight: .semibold))
          }
          .buttonStyle(.plain)
          .focusable(false)
          .focusEffectDisabled()
          Button {
            onRemoveKey(account.id)
          } label: {
            Image(systemName: "trash")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(TokMonGlass.danger)
          }
          .buttonStyle(.plain)
          .focusable(false)
          .focusEffectDisabled()
          Button {
            onSelectAccount(account.id)
          } label: {
            Text(isSelected ? "Selected" : "Select")
              .font(.system(size: 11, weight: .semibold, design: .rounded))
              .requestActionButton()
          }
          .buttonStyle(.plain)
          .disabled(isSelected)
          .focusable(false)
          .focusEffectDisabled()
        }
      }

      accountQuotaContent(snapshot: snapshot)
    }
    .padding(10)
    .hudCard(background: TokMonGlass.cardBackgroundInner, isSelected: isSelected)
  }

  @ViewBuilder
  private func accountQuotaContent(snapshot: KimiQuotaSnapshot?) -> some View {
    if let snapshot {
      if let error = snapshot.error, error != .noAPIKey {
        Text(errorMessage(error))
          .font(.system(size: 11, weight: .semibold, design: .rounded))
          .foregroundStyle(TokMonGlass.danger)
          .lineLimit(2)
      }

      if let weekly = snapshot.weekly {
        quotaCard(title: "Weekly", window: weekly)
      }

      if let fiveHour = snapshot.fiveHour {
        quotaCard(title: "5-Hour", window: fiveHour)
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

  private func quotaCard(title: String, window: KimiQuotaWindow) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(title)
          .font(.system(size: 11, weight: .semibold, design: .rounded))
        Spacer()
        Text("\(Int(window.percentUsed))%")
          .font(.system(size: 11, weight: .heavy, design: .rounded))
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
      if let countdown = window.countdown {
        HStack {
          Spacer()
          Text("Resets in \(countdown)")
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
        }
      }
    }
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

  private func color(for percent: Double) -> Color {
    if percent >= 95 { return TokMonGlass.danger }
    if percent >= 80 { return .orange }
    return TokMonGlass.accent
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
