import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class TokMonApplicationDelegate: NSObject, NSApplicationDelegate {
  private let runtime = TokMonRuntime.shared
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private var statusPanel: NSPanel?
  private var outsideClickMonitor: Any?
  private var localClickMonitor: Any?
  private var cancellables = Set<AnyCancellable>()
  private var isClosingStatusPanel = false
  private let statusPanelAnimationDuration: TimeInterval = 0.18
  private let statusPanelAnimationOffset: CGFloat = 10

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
    statusItem.length = NSStatusItem.variableLength
    let statusImage = TokMonMenuBarIcon.makeImage()

    statusItem.button?.image = statusImage
    statusItem.button?.imagePosition = .imageOnly
    statusItem.button?.target = self
    statusItem.button?.action = #selector(toggleStatusPanel)
    statusItem.button?.contentTintColor = .labelColor
    statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    bindStatusItemUpdates()
    updateStatusItem(snapshot: runtime.stats.snapshot)
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
      await runtime.stats.refresh()
    }

    let panelFrame = statusPanelFrame(relativeTo: button)
    let panel = makeStatusPanel()
    panel.setFrame(panelFrame, display: false)
    statusPanel = panel
    animateStatusPanelOpen(panel, targetFrame: panelFrame)
    DispatchQueue.main.async { [weak self] in
      self?.installOutsideClickMonitor()
    }
  }

  private func closeStatusPanel() {
    guard let panel = statusPanel, !isClosingStatusPanel else {
      return
    }
    isClosingStatusPanel = true
    removeOutsideClickMonitor()
    setStatusItemHighlighted(false)
    animateStatusPanelClose(panel)
  }

  private func bindStatusItemUpdates() {
    runtime.stats.$snapshot
      .receive(on: DispatchQueue.main)
      .sink { [weak self] snapshot in
        self?.updateStatusItem(snapshot: snapshot)
      }
      .store(in: &cancellables)
  }

  private func updateStatusItem(snapshot: TokMonStatsSnapshot) {
    let mode = snapshot.dashboardState?.menuBarDisplayMode ?? .iconOnly
    let title = TokMonMenuBarPresentation.title(for: mode, snapshot: snapshot)
    statusItem.button?.title = title ?? ""
    statusItem.button?.imagePosition = title == nil ? .imageOnly : .imageLeft
    statusItem.button?.toolTip = TokMonMenuBarPresentation.accessibilityLabel(for: mode, snapshot: snapshot)
    statusItem.length = NSStatusItem.variableLength
  }

  private func finishClosingStatusPanel(_ panel: NSPanel) {
    panel.orderOut(nil)
    statusPanel?.delegate = nil
    if statusPanel === panel {
      statusPanel = nil
    }
    isClosingStatusPanel = false
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

    let panel = TokMonStatusPanel(
      contentRect: NSRect(origin: .zero, size: NSSize(width: statusPanelContentWidth, height: statusPanelHeight)),
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

  private func animateStatusPanelOpen(_ panel: NSPanel, targetFrame: NSRect) {
    var startFrame = targetFrame
    startFrame.origin.y -= statusPanelAnimationOffset
    panel.alphaValue = 0
    panel.setFrame(startFrame, display: false)
    panel.orderFrontRegardless()
    panel.makeKeyAndOrderFront(nil)
    NSAnimationContext.runAnimationGroup { context in
      context.duration = statusPanelAnimationDuration
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      panel.animator().alphaValue = 1
      panel.animator().setFrameOrigin(targetFrame.origin)
    }
  }

  private func animateStatusPanelClose(_ panel: NSPanel) {
    var closingFrame = panel.frame
    closingFrame.origin.y -= statusPanelAnimationOffset
    NSAnimationContext.runAnimationGroup { context in
      context.duration = statusPanelAnimationDuration
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      panel.animator().alphaValue = 0
      panel.animator().setFrameOrigin(closingFrame.origin)
    } completionHandler: { [weak self, weak panel] in
      Task { @MainActor in
        guard let panel else {
          return
        }
        self?.finishClosingStatusPanel(panel)
      }
    }
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
      return NSRect(x: 0, y: 0, width: statusPanelContentWidth, height: statusPanelHeight)
    }

    let panelSize = NSSize(width: statusPanelContentWidth, height: statusPanelHeight)
    let mainPanelWidth: CGFloat = statusPanelMainWidth
    let buttonFrameInScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
    let screenFrame = screen.visibleFrame
    let preferredMainX = buttonFrameInScreen.midX - mainPanelWidth / 2
    let minMainX = screenFrame.minX + 8 + sessionBubbleWidth + sessionBubbleGutter
    let maxMainX = screenFrame.maxX - mainPanelWidth - 8
    let mainX = min(max(preferredMainX, minMainX), maxMainX)
    let x = mainX - sessionBubbleWidth - sessionBubbleGutter
    let y = screenFrame.maxY - panelSize.height

    return NSRect(origin: NSPoint(x: x, y: y), size: panelSize)
  }

  private func installOutsideClickMonitor() {
    removeOutsideClickMonitor()
    localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
      self?.handleLocalMouseDown(event) ?? event
    }
    outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
      guard self?.shouldCloseStatusPanel(for: event) == true else {
        return
      }
      Task { @MainActor in
        self?.closeStatusPanel()
      }
    }
  }

  private func handleLocalMouseDown(_ event: NSEvent) -> NSEvent? {
    guard let statusPanel else {
      return event
    }
    let isStatusPanelEvent = event.window === statusPanel
    guard isStatusPanelEvent, shouldCloseStatusPanel(for: event) else {
      return event
    }
    Task { @MainActor in
      self.closeStatusPanel()
    }
    return isStatusPanelEvent ? nil : event
  }

  private func shouldCloseStatusPanel(for event: NSEvent) -> Bool {
    guard let statusPanel else {
      return false
    }
    return !isPointInsideVisibleStatusPanel(NSEvent.mouseLocation, statusPanel: statusPanel)
  }

  private func isPointInsideVisibleStatusPanel(_ point: NSPoint, statusPanel: NSPanel) -> Bool {
    var mainFrame = statusPanel.frame
    mainFrame.origin.x += sessionBubbleWidth + sessionBubbleGutter
    mainFrame.size.width = statusPanelMainWidth
    if mainFrame.insetBy(dx: -2, dy: -2).contains(point) {
      return true
    }

    guard let sessionBubbleY = runtime.statusPanelSessionBubbleY else {
      return false
    }

    var bubbleFrame = statusPanel.frame
    bubbleFrame.origin.y = statusPanel.frame.maxY - sessionBubbleY - sessionBubbleMaxHeight
    bubbleFrame.size.width = sessionBubbleWidth
    bubbleFrame.size.height = sessionBubbleMaxHeight
    return bubbleFrame.insetBy(dx: -2, dy: -2).contains(point)
  }

  private func removeOutsideClickMonitor() {
    if let localClickMonitor {
      NSEvent.removeMonitor(localClickMonitor)
      self.localClickMonitor = nil
    }

    if let outsideClickMonitor {
      NSEvent.removeMonitor(outsideClickMonitor)
      self.outsideClickMonitor = nil
    }
  }

  private func setStatusItemHighlighted(_ highlighted: Bool) {
    statusItem.button?.state = highlighted ? .on : .off
    statusItem.button?.contentTintColor = highlighted ? .controlAccentColor : .labelColor
    statusItem.button?.highlight(highlighted)
  }
}

private final class TokMonStatusPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

let app = NSApplication.shared
let delegate = TokMonApplicationDelegate()
tokMonLog("TokMon main started")
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.finishLaunching()
app.run()
