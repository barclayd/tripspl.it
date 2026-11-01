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
      var loadTable: (@Sendable (String, String) async throws -> FXTable)?
      if baseURL != nil {
        loadQuote = { from, to, date in
          try await api.quote(from: from, to: to, date: date, token: nil)
        }
        loadTable = { base, date in try await api.rates(base: base, date: date) }
      }
      let send: @MainActor (CompanionCommand) throws -> Void = { try session.send($0) }
      let model = WatchModel(
        state: mirror.load(), mirror: mirror, send: send, loadQuote: loadQuote,
        loadTable: loadTable)
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
    // Reference rates from GBP, as the design's examples use (€24 = £20.69, $50 = €43.61).
    model.cache(
      FXTable(
        base: "GBP", requestedDate: CivilDate.string(instant), rateDate: CivilDate.string(instant),
        source: "Demo",
        rates: [
          "GBP": "1", "EUR": "1.16", "USD": "1.33", "CHF": "1.07", "JPY": "198.67", "AUD": "2.03",
          "CAD": "1.84", "THB": "43.21", "MXN": "24.62", "NZD": "2.24", "SEK": "12.61",
          "NOK": "13.38", "DKK": "8.66", "PLN": "4.93", "CZK": "29.03", "HUF": "449.8",
          "TRY": "55.13", "SGD": "1.71", "HKD": "10.38", "KRW": "1855.4", "INR": "116.24",
          "ZAR": "23.12", "MAD": "12.27", "ISK": "163.9", "AED": "4.88", "VND": "34433",
        ]))
    return model
  }
}

extension Array {
  fileprivate subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
