import SwiftUI

struct TokMonSettingsWindow: View {
  @ObservedObject var store: TokMonSettingsStore
  let onSaveAndClose: () -> Void
  @State private var selectedPricingModel = ""

  private let sources = [
    ("", "All Sources"),
    ("claude-code", "Claude Code"),
    ("codex", "Codex"),
    ("opencode", "OpenCode"),
    ("qwen-code", "Qwen Code"),
  ]

  var body: some View {
    TokMonLiquidGlassScene {
      ZStack {
        SettingsWindowShell()
        VStack(alignment: .leading, spacing: 0) {
          header
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

          ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
              SettingsSection("Sources") {
                FieldRow("Default") {
                  Picker("Source", selection: $store.draft.source) {
                    ForEach(sources, id: \.0) { value, label in
                      Text(label).tag(value)
                    }
                  }
                  .pickerStyle(.segmented)
                  .labelsHidden()
                  .frame(width: 330)
                }
                FieldRow("Claude Code") {
                  TextField("~/.claude/projects", text: $store.draft.claudePath)
                    .settingsTextField(width: 430)
                }
                FieldRow("Codex") {
                  TextField("~/.codex/sessions", text: $store.draft.codexPath)
                    .settingsTextField(width: 430)
                }
                FieldRow("OpenCode") {
                  TextField("~/.local/share/opencode", text: $store.draft.openCodePath)
                    .settingsTextField(width: 430)
                }
                FieldRow("Qwen Code") {
                  TextField("~/.qwen/projects", text: $store.draft.qwenCodePath)
                    .settingsTextField(width: 430)
                }
              }

              SettingsSection("Menu Bar") {
                FieldRow("Display") {
                  Picker("Menu Bar Display", selection: $store.draft.menuBarDisplayMode) {
                    ForEach(TokMonMenuBarDisplayMode.allCases) { mode in
                      Text(mode.displayLabel).tag(mode)
                    }
                  }
                  .pickerStyle(.menu)
                  .labelsHidden()
                  .frame(width: 220)
                }
              }

              SettingsSection("Model Pricing") {
                modelPricingEditor
              }

              SettingsSection("Maintenance") {
                FieldRow("Actions") {
                  HStack(spacing: 8) {
                    Button("Scan Now") {
                      Task { try? await store.scanNow() }
                    }
                    .tokMonGlassButton()
                    .disabled(store.isBusy)

                    Button("Rebuild Database") {
                      Task { try? await store.rebuildAndRescan() }
                    }
                    .tokMonGlassButton()
                    .disabled(store.isBusy)
                  }
                }
              }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
          }

          footer
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
      }
      .preferredColorScheme(.dark)
    }
    .frame(minWidth: 660, minHeight: 580)
    .task {
      try? await store.load()
      selectedPricingModel = firstUnconfiguredPricingModel ?? ""
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
          .fill(Color.white.opacity(0.08))
          .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
              .strokeBorder(TokMonGlass.hudCardStroke, lineWidth: 1)
          }
        Image(systemName: "gearshape")
          .font(.system(size: 15, weight: .heavy))
          .foregroundStyle(TokMonGlass.accent)
      }
      .frame(width: 34, height: 34)

