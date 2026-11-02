import Foundation
import Testing

@testable import TripSplitDomain

struct ReturnTicketTests {
  private func trip() throws -> TripSnapshot {
    var draft = OnboardingDraft()
    draft.stops = [try #require(Destination.search("Lisbon").first).stop(nights: 3)]
    draft.currency = "GBP"
    draft.travellers += [Traveller(name: "Maya", hue: 250)]
    draft.startsOn = CivilDate.adding(10, to: CivilDate.today(timeZone: "UTC"))
    return try draft.makeTrip()
  }

  private func leg(_ trip: TripSnapshot, _ kind: TravelLeg.Kind) throws -> TripSplitDomain.Attachment {
    .init(kind: .leg, id: try #require(trip.legs.first { $0.kind == kind }).id)
  }

  private func flight(
    _ trip: TripSnapshot, on attachment: TripSplitDomain.Attachment, amount: String = "42001",
    currency: String = "GBP", conversion: Conversion? = nil
  ) -> Expense {
    Expense(
      attachment: attachment, title: "Return flight", category: .flight, amountMinor: amount,
      currency: currency, status: .planned, paidBy: trip.travellers[0].id,
      splitWith: trip.travellers.map(\.id), conversion: conversion)
  }

  @Test func onlyTravelThereAndBackBeforeYouGoIsAsked() throws {
    let trip = try trip()
    let out = try leg(trip, .outbound)
    #expect(trip.asksReturn(.flight, on: out))
    #expect(trip.asksReturn(.train, on: out))
    #expect(trip.asksReturn(.transport, on: out))
    #expect(!trip.asksReturn(.taxi, on: out))
    #expect(!trip.asksReturn(.stay, on: out))
    #expect(!trip.asksReturn(.flight, on: try leg(trip, .return)))
    #expect(!trip.asksReturn(.flight, on: .init(kind: .day, id: trip.days[0].id)))
    var oneWay = trip
    oneWay.legs.removeAll { $0.kind == .return }
    #expect(!oneWay.asksReturn(.flight, on: out))
  }

  @Test func aReturnSplitsAcrossTheTripWithTheOddPennyGoingOut() throws {
    var trip = try trip()
    let whole = flight(
      trip, on: try leg(trip, .outbound), amount: "48301", currency: "EUR",
      conversion: .init(
        homeAmountMinor: "42001", rate: "0.8696", rateDate: trip.startsOn, source: "Test",
        kind: "reference"))
    let halves = try #require(trip.splitReturn(whole))
    #expect(halves.map(\.amountMinor) == ["24151", "24150"])
    #expect(halves.map { $0.conversion?.homeAmountMinor } == ["21001", "21000"])
    #expect(halves.map(\.conversion?.rate) == ["0.8696", "0.8696"])
    #expect(halves.map(\.attachment) == [try leg(trip, .outbound), try leg(trip, .return)])
    #expect(halves[0].id == whole.id)
    #expect(halves[1].id != whole.id)
    #expect(halves.map(\.returnPairId) == [whole.id, whole.id])
    #expect(halves.allSatisfy { $0.title == "Return flight" && $0.splitWith == whole.splitWith })

    trip.expenses = halves
    let (out, back) = try #require(trip.returnHalves(of: halves[1]))
    #expect(out == halves[0] && back == halves[1])
    let rejoined = trip.wholeTicket(back)
    #expect(rejoined.id == whole.id && rejoined.attachment == whole.attachment)
    #expect(rejoined.amountMinor == "48301")
    #expect(rejoined.conversion?.homeAmountMinor == "42001")
    #expect(trip.ticket(of: out).map(\.id) == halves.map(\.id))

    // Splitting it again keeps both halves' ids and revisions, so it edits in place.
    var edited = rejoined
    edited.amountMinor = "50000"
    trip.expenses[1].revision = 3
    let again = try #require(trip.splitReturn(edited, back: trip.expenses[1]))
    #expect(again.map(\.id) == halves.map(\.id))
    #expect(again[1].revision == 3)
    #expect(again.map(\.amountMinor) == ["25000", "25000"])
  }

  @Test func aLoneHalfIsAPlainExpense() throws {
    var trip = try trip()
    let halves = try #require(trip.splitReturn(flight(trip, on: try leg(trip, .outbound))))
    trip.expenses = [halves[0]]
    #expect(trip.returnHalves(of: halves[0]) == nil)
    #expect(trip.wholeTicket(halves[0]) == halves[0])
    #expect(trip.ticket(of: halves[0]) == [halves[0]])
  }

  @Test func aHalfWithoutAHomeRateLeavesTheWholeUnconverted() throws {
    var trip = try trip()
    let whole = flight(
      trip, on: try leg(trip, .outbound), currency: "EUR",
      conversion: .init(
        homeAmountMinor: "36000", rate: "0.8571", rateDate: trip.startsOn, source: "Test",
        kind: "reference"))
    var halves = try #require(trip.splitReturn(whole))
    halves[1].conversion = nil
    trip.expenses = halves
    #expect(trip.wholeTicket(halves[0]).conversion == nil)
    #expect(trip.wholeTicket(halves[0]).amountMinor == "42001")
  }

  @Test func thePairSurvivesSavingAndSyncing() throws {
    var trip = try trip()
    let plain = flight(trip, on: try leg(trip, .outbound))
    let halves = try #require(trip.splitReturn(plain))
    trip.expenses = halves + [plain]
    let decoded = try JSONDecoder().decode(TripSnapshot.self, from: JSONEncoder().encode(trip))
    #expect(decoded.expenses == trip.expenses)
    #expect(decoded.returnHalves(of: halves[1])?.out == halves[0])
    // A plain expense goes out without the key, as the API takes it as optional but never null.
    let json = try #require(String(data: JSONEncoder().encode(plain), encoding: .utf8))
    #expect(!json.contains("returnPairId"))
  }
}
