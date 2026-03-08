import Foundation
import SystemExtensions

/// Manages installation and removal of the `com.openjoystickdriver.VirtualHIDDevice`
/// DriverKit system extension via `OSSystemExtensionManager`.
///
/// Usage: call ``installExtension()`` from the GUI; monitor ``installState`` for
/// progress. The extension must be embedded in the app bundle under
/// `Contents/Library/SystemExtensions/OpenJoystickVirtualHID.dext`.
///
/// The GUI app requires `com.apple.developer.system-extension.install` in its
/// entitlements (`Sources/OpenJoystickDriver/OpenJoystickDriver.entitlements`).
///
/// - Note: `@unchecked Sendable` suppresses the Sendable warning that arises
///   when `AppModel` (a `@MainActor` class) holds a reference to this object.
///   All `@Published` mutations happen on the main queue (the delegate callbacks
///   use `queue: .main` and `Task { @MainActor in }`).
@MainActor
final class SystemExtensionManager: NSObject, ObservableObject, @unchecked Sendable {

  // MARK: - Install state

  enum InstallState: Equatable {
    case unknown
    case installing
    case requiresApproval
    case installed
    case failed(String)

    static func == (lhs: Self, rhs: Self) -> Bool {
      switch (lhs, rhs) {
      case (.unknown, .unknown), (.installing, .installing),
           (.requiresApproval, .requiresApproval), (.installed, .installed):
        return true
      case (.failed(let a), .failed(let b)):
        return a == b
      default:
        return false
      }
    }

    var label: String {
      switch self {
      case .unknown:          return "Unknown"
      case .installing:       return "Installing…"
      case .requiresApproval: return "Requires Approval"
      case .installed:        return "Installed"
      case .failed(let msg):  return "Failed: \(msg)"
      }
    }

    var isInstalled: Bool { self == .installed }
    var isPending: Bool { self == .installing || self == .requiresApproval }
  }

  @Published var installState: InstallState = .unknown

  // MARK: - Constants

  private let extensionBundleID = "com.openjoystickdriver.VirtualHIDDevice"

  // MARK: - Public API

  func installExtension() {
    installState = .installing
    let request = OSSystemExtensionRequest.activationRequest(
      forExtensionWithIdentifier: extensionBundleID,
      queue: .main
    )
    request.delegate = self
    OSSystemExtensionManager.shared.submitRequest(request)
  }

  func uninstallExtension() {
    let request = OSSystemExtensionRequest.deactivationRequest(
      forExtensionWithIdentifier: extensionBundleID,
      queue: .main
    )
    request.delegate = self
    OSSystemExtensionManager.shared.submitRequest(request)
  }
}

// MARK: - OSSystemExtensionRequestDelegate

extension SystemExtensionManager: OSSystemExtensionRequestDelegate {

  nonisolated func request(
    _ request: OSSystemExtensionRequest,
    didFinishWithResult result: OSSystemExtensionRequest.Result
  ) {
    Task { @MainActor [weak self] in self?.installState = .installed }
  }

  nonisolated func request(
    _ request: OSSystemExtensionRequest,
    didFailWithError error: Error
  ) {
    let message = error.localizedDescription
    Task { @MainActor [weak self] in self?.installState = .failed(message) }
  }

  nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
    Task { @MainActor [weak self] in self?.installState = .requiresApproval }
  }

  nonisolated func request(
    _ request: OSSystemExtensionRequest,
    actionForReplacingExtension existing: OSSystemExtensionProperties,
    withExtension ext: OSSystemExtensionProperties
  ) -> OSSystemExtensionRequest.ReplacementAction {
    // Always upgrade in place — no manual removal needed on update.
    .replace
  }
}
