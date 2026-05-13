import Foundation
import Testing

@testable import OpenJoystickDriverKit

private func makeDS4Report(
  includesReportID: Bool = false,
  leftStickX: UInt8 = 128,
  leftStickY: UInt8 = 128,
  rightStickX: UInt8 = 128,
  rightStickY: UInt8 = 128,
  buttons0: UInt8 = 0x08,
  buttons1: UInt8 = 0,
  buttons2: UInt8 = 0,
  leftTrigger: UInt8 = 0,
  rightTrigger: UInt8 = 0
) -> Data {
  var report = [UInt8](repeating: 0, count: includesReportID ? 64 : 63)
  let base = includesReportID ? 1 : 0
  if includesReportID { report[0] = 0x01 }
  report[base + 0] = leftStickX
  report[base + 1] = leftStickY
  report[base + 2] = rightStickX
  report[base + 3] = rightStickY
  report[base + 4] = buttons0
  report[base + 5] = buttons1
  report[base + 6] = buttons2
  report[base + 7] = leftTrigger
  report[base + 8] = rightTrigger
  return Data(report)
}

@Suite("DS4 Parser Tests") struct DS4ParserTests {
  @Test("Wired IOHID reports without report ID parse face buttons")
  func wiredIOHIDReportWithoutReportIDParsesFaceButtons() throws {
    let parser = DS4Parser()
    _ = try parser.parse(data: makeDS4Report())

    let events = try parser.parse(data: makeDS4Report(buttons0: 0x28))

    #expect(events.contains(.buttonPressed(.cross)))
  }

  @Test("Raw USB reports with report ID parse face buttons")
  func rawUSBReportWithReportIDParsesFaceButtons() throws {
    let parser = DS4Parser()
    _ = try parser.parse(data: makeDS4Report(includesReportID: true))

    let events = try parser.parse(
      data: makeDS4Report(includesReportID: true, buttons0: 0x28)
    )

    #expect(events.contains(.buttonPressed(.cross)))
  }

  @Test("Wired IOHID reports parse sticks triggers and system buttons")
  func wiredIOHIDReportParsesSticksTriggersAndSystemButtons() throws {
    let parser = DS4Parser()
    _ = try parser.parse(data: makeDS4Report())

    let events = try parser.parse(
      data: makeDS4Report(
        leftStickX: 255,
        leftStickY: 0,
        rightStickX: 0,
        rightStickY: 255,
        buttons1: 0x30,
        buttons2: 0x03,
        leftTrigger: 255,
        rightTrigger: 128
      )
    )

    #expect(events.contains(.leftStickChanged(x: 127.0 / 128.0, y: 1.0)))
    #expect(events.contains(.rightStickChanged(x: -1.0, y: -127.0 / 128.0)))
    #expect(events.contains(.leftTriggerChanged(1.0)))
    #expect(events.contains(.rightTriggerChanged(128.0 / 255.0)))
    #expect(events.contains(.buttonPressed(.share)))
    #expect(events.contains(.buttonPressed(.options)))
    #expect(events.contains(.buttonPressed(.ps)))
    #expect(events.contains(.buttonPressed(.touchpad)))
  }

  @Test("Wired IOHID reports parse D-pad directions")
  func wiredIOHIDReportParsesDpadDirections() throws {
    let parser = DS4Parser()
    _ = try parser.parse(data: makeDS4Report())

    let upEvents = try parser.parse(data: makeDS4Report(buttons0: 0x00))
    let rightEvents = try parser.parse(data: makeDS4Report(buttons0: 0x02))
    let downEvents = try parser.parse(data: makeDS4Report(buttons0: 0x04))
    let leftEvents = try parser.parse(data: makeDS4Report(buttons0: 0x06))

    #expect(upEvents.contains(.dpadChanged(.north)))
    #expect(rightEvents.contains(.dpadChanged(.east)))
    #expect(downEvents.contains(.dpadChanged(.south)))
    #expect(leftEvents.contains(.dpadChanged(.west)))
  }

  @Test("Small DS4 stick jitter is normalized to idle")
  func smallDS4StickJitterIsNormalizedToIdle() throws {
    let parser = DS4Parser()
    _ = try parser.parse(data: makeDS4Report())

    let events = try parser.parse(
      data: makeDS4Report(leftStickX: 123, leftStickY: 126, rightStickX: 126, rightStickY: 130)
    )

    #expect(events.contains(.leftStickChanged(x: 0, y: 0)))
    #expect(events.contains(.rightStickChanged(x: 0, y: 0)))
  }

  @Test("Observed DS4 left-stick X drift is normalized to idle")
  func observedDS4LeftStickXDriftIsNormalizedToIdle() throws {
    let parser = DS4Parser()
    _ = try parser.parse(data: makeDS4Report())

    let events = try parser.parse(data: makeDS4Report(leftStickX: 120))

    #expect(events.contains(.leftStickChanged(x: 0, y: 0)))
  }

  @Test("DS4 stick reports raw HID normalized range")
  func ds4StickReportsRawHIDNormalizedRange() throws {
    let parser = DS4Parser()
    _ = try parser.parse(data: makeDS4Report())

    let events = try parser.parse(
      data: makeDS4Report(leftStickX: 254, leftStickY: 2, rightStickX: 2, rightStickY: 254)
    )

    #expect(events.contains(.leftStickChanged(x: 126.0 / 128.0, y: 126.0 / 128.0)))
    #expect(events.contains(.rightStickChanged(x: -126.0 / 128.0, y: -126.0 / 128.0)))
  }

  @Test("Observed DS4 right-stick Y shortfall remains visible")
  func observedDS4RightStickYShortfallRemainsVisible() throws {
    let parser = DS4Parser()
    _ = try parser.parse(data: makeDS4Report())

    let events = try parser.parse(data: makeDS4Report(rightStickY: 8))

    #expect(events.contains(.rightStickChanged(x: 0, y: 120.0 / 128.0)))
  }

  @Test("Device input state exposes DS4 D-pad as held buttons")
  func deviceInputStateExposesDS4DpadAsHeldButtons() async throws {
    let dispatcher = CapturingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 1356, productID: 2508),
      transport: .hid(locationID: 1),
      parser: DS4Parser(),
      dispatcher: dispatcher,
      usbContext: nil
    )
    await pipeline.start()
    await pipeline.feedHIDData(makeDS4Report())

    await pipeline.feedHIDData(makeDS4Report(buttons0: 0x00))
    #expect(pipeline.inputState().pressedButtons == [Button.dpadUp.rawValue])

    await pipeline.feedHIDData(makeDS4Report(buttons0: 0x03))
    #expect(Set(pipeline.inputState().pressedButtons) == Set([
      Button.dpadRight.rawValue,
      Button.dpadDown.rawValue,
    ]))

    await pipeline.feedHIDData(makeDS4Report())
    #expect(pipeline.inputState().pressedButtons.isEmpty)
  }

  @Test("Registry maps connected DS4 v2 USB identity to DS4 parser")
  func registryMapsDS4V2IdentityToDS4Parser() {
    let registry = ParserRegistry()
    let identifier = DeviceIdentifier(vendorID: 1356, productID: 2508)
    let profile = registry.runtimeProfile(for: identifier)

    #expect(registry.parserName(for: identifier) == "DS4")
    #expect(profile.protocolVariant == .dualShock4)
  }
}

private final class CapturingOutputDispatcher: OutputDispatcher, @unchecked Sendable {
  var suppressOutput = false

  // swiftlint:disable:next async_without_await
  func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {}
}
