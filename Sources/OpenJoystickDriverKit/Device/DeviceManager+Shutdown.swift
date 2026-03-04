import Foundation

extension DeviceManager {
  /// Installs SIGTERM and SIGINT handlers that stop
  /// device manager and exit cleanly. Call once at startup.
  nonisolated public func setupGracefulShutdown(label: String) {
    let dm = self
    let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    sigterm.setEventHandler {
      print("[\(label)] SIGTERM - stopping...")
      Task {
        await dm.stop()
        exit(0)
      }
    }
    sigterm.resume()
    signal(SIGTERM, SIG_IGN)

    let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    sigint.setEventHandler {
      print("[\(label)] SIGINT - stopping...")
      Task {
        await dm.stop()
        exit(0)
      }
    }
    sigint.resume()
    signal(SIGINT, SIG_IGN)
  }
}