      VStack(alignment: .leading, spacing: 3) {
        Text("TokMon Settings")
          .font(.system(size: 15, weight: .heavy, design: .rounded))
          .foregroundStyle(TokMonGlass.neutralTint)
        Text("TokenMonitor")
          .font(.system(size: 12, weight: .semibold, design: .rounded))
          .foregroundStyle(TokMonGlass.mutedTint)
      }
      Spacer()
    }
  }

  private var footer: some View {
    HStack(spacing: 10) {
      if store.isBusy {
        ProgressView()
          .scaleEffect(0.72)
      }
      Text(store.errorMessage ?? store.statusMessage)
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(store.errorMessage == nil ? TokMonGlass.mutedTint : TokMonGlass.danger)
        .lineLimit(1)
      Spacer()
      Button("Save and Close") {
        Task {
          do {
            try await store.save()
            onSaveAndClose()
          } catch {}
        }
      }
      .tokMonGlassButton(prominent: true)
      .keyboardShortcut(.defaultAction)
      .disabled(store.isBusy)
    }
  }

  private var modelPricingEditor: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Picker("Model", selection: $selectedPricingModel) {
          ForEach(availablePricingModels, id: \.self) { model in
            Text(model).tag(model)
          }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(width: 270)

        Button("Add Model") {
          addSelectedPricingModel()
        }
        .tokMonGlassButton()
        .disabled(selectedPricingModel.isEmpty)
      }

      if configuredPricingModels.isEmpty {
        Text("Add a model to configure pricing.")
          .font(.system(size: 12, weight: .semibold, design: .rounded))
          .foregroundStyle(TokMonGlass.mutedTint)
          .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
      } else {
        VStack(alignment: .leading, spacing: 8) {
          pricingHeader
          ForEach(configuredPricingModels, id: \.self) { model in
            ModelPricingRow(
              model: model,
              rates: pricingBinding(for: model),
              onRemove: {
                store.draft.modelPricing.removeValue(forKey: model)
                selectedPricingModel = firstUnconfiguredPricingModel ?? ""
              },
            )
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .onChange(of: availablePricingModels, initial: true) { _, models in
      if selectedPricingModel.isEmpty || !models.contains(selectedPricingModel) {
        selectedPricingModel = models.first ?? ""
      }
    }
  }

  private var pricingHeader: some View {
    HStack(spacing: 8) {
      Text("Model")
        .frame(width: 178, alignment: .leading)
      Text("Input")
        .frame(width: 74, alignment: .trailing)
      Text("Output")
        .frame(width: 74, alignment: .trailing)
      Text("Cache W")
        .frame(width: 74, alignment: .trailing)
      Text("Cache R")
        .frame(width: 74, alignment: .trailing)
      Spacer(minLength: 0)
    }
    .font(.system(size: 10, weight: .bold, design: .rounded))
    .foregroundStyle(TokMonGlass.mutedTint)
  }

  private var configuredPricingModels: [String] {
    store.draft.modelPricing.keys.sorted()
  }

  private var availablePricingModels: [String] {
    let configured = Set(configuredPricingModels)
    let discovered = store.draft.availableModels
      .map(\.model)
      .filter { !$0.isEmpty && !configured.contains($0) }
    let allModels = discovered + configuredPricingModels
    return Array(NSOrderedSet(array: allModels)) as? [String] ?? allModels
  }

  private var firstUnconfiguredPricingModel: String? {
    let configured = Set(configuredPricingModels)
    return store.draft.availableModels
      .map(\.model)
      .first { !$0.isEmpty && !configured.contains($0) }
  }

  private func addSelectedPricingModel() {
    guard !selectedPricingModel.isEmpty else {
      return
    }
    store.draft.modelPricing[selectedPricingModel] = store.draft.modelPricing[selectedPricingModel] ?? .zero
    selectedPricingModel = firstUnconfiguredPricingModel ?? selectedPricingModel
  }

  private func pricingBinding(for model: String) -> Binding<TokMonCostRates> {
    Binding(
      get: {
        store.draft.modelPricing[model] ?? .zero
      },
      set: { rates in
        store.draft.modelPricing[model] = rates
      },
    )
  }
}

private struct SettingsWindowShell: View {
  var body: some View {
    RoundedRectangle(cornerRadius: 24, style: .continuous)
      .fill(.regularMaterial)
      .overlay {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .fill(TokMonGlass.hudCardFill)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .strokeBorder(TokMonGlass.hudCardStroke, lineWidth: 1)
      }
      .shadow(color: Color.black.opacity(0.22), radius: 22, y: 10)
      .allowsHitTesting(false)
  }
}

private struct ModelPricingRow: View {
  let model: String
  @Binding var rates: TokMonCostRates
  let onRemove: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Text(model)
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(TokMonGlass.neutralTint)
        .lineLimit(1)
        .truncationMode(.middle)
        .frame(width: 178, alignment: .leading)
      CompactRateField(value: $rates.input)
      CompactRateField(value: $rates.output)
      CompactRateField(value: $rates.cacheCreate)
      CompactRateField(value: $rates.cacheRead)
      Button {
        onRemove()
      } label: {
        Image(systemName: "minus.circle")
          .font(.system(size: 13, weight: .semibold))
      }
      .tokMonGlassButton()
      .help("Remove \(model) pricing")
    }
    .padding(10)
    .settingsInsetCard()
  }
}

private struct CompactRateField: View {
  @Binding var value: Double

  var body: some View {
    TextField("0", value: $value, format: .number.precision(.fractionLength(0...6)))
      .multilineTextAlignment(.trailing)
      .monospacedDigit()
      .settingsTextField(width: 74)
  }
}

private struct SettingsSection<Content: View>: View {
  private let title: String
  @ViewBuilder private let content: Content

  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text(title)
        .font(.system(size: 14, weight: .heavy, design: .rounded))
        .foregroundStyle(TokMonGlass.neutralTint.opacity(0.84))
      VStack(alignment: .leading, spacing: 10) {
        content
      }
      .padding(12)
      .settingsCard()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct FieldRow<Content: View>: View {
  private let label: String
  @ViewBuilder private let content: Content

  init(_ label: String, @ViewBuilder content: () -> Content) {
    self.label = label
    self.content = content()
  }

  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      Text(label)
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .foregroundStyle(TokMonGlass.mutedTint)
        .frame(width: 104, alignment: .trailing)
      content
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private extension View {
  func settingsCard() -> some View {
    background {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(TokMonGlass.hudCardFill)
        .overlay {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(TokMonGlass.hudCardStroke, lineWidth: 1)
        }
    }
  }

  func settingsInsetCard() -> some View {
    background {
      RoundedRectangle(cornerRadius: 13, style: .continuous)
        .fill(Color.black.opacity(0.14))
        .overlay {
          RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
  }

  func settingsTextField(width: CGFloat) -> some View {
    textFieldStyle(.plain)
      .font(.system(size: 12, weight: .semibold, design: .rounded))
      .foregroundStyle(TokMonGlass.neutralTint)
      .padding(.horizontal, 10)
      .frame(width: width, height: 28)
      .background {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .fill(Color.black.opacity(0.16))
          .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
              .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
          }
      }
  }
}

@MainActor
final class TokMonSettingsWindowController {
  private var window: NSWindow?
  private let settingsStore: TokMonSettingsStore

  init(engine: TokMonEngine) {
    settingsStore = TokMonSettingsStore(engine: engine)
  }

  init(engineActor: TokMonEngineActor) {
    settingsStore = TokMonSettingsStore(engineActor: engineActor)
  }

  func show() {
    if let window {
      window.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
      return
    }

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 660, height: 580),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false,
    )
    window.title = "TokMon Settings"
    window.center()
    window.minSize = NSSize(width: 660, height: 580)
    window.contentView = NSHostingView(rootView: TokMonSettingsWindow(
      store: settingsStore,
      onSaveAndClose: { [weak self] in
        self?.window?.close()
      },
    ))
    window.isReleasedWhenClosed = false
    window.makeKeyAndOrderFront(nil)
    self.window = window
    NSApplication.shared.activate(ignoringOtherApps: true)
  }
}
