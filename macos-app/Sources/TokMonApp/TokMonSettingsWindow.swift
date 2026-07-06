import AppKit
import SwiftUI

struct TokMonSettingsWindow: View {
  @ObservedObject var store: TokMonSettingsStore
  let onSaveAndClose: () -> Void
  let onCancel: () -> Void
  @State private var selectedPricingModel = ""

  private let sources = [
    ("", "All Sources"),
    ("claude-code", "Claude Code"),
    ("codex", "Codex"),
    ("kimi-code", "Kimi Code"),
    ("opencode", "OpenCode"),
    ("qwen-code", "Qwen Code"),
  ]

  private let refreshRateOptions = [
    (1000, "1s"),
    (3000, "3s"),
    (5000, "5s"),
    (10000, "10s"),
    (30000, "30s"),
    (60000, "60s"),
  ]

  var body: some View {
    ZStack {
      SettingsHitSurface()
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
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 220)
              }
              FieldRow("Claude Code") {
                TextField("~/.claude/projects", text: $store.draft.claudePath)
                  .settingsTextField(width: 430)
              }
              FieldRow("Codex") {
                TextField("~/.codex/sessions", text: $store.draft.codexPath)
                  .settingsTextField(width: 430)
              }
              FieldRow("Kimi Code") {
                TextField("~/.kimi-code", text: $store.draft.kimiCodePath)
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
              FieldRow("Refresh") {
                Picker("Refresh Rate", selection: $store.draft.refreshRate) {
                  ForEach(refreshRateOptions, id: \.0) { ms, label in
                    Text(label).tag(ms)
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
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .background(SettingsHitSurface())
          .contentShape(Rectangle())
        }
        .background(SettingsHitSurface())
        .contentShape(Rectangle())
        .tokMonScrollEdgeFade(top: 10, bottom: 12)

        footer
          .padding(.horizontal, 20)
          .padding(.vertical, 14)
      }
      .background(SettingsHitSurface())
      .contentShape(Rectangle())
    }
    .frame(minWidth: 660, minHeight: 580)
    .background(SettingsHitSurface())
    .clipShape(SettingsWindowShape())
    .contentShape(SettingsWindowShape())
    .task {
      try? await store.load()
      selectedPricingModel = firstUnconfiguredPricingModel ?? ""
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 12) {
      ZStack {
        if #available(macOS 26.0, *) {
          RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(.clear)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        } else {
          RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
              RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(TokMonGlass.glassEdge, lineWidth: 1)
            }
            .shadow(color: TokMonGlass.ambientShadow, radius: 4, y: 2)
        }
        Image(systemName: "gearshape")
          .font(.system(size: 15, weight: .heavy))
          .foregroundStyle(TokMonGlass.accent)
      }
      .frame(width: 34, height: 34)

