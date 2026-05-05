import Foundation

/// Named GIP startup packets used by Xbox One-class controllers.
public enum GIPStartupPacket: String, CaseIterable, Sendable {
  case powerOn
  case xboxOneSInit
  case extraInput
  case horiAck
  case ledOn
  case authDone
  case rumbleBegin
  case rumbleEnd

  public static let defaultSequence: [Self] = [.powerOn, .ledOn, .authDone]

  public var command: UInt8 {
    switch self {
    case .powerOn, .xboxOneSInit: GIPCommand.power
    case .extraInput: 0x4D
    case .horiAck: 0x01
    case .ledOn: GIPCommand.led
    case .authDone: 0x06
    case .rumbleBegin, .rumbleEnd: GIPCommand.rumble
    }
  }

  public func packet(sequence: UInt8) -> [UInt8] {
    switch self {
    case .powerOn:
      [GIPCommand.power, GIPOption.internal, sequence, 1, 0]
    case .xboxOneSInit:
      [GIPCommand.power, GIPOption.internal, sequence, 15, 6]
    case .extraInput:
      [0x4D, 0x10, sequence, 2, GIPCommand.virtualKey, 0]
    case .horiAck:
      [1, GIPOption.internal, sequence, 9, 0, 4, GIPOption.internal, 58, 0, 0, 0, 128, 0]
    case .ledOn:
      [GIPCommand.led, GIPOption.internal, sequence, 3, 0, 1, 20]
    case .authDone:
      [6, GIPOption.internal, sequence, 2, 1, 0]
    case .rumbleBegin:
      [GIPCommand.rumble, 0, sequence, 9, 0, 15, 0, 0, 29, 29, 255, 0, 0]
    case .rumbleEnd:
      [GIPCommand.rumble, 0, sequence, 9, 0, 15, 0, 0, 0, 0, 0, 0, 0]
    }
  }
}
