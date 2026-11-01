import Foundation
import TripSplitApplication
import TripSplitCompanion
import TripSplitDomain
import TripSplitNetworking
import TripSplitPersistence

extension WatchModel {
  #if canImport(WatchConnectivity)
    /// The watch app's model: mirrored trips from the App Group, kept current over
    /// WatchConnectivity, with reference rates from the TripSplit API when configured.
    public static func live(baseURL: URL?) -> WatchModel {
      let session = CompanionSession()
      let api = APIClient(baseURL: baseURL)
      let mirror = CompanionMirror.shared()
      var loadQuote: (@Sendable (String, String, String) async throws -> FXQuote)?
      if baseURL != nil {
        loadQuote = { from, to, date in
          try await api.quote(from: from, to: to, date: date, token: nil)
        }
      }
      let send: @MainActor (CompanionCommand) throws -> Void = { try session.send($0) }
      let model = WatchModel(state: mirror.load(), mirror: mirror, send: send, loadQuote: loadQuote)
      session.onContext = { [weak model] in model?.receive($0) }
      model.retain(session)
      return model
    }
  #endif

  /// Sample trips for screenshots and simulator runs, matching the phone's `--demo` data.
  public static func demo(at instant: Date = Date()) throws -> WatchModel {
    let store = try LocalStore(inMemory: true)
    try DemoData.install(into: store)
    var trips = store.trips
    // Give the past trips some spend so the passport has a total, as in the design.
    for (index, amount) in ["212600", "270000"].enumerated() {
      guard
        let past = trips.indices.filter({ trips[$0].phase(at: instant) == .past })
          .sorted(by: { trips[$0].startsOn > trips[$1].startsOn })[safe: index]
      else { continue }
      let trip = trips[past]
      trips[past].expenses.append(
        Expense(
          attachment: .init(kind: .day, id: trip.days[0].id), title: "Everything", category: .other,
          amountMinor: amount, currency: trip.homeCurrency, status: .paid,
          paidOn: trip.startsOn, paidBy: trip.currentTravellerId,
          splitWith: trip.travellers.map(\.id)))
    }
    let model = WatchModel(state: .init(context: .init(trips: trips, sentAt: instant)))
    model.now = instant
    return model
  }
}

extension Array {
  fileprivate subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
