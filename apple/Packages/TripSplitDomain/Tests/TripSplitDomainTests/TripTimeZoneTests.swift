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
    #expect(trip.phase(at: now, localTimeZone: "Asia/Tokyo") == .now)
    #expect(trip.timeZone == "America/Los_Angeles")
    #expect(trip.timeZone(for: .init(kind: .leg, id: trip.legs.last!.id)) == "Asia/Tokyo")
  }

  @Test func tripRunsOnDestinationDatesOnceYouAreThere() throws {
    var draft = OnboardingDraft()
    draft.startsOn = "2026-11-01"
    draft.stops = [try stop("Tokyo", zone: "Asia/Tokyo")]
    let trip = try draft.makeTrip()
    let phone = "Asia/Tokyo"
    #expect(trip.phase(at: try instant("2026-10-31T14:59:00Z"), localTimeZone: phone) == .upcoming)
    #expect(trip.phase(at: try instant("2026-10-31T15:00:00Z"), localTimeZone: phone) == .now)
    #expect(trip.phase(at: try instant("2026-11-02T14:59:00Z"), localTimeZone: phone) == .now)
    #expect(trip.phase(at: try instant("2026-11-02T15:00:00Z"), localTimeZone: phone) == .past)
  }

  @Test func tripPlannedFromHomeStartsOnTheHomeDate() throws {
    var draft = OnboardingDraft()
    draft.startsOn = "2026-11-01"
    draft.stops = [try stop("Tokyo", zone: "Asia/Tokyo")]
    let trip = try draft.makeTrip()
    let phone = "Europe/London"
    // Tokyo's already on 1 November, but London isn't.
    let tokyoMidnight = try instant("2026-10-31T15:00:00Z")
    #expect(trip.phase(at: tokyoMidnight, localTimeZone: phone) == .upcoming)
    #expect(trip.currentDay(at: tokyoMidnight, localTimeZone: phone) == nil)
    let londonMidnight = try instant("2026-11-01T00:00:00Z")
    #expect(trip.phase(at: londonMidnight, localTimeZone: phone) == .now)
    #expect(trip.currentDay(at: londonMidnight, localTimeZone: phone)?.date == "2026-11-01")
    // Back home, the last day lasts until London's midnight too.
    #expect(trip.phase(at: try instant("2026-11-02T23:59:00Z"), localTimeZone: phone) == .now)
    #expect(trip.phase(at: try instant("2026-11-03T00:00:00Z"), localTimeZone: phone) == .past)
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
