import Foundation
import Testing

@testable import TripSplitDomain

struct TripGeographyTests {
  private func trip(_ cities: [String], startsOn: String = "2026-11-01") throws -> TripSnapshot {
    var draft = OnboardingDraft()
    draft.startsOn = startsOn
    draft.timeZone = "Europe/London"
    draft.stops = try cities.map { city in
      try #require(Destination.all.first { $0.city == city }).stop(nights: 2)
    }
    return try draft.makeTrip()
  }

  @Test func centreCrossesTheAntimeridian() throws {
    let trip = try trip(["Tokyo", "Vancouver"])
    let centre = try #require(trip.centre)
    // A plain average of the longitudes would land in Europe.
    #expect(abs(centre.longitude) > 150)
    #expect(centre.latitude > 45)
  }

  @Test func reachIsTheFurthestStopFromTheCentre() throws {
    let single = try trip(["Lisbon"])
    #expect(single.reach < 1)
    let iberia = try trip(["Lisbon", "Porto", "Seville"])
    #expect(iberia.reach > 150_000 && iberia.reach < 300_000)
  }

  @Test func flagsRepeatOncePerCountry() throws {
    let trip = try trip(["Lisbon", "Seville", "Porto"])
    #expect(trip.uniqueFlags == ["🇵🇹", "🇪🇸"])
  }

  @Test func dayProgressCountsFromTheFirstDay() throws {
    let trip = try trip(["Lisbon", "Porto"])
    let now = try #require(ISO8601DateFormatter().date(from: "2026-11-02T12:00:00Z"))
    let progress = try #require(trip.dayProgress(at: now))
    #expect(progress.day == 2 && progress.of == trip.days.count)
    let before = try #require(ISO8601DateFormatter().date(from: "2026-10-20T12:00:00Z"))
    #expect(trip.dayProgress(at: before) == nil)
  }

  @Test func homeIsTheRegionsLeadingCity() {
    #expect(Destination.home(region: "GB")?.city == "London")
    #expect(Destination.home(region: "us")?.city == "New York")
    #expect(Destination.home(region: nil) == nil)
    #expect(Destination.home(region: "ZZ") == nil)
  }
}
