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
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
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
      button.action = #selector(togglePopover(_:))
    }
    statusItem = item
  }

  // MARK: - Popover

  @objc private func togglePopover(_ sender: Any?) {
    guard let button = statusItem?.button else { return }

    if popover == nil {
      let pop = NSPopover()
      pop.behavior = .transient
      let contentView = MenuBarPopoverView().environmentObject(model)
      let controller = NSHostingController(rootView: contentView)
      pop.contentViewController = controller
      pop.contentSize = NSSize(width: 420, height: 460)
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
