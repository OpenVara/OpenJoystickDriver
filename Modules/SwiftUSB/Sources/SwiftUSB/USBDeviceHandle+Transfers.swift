import CLibUSB
import Foundation

@usableFromInline let kDefaultTimeout: UInt32 = 5000
private let kIsoMaxPacketSize = 1024
private let kIsoDefaultReadLength = 2048

extension USBDeviceHandle {
  func bulkTransfer(endpoint: UInt8, data: Data, timeout: UInt32 = kDefaultTimeout) throws -> Int {
    try bulkWrite(on: handle, to: endpoint, data: data, timeout: timeout)
  }

  func readBulk(endpoint: UInt8, length: Int, timeout: UInt32 = kDefaultTimeout) throws -> Data {
    try bulkRead(on: handle, from: endpoint, length: length, timeout: timeout)
  }
}

extension USBDeviceHandle {
  /// Sends bytes to an OUT endpoint via an interrupt transfer.
  /// Returns the number of bytes actually transferred.
  public func interruptTransfer(endpoint: UInt8, data: [UInt8], timeout: UInt32 = kDefaultTimeout)
    throws -> Int
  {
    var transferred: Int32 = 0
    var buffer = data

    let result = buffer.withUnsafeMutableBufferPointer { ptr in
      libusb_interrupt_transfer(
        handle,
        endpoint,
        ptr.baseAddress,
        Int32(data.count),
        &transferred,
        timeout
      )
    }

    if result < 0 { try USBError.check(result) }

    return Int(transferred)
  }

  /// Reads up to `length` bytes from an IN endpoint via an interrupt transfer.
  /// Returns only the bytes actually received (may be fewer than `length`).
  public func readInterrupt(endpoint: UInt8, length: Int, timeout: UInt32 = kDefaultTimeout) throws
    -> [UInt8]
  {
    var buffer = [UInt8](repeating: 0, count: length)
    var transferred: Int32 = 0

    let result = buffer.withUnsafeMutableBufferPointer { ptr in
      libusb_interrupt_transfer(
        handle,
        endpoint,
        ptr.baseAddress,
        Int32(length),
        &transferred,
        timeout
      )
    }

    try USBError.check(result)
    return Array(buffer[0..<Int(transferred)])
  }
}

extension USBDeviceHandle {
  func isochronousTransfer(endpoint: UInt8, data: Data, timeout: UInt32 = kDefaultTimeout)
    async throws -> Int
  {
    try await withCheckedThrowingContinuation { continuation in
      guard
        let transfer = allocateIsoTransferBuffer(
          bufferSize: data.count,
          endpoint: endpoint,
          timeout: timeout,
          continuation: continuation
        )
      else { return }

      submitTransfer(transfer: transfer, endpoint: endpoint, continuation: continuation)
    }
  }

  func readIsochronous(endpoint: UInt8, length: Int, timeout: UInt32 = kDefaultTimeout) async throws
    -> Data
  {
    try await withCheckedThrowingContinuation { continuation in
      guard
        let transfer = createIsochronousReadTransfer(
          endpoint: endpoint,
          length: length,
          timeout: timeout,
          continuation: continuation
        )
      else { return }

      submitIsochronousReadTransfer(transfer: transfer, continuation: continuation)
    }
  }
}

extension USBDeviceHandle {
  private func allocateIsoTransferBuffer(
    bufferSize: Int,
    endpoint: UInt8,
    timeout: UInt32,
    continuation: CheckedContinuation<Int, Error>
  ) -> UnsafeMutablePointer<libusb_transfer>? {
    var buffer = [UInt8](repeating: 0, count: bufferSize)

    guard let transfer = libusb_alloc_transfer(0) else {
      continuation.resume(throwing: USBError(code: -1))
      return nil
    }

    let numPackets = (bufferSize + kIsoMaxPacketSize - 1) / kIsoMaxPacketSize

    let continuationHolder = IsoContinuationHolder<Int>()
    continuationHolder.continuation = continuation

    buffer.withUnsafeMutableBufferPointer { bufferPtr in
      libusb_fill_iso_transfer(
        transfer,
        handle,
        endpoint,
        bufferPtr.baseAddress,
        Int32(bufferSize),
        Int32(numPackets),
        { (transfer: UnsafeMutablePointer<libusb_transfer>?) in
          guard let transfer else { return }

          let status = transfer.pointee.status

          let holder =
            Unmanaged<IsoContinuationHolder<Int>>.fromOpaque(transfer.pointee.user_data)
            .takeRetainedValue() as IsoContinuationHolder<Int>

          switch status {
          case LIBUSB_TRANSFER_COMPLETED:
            let bytesTransferred = Int(transfer.pointee.actual_length)
            holder.continuation?.resume(returning: bytesTransferred)

          case LIBUSB_TRANSFER_ERROR: holder.continuation?.resume(throwing: USBError(code: -1))

          default: holder.continuation?.resume(throwing: USBError(code: -1))
          }

          libusb_free_transfer(transfer)
        },
        UnsafeMutableRawPointer(Unmanaged.passRetained(continuationHolder).toOpaque()),
        timeout
      )
    }

    transfer.pointee.num_iso_packets = Int32(numPackets)
    return transfer
  }

