import Foundation

/// All GIP command bytes identified from Windows driver decompilation.
public enum GIPCommand {
  static let announce: UInt8 = 0x01
  static let status: UInt8 = 0x02
  static let keepAlive: UInt8 = 0x03
  static let power: UInt8 = 0x05
  static let authenticate: UInt8 = 0x06
  static let virtualKey: UInt8 = 0x07
  static let rumble: UInt8 = 0x09
  static let led: UInt8 = 0x0A
  static let input: UInt8 = 0x20
}

/// GIP packet option flags.
public enum GIPOption { static let `internal`: UInt8 = 0x20 }

/// Device power states from the xboxgip.sys state machine.
public enum GIPDeviceState: UInt8, Sendable, CustomStringConvertible {
  case start = 0x00
  case stop = 0x01
  case standby = 0x02
  case fullPower = 0x03
  case off = 0x04
  case quiesce = 0x05
  case enroll = 0x06
  case reset = 0x07

  /// Returns a short uppercase label for the device state.
  public var description: String {
    switch self {
    case .start: "START"
    case .stop: "STOP"
    case .standby: "STANDBY"
    case .fullPower: "FULL_POWER"
    case .off: "OFF"
    case .quiesce: "QUIESCE"
    case .enroll: "ENROLL"
    case .reset: "RESET"
    }
  }
}

/// Auth sub-protocol states from devauthe.sys decompilation.
public enum GIPAuthState: UInt8, Sendable, CustomStringConvertible {
  // Device -> Host
  case devInit = 0x01
  case devCertificate = 0x02
  case devIntermediate = 0x03
  case devData1 = 0x04
  case devData2 = 0x05
  case devFinal = 0x06
  case devComplete = 0x07
  case devStatus = 0x08
  case devAck1 = 0x0B
  case devAck2 = 0x0C
  // Host -> Device
  case hostInit = 0x21
  case hostResponse1 = 0x22
  case hostResponse2 = 0x23
  case hostResponse3 = 0x24
  case hostResponse4 = 0x25
  case hostResponse5 = 0x26
  case hostComplete = 0x27

  /// Expected payload size for host->device messages. `nil` for device->host states.
  public var expectedPayloadSize: Int? {
    switch self {
    case .hostInit: 40
    case .hostResponse1: 176
    case .hostResponse2: 772
    case .hostResponse3: 132
    case .hostResponse4: 68
    case .hostResponse5: 36
    case .hostComplete: 68
    default: nil
    }
  }

  /// Whether this state represents a device-to-host message.
  public var isDeviceToHost: Bool { rawValue < 0x20 }

  /// Returns a short uppercase label for the auth state.
  public var description: String {
    switch self {
    case .devInit: "DEV_INIT"
    case .devCertificate: "DEV_CERTIFICATE"
    case .devIntermediate: "DEV_INTERMEDIATE"
    case .devData1: "DEV_DATA_1"
    case .devData2: "DEV_DATA_2"
    case .devFinal: "DEV_FINAL"
    case .devComplete: "DEV_COMPLETE"
    case .devStatus: "DEV_STATUS"
    case .devAck1: "DEV_ACK_1"
    case .devAck2: "DEV_ACK_2"
    case .hostInit: "HOST_INIT"
    case .hostResponse1: "HOST_RESPONSE_1"
    case .hostResponse2: "HOST_RESPONSE_2"
    case .hostResponse3: "HOST_RESPONSE_3"
    case .hostResponse4: "HOST_RESPONSE_4"
    case .hostResponse5: "HOST_RESPONSE_5"
    case .hostComplete: "HOST_COMPLETE"
    }
  }
}

/// Auth message direction markers.
public enum GIPAuthType {
  static let host: UInt8 = 0x41  // 'A'
  static let device: UInt8 = 0x42  // 'B'
  static let version: UInt8 = 0x01
}
