import Testing

@testable import SwiftUSB

@Suite struct USBErrorTests {

  @Test("USBError initializes with negative code") func errorInitWithCode() {
    let error = USBError(code: -3, log: false)
    #expect(error.code == -3)
    #expect(!error.message.isEmpty)
  }

  @Test("USBError.check throws for negative result") func checkThrowsForNegative() {
    #expect(throws: USBError.self) { try USBError.check(-1) }
  }

  @Test("USBError.check does not throw for zero") func checkSucceedsForZero() throws {
    try USBError.check(0)
  }

  @Test("USBError isTimeout returns true for timeout code") func isTimeoutProperty() {
    let error = USBError(code: USBError.errorTimeout, log: false)
    #expect(error.isTimeout)
    #expect(!error.isNoDevice)
  }

  @Test("USBError isNoDevice returns true for no-device code") func isNoDeviceProperty() {
    let error = USBError(code: USBError.errorNoDevice, log: false)
    #expect(error.isNoDevice)
    #expect(!error.isTimeout)
  }

  @Test("USBError equality compares code, message, and context") func errorEquality() {
    let error1 = USBError(code: -3, log: false)
    let error2 = USBError(code: -3, log: false)
    let error3 = USBError(code: -1, log: false)
    #expect(error1 == error2)
    #expect(error1 != error3)
  }

  @Test("USBError description includes code") func errorDescription() {
    let error = USBError(code: -3, log: false)
    #expect(error.description.contains("-3"))
  }

  @Test("USBError boolean properties match their error codes") func booleanProperties() {
    #expect(USBError(code: USBError.errorAccess, log: false).isAccessDenied)
    #expect(USBError(code: USBError.errorBusy, log: false).isBusy)
    #expect(USBError(code: USBError.errorIO, log: false).isIOError)
    #expect(USBError(code: USBError.errorOverflow, log: false).isOverflow)
    #expect(USBError(code: USBError.errorPipe, log: false).isPipeError)
    #expect(USBError(code: USBError.errorInterrupted, log: false).isInterrupted)
    #expect(USBError(code: USBError.errorNoMem, log: false).isNoMemory)
    #expect(USBError(code: USBError.errorNotSupported, log: false).isNotSupported)
    #expect(USBError(code: USBError.errorInvalidParam, log: false).isInvalidParam)
    #expect(USBError(code: USBError.errorNotFound, log: false).isNotFound)
  }

  @Test("USBError.checkSuccess throws for non-zero results") func checkSuccessThrows() {
    #expect(throws: USBError.self) { try USBError.checkSuccess(-1, context: "test") }
  }

  @Test("USBError.checkSuccess passes for zero") func checkSuccessPasses() throws {
    try USBError.checkSuccess(0)
  }

  @Test("USBError with context includes context in description") func errorWithContext() {
    let error = USBError(code: -1, context: "test context", log: false)
    #expect(error.context == "test context")
    #expect(error.description.contains("test context"))
  }

  @Test("USBTimeoutError wraps USBError correctly") func timeoutError() {
    let timeout = USBTimeoutError()
    #expect(timeout.underlyingError.isTimeout)
  }
}
