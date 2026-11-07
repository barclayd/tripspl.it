import Foundation
import Testing
@testable import TripSplitDomain

struct DayLocationTests {
  private let location = TripOrigin(place: "Kamakura", countryCode: "JP", latitude: 35.319, longitude: 139.55)

  private func trip() throws -> TripSnapshot {
    var draft = OnboardingDraft()
    draft.startsOn = "2026-11-01"
    draft.stops = [try #require(Destination.country("JP")).stop(nights: 3)]
    return try draft.makeTrip()
  }

  @Test func legacyDaysKeepTheirWireShapeAndResetIsExplicit() throws {
    let day = TripDay(id: "day", date: "2026-11-01", stopId: "stop")
    let data = try JSONEncoder().encode(day)
    let fields = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(fields.keys) == ["id", "date", "stopId"])
    #expect(try JSONDecoder().decode(TripDay.self, from: data).location == nil)
    let reset = Operation(syncEpoch: "epoch", type: "day.location", entityId: "day",
      expectedRevision: 1, payload: .dayLocation(.init(location: nil)))
    let encoded = try JSONEncoder().encode(reset)
    #expect(String(decoding: encoded, as: UTF8.self).contains("\"location\":null"))
    #expect(try JSONDecoder().decode(Operation.self, from: encoded) == reset)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(DayLocationUpdate.self, from: Data("{}".utf8))
    }
  }

  @Test func onlyTheChosenDayChangesAndResetRestoresItsStop() throws {
    var trip = try trip()
    let original = trip
    let first = trip.days[0]
    Operation(syncEpoch: "local", type: "day.location", entityId: first.id,
      payload: .dayLocation(.init(location: location))).apply(to: &trip)
    #expect(trip.location(for: trip.days[0]) == location)
    #expect(trip.days.dropFirst() == original.days.dropFirst())
    #expect(trip.stops == original.stops)
    Operation(syncEpoch: "local", type: "day.location", entityId: first.id,
      payload: .dayLocation(.init(location: nil))).apply(to: &trip)
    #expect(trip.days == original.days)
    #expect(trip.location(for: first)?.place == original.stops[0].place)
  }

  @Test func settingsAndReschedulesPreserveOverridesByDayID() throws {
    var trip = try trip()
    let legacy = TripSettings(trip)
    trip.days[0].location = location
    trip.days[0].locationRevision = 3
    Operation(syncEpoch: "local", type: "trip.update", entityId: trip.id,
      payload: .settings(legacy)).apply(to: &trip)
    #expect(trip.days[0].location == location)
    var moved = trip.rescheduled(leaving: "2026-12-01", home: "2026-12-04")
    #expect(moved.days[0].location == location)
    moved.days[0].location = nil // An older client omits this field.
    moved.days[0].locationRevision = nil
    Operation(syncEpoch: "local", type: "trip.reschedule", entityId: trip.id,
      payload: .reschedule(moved)).apply(to: &trip)
    #expect(trip.days[0].location == location)
    #expect(trip.days[0].locationRevision == 3)
    #expect(trip.days[0].date == "2026-12-01")
  }
}
