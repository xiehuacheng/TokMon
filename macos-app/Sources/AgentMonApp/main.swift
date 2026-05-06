import AppKit
import SwiftUI

@MainActor
final class AgentMonApplicationDelegate: NSObject, NSApplicationDelegate {
  private let runtime = AgentMonRuntime.shared
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let popover = NSPopover()
  private var popoverDelegate: AgentMonPopoverDelegate?

  override init() {
    super.init()
    runtime.start()
    configureStatusItem()
  }

  func applicationWillTerminate(_ notification: Notification) {
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
    statusItem.button?.action = #selector(togglePopover)
    statusItem.button?.contentTintColor = .labelColor

    popover.behavior = .transient
    popoverDelegate = AgentMonPopoverDelegate(
      didShow: { [weak self] in
        self?.setStatusItemHighlighted(true)
      },
      didClose: { [weak self] in
        self?.setStatusItemHighlighted(false)
      },
    )
    popover.delegate = popoverDelegate
    popover.contentSize = NSSize(width: 360, height: 500)
    popover.contentViewController = NSHostingController(
      rootView: StatusPopoverView()
        .environmentObject(runtime)
        .environmentObject(runtime.server)
        .environmentObject(runtime.stats)
        .environment(\.controlActiveState, .active),
    )
  }

  @objc private func togglePopover() {
    guard let button = statusItem.button else { return }

    if popover.isShown {
      popover.performClose(nil)
      setStatusItemHighlighted(false)
      return
    }

    setStatusItemHighlighted(true)
    NSApplication.shared.activate(ignoringOtherApps: true)
    Task { @MainActor in
      await runtime.stats.refresh()
    }
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    DispatchQueue.main.async { [weak self] in
      self?.setStatusItemHighlighted(true)
      NSApplication.shared.activate(ignoringOtherApps: true)
      self?.popover.contentViewController?.view.window?.makeKey()
    }
  }

  private func setStatusItemHighlighted(_ highlighted: Bool) {
    statusItem.button?.state = highlighted ? .on : .off
    statusItem.button?.contentTintColor = highlighted ? .controlAccentColor : .labelColor
    statusItem.button?.highlight(highlighted)
  }
}

private final class AgentMonPopoverDelegate: NSObject, NSPopoverDelegate {
  private let didShow: () -> Void
  private let didClose: () -> Void

  init(didShow: @escaping () -> Void, didClose: @escaping () -> Void) {
    self.didShow = didShow
    self.didClose = didClose
  }

  func popoverDidShow(_ notification: Notification) {
    didShow()
  }

  func popoverDidClose(_ notification: Notification) {
    didClose()
  }
}

let app = NSApplication.shared
let delegate = AgentMonApplicationDelegate()
agentMonLog("AgentMon main started")
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.finishLaunching()
app.run()