  private func submitTransfer(
    transfer: UnsafeMutablePointer<libusb_transfer>,
    endpoint: UInt8,
    continuation: CheckedContinuation<Int, Error>
  ) {
    let result = libusb_submit_transfer(transfer)

    if result < 0 {
      libusb_free_transfer(transfer)
      continuation.resume(throwing: USBError(code: result))
    }
  }

  private func createIsochronousReadTransfer(
    endpoint: UInt8,
    length: Int,
    timeout: UInt32,
    continuation: CheckedContinuation<Data, Error>
  ) -> UnsafeMutablePointer<libusb_transfer>? {
    var buffer = [UInt8](repeating: 0, count: length)

    guard let transfer = libusb_alloc_transfer(0) else {
      continuation.resume(throwing: USBError(code: -1))
      return nil
    }

    let numPackets = calculateIsoPacketCount(length: length)
    let continuationHolder = IsoContinuationHolder<Data>()
    continuationHolder.continuation = continuation

    buffer.withUnsafeMutableBufferPointer { bufferPtr in
      libusb_fill_iso_transfer(
        transfer,
        handle,
        endpoint,
        bufferPtr.baseAddress,
        Int32(length),
        Int32(numPackets),
        isoReadTransferCallback,
        UnsafeMutableRawPointer(Unmanaged.passRetained(continuationHolder).toOpaque()),
        timeout
      )
    }

    transfer.pointee.num_iso_packets = Int32(numPackets)
    return transfer
  }

  private func calculateIsoPacketCount(length: Int) -> Int {
    (length + kIsoMaxPacketSize - 1) / kIsoMaxPacketSize
  }

  private func submitIsochronousReadTransfer(
    transfer: UnsafeMutablePointer<libusb_transfer>,
    continuation: CheckedContinuation<Data, Error>
  ) {
    let result = libusb_submit_transfer(transfer)

    if result < 0 {
      libusb_free_transfer(transfer)
      continuation.resume(throwing: USBError(code: result))
    }
  }

  private func handleIsoReadCompletion(
    transfer: UnsafeMutablePointer<libusb_transfer>,
    holder: IsoContinuationHolder<Data>
  ) {
    let status = transfer.pointee.status
    let bytesTransferred = Int(transfer.pointee.actual_length)

    switch status {
    case LIBUSB_TRANSFER_COMPLETED:
      let bufferPtr = transfer.pointee.buffer
      var resultData = Data()
      if let bufferPtr, bytesTransferred > 0 {
        resultData = Data(bytes: bufferPtr, count: bytesTransferred)
      }
      holder.continuation?.resume(returning: resultData)

    case LIBUSB_TRANSFER_ERROR: holder.continuation?.resume(throwing: USBError(code: -1))

    case LIBUSB_TRANSFER_TIMED_OUT: holder.continuation?.resume(throwing: USBError(code: -110))

    case LIBUSB_TRANSFER_CANCELLED: holder.continuation?.resume(throwing: USBError(code: -1))

    case LIBUSB_TRANSFER_NO_DEVICE: holder.continuation?.resume(throwing: USBError(code: -1))

    case LIBUSB_TRANSFER_OVERFLOW: holder.continuation?.resume(throwing: USBError(code: -1))

    default: holder.continuation?.resume(throwing: USBError(code: -1))
    }

    libusb_free_transfer(transfer)
  }
}

private func isoReadTransferCallback(_ transfer: UnsafeMutablePointer<libusb_transfer>?) {
  guard let transfer else { return }

  let status = transfer.pointee.status
  let holder = Unmanaged<IsoContinuationHolder<Data>>.fromOpaque(transfer.pointee.user_data)
    .takeRetainedValue()

  handleIsoReadStatus(status: status, transfer: transfer, holder: holder)
  libusb_free_transfer(transfer)
}

private func handleIsoReadStatus(
  status: libusb_transfer_status,
  transfer: UnsafeMutablePointer<libusb_transfer>,
  holder: IsoContinuationHolder<Data>
) {
  let bytesTransferred = Int(transfer.pointee.actual_length)

  switch status {
  case LIBUSB_TRANSFER_COMPLETED:
    let bufferPtr = transfer.pointee.buffer
    var resultData = Data()
    if let bufferPtr, bytesTransferred > 0 {
      resultData = Data(bytes: bufferPtr, count: bytesTransferred)
    }
    holder.continuation?.resume(returning: resultData)

  case LIBUSB_TRANSFER_ERROR: holder.continuation?.resume(throwing: USBError(code: -1))

  case LIBUSB_TRANSFER_TIMED_OUT: holder.continuation?.resume(throwing: USBError(code: -110))

  case LIBUSB_TRANSFER_CANCELLED: holder.continuation?.resume(throwing: USBError(code: -1))

  case LIBUSB_TRANSFER_NO_DEVICE: holder.continuation?.resume(throwing: USBError(code: -1))

  case LIBUSB_TRANSFER_OVERFLOW: holder.continuation?.resume(throwing: USBError(code: -1))

  default: holder.continuation?.resume(throwing: USBError(code: -1))
  }
}

final class ContinuationHolder<T> { var continuation: CheckedContinuation<T, Error>? }

final class IsoContinuationHolder<T> { var continuation: CheckedContinuation<T, Error>? }
