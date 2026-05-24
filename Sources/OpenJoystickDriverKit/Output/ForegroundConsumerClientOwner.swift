import Foundation

/// Helpers for interpreting HID client-owner metadata exposed through IORegistry.
public enum ForegroundConsumerClientOwner {
  /// Extracts a process ID from an `IOUserClientCreator` property payload.
  ///
  /// Recent macOS builds commonly expose this as a string such as
  /// `"pid 30617, Google Chrome"`, while other call sites may surface an
  /// integer-backed NSNumber/Int.
  public static func pid(from value: Any?) -> Int? {
    switch value {
    case let number as NSNumber:
      return number.intValue > 0 ? number.intValue : nil
    case let integer as Int:
      return integer > 0 ? integer : nil
    case let string as String:
      return pid(from: string)
    default:
      return nil
    }
  }

  public static func pid(from creatorString: String) -> Int? {
    let trimmed = creatorString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("pid ") else { return nil }
    let digits = trimmed.dropFirst(4).prefix { $0.isNumber }
    guard let pid = Int(digits), pid > 0 else { return nil }
    return pid
  }
}
