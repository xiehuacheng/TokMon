import AppKit
import Combine
import SwiftUI

@MainActor
final class TokMonApplicationDelegate: NSObject, NSApplicationDelegate {
  private let runtime = TokMonRuntime.shared
  private let updater = TokMonUpdater.shared
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private var statusPanel: NSPanel?
  private var outsideClickMonitor: Any?
  private var localClickMonitor: Any?
  private var panelKeyObserver: NSObjectProtocol?
  private var cancellables = Set<AnyCancellable>()
  private var isClosingStatusPanel = false
  private var appearanceObserver: NSObjectProtocol?
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
    removeAppearanceObserver()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    configureMainMenu()
  }

  private func configureMainMenu() {
    let mainMenu = NSMenu()
    let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editMenuItem.submenu = editMenu
    mainMenu.addItem(editMenuItem)
    NSApplication.shared.mainMenu = mainMenu
  }

  func applicationDidResignActive(_ notification: Notification) {
    guard statusPanel?.isVisible == true else {
      return
    }
    closeStatusPanel()
  }

  private func configureStatusItem() {
    statusItem.length = NSStatusItem.variableLength
    refreshStatusItemImage()

    statusItem.button?.imagePosition = .imageOnly
    statusItem.button?.target = self
    statusItem.button?.action = #selector(toggleStatusPanel)
    statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    bindStatusItemUpdates()
    bindAppearanceChanges()
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
      await runtime.stats.refreshWithScan()
    }

    let panelFrame = statusPanelFrame(relativeTo: button)
    let panel = makeStatusPanel()
    panel.setFrame(panelFrame, display: false)
    statusPanel = panel
    runtime.statusPanel = panel
    animateStatusPanelOpen(panel, targetFrame: panelFrame)
    installOutsideClickMonitor()
    installPanelKeyObserver(panel)
  }

  private func installPanelKeyObserver(_ panel: NSPanel) {
    removePanelKeyObserver()
    panelKeyObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didResignKeyNotification,
      object: panel,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.closeStatusPanel()
      }
    }
  }

  private func removePanelKeyObserver() {
    if let panelKeyObserver {
      NotificationCenter.default.removeObserver(panelKeyObserver)
      self.panelKeyObserver = nil
    }
  }

  private func closeStatusPanel() {
    guard let panel = statusPanel, !isClosingStatusPanel else {
      return
    }
    runtime.stats.popoverDidDisappear()
    isClosingStatusPanel = true
    removeOutsideClickMonitor()
    removePanelKeyObserver()
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

    runtime.stats.$kimiQuotaSnapshot
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        guard let self else { return }
        self.updateStatusItem(snapshot: self.runtime.stats.snapshot)
      }
      .store(in: &cancellables)
  }

  private func refreshStatusItemImage() {
    statusItem.button?.image = TokMonMenuBarIcon.makeImage()
  }

  private func bindAppearanceChanges() {
    appearanceObserver = DistributedNotificationCenter.default.addObserver(
      forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.refreshStatusItemImage()
        self.updateStatusItem(snapshot: self.runtime.stats.snapshot)
      }
    }
  }

  private func removeAppearanceObserver() {
    if let appearanceObserver {
      DistributedNotificationCenter.default.removeObserver(appearanceObserver)
      self.appearanceObserver = nil
    }
  }

  private func updateStatusItem(snapshot: TokMonStatsSnapshot) {
    let items = snapshot.dashboardState?.menuBarDisplayItems ?? .empty
    let quotaSnapshot = runtime.stats.kimiQuotaSnapshot
    let title = TokMonMenuBarPresentation.title(for: items, snapshot: snapshot, kimiQuotaSnapshot: quotaSnapshot)
    let button = statusItem.button

    button?.title = title ?? ""
    button?.imagePosition = title == nil ? .imageOnly : .imageLeft
    button?.toolTip = TokMonMenuBarPresentation.accessibilityLabel(for: items, snapshot: snapshot, kimiQuotaSnapshot: quotaSnapshot)
    statusItem.length = NSStatusItem.variableLength
  }

  private func finishClosingStatusPanel(_ panel: NSPanel) {
    panel.orderOut(nil)
    statusPanel?.delegate = nil
    removePanelKeyObserver()
    if statusPanel === panel {
      statusPanel = nil
      runtime.statusPanel = nil
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
    view.layer?.masksToBounds = false

    let panel = TokMonStatusPanel(
      contentRect: NSRect(origin: .zero, size: NSSize(width: statusPanelContentWidth, height: statusPanelHeight)),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false,
    )
    panel.contentViewController = hostingController
    panel.contentView?.wantsLayer = true
    panel.contentView?.layer?.masksToBounds = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .modalPanel
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    return panel
  }

  private func animateStatusPanelOpen(_ panel: NSPanel, targetFrame: NSRect) {
    var startFrame = targetFrame
    startFrame.origin.y -= statusPanelAnimationOffset
    panel.alphaValue = 0
    panel.setFrame(startFrame, display: false)
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

  private func statusPanelFrame(relativeTo button: NSStatusBarButton) -> NSRect {
    guard let buttonWindow = button.window, let screen = buttonWindow.screen ?? NSScreen.main else {
      return NSRect(
        x: 0,
        y: 0,
        width: statusPanelContentWidth + statusPanelShadowPadding * 2,
        height: statusPanelHeight + statusPanelShadowPadding
      )
    }

    let panelSize = NSSize(
      width: statusPanelContentWidth + statusPanelShadowPadding * 2,
      height: statusPanelHeight + statusPanelShadowPadding
    )
    let mainPanelWidth: CGFloat = statusPanelMainWidth
    let buttonFrameInScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
    let screenFrame = screen.visibleFrame
    let preferredMainX = buttonFrameInScreen.midX - mainPanelWidth / 2
    let minMainX = screenFrame.minX + 8 + sessionBubbleWidth + sessionBubbleGutter
    let maxMainX = screenFrame.maxX - mainPanelWidth - 8
    let mainX = min(max(preferredMainX, minMainX), maxMainX)
    let x = mainX - sessionBubbleWidth - sessionBubbleGutter - statusPanelShadowPadding
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
    guard shouldCloseStatusPanel(for: event) else {
      return event
    }
    Task { @MainActor in
      self.closeStatusPanel()
    }
    return event.window === statusPanel ? nil : event
  }

  private func shouldCloseStatusPanel(for event: NSEvent) -> Bool {
    guard let statusPanel else {
      return false
    }
    if runtime.isSettingsWindowEvent(event) {
      return false
    }
    return !isPointInsideVisibleStatusPanel(NSEvent.mouseLocation, statusPanel: statusPanel)
  }

  private func isPointInsideVisibleStatusPanel(_ point: NSPoint, statusPanel: NSPanel) -> Bool {
    let contentMinX = statusPanel.frame.minX + statusPanelShadowPadding
    let contentMinY = statusPanel.frame.maxY - statusPanelHeight
    let mainFrame = NSRect(
      x: contentMinX + sessionBubbleWidth + sessionBubbleGutter,
      y: contentMinY,
      width: statusPanelMainWidth,
      height: statusPanelHeight
    )
    if mainFrame.insetBy(dx: -2, dy: -2).contains(point) {
      return true
    }

    let bubbleGutterFrame = NSRect(
      x: contentMinX,
      y: contentMinY,
      width: sessionBubbleWidth + sessionBubbleGutter,
      height: statusPanelHeight
    )
    if bubbleGutterFrame.insetBy(dx: -2, dy: -2).contains(point) {
      return true
    }

    guard let sessionBubbleY = runtime.statusPanelSessionBubbleY else {
      return false
    }

    let bubbleFrame = NSRect(
      x: contentMinX,
      y: statusPanel.frame.maxY - sessionBubbleY - sessionBubbleMaxHeight,
      width: sessionBubbleWidth,
      height: sessionBubbleMaxHeight
    )
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
    statusItem.button?.highlight(highlighted)
  }
}

private final class TokMonStatusPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

let app = NSApplication.shared
let delegate = TokMonApplicationDelegate()
tokMonLog("TokMon main started")
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.finishLaunching()
app.run()
