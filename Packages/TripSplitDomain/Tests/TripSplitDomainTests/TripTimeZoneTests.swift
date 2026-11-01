import Foundation
import Testing

@testable import TripSplitDomain

struct TripTimeZoneTests {
  private func stop(_ city: String, zone: String) throws -> Stop {
    var stop = try #require(Destination.all.first { $0.city == city }).stop(nights: 1)
    stop.timeZone = zone
    return stop
  }
  private func instant(_ value: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: value))
  }

  @Test func eachAttachmentUsesItsDestinationLocalDate() throws {
    var draft = OnboardingDraft()
    draft.startsOn = "2026-10-31"
    draft.timeZone = "Europe/London"
    draft.stops = [
      try stop("San Francisco", zone: "America/Los_Angeles"),
      try stop("Tokyo", zone: "Asia/Tokyo"),
    ]
    let trip = try draft.makeTrip()
    let now = try instant("2026-11-01T01:30:00Z")
    let sanFrancisco = Attachment(kind: .day, id: trip.days[0].id)
    let tokyo = Attachment(kind: .day, id: trip.days[1].id)
    #expect(trip.today(for: sanFrancisco, at: now) == "2026-10-31")
    #expect(trip.today(for: tokyo, at: now) == "2026-11-01")
    #expect(trip.isToday(trip.days[0], at: now))
    #expect(trip.isToday(trip.days[1], at: now))
    #expect(trip.currentAttachment(at: now) == tokyo)
    #expect(trip.phase(at: now) == .now)
    #expect(trip.timeZone == "America/Los_Angeles")
    #expect(trip.timeZone(for: .init(kind: .leg, id: trip.legs.last!.id)) == "Asia/Tokyo")
  }

  @Test func tripStartsAndEndsOnDestinationDatesInsteadOfPhoneDates() throws {
    var draft = OnboardingDraft()
    draft.startsOn = "2026-11-01"
    draft.stops = [try stop("Tokyo", zone: "Asia/Tokyo")]
    let trip = try draft.makeTrip()
    #expect(trip.phase(at: try instant("2026-10-31T14:59:00Z")) == .upcoming)
    #expect(trip.phase(at: try instant("2026-10-31T15:00:00Z")) == .now)
    #expect(trip.phase(at: try instant("2026-11-02T14:59:00Z")) == .now)
    #expect(trip.phase(at: try instant("2026-11-02T15:00:00Z")) == .past)
  }

  @Test func regionalDaylightSavingRulesApplyToLoggedDates() throws {
    var draft = OnboardingDraft()
    draft.startsOn = "2026-10-31"
    draft.stops = [try stop("New York", zone: "America/New_York")]
    let trip = try draft.makeTrip()
    let attachment = Attachment(kind: .day, id: trip.days[0].id)
    #expect(trip.today(for: attachment, at: try instant("2026-11-01T03:59:00Z")) == "2026-10-31")
    #expect(trip.today(for: attachment, at: try instant("2026-11-01T04:00:00Z")) == "2026-11-01")
    #expect(trip.today(for: attachment, at: try instant("2026-11-02T04:59:00Z")) == "2026-11-01")
    #expect(trip.today(for: attachment, at: try instant("2026-11-02T05:00:00Z")) == "2026-11-02")
  }

  @Test func destinationZoneIsPersistedAndOldStopsResolveFromCatalogue() throws {
    let destination = try #require(Destination.all.first { $0.city == "San Francisco" })
    var stop = destination.stop()
    #expect(stop.timeZone == "America/Los_Angeles")
    let saved = try JSONDecoder().decode(Stop.self, from: JSONEncoder().encode(stop))
    #expect(saved.timeZone == stop.timeZone)
    stop.timeZone = nil
    #expect(stop.resolvedTimeZone == "America/Los_Angeles")
    stop.timeZone = "America/New_York"
    #expect(stop.resolvedTimeZone == "America/New_York")
  }

  @Test func destinationsWithoutADefaultRequireAnExplicitZone() throws {
    var draft = OnboardingDraft()
    draft.stops = [try #require(Destination.country("AQ")).stop()]
    draft.step = 1
    #expect(!draft.canAdvance)
    draft.stops[0].timeZone = "Antarctica/McMurdo"
    #expect(draft.canAdvance)
  }
}
