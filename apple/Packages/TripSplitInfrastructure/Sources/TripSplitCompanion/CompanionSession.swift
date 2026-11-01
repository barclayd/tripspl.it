#if canImport(WatchConnectivity)
  import Foundation
  import TripSplitDomain
  import WatchConnectivity

  /// WatchConnectivity transport between the iPhone and its watch.
  ///
  /// The phone publishes its latest trips as application context (or a file when too large);
  /// the watch queues commands as user-info transfers, which survive either side being asleep.
  @MainActor public final class CompanionSession: NSObject {
    /// Application context is kept small; larger contexts travel as a file transfer.
    static let contextLimit = 48_000

    public var onContext: (@MainActor (CompanionContext) -> Void)?
    public var onCommand: (@MainActor (CompanionCommand) -> Void)?
    public var onActivate: (@MainActor () -> Void)?
    public private(set) var isActive = false
    public private(set) var isReachable = false

    private let session: WCSession?
    private var unsent: CompanionContext?

    public override init() {
      session = WCSession.isSupported() ? .default : nil
      super.init()
      session?.delegate = self
      session?.activate()
    }

    /// Whether the other side has TripSplit installed.
    public var isCounterpartInstalled: Bool {
      guard let session, isActive else { return false }
      #if os(watchOS)
        return session.isCompanionAppInstalled
      #else
        return session.isPaired && session.isWatchAppInstalled
      #endif
    }

    /// Commands queued for the phone that have not been delivered yet.
    public var outstandingCommands: Int {
      session?.outstandingUserInfoTransfers.count ?? 0
    }

    /// Phone side: replaces the watch's copy of the trips.
    public func publish(_ context: CompanionContext) throws {
      guard let session, isActive else {
        unsent = context
        return
      }
      #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
      #endif
      let data = try CompanionCodec.encode(context)
      if data.count <= Self.contextLimit {
        try session.updateApplicationContext([CompanionCodec.contextKey: data])
      } else {
        session.outstandingFileTransfers.filter(\.isTransferring).forEach { $0.cancel() }
        let url = URL.temporaryDirectory.appending(path: "companion-\(UUID().uuidString).lzfse")
        try data.write(to: url)
        session.transferFile(url, metadata: [CompanionCodec.contextKey: true])
      }
    }

    /// Watch side: queues a change for the phone to apply.
    public func send(_ command: CompanionCommand) throws {
      guard let session else { return }
      session.transferUserInfo([CompanionCodec.commandKey: try CompanionCodec.encode(command)])
    }

    private func activated(context: Data?, reachable: Bool) {
      isActive = true
      isReachable = reachable
      if let context { received(context: context) }
      if let unsent {
        self.unsent = nil
        try? publish(unsent)
      }
      onActivate?()
    }

    private func received(context data: Data) {
      guard let context = try? CompanionCodec.decode(CompanionContext.self, from: data) else {
        return
      }
      onContext?(context)
    }

    private func received(command data: Data) {
      guard let command = try? CompanionCodec.decode(CompanionCommand.self, from: data) else {
        return
      }
      onCommand?(command)
    }
  }

  extension CompanionSession: WCSessionDelegate {
    nonisolated public func session(
      _ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
      error: (any Error)?
    ) {
      guard state == .activated else { return }
      let context = session.receivedApplicationContext[CompanionCodec.contextKey] as? Data
      let reachable = session.isReachable
      Task { @MainActor in self.activated(context: context, reachable: reachable) }
    }

    nonisolated public func sessionReachabilityDidChange(_ session: WCSession) {
      let reachable = session.isReachable
      Task { @MainActor in self.isReachable = reachable }
    }

    nonisolated public func session(
      _ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]
    ) {
      guard let data = applicationContext[CompanionCodec.contextKey] as? Data else { return }
      Task { @MainActor in self.received(context: data) }
    }

    nonisolated public func session(_ session: WCSession, didReceive file: WCSessionFile) {
      // The system removes the file when this method returns, so read it now.
      guard file.metadata?[CompanionCodec.contextKey] != nil,
        let data = try? Data(contentsOf: file.fileURL)
      else { return }
      Task { @MainActor in self.received(context: data) }
    }

    nonisolated public func session(
      _ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: (any Error)?
    ) {
      try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
    }

    nonisolated public func session(
      _ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
      guard let data = userInfo[CompanionCodec.commandKey] as? Data else { return }
      Task { @MainActor in self.received(command: data) }
    }

    #if os(iOS)
      nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}

      nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        // Switching watches deactivates the session; activate again for the new one.
        session.activate()
      }

      nonisolated public func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.onActivate?() }
      }
    #endif
  }
#endif
