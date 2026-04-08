import Foundation
import IOKit
import IOKit.hid

/// Builds input reports according to a HID report descriptor (subset parser).
///
/// This is used for Compatibility identities where consumers switch behavior based on VID/PID
/// (often SDL-based). In those cases, spoofing VID/PID alone is not enough: the descriptor and
/// report bytes must match what the consumer expects.
public struct HIDDescriptorReportFormat: VirtualGamepadReportFormat, @unchecked Sendable {
  public let descriptor: [UInt8]
  public let inputReportPayloadSize: Int
  public let inputReportID: UInt8?

  private let packer: HIDReportPacker

  public enum Error: Swift.Error, CustomStringConvertible, Sendable {
    case noSuitableInputReport
    case cannotParseDescriptor

    public var description: String {
      switch self {
      case .noSuitableInputReport:
        return "Descriptor does not contain a usable GamePad-style input report (buttons/axes/hat)."
      case .cannotParseDescriptor:
        return "Failed to parse HID report descriptor."
      }
    }
  }

  public init(descriptor: [UInt8]) throws {
    self.descriptor = descriptor
    guard let parsed = HIDReportDescriptorParser.parse(descriptor: descriptor) else {
      throw Error.cannotParseDescriptor
    }
    guard let packer = HIDReportPacker.bestEffortGamepadPacker(from: parsed) else {
      throw Error.noSuitableInputReport
    }
    self.packer = packer
    self.inputReportID = packer.reportID == 0 ? nil : packer.reportID
    self.inputReportPayloadSize = packer.payloadSizeBytes
  }

  public func buildInputReport(from state: VirtualGamepadState) -> [UInt8] {
    packer.pack(state: state)
  }

  // MARK: - Descriptor sourcing helpers

  /// Copies the HID report descriptor from a currently connected physical HID device.
  ///
  /// This avoids hardcoding descriptor bytes in the repo and lets developers confirm
  /// the exact descriptor used by their controller on their macOS build.
  public static func copyPhysicalReportDescriptor(vendorID: Int, productID: Int) -> [UInt8]? {
    copyPhysicalReportDescriptor(vendorID: vendorID, productID: productID, preferredTransport: nil)
  }

  /// Copies the HID report descriptor from a currently connected physical HID device,
  /// optionally preferring a specific transport ("USB", "Bluetooth", ...).
  ///
  /// This function explicitly filters out OpenJoystickDriver-created virtual devices.
  public static func copyPhysicalReportDescriptor(
    vendorID: Int,
    productID: Int,
    preferredTransport: String?
  ) -> [UInt8]? {
    let matching: [String: Any] = [
      kIOHIDVendorIDKey as String: vendorID,
      kIOHIDProductIDKey as String: productID,
    ]
    let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(mgr, matching as CFDictionary)
    _ = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
    defer {
      IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    let devices = (IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>) ?? []

    func strProp(_ dev: IOHIDDevice, _ key: String) -> String? {
      IOHIDDeviceGetProperty(dev, key as CFString) as? String
    }

    func score(_ dev: IOHIDDevice) -> Int {
      let transport = strProp(dev, kIOHIDTransportKey as String)
      let ioUserClass = strProp(dev, "IOUserClass")
      let serial = strProp(dev, kIOHIDSerialNumberKey as String) ?? strProp(dev, "SerialNumber")

      // Exclude OJD virtual devices.
      if ioUserClass == "OpenJoystickVirtualHIDDevice" { return Int.min / 2 }
      if ioUserClass == "IOHIDUserDevice" { return Int.min / 2 }
      if UserSpaceVirtualDeviceConstants.isOJDUserSpaceSerial(serial) { return Int.min / 2 }
      if serial == VirtualDeviceIdentityConstants.driverKitSerialNumber { return Int.min / 2 }

      var s = 0
      if let preferredTransport, let transport, transport == preferredTransport { s += 10_000 }
      if let transport, transport != "Virtual" { s += 1_000 }
      if transport == "USB" { s += 100 }
      return s
    }

    let candidates = devices
      .map { ($0, score($0)) }
      .sorted { a, b in a.1 > b.1 }

    for (dev, s) in candidates {
      if s <= Int.min / 4 { continue }
      if let data = IOHIDDeviceGetProperty(dev, kIOHIDReportDescriptorKey as CFString) as? Data {
        return [UInt8](data)
      }
    }
    return nil
  }
}

// MARK: - HID report descriptor parsing (subset)

private enum HIDItemType: UInt8 {
  case main = 0
  case global = 1
  case local = 2
  case reserved = 3
}

private enum HIDGlobalTag: UInt8 {
  case usagePage = 0x0
  case logicalMinimum = 0x1
  case logicalMaximum = 0x2
  case reportSize = 0x7
  case reportID = 0x8
  case reportCount = 0x9
}

private enum HIDLocalTag: UInt8 {
  case usage = 0x0
  case usageMinimum = 0x1
  case usageMaximum = 0x2
}

private enum HIDMainTag: UInt8 {
  case input = 0x8
  case collection = 0xA
  case endCollection = 0xC
}

private struct HIDInputFlags: Sendable {
  let isConstant: Bool
  let hasNullState: Bool

