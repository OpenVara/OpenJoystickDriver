import Foundation

/// Dispatches output to a primary dispatcher, optionally mirroring to a secondary dispatcher.
///
/// Used to keep DriverKit output working while also enabling a user-space
/// IOHIDUserDevice for SDL/IOKit compatibility without a reboot.
public final class CompositeOutputDispatcher: OutputDispatcher, @unchecked Sendable {

  public enum Mode: String, Sendable {
    case primaryOnly
    case secondaryOnly
    case both
  }

  private let primary: any OutputDispatcher
  private var secondary: (any OutputDispatcher)?
  private var mode: Mode = .primaryOnly
  private let lock = NSLock()

  public var suppressOutput: Bool {
    get { lock.withLock { _suppressOutput } }
    set {
      lock.withLock {
        _suppressOutput = newValue
        primary.suppressOutput = newValue
        secondary?.suppressOutput = newValue
      }
    }
  }
  private var _suppressOutput: Bool = false

  public init(primary: any OutputDispatcher, secondary: (any OutputDispatcher)? = nil) {
    self.primary = primary
    self.secondary = secondary
    self._suppressOutput = primary.suppressOutput
    self.secondary?.suppressOutput = self._suppressOutput
  }

  public func setMode(_ newMode: Mode) {
    lock.withLock {
      mode = newMode
    }
  }

  public func getMode() -> Mode { lock.withLock { mode } }

  public func setSecondary(_ newSecondary: (any OutputDispatcher)?) {
    lock.withLock {
      secondary = newSecondary
      secondary?.suppressOutput = _suppressOutput
    }
  }

  public func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {
    guard !suppressOutput else { return }
    let (p, s, m) = lock.withLock { (primary, secondary, mode) }
    switch m {
    case .primaryOnly:
      await p.dispatch(events: events, from: identifier)
    case .secondaryOnly:
      if let s { await s.dispatch(events: events, from: identifier) }
    case .both:
      await p.dispatch(events: events, from: identifier)
      if let s { await s.dispatch(events: events, from: identifier) }
    }
  }
}
