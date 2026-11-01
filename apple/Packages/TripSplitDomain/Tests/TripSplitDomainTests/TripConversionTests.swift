import Foundation
import Testing

@testable import TripSplitDomain

struct TripConversionTests {
  private func trip() throws -> TripSnapshot {
    var draft = OnboardingDraft()
    draft.stops = [
      try #require(Destination.search("London").first).stop(nights: 1),
      try #require(Destination.search("Rome").first).stop(nights: 1),
    ]
    draft.currency = "GBP"
    return try draft.makeTrip()
  }

  @Test func homeShortcutFollowsTheCurrentDayCurrency() throws {
    let trip = try trip()
    #expect(!trip.showsHomeConverter(on: trip.days[0].date))
    #expect(trip.showsHomeConverter(on: trip.days[1].date))
    #expect(!trip.showsHomeConverter(on: "1900-01-01"))
    #expect(!trip.showsHomeConverter(on: "2999-01-01"))
  }

  @Test func openingDefaultsFollowCurrentStopAndHome() throws {
    let trip = try trip()
    let london = trip.conversionDefaults(on: trip.days[0].date)
    #expect(london.from.code == "GBP")
    #expect(london.to.code == "GBP")
    let rome = trip.conversionDefaults(on: trip.days[1].date)
    #expect(rome.from.code == "EUR")
    #expect(rome.from.countryCode == "IT")
    #expect(rome.from.place == "Rome")
    #expect(rome.to.code == "GBP")
    let planning = trip.conversionDefaults(on: "1900-01-01")
    #expect(planning.from.code == "GBP")
  }

  @Test func sharedCurrencyHidesShortcutAcrossDifferentCountries() throws {
    var trip = try trip()
    trip.homeCurrency = "EUR"
    #expect(!trip.showsHomeConverter(on: trip.days[1].date))
    #expect(trip.showsHomeConverter(on: trip.days[0].date))
  }

  @Test func abroadMeansADayAwayFromTheHomeCurrency() throws {
    let trip = try trip()
    #expect(!trip.isAbroad(.init(kind: .day, id: trip.days[0].id)))
    #expect(trip.isAbroad(.init(kind: .day, id: trip.days[1].id)))
    #expect(!trip.isAbroad(.init(kind: .leg, id: trip.legs[0].id)))
  }

  @Test func missingStopDoesNotProduceAnEmptyShortcut() throws {
    var trip = try trip()
    trip.stops = []
    #expect(!trip.showsHomeConverter(on: trip.days[0].date))
    let defaults = trip.conversionDefaults(on: trip.days[0].date)
    #expect(defaults.from.code == "GBP")
    #expect(defaults.to.code == "GBP")
  }
}
