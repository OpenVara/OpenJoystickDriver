import Foundation
import XCTest

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

private func makeDS4BluetoothReport(
  includesHIDTransaction: Bool = false,
  includesReportID: Bool = true,
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
  var report: [UInt8] = []
  if includesHIDTransaction { report.append(0xA1) }
  if includesReportID { report.append(0x11) }
  report.append(contentsOf: [0xC0, 0x00])
  report.append(contentsOf: [
    leftStickX, leftStickY, rightStickX, rightStickY, buttons0, buttons1, buttons2, leftTrigger,
    rightTrigger,
  ])
  report.append(contentsOf: [UInt8](repeating: 0, count: 64))
  report.append(contentsOf: [0x7D, 0x0A, 0x5D, 0x0B])
  return Data(report)
}

private func containsEvent(_ events: [ControllerEvent], _ expected: ControllerEvent) -> Bool {
  events.contains(expected)
}

final class DS4ParserTests: XCTestCase {
  func testWiredIOHIDReportWithoutReportIDParsesFaceButtons() throws {
    let parser = DS4Parser()
    _ = try parser.parse(data: makeDS4Report())

    let events = try parser.parse(data: makeDS4Report(buttons0: 0x28))

    XCTAssertTrue(containsEvent(events, .buttonPressed(.cross)))
  }
  func testRawUSBReportWithReportIDParsesFaceButtons() throws {
    let parser = DS4Parser()
    _ = try parser.parse(data: makeDS4Report(includesReportID: true))

    let events = try parser.parse(
      data: makeDS4Report(includesReportID: true, buttons0: 0x28)
    )

    XCTAssertTrue(containsEvent(events, .buttonPressed(.cross)))
  }
  func testBluetoothReport11ParsesFaceButtons() throws {
    let parser = DS4Parser()
    _ = try parser.parse(data: makeDS4BluetoothReport())

    let events = try parser.parse(data: makeDS4BluetoothReport(buttons0: 0x28))

    XCTAssertTrue(containsEvent(events, .buttonPressed(.cross)))
  }
  func testBluetoothHIDTransactionReportParsesSticksTriggersAndSystemButtons() throws {
    let parser = DS4Parser()
    _ = try parser.parse(data: makeDS4BluetoothReport(includesHIDTransaction: true))

    let events = try parser.parse(
      data: makeDS4BluetoothReport(
        includesHIDTransaction: true,
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

    XCTAssertTrue(containsEvent(events, .leftStickChanged(x: 127.0 / 128.0, y: 1.0)))
    XCTAssertTrue(containsEvent(events, .rightStickChanged(x: -1.0, y: -127.0 / 128.0)))
    XCTAssertTrue(containsEvent(events, .leftTriggerChanged(1.0)))
    XCTAssertTrue(containsEvent(events, .rightTriggerChanged(128.0 / 255.0)))
    XCTAssertTrue(containsEvent(events, .buttonPressed(.share)))
    XCTAssertTrue(containsEvent(events, .buttonPressed(.options)))
    XCTAssertTrue(containsEvent(events, .buttonPressed(.ps)))
    XCTAssertTrue(containsEvent(events, .buttonPressed(.touchpad)))
  }
  func testBluetoothPayloadWithoutReportIDParsesDpad() throws {
    let parser = DS4Parser()
    _ = try parser.parse(data: makeDS4BluetoothReport(includesReportID: false))

    let events = try parser.parse(
      data: makeDS4BluetoothReport(includesReportID: false, buttons0: 0x02)
    )

    XCTAssertTrue(containsEvent(events, .dpadChanged(.east)))
  }
  func testBluetoothShortReportWithHIDTransactionParsesFaceButtons() throws {
    let parser = DS4Parser(prefersBluetooth: true)
    _ = try parser.parse(data: Data([0xA1] + Array(makeDS4Report(includesReportID: true))))

    let events = try parser.parse(
      data: Data([0xA1] + Array(makeDS4Report(includesReportID: true, buttons0: 0x28)))
    )

    XCTAssertTrue(containsEvent(events, .buttonPressed(.cross)))
  }
  func testObservedMacOSBluetoothReport11ParsesStickState() throws {
    let parser = DS4Parser(prefersBluetooth: true)
    let observedPrefix: [UInt8] = [
      0x11, 0xC0, 0x00, 0x7A, 0x81, 0x81, 0x82, 0x08, 0x00, 0xCC, 0x00, 0x00,
      0xF5, 0xD1, 0x0C, 0xF6, 0xFF, 0x0B, 0x00, 0xF3, 0xFF, 0x78, 0x00, 0x8E,
    ]
    let observedReport = Data(observedPrefix + [UInt8](repeating: 0, count: 54))

    let events = try parser.parse(data: observedReport)

    XCTAssertTrue(containsEvent(events, .leftStickChanged(x: 0, y: 0)))
    XCTAssertTrue(containsEvent(events, .rightStickChanged(x: 0, y: 0)))
    XCTAssertTrue(containsEvent(events, .dpadChanged(.neutral)))
    XCTAssertTrue(!events.contains { event in
      if case .buttonPressed = event { return true }
      return false
    })
  }
  func testWiredIOHIDReportParsesSticksTriggersAndSystemButtons() throws {
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

    let expectedLeftStick = ControllerEvent.leftStickChanged(x: 127.0 / 128.0, y: 1.0)
    let expectedRightStick = ControllerEvent.rightStickChanged(x: -1.0, y: -127.0 / 128.0)
    let expectedLeftTrigger = ControllerEvent.leftTriggerChanged(1.0)
    let expectedRightTrigger = ControllerEvent.rightTriggerChanged(128.0 / 255.0)

    XCTAssertTrue(containsEvent(events, expectedLeftStick))
    XCTAssertTrue(containsEvent(events, expectedRightStick))
    XCTAssertTrue(containsEvent(events, expectedLeftTrigger))
    XCTAssertTrue(containsEvent(events, expectedRightTrigger))
    XCTAssertTrue(containsEvent(events, .buttonPressed(.share)))
    XCTAssertTrue(containsEvent(events, .buttonPressed(.options)))
    XCTAssertTrue(containsEvent(events, .buttonPressed(.ps)))
    XCTAssertTrue(containsEvent(events, .buttonPressed(.touchpad)))
  }
  func testWiredIOHIDReportParsesDpadDirections() throws {
    let parser = DS4Parser()
    _ = try parser.parse(data: makeDS4Report())

    let upEvents = try parser.parse(data: makeDS4Report(buttons0: 0x00))
    let rightEvents = try parser.parse(data: makeDS4Report(buttons0: 0x02))
    let downEvents = try parser.parse(data: makeDS4Report(buttons0: 0x04))
    let leftEvents = try parser.parse(data: makeDS4Report(buttons0: 0x06))

    XCTAssertTrue(containsEvent(upEvents, .dpadChanged(.north)))
    XCTAssertTrue(containsEvent(rightEvents, .dpadChanged(.east)))
    XCTAssertTrue(containsEvent(downEvents, .dpadChanged(.south)))
    XCTAssertTrue(containsEvent(leftEvents, .dpadChanged(.west)))
  }
  func testSmallDS4StickJitterIsNormalizedToIdle() throws {
    let parser = DS4Parser()
    _ = try parser.parse(data: makeDS4Report())

    let events = try parser.parse(
      data: makeDS4Report(leftStickX: 123, leftStickY: 126, rightStickX: 126, rightStickY: 130)
    )

    XCTAssertTrue(containsEvent(events, .leftStickChanged(x: 0, y: 0)))
    XCTAssertTrue(containsEvent(events, .rightStickChanged(x: 0, y: 0)))
  }
  func testObservedDS4LeftStickXDriftIsNormalizedToIdle() throws {
    let parser = DS4Parser()
    _ = try parser.parse(data: makeDS4Report())

    let events = try parser.parse(data: makeDS4Report(leftStickX: 120))

    XCTAssertTrue(containsEvent(events, .leftStickChanged(x: 0, y: 0)))
  }
  func testDs4StickReportsRawHIDNormalizedRange() throws {
    let parser = DS4Parser()
    _ = try parser.parse(data: makeDS4Report())

    let events = try parser.parse(
      data: makeDS4Report(leftStickX: 254, leftStickY: 2, rightStickX: 2, rightStickY: 254)
    )

    let expectedLeftStick = ControllerEvent.leftStickChanged(x: 126.0 / 128.0, y: 126.0 / 128.0)
    let expectedRightStick = ControllerEvent.rightStickChanged(x: -126.0 / 128.0, y: -126.0 / 128.0)

    XCTAssertTrue(containsEvent(events, expectedLeftStick))
    XCTAssertTrue(containsEvent(events, expectedRightStick))
  }
  func testObservedDS4RightStickYShortfallRemainsVisible() throws {
    let parser = DS4Parser()
    _ = try parser.parse(data: makeDS4Report())

    let events = try parser.parse(data: makeDS4Report(rightStickY: 8))
    let expectedRightStick = ControllerEvent.rightStickChanged(x: 0, y: 120.0 / 128.0)

    XCTAssertTrue(containsEvent(events, expectedRightStick))
  }
  func testDeviceInputStateExposesDS4DpadAsHeldButtons() async throws {
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
    XCTAssertTrue(pipeline.inputState().pressedButtons == [Button.dpadUp.rawValue])

    await pipeline.feedHIDData(makeDS4Report(buttons0: 0x03))
    XCTAssertTrue(Set(pipeline.inputState().pressedButtons) == Set([
      Button.dpadRight.rawValue,
      Button.dpadDown.rawValue,
    ]))

    await pipeline.feedHIDData(makeDS4Report())
    XCTAssertTrue(pipeline.inputState().pressedButtons.isEmpty)
  }
  func testRegistryMapsDS4V2IdentityToDS4Parser() {
    let registry = ParserRegistry()
    let identifier = DeviceIdentifier(vendorID: 1356, productID: 2508)
    let profile = registry.runtimeProfile(for: identifier)

    XCTAssertTrue(registry.parserName(for: identifier) == "DS4")
    XCTAssertTrue(profile.protocolVariant == .dualShock4)
  }
}

private final class CapturingOutputDispatcher: OutputDispatcher, @unchecked Sendable {
  var suppressOutput = false

  // swiftlint:disable:next async_without_await
  func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {}
}