      VStack(alignment: .leading, spacing: 3) {
        Text("TokMon Settings")
          .font(.system(size: 15, weight: .heavy, design: .rounded))
          .foregroundStyle(.primary)
        Text("TokenMonitor")
          .font(.system(size: 12, weight: .semibold, design: .rounded))
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
    .overlay {
      SettingsWindowDragHandle()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .foregroundStyle(store.errorMessage == nil ? .secondary : TokMonGlass.danger)
        .lineLimit(1)
      Spacer()
      Button("Cancel") {
        Task {
          try? await store.load()
          onCancel()
        }
      }
      .tokMonGlassButton()
      .keyboardShortcut(.cancelAction)
      .focusable(false)
      .disabled(store.isBusy)
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
      .focusable(false)
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
          .foregroundStyle(.secondary)
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
    .foregroundStyle(.secondary)
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

private struct SettingsHitSurface: View {
  var body: some View {
    SettingsWindowShape()
      .fill(Color(nsColor: NSColor(white: 1.0, alpha: 0.001)))
  }
}

private struct SettingsWindowShell: View {
  var body: some View {
    if #available(macOS 26.0, *) {
      shellShape
        .fill(.clear)
        .glassEffect(.regular, in: shellShape)
        .clipShape(shellShape)
        .allowsHitTesting(false)
    } else {
      shellShape
        .inset(by: SettingsWindowMetrics.shellInset)
        .fill(.ultraThinMaterial)
        .overlay {
          shellShape
            .inset(by: SettingsWindowMetrics.shellInset)
            .strokeBorder(TokMonGlass.glassEdge, lineWidth: SettingsWindowMetrics.shellStrokeWidth)
        }
        .compositingGroup()
        .shadow(color: TokMonGlass.ambientShadow, radius: 22, y: 10)
        .allowsHitTesting(false)
    }
  }

  private var shellShape: SettingsWindowShape {
    SettingsWindowShape()
  }
}

private enum SettingsWindowMetrics {
  static let cornerRadius: CGFloat = 24
  static let shellInset: CGFloat = 0.75
  static let shellStrokeWidth: CGFloat = 0.75
}

private struct SettingsWindowShape: InsettableShape {
  var insetAmount: CGFloat = 0

  func path(in rect: CGRect) -> Path {
    let adjustedRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
    return RoundedRectangle(
      cornerRadius: max(0, SettingsWindowMetrics.cornerRadius - insetAmount),
      style: .continuous,
    )
    .path(in: adjustedRect)
  }

  func inset(by amount: CGFloat) -> SettingsWindowShape {
    var shape = self
    shape.insetAmount += amount
    return shape
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
        .foregroundStyle(.primary)
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
        .foregroundStyle(.primary.opacity(0.84))
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
        .foregroundStyle(.secondary)
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
        .fill(.thinMaterial)
        .overlay {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(TokMonGlass.glassEdge, lineWidth: 1)
        }
        .shadow(color: TokMonGlass.ambientShadow, radius: 8, y: 3)
    }
  }

  func settingsInsetCard() -> some View {
    background {
      RoundedRectangle(cornerRadius: 13, style: .continuous)
        .fill(.regularMaterial)
        .overlay {
          RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(TokMonGlass.glassEdge, lineWidth: 1)
        }
    }
  }

  func settingsTextField(width: CGFloat) -> some View {
    textFieldStyle(.plain)
      .font(.system(size: 12, weight: .semibold, design: .rounded))
      .foregroundStyle(.primary)
      .padding(.horizontal, 10)
      .frame(width: width, height: 28)
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

@MainActor
final class TokMonSettingsWindowController: NSObject, NSWindowDelegate {
  private var window: NSWindow?
  private let settingsStore: TokMonSettingsStore
  private let onSettingsSaved: (@MainActor () -> Void)?
  var onWindowClosed: (@MainActor () -> Void)?

  var isWindowVisible: Bool { window?.isVisible == true }

  init(engine: TokMonEngine, onSettingsSaved: (@MainActor () -> Void)? = nil, onWindowClosed: (@MainActor () -> Void)? = nil) {
    settingsStore = TokMonSettingsStore(engine: engine)
    self.onSettingsSaved = onSettingsSaved
    self.onWindowClosed = onWindowClosed
    super.init()
  }

  init(engineActor: TokMonEngineActor, onSettingsSaved: (@MainActor () -> Void)? = nil, onWindowClosed: (@MainActor () -> Void)? = nil) {
    settingsStore = TokMonSettingsStore(engineActor: engineActor)
    self.onSettingsSaved = onSettingsSaved
    self.onWindowClosed = onWindowClosed
    super.init()
  }

  func show() {
    if let window {
      NSRunningApplication.current.activate(options: .activateAllWindows)
      present(window)
      return
    }

    let window = SettingsWindow(
      contentRect: NSRect(x: 0, y: 0, width: 660, height: 580),
      styleMask: [.titled, .fullSizeContentView],
      backing: .buffered,
      defer: false,
    )
    window.title = "TokMon Settings"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.center()
    window.minSize = NSSize(width: 660, height: 580)
    window.contentView = SettingsHostingView(rootView: TokMonSettingsWindow(
      store: settingsStore,
      onSaveAndClose: { [weak self] in
        self?.window?.close()
        self?.onSettingsSaved?()
      },
      onCancel: { [weak self] in
        self?.window?.close()
      },
    ))
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.level = .modalPanel
    window.isMovable = true
    window.isMovableByWindowBackground = true
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.initialFirstResponder = nil
    self.window = window
    NSRunningApplication.current.activate(options: .activateAllWindows)
    present(window)
  }

  private func present(_ window: NSWindow) {
    window.level = .modalPanel
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
  }

  func containsEvent(_ event: NSEvent) -> Bool {
    guard let window, window.isVisible else {
      return false
    }
    if event.window === window {
      return true
    }
    return window.frame.contains(NSEvent.mouseLocation)
  }

  func windowWillClose(_ notification: Notification) {
    onWindowClosed?()
  }
}

private final class SettingsWindow: NSWindow {
  override func sendEvent(_ event: NSEvent) {
    switch event.type {
    case .scrollWheel:
      if forwardScrollWheelToContentScroller(event) {
        return
      }
    default:
      break
    }
    super.sendEvent(event)
  }

  @discardableResult
  private func forwardScrollWheelToContentScroller(_ event: NSEvent) -> Bool {
    guard let contentView else {
      return false
    }
    let point = contentView.convert(event.locationInWindow, from: nil)
    guard contentView.bounds.contains(point) else {
      return false
    }
    if contentView.hitTest(point)?.firstAncestor(of: NSScrollView.self) != nil {
      return false
    }
    guard let scrollView = contentView.firstDescendant(of: NSScrollView.self) else {
      return false
    }
    scrollView.scrollWheel(with: event)
    return true
  }
}

private final class SettingsHostingView<Content: View>: NSHostingView<Content> {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func scrollWheel(with event: NSEvent) {
    if shouldConsumeScrollWheel(event) {
      nearestScrollView()?.scrollWheel(with: event)
      return
    }
    super.scrollWheel(with: event)
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    if let hitView = super.hitTest(point) {
      return hitView
    }
    return bounds.contains(point) ? self : nil
  }

  private func shouldConsumeScrollWheel(_ event: NSEvent) -> Bool {
    guard let contentView = window?.contentView else {
      return false
    }
    let windowPoint = contentView.convert(event.locationInWindow, from: nil)
    return window?.contentView?.hitTest(windowPoint) === self
  }

  private func nearestScrollView() -> NSScrollView? {
    firstDescendant(of: NSScrollView.self)
  }
}

private extension NSView {
  func firstAncestor<T: NSView>(of type: T.Type) -> T? {
    var view: NSView? = self
    while let currentView = view {
      if let matchingView = currentView as? T {
        return matchingView
      }
      view = currentView.superview
    }
    return nil
  }

  func firstDescendant<T: NSView>(of type: T.Type) -> T? {
    if let matchingView = self as? T {
      return matchingView
    }
    for subview in subviews {
      if let matchingView = subview.firstDescendant(of: type) {
        return matchingView
      }
    }
    return nil
  }
}

private struct SettingsWindowDragHandle: NSViewRepresentable {
  func makeNSView(context: Context) -> DragView {
    DragView()
  }

  func updateNSView(_ nsView: DragView, context: Context) {}

  final class DragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
      true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
      bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
      guard event.type == .leftMouseDown else {
        super.mouseDown(with: event)
        return
      }
      window?.performDrag(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
      window?.contentView?.firstDescendant(of: NSScrollView.self)?.scrollWheel(with: event)
    }
  }
}
