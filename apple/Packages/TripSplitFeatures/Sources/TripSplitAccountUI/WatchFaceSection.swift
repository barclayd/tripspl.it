import ClockKit
import SwiftUI
import WatchConnectivity

/// G4: offers the TripSplit face to a paired Apple Watch that has TripSplit on it. Its corners
/// are convert, budget left, who owes you and today's spend, and each opens its own screen.
///
/// Faces can only be made on a watch, so the face is exported from one and bundled as
/// `TripSplit.watchface` (see `apple/watch/README.md`). Without it, nothing shows.
struct WatchFaceSection: View {
  @State private var adding = false
  @State private var message: String?

  static var face: URL? { Bundle.main.url(forResource: "TripSplit", withExtension: "watchface") }

  /// The face needs TripSplit's complications on the watch it's added to.
  static var hasWatchApp: Bool {
    guard WCSession.isSupported() else { return false }
    let session = WCSession.default
    return session.activationState == .activated && session.isPaired
      && session.isWatchAppInstalled
  }

  var body: some View {
    if let face = Self.face, Self.hasWatchApp {
      Section("Apple Watch") {
        Button("Add the TripSplit face", systemImage: "applewatch") { add(face) }
          .disabled(adding)
        Text(
          "Convert, budget left, who owes you and today’s spend in the corners. Each opens its own screen."
        ).font(.footnote).foregroundStyle(.secondary)
        if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
      }
    }
  }

  private func add(_ face: URL) {
    adding = true
    message = nil
    Task {
      defer { adding = false }
      do {
        try await CLKWatchFaceLibrary().addWatchFace(at: face)
      } catch let error as NSError
        where error.domain == CLKWatchFaceLibrary.ErrorDomain
        && error.code == CLKWatchFaceLibrary.ErrorCode.faceNotAvailable.rawValue
      {
        message = "This face needs a newer Apple Watch or watchOS."
      } catch {
        message = "The face couldn’t be added. Try again in a moment."
      }
    }
  }
}
