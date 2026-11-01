import Foundation
import Testing

@testable import TripSplitDomain

struct TripOriginTests {
  private let dublin = TripOrigin(
    place: "Dublin", countryCode: "IE", latitude: 53.3498, longitude: -6.2603)
  private func trip() throws -> TripSnapshot {
    var draft = OnboardingDraft()
    draft.startsOn = "2026-11-01"
    draft.timeZone = "Europe/London"
    draft.stops = [try #require(Destination.all.first { $0.city == "Lisbon" }).stop(nights: 3)]
    return try draft.makeTrip()
  }

  @Test func originDerivesFlagCurrencyAndPoint() {
    #expect(dublin.flag == "🇮🇪")
    #expect(dublin.currency == "EUR")
    #expect(dublin.point == GeoPoint(latitude: 53.3498, longitude: -6.2603))
  }

  @Test func legacyTripsDecodeWithoutAnOriginAndNeverEncodeNull() throws {
    var trip = try trip()
    let legacy = try JSONEncoder().encode(trip)
    #expect(!String(decoding: legacy, as: UTF8.self).contains("origin"))
    #expect(try JSONDecoder().decode(TripSnapshot.self, from: legacy).origin == nil)
    trip.origin = dublin
    let settings = try JSONEncoder().encode(TripSettings(trip))
    #expect(try JSONDecoder().decode(TripSettings.self, from: settings).origin == dublin)
  }

  @Test func settingsWithoutAnOriginKeepTheSavedOne() throws {
    var trip = try trip()
    trip.origin = dublin
    var legacy = TripSettings(trip)
    legacy.origin = nil
    legacy.name = "Renamed"
    Operation(syncEpoch: "1", type: "trip.update", entityId: trip.id, payload: .settings(legacy))
      .apply(to: &trip)
    #expect(trip.name == "Renamed")
    #expect(trip.origin == dublin)
    let london = TripOrigin(
      place: "London", countryCode: "GB", latitude: 51.5072, longitude: -0.1276)
    var moved = TripSettings(trip)
    moved.origin = london
    Operation(syncEpoch: "1", type: "trip.update", entityId: trip.id, payload: .settings(moved))
      .apply(to: &trip)
    #expect(trip.origin == london)
  }
}
