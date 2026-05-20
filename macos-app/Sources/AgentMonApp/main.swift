import AppKit
import SwiftUI

@MainActor
final class AgentMonApplicationDelegate: NSObject, NSApplicationDelegate {
  private let runtime = AgentMonRuntime.shared
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private var statusPanel: NSPanel?
  private var outsideClickMonitor: Any?

  override init() {
    super.init()
    runtime.start()
    configureStatusItem()
  }

  func applicationWillTerminate(_ notification: Notification) {
    closeStatusPanel()
    runtime.stop()
  }

  private func configureStatusItem() {
    statusItem.length = NSStatusItem.squareLength
    let statusImage = NSImage(
      systemSymbolName: "chart.line.uptrend.xyaxis",
      accessibilityDescription: "AgentMon",
    )
    statusImage?.isTemplate = true

    statusItem.button?.image = statusImage
    statusItem.button?.imagePosition = .imageOnly
    statusItem.button?.target = self
    statusItem.button?.action = #selector(toggleStatusPanel)
    statusItem.button?.contentTintColor = .labelColor
  }

  @objc private func toggleStatusPanel() {
    if statusPanel?.isVisible == true {
      closeStatusPanel()
      return
    }

    showStatusPanel()
  }

  private func showStatusPanel() {
    guard let button = statusItem.button else { return }

    setStatusItemHighlighted(true)
    Task { @MainActor in
      runtime.stats.startObserving()
      await runtime.stats.refresh()
    }

    let panel = makeStatusPanel()
    panel.setFrame(statusPanelFrame(relativeTo: button), display: false)
    statusPanel = panel
    panel.orderFrontRegardless()
    panel.makeKeyAndOrderFront(nil)
    DispatchQueue.main.async { [weak self] in
      self?.installOutsideClickMonitor()
    }
  }

  private func closeStatusPanel() {
    statusPanel?.orderOut(nil)
    statusPanel?.delegate = nil
    statusPanel = nil
    runtime.stats.stopObserving()
    removeOutsideClickMonitor()
    setStatusItemHighlighted(false)
  }

  private func makeStatusPanel() -> NSPanel {
    let hostingController = NSHostingController(
      rootView: StatusPopoverView()
        .environmentObject(runtime)
        .environmentObject(runtime.stats)
        .environment(\.controlActiveState, .active),
    )
    let view = hostingController.view
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.clear.cgColor

    let panel = AgentMonStatusPanel(
      contentRect: NSRect(origin: .zero, size: NSSize(width: 360, height: 740)),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false,
    )
    panel.contentViewController = hostingController
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    makePanelWindowTransparent(panel)
    return panel
  }

  private func makePanelWindowTransparent(_ window: NSWindow) {
    guard let view = window.contentViewController?.view else {
      return
    }

    window.isOpaque = false
    window.backgroundColor = .clear
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.clear.cgColor
  }

  private func statusPanelFrame(relativeTo button: NSStatusBarButton) -> NSRect {
    guard let buttonWindow = button.window, let screen = buttonWindow.screen ?? NSScreen.main else {
      return NSRect(x: 0, y: 0, width: 360, height: 740)
    }

    let panelSize = NSSize(width: 360, height: 740)
    let buttonFrameInScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
    let screenFrame = screen.visibleFrame
    let preferredX = buttonFrameInScreen.midX - panelSize.width / 2
    let x = min(max(preferredX, screenFrame.minX + 8), screenFrame.maxX - panelSize.width - 8)
    let y = screenFrame.maxY - panelSize.height

    return NSRect(origin: NSPoint(x: x, y: y), size: panelSize)
  }

  private func installOutsideClickMonitor() {
    removeOutsideClickMonitor()
    outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
      Task { @MainActor in
        self?.closeStatusPanel()
      }
    }
  }

  private func removeOutsideClickMonitor() {
    guard let outsideClickMonitor else {
      return
    }

    NSEvent.removeMonitor(outsideClickMonitor)
    self.outsideClickMonitor = nil
  }

  private func setStatusItemHighlighted(_ highlighted: Bool) {
    statusItem.button?.state = highlighted ? .on : .off
    statusItem.button?.contentTintColor = highlighted ? .controlAccentColor : .labelColor
    statusItem.button?.highlight(highlighted)
  }
}

private final class AgentMonStatusPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

let app = NSApplication.shared
let delegate = AgentMonApplicationDelegate()
agentMonLog("AgentMon main started")
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.finishLaunching()
app.run()
