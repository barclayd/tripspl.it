import Foundation
import Testing
import TripSplitApplication
import TripSplitConversion
import TripSplitDomain
import TripSplitNetworking
import TripSplitPersistence
import TripSplitSync

/// A host app can compose and use the packages without testable imports or iOS frameworks.
@MainActor struct PublicAPITests {
  @Test func hostComposesOfflineTripAndExpense() async throws {
    let store = try LocalStore(inMemory: true, installationID: "public-api-test")
    let sync = SyncCoordinator(store: store, api: APIClient(baseURL: nil))
    let app = AppModel(store: store, sync: sync)
    app.onboarding.stops = [try #require(Destination.country("PT")).stop(nights: 2)]
    #expect(throws: MoneyError.self) { try app.createTrip() }
    app.onboarding.budget = "500"
    let trip = try app.createTrip()
    let converter = ConversionModel(
      from: .forCurrency("EUR"), to: .forCurrency("GBP"), date: trip.startsOn,
      loadQuote: { _, _, _ in throw URLError(.notConnectedToInternet) })
    converter.amount = "12.50"
    converter.enterManualRate("0.8")
    app.expenseDraft = try converter.expenseDraft(
      trip: trip, attachment: .init(kind: .day, id: trip.days[0].id))
    let expense = try await app.saveExpense()
    #expect(expense.conversion?.homeAmountMinor == "1000")
    #expect(store.trip(trip.id)?.expenses == [expense])
    #expect(store.envelopes[trip.id]?.pending.count == 1)
    #expect(!sync.configured)
  }

  @Test func referenceRatesStayAvailableOfflineAfterRestart() throws {
    let store = try LocalStore(inMemory: true, installationID: "public-api-test")
    let sync = SyncCoordinator(store: store, api: APIClient(baseURL: nil))
    let app = AppModel(store: store, sync: sync)
    #expect(app.indicativeRate(from: "GBP", to: "EUR") == nil)
    #expect(app.indicativeRate(from: "EUR", to: "EUR") == 1)
    app.cacheReferenceRates(
      FXTable(
        base: "GBP", requestedDate: "2026-11-01", rateDate: "2026-10-30", source: "Test",
        rates: ["EUR": "1.16", "JPY": "190"]))
    let restarted = AppModel(store: store, sync: sync)
    #expect(restarted.indicativeRate(from: "GBP", to: "EUR") == 1.16)
    #expect(restarted.indicativeRate(from: "EUR", to: "GBP").map { ($0 * 100).rounded() } == 86)
  }
}
