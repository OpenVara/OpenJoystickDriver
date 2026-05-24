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
  private var statusItemRightClickMonitor: Any?
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
      showStatusMenu()
    } else {
      togglePopover(sender)
    }
  }

  private func installStatusItemRightClickMonitor() {
    guard statusItemRightClickMonitor == nil else { return }
    statusItemRightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) {
      [weak self] event in
      guard let self, let button = self.statusItem?.button, event.window === button.window else {
        return event
      }

      let point = button.convert(event.locationInWindow, from: nil)
      guard button.bounds.contains(point) else { return event }

      self.showStatusMenu()
      return nil
    }
  }

  private func showStatusMenu() {
    guard let button = statusItem?.button else {
      togglePopover(nil)
      return
    }

    let menu = NSMenu()
    let openItem = NSMenuItem(
      title: "Open OpenJoystickDriver",
      action: #selector(openFromStatusMenu(_:)),
      keyEquivalent: ""
    )
    openItem.target = self
    let quitItem = NSMenuItem(
      title: "Quit OpenJoystickDriver",
      action: #selector(quitFromStatusMenu(_:)),
      keyEquivalent: ""
    )
    quitItem.target = self

    if #available(macOS 11.0, *) {
      openItem.image = NSImage(
        systemSymbolName: "rectangle.grid.1x2",
        accessibilityDescription: "Open"
      )
      quitItem.image = NSImage(
        systemSymbolName: "power",
        accessibilityDescription: "Quit"
      )
    }

    menu.addItem(openItem)
    menu.addItem(.separator())
    menu.addItem(quitItem)
    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
  }

  @objc private func openFromStatusMenu(_ sender: Any?) {
    if popover?.isShown == true {
      return
    }
    togglePopover(sender)
  }

  @objc private func quitFromStatusMenu(_ sender: Any?) {
    NSApplication.shared.terminate(sender)
  }

  @objc private func togglePopover(_ sender: Any?) {
    guard let button = statusItem?.button else { return }

    if popover == nil {
      let pop = NSPopover()
      pop.behavior = .transient
      let contentView = MenuBarPopoverView().environmentObject(model)
      let controller = NSHostingController(rootView: contentView)
      pop.contentViewController = controller
      pop.contentSize = NSSize(width: 440, height: 560)
      popover = pop
    }

    guard let popover else { return }
    if popover.isShown {
      popover.performClose(sender)
    } else {
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      NSApp.activate(ignoringOtherApps: true)
    }
  }

}
