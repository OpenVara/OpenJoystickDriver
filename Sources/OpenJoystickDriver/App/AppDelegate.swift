import AppKit
import ApplicationServices
import IOKit.hid
import OpenJoystickDriverKit
import SwiftUI

private enum WindowMetrics {
  static let size = NSSize(width: 900, height: 580)
  static let minSize = NSSize(width: 700, height: 480)
}

/// Application delegate: sets up menu bar icon and manages main window.
/// App runs as accessory (no Dock icon) - it is persistent system utility.
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem?
  private var mainWindow: NSWindow?
  private(set) var model = AppModel()

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    setupStatusItem()
    requestPermissions()
    Task { @MainActor in await model.start() }
  }

  /// Trigger system permission dialogs on first launch.
  /// These are no-ops if already granted.
  private func requestPermissions() {
    IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    // CFString global - bridge to String to satisfy Swift 6 Sendable check.
    let promptKey = "AXTrustedCheckOptionPrompt"
    AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

  // MARK: - Status Item

  private func setupStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = item.button {
      button.image = NSImage(
        systemSymbolName: "gamecontroller.fill",
        accessibilityDescription: "OpenJoystickDriver"
      )
    }
    let menu = NSMenu()
    let openItem = NSMenuItem(
      title: "Open Dashboard",
      action: #selector(openMainWindow),
      keyEquivalent: ""
    )
    openItem.target = self
    menu.addItem(openItem)
    menu.addItem(.separator())
    let quitItem = NSMenuItem(
      title: "Quit OpenJoystickDriver",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    menu.addItem(quitItem)
    item.menu = menu
    statusItem = item
  }

  // MARK: - Main Window

  @objc func openMainWindow() {
    if let existing = mainWindow, existing.isVisible {
      existing.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    let contentView = ContentView().environmentObject(model)
    let controller = NSHostingController(rootView: contentView)
    let window = NSWindow(contentViewController: controller)
    window.title = "OpenJoystickDriver"
    window.setContentSize(WindowMetrics.size)
    window.minSize = WindowMetrics.minSize
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    mainWindow = window
  }
}
