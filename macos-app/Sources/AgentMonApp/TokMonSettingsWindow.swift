import SwiftUI

struct TokMonSettingsWindow: View {
  @ObservedObject var store: TokMonSettingsStore

  private let sources = [
    ("", "All Sources"),
    ("claude-code", "Claude Code"),
    ("codex", "Codex"),
  ]
  private let ranges = ["1H", "24H", "7D", "30D", "90D"]
  private let rangeModes = [("exact", "Exact"), ("round", "Round")]
  private let intervals = [("hour", "Hour"), ("day", "Day")]
  private let metrics = [
    ("total", "Total Tokens"),
    ("reqs", "Requests"),
    ("input", "Input"),
    ("output", "Output"),
    ("cache", "Cache Created"),
    ("cacheHit", "Cache Hit"),
    ("cost", "Estimated Cost"),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header
      Form {
        Section("Source Paths") {
          TextField("Claude Code", text: $store.draft.claudePath)
          TextField("Codex", text: $store.draft.codexPath)
        }

        Section("Defaults") {
          Picker("Source", selection: $store.draft.source) {
            ForEach(sources, id: \.0) { value, label in
              Text(label).tag(value)
            }
          }
          Picker("Range", selection: $store.draft.rangeLabel) {
            ForEach(ranges, id: \.self) { range in
              Text(range).tag(range)
            }
          }
          Toggle("Live Mode", isOn: $store.draft.liveMode)
          Picker("Range Mode", selection: $store.draft.rangeMode) {
            ForEach(rangeModes, id: \.0) { value, label in
              Text(label).tag(value)
            }
          }
          Picker("Interval", selection: $store.draft.interval) {
            ForEach(intervals, id: \.0) { value, label in
              Text(label).tag(value)
            }
          }
          Picker("Metric", selection: $store.draft.activeSeries) {
            ForEach(metrics, id: \.0) { value, label in
              Text(label).tag(value)
            }
          }
          Stepper(value: $store.draft.refreshRate, in: 1000...60000, step: 1000) {
            Text("Refresh \(store.draft.refreshRate) ms")
          }
        }

        Section("Cost Rates Per 1M Tokens") {
          RateField(label: "Input", value: $store.draft.inputRate)
          RateField(label: "Output", value: $store.draft.outputRate)
          RateField(label: "Cache Create", value: $store.draft.cacheCreateRate)
          RateField(label: "Cache Read", value: $store.draft.cacheReadRate)
        }

        Section("Maintenance") {
          HStack {
            Button("Scan Now") {
              Task { try? await store.scanNow() }
            }
            .disabled(store.isBusy)

            Button("Rebuild Database") {
              Task { try? await store.rebuildAndRescan() }
            }
            .disabled(store.isBusy)

            Button("Check Parity") {
              Task { try? await store.runParityCheck() }
            }
            .disabled(store.isBusy)
          }
          parityStatus
        }
      }

      footer
    }
    .padding(20)
    .frame(minWidth: 520, minHeight: 560)
    .task {
      try? await store.load()
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("TokMon Settings")
        .font(.title3.weight(.semibold))
      Text("Native token monitoring configuration")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var footer: some View {
    HStack {
      if store.isBusy {
        ProgressView()
          .scaleEffect(0.7)
      }
      Text(store.errorMessage ?? store.statusMessage)
        .font(.caption)
        .foregroundStyle(store.errorMessage == nil ? .secondary : Color.red)
      Spacer()
      Button("Save") {
        Task { try? await store.save() }
      }
      .keyboardShortcut(.defaultAction)
      .disabled(store.isBusy)
    }
  }

  private var parityStatus: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(store.parityReport?.summary ?? "Compares native queries with retained legacy route SQL semantics.")
        .font(.caption)
        .foregroundStyle(.secondary)
      if let differences = store.parityReport?.differences, !differences.isEmpty {
        ForEach(differences.prefix(3)) { difference in
          Text("\(difference.endpoint).\(difference.path): native \(difference.native), legacy \(difference.legacy)")
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
    }
  }
}

private struct RateField: View {
  let label: String
  @Binding var value: Double

  var body: some View {
    HStack {
      Text(label)
      Spacer()
      TextField(label, value: $value, format: .number.precision(.fractionLength(0...6)))
        .multilineTextAlignment(.trailing)
        .frame(width: 110)
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
      contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false,
    )
    window.title = "TokMon Settings"
    window.center()
    window.contentView = NSHostingView(rootView: TokMonSettingsWindow(store: settingsStore))
    window.isReleasedWhenClosed = false
    window.makeKeyAndOrderFront(nil)
    self.window = window
    NSApplication.shared.activate(ignoringOtherApps: true)
  }
}
