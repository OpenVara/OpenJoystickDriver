// Sources/OpenJoystickDriverKit/Protocol/InputParser.swift
import Foundation
import SwiftUSB

/// Parser that converts raw USB/HID data into ControllerEvents.
/// Each protocol (GIP, DS4, GenericHID) provides its own implementation.
public protocol InputParser: AnyObject, Sendable {
  /// Perform any required protocol handshake before input reports will flow.
  /// GIP requires sending power-on packet; DS4 and GenericHID are no-ops.
  /// - Parameter handle: USB device handle for GIP devices. Nil for HID devices.
  func performHandshake(handle: USBDeviceHandle?) async throws

  /// Parse raw data into list of controller events.
  /// Called once per received USB interrupt or HID input report.
  func parse(data: Data) throws -> [ControllerEvent]
}
