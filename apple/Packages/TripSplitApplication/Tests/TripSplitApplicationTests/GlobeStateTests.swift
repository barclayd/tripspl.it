import Foundation
import Testing
import TripSplitApplication
import TripSplitDomain
import TripSplitNetworking
import TripSplitPersistence
import TripSplitSync

@MainActor struct GlobeStateTests {
  private func app() throws -> AppModel {
    let store = try LocalStore(inMemory: true, installationID: "globe-test")
    return AppModel(store: store, sync: SyncCoordinator(store: store, api: APIClient(baseURL: nil)))
  }
  private func addTrip(to app: AppModel, country: String, home: String, startsOn: String) throws {
    app.onboarding = OnboardingDraft.newTrip()
    app.onboarding.stops = [try #require(Destination.country(country)).stop(nights: 2)]
    app.onboarding.startsOn = startsOn
    app.onboarding.currency = home
    app.onboarding.budget = "500"
    _ = try app.createTrip()
  }

  @Test func changingTheFilterClearsTheSelection() throws {
    let app = try app()
    app.globeTripID = "trip"
    app.globeFilter = .all
    #expect(app.globeTripID == "trip")
    app.globeFilter = .past
    #expect(app.globeTripID == nil)
  }

  @Test func spendingCountsStartedTripsInTheUsualCurrency() throws {
    let app = try app()
    try addTrip(to: app, country: "PT", home: "EUR", startsOn: "2025-03-01")
    try addTrip(to: app, country: "ES", home: "EUR", startsOn: "2025-06-01")
    try addTrip(to: app, country: "JP", home: "GBP", startsOn: "2099-01-01")
    #expect(app.displayCurrency == "EUR")
    #expect(app.spentSoFar(in: "EUR") == 0)
    // Upcoming trips stay out, so no rate is needed for them yet.
    #expect(app.spentSoFar(in: "GBP") == nil)
    app.cacheReferenceRates(
      FXTable(
        base: "GBP", requestedDate: "2026-11-01", rateDate: "2026-10-30", source: "Test",
        rates: ["EUR": "1.16"]))
    #expect(app.spentSoFar(in: "GBP") == 0)
  }

  @Test func upcomingIncludesTripsUnderWay() throws {
    let app = try app()
    try addTrip(to: app, country: "PT", home: "GBP", startsOn: CivilDate.today(timeZone: "UTC"))
    let trip = try #require(app.store.trips.first)
    #expect(GlobeFilter.upcoming.includes(trip))
    #expect(!GlobeFilter.past.includes(trip))
  }
}