  init(_ raw: Int) {
    // HID Input flags are bitfields; we care only about:
    // - Constant (bit 0: 1 = Constant)
    // - Null State (bit 6: 1 = Null state)
    self.isConstant = (raw & 0x01) != 0
    self.hasNullState = (raw & 0x40) != 0
  }
}

private struct HIDField: Sendable {
  let reportID: UInt8
  let bitOffset: Int
  let bitSize: Int
  let usagePage: Int
  let usage: Int
  let logicalMin: Int
  let logicalMax: Int
  let flags: HIDInputFlags
}

private struct HIDParsedDescriptor: Sendable {
  /// All variable input fields across all report IDs.
  let fields: [HIDField]
  /// Payload size (excluding report ID byte) for each report ID.
  let payloadSizeBytesByReportID: [UInt8: Int]
}

private enum HIDReportDescriptorParser {
  static func parse(descriptor: [UInt8]) -> HIDParsedDescriptor? {
    var i = 0

    var usagePage: Int = 0
    var logicalMin: Int = 0
    var logicalMax: Int = 0
    var reportSize: Int = 0
    var reportCount: Int = 0
    var reportID: UInt8 = 0

    var localUsages: [Int] = []
    var usageMin: Int?
    var usageMax: Int?

    var bitOffsetByReportID: [UInt8: Int] = [:]
    var fields: [HIDField] = []

    func readSigned(_ bytes: [UInt8]) -> Int {
      switch bytes.count {
      case 0: return 0
      case 1: return Int(Int8(bitPattern: bytes[0]))
      case 2:
        let v = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
        return Int(Int16(bitPattern: v))
      case 4:
        let v = UInt32(bytes[0])
          | (UInt32(bytes[1]) << 8)
          | (UInt32(bytes[2]) << 16)
          | (UInt32(bytes[3]) << 24)
        return Int(Int32(bitPattern: v))
      default:
        return 0
      }
    }

    func readUnsigned(_ bytes: [UInt8]) -> Int {
      var v = 0
      for (idx, b) in bytes.enumerated() { v |= Int(b) << (8 * idx) }
      return v
    }

    func currentBitOffset() -> Int { bitOffsetByReportID[reportID] ?? 0 }
    func advanceBits(_ bits: Int) { bitOffsetByReportID[reportID] = currentBitOffset() + bits }

    while i < descriptor.count {
      let prefix = descriptor[i]
      i += 1

      if prefix == 0xFE {
        // Long item: [0xFE][size][tag][data...]
        guard i + 2 <= descriptor.count else { return nil }
        let size = Int(descriptor[i])
        i += 2  // skip size + tag
        i += size
        continue
      }

      let sizeCode = prefix & 0x03
      let dataSize: Int = (sizeCode == 0x03) ? 4 : Int(sizeCode)
      let type = HIDItemType(rawValue: (prefix >> 2) & 0x03) ?? .reserved
      let tag = (prefix >> 4) & 0x0F

      guard i + dataSize <= descriptor.count else { return nil }
      let data = Array(descriptor[i..<(i + dataSize)])
      i += dataSize

      switch type {
      case .global:
        guard let g = HIDGlobalTag(rawValue: tag) else { break }
        switch g {
        case .usagePage: usagePage = readUnsigned(data)
        case .logicalMinimum: logicalMin = readSigned(data)
        case .logicalMaximum: logicalMax = readSigned(data)
        case .reportSize: reportSize = readUnsigned(data)
        case .reportCount: reportCount = readUnsigned(data)
        case .reportID:
          reportID = UInt8(clamping: readUnsigned(data))
          if bitOffsetByReportID[reportID] == nil { bitOffsetByReportID[reportID] = 0 }
        }
      case .local:
        guard let l = HIDLocalTag(rawValue: tag) else { break }
        switch l {
        case .usage: localUsages.append(readUnsigned(data))
        case .usageMinimum: usageMin = readUnsigned(data)
        case .usageMaximum: usageMax = readUnsigned(data)
        }
      case .main:
        guard let m = HIDMainTag(rawValue: tag) else { break }
        switch m {
        case .input:
          let flags = HIDInputFlags(readUnsigned(data))
          let bitsTotal = reportSize * reportCount
          defer {
            // Main items consume the local state.
            localUsages.removeAll(keepingCapacity: true)
            usageMin = nil
            usageMax = nil
            advanceBits(bitsTotal)
          }
          if flags.isConstant { continue }
          guard reportSize > 0, reportCount > 0 else { continue }

          // Determine usage list for this Input item.
          var usages: [Int] = []
          if !localUsages.isEmpty {
            usages = localUsages
          } else if let min = usageMin, let max = usageMax, max >= min {
            usages = Array(min...max)
          }

          // Expand/trim to reportCount.
          if usages.count < reportCount {
            if let last = usages.last {
              usages += Array(repeating: last, count: reportCount - usages.count)
            } else {
              usages = Array(repeating: 0, count: reportCount)
            }
          } else if usages.count > reportCount {
            usages = Array(usages.prefix(reportCount))
          }

          let base = currentBitOffset()
          for idx in 0..<reportCount {
            fields.append(
              HIDField(
                reportID: reportID,
                bitOffset: base + (idx * reportSize),
                bitSize: reportSize,
                usagePage: usagePage,
                usage: usages[idx],
                logicalMin: logicalMin,
                logicalMax: logicalMax,
                flags: flags
              )
            )
          }
        case .collection, .endCollection:
          // Ignore.
          // Local state is consumed only by main items that take it (Input/Output/Feature),
          // but leaving it around across collections is harmless for our subset parser.
          break
        }
      case .reserved:
        break
      }
    }

    // Compute payload size per report ID.
    var payloadSize: [UInt8: Int] = [:]
    for (rid, bits) in bitOffsetByReportID {
      payloadSize[rid] = (bits + 7) / 8
    }
    return HIDParsedDescriptor(fields: fields, payloadSizeBytesByReportID: payloadSize)
  }
}

// MARK: - Packing

private struct HIDReportPacker: @unchecked Sendable {
  let reportID: UInt8
  let payloadSizeBytes: Int

