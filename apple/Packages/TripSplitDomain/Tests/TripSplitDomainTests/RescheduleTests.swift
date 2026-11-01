import Foundation
import Testing

@testable import TripSplitDomain

struct RescheduleTests {
  /// A trip from 1 November with a stop for each of `nights`.
  private func trip(_ nights: Int...) throws -> TripSnapshot {
    var draft = OnboardingDraft()
    draft.startsOn = "2026-11-01"
    draft.stops = nights.enumerated().map { Destination.all[$0.offset].stop(nights: $0.element) }
    return try draft.makeTrip()
  }

  private func expense(on day: String, in trip: TripSnapshot) -> Expense {
    Expense(
      attachment: .init(kind: .day, id: day), title: "Dinner", category: .food,
      amountMinor: "100", currency: "GBP", status: .planned, paidBy: trip.ownerTravellerId,
      splitWith: [trip.ownerTravellerId])
  }

  /// Applies the reschedule as the sync queue does.
  private func applying(_ reschedule: TripReschedule, to trip: TripSnapshot) -> TripSnapshot {
    var trip = trip
    Operation(
      syncEpoch: "1", type: "trip.reschedule", entityId: trip.id, payload: .reschedule(reschedule)
    ).apply(to: &trip)
    return trip
  }

  /// The shape the API checks: a day per night and the day home, in order and by stop.
  private func expectValid(_ trip: TripSnapshot) {
    #expect(trip.days.count == trip.stops.reduce(0) { $0 + $1.nights } + 1)
    var stops = trip.stops.flatMap { stop in Array(repeating: stop.id, count: stop.nights) }
    stops.append(trip.stops.last!.id)
    #expect(trip.days.map(\.stopId) == stops)
    #expect(trip.days.indices.allSatisfy { trip.days[$0].date == CivilDate.adding($0, to: trip.startsOn) })
    let days = Set(trip.days.map(\.id))
    #expect(trip.legs.allSatisfy { $0.dayId.map(days.contains) ?? true })
  }

  @Test func planningLaysOutEachStopThenTheDayHome() throws {
    let trip = try trip(3, 2)
    expectValid(trip)
    #expect(trip.days.map(\.date).last == "2026-11-06")
    #expect(trip.legs.map(\.kind) == [.outbound, .transfer, .return])
    #expect(trip.legs.map(\.date) == ["2026-11-01", "2026-11-04", "2026-11-06"])
    #expect(trip.legs.map(\.dayId) == [trip.days[0].id, trip.days[3].id, trip.days[5].id])
    #expect(trip.legs[1].fromStopId == trip.stops[0].id)
    #expect(trip.legs[1].toStopId == trip.stops[1].id)
  }

  @Test func aLaterLongerTripKeepsEveryDayAndItsExpenses() throws {
    var trip = try trip(3)
    trip.expenses = [expense(on: trip.days[1].id, in: trip)]
    let reschedule = trip.rescheduled(leaving: "2027-03-05", home: "2027-03-10")
    #expect(reschedule.stops.map(\.nights) == [5])
    #expect(reschedule.moves.isEmpty)
    #expect(Array(reschedule.days.prefix(3).map(\.id)) == Array(trip.days.prefix(3).map(\.id)))
    #expect(reschedule.days.last?.id == trip.days.last?.id)
    let moved = applying(reschedule, to: trip)
    expectValid(moved)
    #expect(moved.startsOn == "2027-03-05")
    #expect(moved.endsOn == "2027-03-10")
    #expect(moved.legs.map(\.id) == trip.legs.map(\.id))
    #expect(moved.legs.map(\.date) == ["2027-03-05", "2027-03-10"])
    #expect(moved.expenses[0].attachment.id == trip.days[1].id)
    #expect(moved.days[1].date == "2027-03-06")
  }

  @Test func aShorterTripMovesEachDroppedDayToItsStopsLastKeptDay() throws {
    var trip = try trip(3, 3)
    trip.expenses = trip.days.map { expense(on: $0.id, in: trip) }
    let reschedule = trip.rescheduled(leaving: "2026-12-01", home: "2026-12-03")
    #expect(reschedule.stops.map(\.nights) == [1, 1])
    let ids = trip.days.map(\.id)
    #expect(reschedule.days.map(\.id) == [ids[0], ids[3], ids[6]])
    #expect(
      reschedule.moves == [
        .init(fromDayId: ids[1], toDayId: ids[0]), .init(fromDayId: ids[2], toDayId: ids[0]),
        .init(fromDayId: ids[4], toDayId: ids[3]), .init(fromDayId: ids[5], toDayId: ids[3]),
      ])
    let moved = applying(reschedule, to: trip)
    expectValid(moved)
    #expect(
      moved.expenses.map(\.attachment.id) == [ids[0], ids[0], ids[0], ids[3], ids[3], ids[3], ids[6]]
    )
    #expect(moved.legs.map(\.date) == ["2026-12-01", "2026-12-02", "2026-12-03"])
    #expect(moved.legs.map(\.dayId) == [ids[0], ids[3], ids[6]])
  }

  @Test func nightsAreSharedInTheirCurrentProportions() throws {
    let trip = try trip(2, 4)
    #expect(trip.rescheduled(leaving: "2026-11-01", home: "2026-11-10").stops.map(\.nights) == [3, 6])
    // Moving without changing the length keeps every stop's nights.
    let same = trip.rescheduled(leaving: "2027-01-10", home: "2027-01-16")
    #expect(same.stops.map(\.nights) == [2, 4])
    #expect(same.days.map(\.id) == trip.days.map(\.id))
  }

  @Test func aRouteKeepsANightAtEveryStop() throws {
    let trip = try trip(3, 3)
    let reschedule = trip.rescheduled(leaving: "2026-12-05", home: "2026-12-01")
    #expect(reschedule.stops.map(\.nights) == [1, 1])
    expectValid(applying(reschedule, to: trip))
  }

  @Test func aLoneStopCanBecomeADayTrip() throws {
    var trip = try trip(3)
    trip.expenses = [expense(on: trip.days[1].id, in: trip)]
    let reschedule = trip.rescheduled(leaving: "2026-12-01", home: "2026-12-01")
    #expect(reschedule.days.map(\.id) == [trip.days[3].id])
    #expect(reschedule.moves.allSatisfy { $0.toDayId == trip.days[3].id })
    let moved = applying(reschedule, to: trip)
    expectValid(moved)
    #expect(moved.expenses[0].attachment.id == trip.days[3].id)
    #expect(moved.legs.map(\.dayId) == [nil, trip.days[3].id])
  }

  @Test func theOperationRoundTripsAsItsOwnPayload() throws {
    let trip = try trip(2, 1)
    let operation = Operation(
      syncEpoch: "1", type: "trip.reschedule", entityId: trip.id, expectedRevision: 3,
      payload: .reschedule(trip.rescheduled(leaving: "2026-11-05", home: "2026-11-07")))
    let decoded = try JSONDecoder().decode(Operation.self, from: JSONEncoder().encode(operation))
    #expect(decoded.payload == operation.payload)
    let settings = Operation(
      syncEpoch: "1", type: "trip.update", entityId: trip.id, payload: .settings(.init(trip)))
    let other = try JSONDecoder().decode(Operation.self, from: JSONEncoder().encode(settings))
    #expect(other.payload == settings.payload)
  }
}
