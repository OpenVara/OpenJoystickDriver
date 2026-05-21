import CoreHaptics
import Foundation
import GameController
import IOKit
import IOKit.hid

func hasArg(_ name: String) -> Bool {
  CommandLine.arguments.dropFirst().contains(name)
}

func argValue(_ name: String, default defaultValue: Int) -> Int {
  let args = Array(CommandLine.arguments.dropFirst())
  guard let idx = args.firstIndex(of: name), idx + 1 < args.count,
    let value = Int(args[idx + 1])
  else {
    return defaultValue
  }
  return value
}

func describe(_ controller: GCController) -> String {
  let vendor = controller.vendorName ?? "(unknown)"
  let productCategory = controller.productCategory
  let hasExtended = controller.extendedGamepad != nil
  let hasMicro = controller.microGamepad != nil
  let haptics = controllerHapticsDescription(controller)
  return "vendor=\"\(vendor)\" category=\"\(productCategory)\""
    + " extended=\(hasExtended) micro=\(hasMicro) \(haptics)"
}

func controllerHapticsDescription(_ controller: GCController) -> String {
  if #available(macOS 11.0, *) {
    guard let haptics = controller.haptics else { return "haptics=false" }
    let localities = haptics.supportedLocalities
      .map(\.rawValue)
      .sorted()
      .joined(separator: ",")
    return "haptics=true localities=[\(localities)]"
  }
  return "haptics=unavailable"
}

func playHapticPulse(on controller: GCController) -> String {
  guard #available(macOS 11.0, *) else { return "unavailable: macOS 11 required" }
  guard let haptics = controller.haptics else { return "unavailable: controller has no haptics" }
  guard let engine = haptics.createEngine(withLocality: .default) else {
    return "unavailable: no default haptic engine"
  }
  do {
    try engine.start()
    let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
    let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
    let event = CHHapticEvent(
      eventType: .hapticContinuous,
      parameters: [intensity, sharpness],
      relativeTime: 0,
      duration: 0.5
    )
    let pattern = try CHHapticPattern(events: [event], parameters: [])
    let player = try engine.makePlayer(with: pattern)
    try player.start(atTime: 0)
    Thread.sleep(forTimeInterval: 0.7)
    engine.stop()
    return "played"
  } catch {
    return "failed: \(error)"
  }
}

func intProp(_ device: IOHIDDevice, _ key: String) -> Int {
  IOHIDDeviceGetProperty(device, key as CFString) as? Int ?? 0
}

func strProp(_ device: IOHIDDevice, _ key: String) -> String? {
  IOHIDDeviceGetProperty(device, key as CFString) as? String
}

func looksLikeGamepad(_ device: IOHIDDevice) -> Bool {
  if intProp(device, kIOHIDPrimaryUsagePageKey) == kHIDPage_GenericDesktop,
    intProp(device, kIOHIDPrimaryUsageKey) == kHIDUsage_GD_GamePad
  {
    return true
  }
  let rawPairs = IOHIDDeviceGetProperty(
    device,
    kIOHIDDeviceUsagePairsKey as CFString
  )
  guard let pairs = rawPairs as? [[String: Any]]
  else {
    return false
  }
  return pairs.contains { pair in
    let page = pair[kIOHIDDeviceUsagePageKey as String] as? Int ?? 0
    let usage = pair[kIOHIDDeviceUsageKey as String] as? Int ?? 0
    return page == kHIDPage_GenericDesktop && usage == kHIDUsage_GD_GamePad
  }
}

func printHIDSupport() {
  let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
  IOHIDManagerSetDeviceMatching(manager, nil)
  IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
  let devices = ((IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? [])
    .filter(looksLikeGamepad)
    .sorted {
      let leftVID = intProp($0, kIOHIDVendorIDKey)
      let rightVID = intProp($1, kIOHIDVendorIDKey)
      if leftVID != rightVID { return leftVID < rightVID }
      return intProp($0, kIOHIDProductIDKey) < intProp($1, kIOHIDProductIDKey)
    }

  print("HID GamePad support:")
  if devices.isEmpty {
    print("- none")
  }
  for device in devices {
    let vid = intProp(device, kIOHIDVendorIDKey)
    let pid = intProp(device, kIOHIDProductIDKey)
    let product = strProp(device, kIOHIDProductKey) ?? "(unknown)"
    let transport = strProp(device, kIOHIDTransportKey) ?? "(unknown)"
    let supported: String
    if #available(macOS 11.0, *) {
      supported = GCController.supportsHIDDevice(device) ? "yes" : "no"
    } else {
      supported = "unavailable"
    }
    print(
      String(
        format: "- %04X:%04X \"%@\" transport=%@ gamecontroller=%@",
        vid,
        pid,
        product,
        transport,
        supported
      )
    )
  }
  IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
}

let seconds = argValue("--seconds", default: 5)
let shouldRumble = hasArg("--rumble")

print("GameController probe")
print("Listening for \(seconds)s")
if shouldRumble {
  print("Rumble pulse requested")
}
print("")
if #available(macOS 11.3, *) {
  GCController.shouldMonitorBackgroundEvents = true
}
printHIDSupport()
print("")

let center = NotificationCenter.default
var observerTokens: [NSObjectProtocol] = []
observerTokens.append(
  center.addObserver(
    forName: .GCControllerDidConnect,
    object: nil,
    queue: .main
  ) { note in
    guard let controller = note.object as? GCController else { return }
    print("connect: \(describe(controller))")
  }
)
observerTokens.append(
  center.addObserver(
    forName: .GCControllerDidDisconnect,
    object: nil,
    queue: .main
  ) { note in
    guard let controller = note.object as? GCController else { return }
    print("disconnect: \(describe(controller))")
  }
)

let controllers = GCController.controllers()
print("Initial controllers: \(controllers.count)")
for controller in controllers {
  print("- \(describe(controller))")
}

let end = Date().addingTimeInterval(TimeInterval(seconds))
while Date() < end {
  RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
}

for token in observerTokens {
  center.removeObserver(token)
}

if shouldRumble {
  let controllers = GCController.controllers()
  guard let controller = controllers.first else {
    print("rumble: skipped no controller")
    exit(1)
  }
  print("rumble: \(playHapticPulse(on: controller))")
}
