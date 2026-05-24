import Foundation
import SwiftUSB
import Testing

@testable import OpenJoystickDriverKit

struct DevicePipelineSleepTests {
  @Test
  func testSleepingPipelineKeepsPhysicalInputStateButStopsVirtualDispatch() async {
    let dispatcher = RecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 100, productID: 200),
      transport: .hid(locationID: 1),
      parser: ScriptedInputParser(),
      dispatcher: dispatcher,
      usbContext: nil,
      idleTimeoutNanoseconds: 5_000_000,
      idleMonitorIntervalNanoseconds: 10_000_000
    )

    await pipeline.start()
    await pipeline.feedHIDData(Data([1]))
    await pipeline.feedHIDData(Data([2]))

    try? await Task.sleep(nanoseconds: 80_000_000)

    let dispatchCountBeforeSleepInput = dispatcher.dispatchCount
    await pipeline.feedHIDData(Data([3]))

    #expect(dispatcher.dispatchCount == dispatchCountBeforeSleepInput)
    #expect(abs(pipeline.inputState().leftStickX - 0.8) < 0.001)
  }

  @Test

  func testForegroundGateNeutralizesOutputAndWaitsForNeutralBeforeResuming() async {
    let dispatcher = RecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 100, productID: 200),
      transport: .hid(locationID: 1),
      parser: ScriptedInputParser(),
      dispatcher: dispatcher,
      usbContext: nil,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )

    await pipeline.start()
    await pipeline.feedHIDData(Data([1]))
    #expect(dispatcher.flattenedEvents == [.buttonPressed(.a)])

    await pipeline.setExternalOutputAllowed(false)
    #expect(dispatcher.flattenedEvents == [.buttonPressed(.a), .buttonReleased(.a)])

    await pipeline.setExternalOutputAllowed(true)
    await pipeline.feedHIDData(Data([2]))
    #expect(dispatcher.flattenedEvents == [.buttonPressed(.a), .buttonReleased(.a)])

    await pipeline.feedHIDData(Data([4]))
    #expect(dispatcher.flattenedEvents == [.buttonPressed(.a), .buttonReleased(.a), .buttonPressed(.b)])
  }

  @Test
  func testForegroundGateRearmsAfterFirstPostFocusChangeWithoutFullNeutral() async {
    let dispatcher = RecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 100, productID: 200),
      transport: .hid(locationID: 1),
      parser: ScriptedInputParser(),
      dispatcher: dispatcher,
      usbContext: nil,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )

    await pipeline.start()
    await pipeline.feedHIDData(Data([3]))
    #expect(dispatcher.flattenedEvents == [.leftStickChanged(x: 0.8, y: 0)])

    await pipeline.setExternalOutputAllowed(false)
    #expect(dispatcher.flattenedEvents == [.leftStickChanged(x: 0.8, y: 0), .leftStickChanged(x: 0, y: 0)])

    await pipeline.setExternalOutputAllowed(true)
    await pipeline.feedHIDData(Data([5]))
    #expect(
      dispatcher.flattenedEvents
        == [.leftStickChanged(x: 0.8, y: 0), .leftStickChanged(x: 0, y: 0)]
    )

    await pipeline.feedHIDData(Data([4]))
    #expect(
      dispatcher.flattenedEvents
        == [.leftStickChanged(x: 0.8, y: 0), .leftStickChanged(x: 0, y: 0), .buttonPressed(.b)]
    )
  }

  func testRepeatedAllowedSignalDoesNotRearmForegroundGate() async {
    let dispatcher = RecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 100, productID: 200),
      transport: .hid(locationID: 1),
      parser: ScriptedInputParser(),
      dispatcher: dispatcher,
      usbContext: nil,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )

    await pipeline.start()
    await pipeline.setExternalOutputAllowed(true)
    await pipeline.feedHIDData(Data([4]))

    #expect(dispatcher.flattenedEvents == [.buttonPressed(.b)])
  }
}

private final class ScriptedInputParser: InputParser, @unchecked Sendable {
  func performHandshake(handle: USBDeviceHandle?) async throws {}

  func parse(data: Data) throws -> [ControllerEvent] {
    switch data.first {
    case 1:
      return [.buttonPressed(.a)]
    case 2:
      return [.buttonReleased(.a)]
    case 3:
      return [.leftStickChanged(x: 0.8, y: 0)]
    case 4:
      return [.buttonPressed(.b)]
    case 5:
      return [.leftStickChanged(x: 0.6, y: 0)]
    default:
      return []
    }
  }
}

private final class RecordingOutputDispatcher: OutputDispatcher, @unchecked Sendable {
  var suppressOutput = false

  private let lock = NSLock()
  private var batches: [[ControllerEvent]] = []

  var dispatchCount: Int {
    lock.withLock { batches.count }
  }

  var flattenedEvents: [ControllerEvent] {
    lock.withLock { batches.flatMap { $0 } }
  }

  func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {
    lock.withLock {
      batches.append(events)
    }
  }
}