  private let buttonFields: [Int: HIDField]  // usage -> field
  private let axisFields: [Int: HIDField]  // usage -> field (Generic Desktop)
  private let hatField: HIDField?

  static func bestEffortGamepadPacker(from parsed: HIDParsedDescriptor) -> HIDReportPacker? {
    // Score each report ID by how many "gamepad-ish" fields it contains.
    let grouped = Dictionary(grouping: parsed.fields, by: { $0.reportID })
    var best: (UInt8, Int)? = nil
    for (rid, fields) in grouped {
      let hasButtons = fields.contains { $0.usagePage == 0x09 && (1...32).contains($0.usage) }
      let axisCount = fields.filter { $0.usagePage == 0x01 && (0x30...0x35).contains($0.usage) }.count
      let hasHat = fields.contains { $0.usagePage == 0x01 && $0.usage == 0x39 }
      var score = 0
      if hasButtons { score += 10 }
      score += min(6, axisCount) * 3
      if hasHat { score += 5 }
      if let size = parsed.payloadSizeBytesByReportID[rid] { score += min(20, size) }
      if best == nil || score > best!.1 { best = (rid, score) }
    }
    guard let (rid, _) = best else { return nil }
    let fields = grouped[rid] ?? []
    var buttons: [Int: HIDField] = [:]
    var axes: [Int: HIDField] = [:]
    var hat: HIDField?
    for f in fields {
      if f.usagePage == 0x09 {
        buttons[f.usage] = f
      } else if f.usagePage == 0x01 && (0x30...0x35).contains(f.usage) {
        axes[f.usage] = f
      } else if f.usagePage == 0x01 && f.usage == 0x39 {
        hat = f
      }
    }
    return HIDReportPacker(
      reportID: rid,
      payloadSizeBytes: parsed.payloadSizeBytesByReportID[rid] ?? 0,
      buttonFields: buttons,
      axisFields: axes,
      hatField: hat
    )
  }

