import Foundation
import Network

/// Foreground and reconnect sync remain authoritative; live messages are refresh hints only.
@MainActor final class Connectivity {
  private let monitor = NWPathMonitor()
  private let queue = DispatchQueue(label: "it.tripspl.connectivity")
  init(onReconnect: @escaping @MainActor @Sendable () -> Void) {
    monitor.pathUpdateHandler = { path in
      if path.status == .satisfied { Task { @MainActor in onReconnect() } }
    }
    monitor.start(queue: queue)
  }
  deinit { monitor.cancel() }
}
