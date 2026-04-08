import Foundation
import IOKit
import IOKit.hid

private func parseInt(_ s: String) -> Int? {
  if s.hasPrefix("0x") || s.hasPrefix("0X") {
    return Int(s.dropFirst(2), radix: 16)
  }
  return Int(s)
}

private func intProp(_ dev: IOHIDDevice, _ key: String) -> Int {
  IOHIDDeviceGetProperty(dev, key as CFString) as? Int ?? 0
}

private func strProp(_ dev: IOHIDDevice, _ key: String) -> String? {
  IOHIDDeviceGetProperty(dev, key as CFString) as? String
}

private func dataProp(_ dev: IOHIDDevice, _ key: String) -> Data? {
  IOHIDDeviceGetProperty(dev, key as CFString) as? Data
}

private func enumerateDevices(matching: [String: Any]?) -> [IOHIDDevice] {
  let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
  if let matching {
    IOHIDManagerSetDeviceMatching(mgr, matching as CFDictionary)
  } else {
    IOHIDManagerSetDeviceMatching(mgr, nil)
  }
  _ = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
  defer { IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone)) }
  return Array(((IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>) ?? []).sorted {
    let a = intProp($0, kIOHIDVendorIDKey as String) * 0x1_0000 + intProp($0, kIOHIDProductIDKey as String)
    let b = intProp($1, kIOHIDVendorIDKey as String) * 0x1_0000 + intProp($1, kIOHIDProductIDKey as String)
    return a < b
  })
}

private func printUsageAndExit(_ code: Int32) -> Never {
  fputs(
    """
    OpenJoystickDriverHIDTool

    Usage:
      OpenJoystickDriverHIDTool --list
      OpenJoystickDriverHIDTool --dump --vid 0x045e --pid 0x02ea

    Options:
      --list           List HID devices (vid/pid/product/transport + report sizes).
      --dump           Dump the report descriptor for one device (as hex and Swift [UInt8]).
      --vid <int>      Vendor ID (decimal or 0x... hex).
      --pid <int>      Product ID (decimal or 0x... hex).
      --help           Show this help.

    """,
    stderr
  )
  exit(code)
}

let args = Array(CommandLine.arguments.dropFirst())
if args.contains("--help") { printUsageAndExit(0) }

let list = args.contains("--list")
let dump = args.contains("--dump")

func argValue(_ name: String) -> String? {
  guard let idx = args.firstIndex(of: name), idx + 1 < args.count else { return nil }
  return args[idx + 1]
}

if list {
  let devs = enumerateDevices(matching: nil)
  for dev in devs {
    let vid = intProp(dev, kIOHIDVendorIDKey as String)
    let pid = intProp(dev, kIOHIDProductIDKey as String)
    let product = strProp(dev, kIOHIDProductKey as String) ?? "(unknown)"
    let transport = strProp(dev, kIOHIDTransportKey as String) ?? "(null)"
    let inSize = intProp(dev, kIOHIDMaxInputReportSizeKey as String)
    let outSize = intProp(dev, kIOHIDMaxOutputReportSizeKey as String)
    let primaryPage = intProp(dev, kIOHIDPrimaryUsagePageKey as String)
    let primaryUsage = intProp(dev, kIOHIDPrimaryUsageKey as String)
    print(
      "VID:0x\(String(vid, radix: 16)) PID:0x\(String(pid, radix: 16))"
        + " transport=\(transport)"
        + " primary=\(primaryPage):\(primaryUsage)"
        + " maxIn=\(inSize) maxOut=\(outSize)"
        + " product=\"\(product)\""
    )
  }
  exit(0)
}

if dump {
  guard let vidS = argValue("--vid"), let pidS = argValue("--pid") else {
    fputs("ERROR: --dump requires --vid and --pid.\n", stderr)
    printUsageAndExit(2)
  }
  guard let vid = parseInt(vidS), let pid = parseInt(pidS) else {
    fputs("ERROR: Could not parse --vid/--pid.\n", stderr)
    exit(2)
  }
  let devs = enumerateDevices(matching: [
    kIOHIDVendorIDKey as String: vid,
    kIOHIDProductIDKey as String: pid,
  ])
  guard let dev = devs.first else {
    fputs("ERROR: Device not found. Is it connected?\n", stderr)
    exit(1)
  }
  guard let desc = dataProp(dev, kIOHIDReportDescriptorKey as String) else {
    fputs("ERROR: Device has no report descriptor property.\n", stderr)
    exit(1)
  }
  let bytes = [UInt8](desc)
  print("Descriptor length: \(bytes.count) bytes")
  print("")
  print("--- Hex ---")
  print(bytes.map { String(format: "%02X", $0) }.joined(separator: " "))
  print("")
  print("--- Swift [UInt8] ---")
  print("let descriptor: [UInt8] = [")
  var line: [String] = []
  for (idx, b) in bytes.enumerated() {
    line.append(String(format: "0x%02X", b))
    if line.count == 12 || idx == bytes.count - 1 {
      print("  " + line.joined(separator: ", ") + (idx == bytes.count - 1 ? "" : ","))
      line.removeAll(keepingCapacity: true)
    }
  }
  print("]")
  exit(0)
}

printUsageAndExit(2)