  func pack(state: VirtualGamepadState) -> [UInt8] {
    var payload = [UInt8](repeating: 0, count: max(0, payloadSizeBytes))

    func setBits(bitOffset: Int, bitSize: Int, value: UInt32) {
      // Little-endian bit numbering within the report.
      for bit in 0..<bitSize {
        let dstBit = bitOffset + bit
        let byteIndex = dstBit / 8
        let bitIndex = dstBit % 8
        if byteIndex < 0 || byteIndex >= payload.count { continue }
        let mask = UInt8(1 << bitIndex)
        if ((value >> bit) & 1) != 0 {
          payload[byteIndex] |= mask
        } else {
          payload[byteIndex] &= ~mask
        }
      }
    }

    func encodeAxis(_ v: Int16, field: HIDField, signed: Bool) -> UInt32 {
      let minV = field.logicalMin
      let maxV = field.logicalMax
      if signed && minV < 0 {
        let maxAbs = max(abs(minV), abs(maxV))
        let scaled = Int(Double(v) / 32767.0 * Double(maxAbs))
        let clamped = max(minV, min(maxV, scaled))
        return UInt32(bitPattern: Int32(clamped))
      }
      let scaled = Int((Double(v) + 32767.0) / 65534.0 * Double(maxV - minV) + Double(minV))
      let clamped = max(minV, min(maxV, scaled))
      return UInt32(clamped)
    }

    func encodeTrigger(_ v: Int16, field: HIDField) -> UInt32 {
      let minV = field.logicalMin
      let maxV = field.logicalMax
      let scaled = Int(Double(v) / 32767.0 * Double(maxV - minV) + Double(minV))
      let clamped = max(minV, min(maxV, scaled))
      return UInt32(clamped)
    }

    func encodeHat(_ hat: GamepadHIDDescriptor.Hat, field: HIDField) -> UInt32 {
      let minV = field.logicalMin
      let maxV = field.logicalMax
      let hasNull = field.flags.hasNullState
      if hat == .neutral {
        if hasNull {
          // Many hats use "8" as neutral for 0..7.
          if minV == 0 && maxV == 7 { return UInt32(maxV + 1) }
          // Or "0" as neutral for 1..8 (below min).
          if minV == 1 && maxV == 8 { return 0 }
        }
        return UInt32(minV)
      }
      // Map our 1..8 to either 0..7 or 1..8 depending on logical min.
      let idx = Int(hat.rawValue) - 1
      if minV == 0 && maxV == 7 { return UInt32(idx) }
      if minV == 1 && maxV == 8 { return UInt32(idx + 1) }
      // Fallback: clamp into range.
      return UInt32(max(minV, min(maxV, idx + minV)))
    }

    // Buttons: map our standardized bit positions to HID Button usages 1..15.
    for usage in 1...15 {
      guard let field = buttonFields[usage] else { continue }
      let bitIndex = usage - 1
      let pressed = ((state.buttons >> bitIndex) & 1) != 0
      setBits(bitOffset: field.bitOffset, bitSize: field.bitSize, value: pressed ? 1 : 0)
    }

    // Axes (Generic Desktop): X,Y,Z,Rx,Ry,Rz
    if let f = axisFields[0x30] {
      setBits(bitOffset: f.bitOffset, bitSize: f.bitSize, value: encodeAxis(state.leftStickX, field: f, signed: true))
    }
    if let f = axisFields[0x31] {
      setBits(bitOffset: f.bitOffset, bitSize: f.bitSize, value: encodeAxis(state.leftStickY, field: f, signed: true))
    }
    if let f = axisFields[0x32] {
      setBits(bitOffset: f.bitOffset, bitSize: f.bitSize, value: encodeTrigger(state.leftTrigger, field: f))
    }
    if let f = axisFields[0x33] {
      setBits(bitOffset: f.bitOffset, bitSize: f.bitSize, value: encodeAxis(state.rightStickX, field: f, signed: true))
    }
    if let f = axisFields[0x34] {
      setBits(bitOffset: f.bitOffset, bitSize: f.bitSize, value: encodeAxis(state.rightStickY, field: f, signed: true))
    }
    if let f = axisFields[0x35] {
      setBits(bitOffset: f.bitOffset, bitSize: f.bitSize, value: encodeTrigger(state.rightTrigger, field: f))
    }

    if let f = hatField {
      setBits(bitOffset: f.bitOffset, bitSize: f.bitSize, value: encodeHat(state.hat, field: f))
    }

    if reportID != 0 {
      return [reportID] + payload
    }
    return payload
  }
}
