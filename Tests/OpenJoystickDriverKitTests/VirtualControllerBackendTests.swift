import Testing

@testable import OpenJoystickDriverKit

@Suite("Virtual Controller Backend Tests") struct VirtualControllerBackendTests {

  @Test("GameController virtual backend is tracked as unsupported system-wide output")
  func gameControllerVirtualBackendCapability() {
    let capabilities = VirtualControllerBackendCatalog.gameControllerVirtualCapabilities

    #expect(!capabilities.isImplemented)
    #expect(!capabilities.isSystemWide)
    #expect(capabilities.notes.contains("GCVirtualController"))
  }

  @Test("DriverKit backend reports system-wide entitlement requirement")
  func driverKitBackendCapability() {
    let backend: any VirtualControllerBackend = DextOutputDispatcher()

    #expect(backend.backendID == .driverKitHID)
    #expect(backend.capabilities.isImplemented)
    #expect(backend.capabilities.isSystemWide)
    #expect(backend.capabilities.requiresEntitlement)
  }
}
