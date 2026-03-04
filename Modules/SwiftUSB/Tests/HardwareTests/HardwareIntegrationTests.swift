import Testing

@testable import SwiftUSB

@Suite(.serialized) struct HardwareIntegrationTests {

  @Test("USBContext initializes and deinitializes without crash (validates FOUN-02)")
  func contextLifecycle() throws {
    let context = try USBContext()
    _ = context
  }

  @Test("USBContext can be created and destroyed multiple times (validates FOUN-02)")
  func repeatedContextLifecycle() throws {
    for _ in 0..<5 {
      let context = try USBContext()
      _ = context
    }
  }

  @Test("findDevices returns stream without crash (validates FOUN-01)")
  func findDevicesDoesNotCrash() async throws {
    let context = try USBContext()
    var count = 0
    for await _ in context.findDevices() { count += 1 }
    #expect(count >= 0)
  }

  @Test("findDevices with non-matching VID/PID filter returns empty") func findDevicesWithFilter()
    async throws
  {
    let context = try USBContext()
    var count = 0
    for await _ in context.findDevices(vendorId: 0xFFFF, productId: 0xFFFF) { count += 1 }
    #expect(count == 0)
  }
}
