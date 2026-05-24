import Foundation

public struct ForegroundConsumerClientActivitySignature: Equatable, Sendable {
  public let queueHead: Int?
  public let queueTail: Int?
  public let queueEntries: Int?
  public let getReportCount: Int
  public let setReportCount: Int
  public let setReportErrorCount: Int

  public init(
    queueHead: Int?,
    queueTail: Int?,
    queueEntries: Int?,
    getReportCount: Int,
    setReportCount: Int,
    setReportErrorCount: Int
  ) {
    self.queueHead = queueHead
    self.queueTail = queueTail
    self.queueEntries = queueEntries
    self.getReportCount = getReportCount
    self.setReportCount = setReportCount
    self.setReportErrorCount = setReportErrorCount
  }

  var hasSignal: Bool {
    (queueHead ?? 0) != 0
      || (queueTail ?? 0) != 0
      || (queueEntries ?? 0) != 0
      || getReportCount != 0
      || setReportCount != 0
      || setReportErrorCount != 0
  }
}

public struct ForegroundConsumerClientSample: Equatable, Sendable {
  public let clientID: UInt64
  public let routeToken: String
  public let bundleRootPath: String
  public let isOpened: Bool
  public let isSuspended: Bool
  public let activitySignature: ForegroundConsumerClientActivitySignature

  public init(
    clientID: UInt64,
    routeToken: String = UserSpaceVirtualDeviceConstants.sharedRouteToken,
    bundleRootPath: String,
    isOpened: Bool,
    isSuspended: Bool,
    activitySignature: ForegroundConsumerClientActivitySignature
  ) {
    self.clientID = clientID
    self.routeToken = routeToken
    self.bundleRootPath = bundleRootPath
    self.isOpened = isOpened
    self.isSuspended = isSuspended
    self.activitySignature = activitySignature
  }
}

public struct ForegroundConsumerActivityTracker: Sendable {
  private struct ClientState: Sendable {
    var lastSignature: ForegroundConsumerClientActivitySignature
    var lastChangedNanoseconds: UInt64?
  }

  private let activeRetentionNanoseconds: UInt64
  private var states: [UInt64: ClientState] = [:]

  public init(activeRetentionNanoseconds: UInt64 = 2_000_000_000) {
    self.activeRetentionNanoseconds = activeRetentionNanoseconds
  }

  public mutating func consumerBundleRootPaths(
    frontmostBundleRootPath: String?,
    clients: [ForegroundConsumerClientSample],
    now: UInt64
  ) -> Set<String> {
    let openClients = clients.filter { $0.isOpened && !$0.isSuspended }
    let openBundleRoots = Set(openClients.map(\.bundleRootPath))
    var activeBundleRoots: Set<String> = []
    var seenClientIDs: Set<UInt64> = []

    for client in openClients {
      seenClientIDs.insert(client.clientID)
      var state = states[client.clientID] ?? ClientState(
        lastSignature: client.activitySignature,
        lastChangedNanoseconds: nil
      )

      if state.lastSignature != client.activitySignature {
        state.lastSignature = client.activitySignature
        state.lastChangedNanoseconds = now
      }

      states[client.clientID] = state

      if let lastChanged = state.lastChangedNanoseconds,
        now &- lastChanged <= activeRetentionNanoseconds
      {
        activeBundleRoots.insert(client.bundleRootPath)
      }
    }

    states = states.filter { seenClientIDs.contains($0.key) }

    if openBundleRoots.count > 1,
      let frontmostBundleRootPath,
      openBundleRoots.contains(frontmostBundleRootPath)
    {
      return [frontmostBundleRootPath]
    }

    if activeBundleRoots.count == 1 { return activeBundleRoots }

    return openBundleRoots
  }
}
