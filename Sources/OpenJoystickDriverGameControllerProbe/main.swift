import Foundation
import GameController

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
  return "vendor=\"\(vendor)\" category=\"\(productCategory)\" extended=\(hasExtended) micro=\(hasMicro)"
}

let seconds = argValue("--seconds", default: 5)

print("GameController probe")
print("Listening for \(seconds)s")
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
