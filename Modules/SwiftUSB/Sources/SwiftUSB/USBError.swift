import CLibUSB
import Foundation

public struct USBError: Error, Sendable {
  public static let success: Int32 = 0
  public static let errorIO: Int32 = -1
  public static let errorInvalidParam: Int32 = -2
  public static let errorAccess: Int32 = -3
  public static let errorNoDevice: Int32 = -4
  public static let errorNotFound: Int32 = -5
  public static let errorBusy: Int32 = -6
  public static let errorTimeout: Int32 = -7
  public static let errorOverflow: Int32 = -8
  public static let errorPipe: Int32 = -9
  public static let errorInterrupted: Int32 = -10
  public static let errorNoMem: Int32 = -11
  public static let errorNotSupported: Int32 = -12
  public static let errorOther: Int32 = -99

  public let code: Int32
  public let message: String
  public let context: String?

  public var isSuccess: Bool { code == Self.success }
  public var isTimeout: Bool { code == Self.errorTimeout }
  public var isNoDevice: Bool { code == Self.errorNoDevice }
  public var isNotFound: Bool { code == Self.errorNotFound }
  public var isAccessDenied: Bool { code == Self.errorAccess }
  public var isBusy: Bool { code == Self.errorBusy }
  public var isInvalidParam: Bool { code == Self.errorInvalidParam }
  public var isIOError: Bool { code == Self.errorIO }
  public var isOverflow: Bool { code == Self.errorOverflow }
  public var isPipeError: Bool { code == Self.errorPipe }
  public var isInterrupted: Bool { code == Self.errorInterrupted }
  public var isNoMemory: Bool { code == Self.errorNoMem }
  public var isNotSupported: Bool { code == Self.errorNotSupported }

  public init(code: Int32, log: Bool = true) {
    self.code = code
    self.context = nil
    self.message = Self.humanReadableMessage(for: code)
    if log && !Self.isExpectedError(code) {
      Self.logError(code: code, message: self.message, context: nil)
    }
  }

  public init(code: Int32, context: String, log: Bool = true) {
    self.code = code
    self.context = context
    self.message = Self.humanReadableMessage(for: code)
    if log && !Self.isExpectedError(code) {
      Self.logError(code: code, message: self.message, context: context)
    }
  }

  public init(message: String) {
    self.code = Self.errorOther
    self.context = nil
    self.message = message
    Self.logError(code: self.code, message: message, context: nil)
  }

  private static func isExpectedError(_ code: Int32) -> Bool {
    code == errorTimeout || code == errorNotFound || code == errorNoDevice
  }

  private static func humanReadableMessage(for code: Int32) -> String {
    if let message = try? libusbStrerror(code) { return message }
    return customMessage(for: code)
  }

  private static func customMessage(for code: Int32) -> String {
    switch code {
    case success: return "Success"
    case errorIO: return "Input/output error"
    case errorInvalidParam: return "Invalid parameter"
    case errorAccess: return "Access denied (insufficient permissions)"
    case errorNoDevice: return "No such device (device disconnected)"
    case errorNotFound: return "Entity not found"
    case errorBusy: return "Resource busy"
    case errorTimeout: return "Operation timed out"
    case errorOverflow: return "Overflow"
    case errorPipe: return "Pipe error"
    case errorInterrupted: return "System call interrupted"
    case errorNoMem: return "Out of memory"
    case errorNotSupported: return "Operation not supported"
    case errorOther: return "Unknown error"
    default: return "Unknown libusb error: \(code)"
    }
  }

  private static func libusbStrerror(_ code: Int32) throws -> String? {
    String(cString: libusb_error_name(code))
  }

  private static func logError(code: Int32, message: String, context: String?) {
    if let context {
      debugPrint("[SwiftUSB] \(message) (code: \(code), context: \(context))")
    } else {
      debugPrint("[SwiftUSB] \(message) (code: \(code))")
    }
  }

  public static func check(_ result: Int32) throws { if result < 0 { throw Self(code: result) } }

  @discardableResult public static func check(_ result: Int32, context: String) throws -> Int32 {
    if result < 0 { throw Self(code: result, context: context) }
    return result
  }

  public static func checkSuccess(_ result: Int32, context: String = "") throws {
    if result != success {
      guard context.isEmpty else { throw Self(code: result, context: context) }
      throw Self(code: result)
    }
  }
}

public struct USBTimeoutError: Error, Sendable {
  public let underlyingError: USBError

  public init(underlyingError: USBError) { self.underlyingError = underlyingError }

  public init() { self.underlyingError = USBError(code: USBError.errorTimeout) }
}

extension USBError: CustomStringConvertible {
  public var description: String {
    if let context {
      return "USBError(code: \(code), message: \"\(message)\", context: \"\(context)\")"
    }
    return "USBError(code: \(code), message: \"\(message)\")"
  }
}

extension USBError: Equatable {
  public static func == (lhs: USBError, rhs: USBError) -> Bool {
    lhs.code == rhs.code && lhs.message == rhs.message && lhs.context == rhs.context
  }
}

extension USBError {
  var isTimeoutError: Bool { isTimeout }

  func asTimeoutError() -> USBTimeoutError? {
    guard isTimeout else { return nil }
    return USBTimeoutError(underlyingError: self)
  }
}
