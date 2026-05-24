import AppKit
import IOKit.hid
import OpenJoystickDriverKit
import SwiftUI

/// Application delegate: sets up menu bar icon and manages main window.
///
/// App runs as accessory (no Dock icon) - it is persistent system utility.
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem?
  private var popover: NSPopover?
  private var statusItemLocalRightClickMonitor: Any?
  private var statusItemGlobalRightClickMonitor: Any?
  private(set) var model: AppModel

  init(developerMode: Bool = false) { self.model = AppModel(developerMode: developerMode) }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    configureApplicationIcon()
    setupStatusItem()
    requestPermissions()
    Task { @MainActor in await model.start() }
  }

  /// Trigger system permission dialogs on first launch.
  ///
  /// These are no-ops if already granted.
  private func requestPermissions() { IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

  private func configureApplicationIcon() {
    if let url = Bundle.main.url(forResource: "OpenJoystickDriver", withExtension: "icns"),
       let image = NSImage(contentsOf: url)
    {
      NSApp.applicationIconImage = image
    }
  }

  // MARK: - Status Item

  private func setupStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.autosaveName = "OpenJoystickDriver"
    if let button = item.button {
      if #available(macOS 11.0, *) {
        button.image = NSImage(
          systemSymbolName: "gamecontroller.fill",
          accessibilityDescription: "OpenJoystickDriver"
        )
      } else {
        button.image = NSImage(named: NSImage.actionTemplateName)
      }
      button.target = self
      button.action = #selector(handleStatusItemClick(_:))
      button.sendAction(on: [.leftMouseUp, .rightMouseDown])
    }
    statusItem = item
    installStatusItemRightClickMonitor()
  }

  // MARK: - Popover

  @objc private func handleStatusItemClick(_ sender: Any?) {
    if NSApp.currentEvent?.type == .rightMouseDown {
      showPopover(sender)
    } else {
      togglePopover(sender)
    }
  }

  private func installStatusItemRightClickMonitor() {
    guard statusItemLocalRightClickMonitor == nil, statusItemGlobalRightClickMonitor == nil else {
      return
    }

    statusItemLocalRightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) {
      [weak self] event in
      guard let self, let button = self.statusItem?.button, event.window === button.window else {
        return event
      }

      let point = button.convert(event.locationInWindow, from: nil)
      guard button.bounds.contains(point) else { return event }

      self.showPopover(event)
      return nil
    }

    statusItemGlobalRightClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown]) {
      [weak self] event in
      Task { @MainActor [weak self] in
        guard let self, self.eventIsInsideStatusItem(event) else { return }
        self.showPopover(event)
      }
    }
  }

  private func eventIsInsideStatusItem(_ event: NSEvent) -> Bool {
    guard let frame = statusItem?.button?.window?.frame else { return false }
    return frame.contains(event.locationInWindow)
  }

  @objc private func togglePopover(_ sender: Any?) {
    ensurePopover()

    guard let popover else { return }
    if popover.isShown {
      popover.performClose(sender)
    } else {
      showPopover(sender)
    }
  }

  private func showPopover(_ sender: Any?) {
    guard let button = statusItem?.button else { return }
    ensurePopover()
    guard let popover, !popover.isShown else { return }
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func ensurePopover() {
    guard popover == nil else { return }
    let pop = NSPopover()
    pop.behavior = .transient
    let contentView = MenuBarPopoverView().environmentObject(model)
    let controller = NSHostingController(rootView: contentView)
    pop.contentViewController = controller
    pop.contentSize = NSSize(width: 440, height: 560)
    popover = pop
  }

}
