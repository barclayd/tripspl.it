import Foundation
import Testing

@testable import TripSplitDomain

struct OnboardingDateTests {
  private func draft(multiple: Bool = false) -> OnboardingDraft {
    var draft = OnboardingDraft()
    draft.startsOn = "2026-11-01"
    draft.stops = [Destination.all[0].stop(nights: 3)]
    if multiple { draft.stops.append(Destination.all[1].stop(nights: 3)) }
    return draft
  }

  @Test func onlyARouteWithSeveralStopsAsksHowLongInEachPlace() {
    var single = draft()
    #expect(single.flowSteps == [0, 8, 1, 3, 4, 5, 6])
    #expect(single.totalSteps == 6)
    single.step = 1
    single.advanceStep()
    #expect(single.step == 3)
    single.previousStep()
    #expect(single.step == 1)

    var route = draft(multiple: true)
    #expect(route.flowSteps == [0, 8, 1, 2, 3, 4, 5, 6])
    route.step = 1
    route.advanceStep()
    #expect(route.step == 2)
    route.advanceStep()
    #expect(route.step == 3)
    route.previousStep()
    #expect(route.step == 2)
  }

  @Test func droppingToOneStopSkipsHowLong() {
    var draft = draft(multiple: true)
    draft.step = 2
    draft.stops.removeLast()
    draft.reconcileRoute()
    #expect(draft.step == 1)
  }

  @Test func aThirteenDayTripCanBePickedFromTheCalendar() throws {
    var draft = draft()
    draft.setReturn("2026-11-13")
    #expect(draft.nights == 12)
    #expect(draft.days == 13)
    #expect(draft.returnDate == "2026-11-13")
    draft.step = 1
    #expect(draft.canAdvance)
    #expect(try draft.makeTrip().endsOn == "2026-11-13")
  }

  @Test func movingTheDepartureKeepsTheTripLength() {
    var draft = draft()
    draft.setReturn("2026-11-13")
    draft.setDeparture("2026-12-01")
    #expect(draft.returnDate == "2026-12-13")
  }

  @Test func returnDatesSplitNightsInProportionAcrossStops() {
    var draft = draft(multiple: true)
    draft.stops.append(Destination.all[2].stop(nights: 2))
    draft.setReturn("2026-11-17")
    #expect(draft.stops.map(\.nights) == [6, 6, 4])
    draft.setReturn("2026-11-03")
    #expect(draft.stops.map(\.nights) == [1, 1, 1])
    #expect(draft.returnDate == "2026-11-04")
    draft.setReturn("2026-11-06")
    #expect(draft.stops.map(\.nights) == [2, 2, 1])
  }

  @Test func tripsStopAtAYear() {
    var draft = draft()
    draft.setReturn("2028-01-01")
    #expect(draft.nights == OnboardingDraft.maximumNights)
  }

  @Test func pickingAnEarlierStartKeepsTheDayHome() {
    var draft = draft()
    draft.setDates(leaving: "2026-10-30", home: draft.returnDate)
    #expect(draft.startsOn == "2026-10-30")
    #expect(draft.returnDate == "2026-11-04")
  }

  @Test func howLongMovesNightsBetweenStopsWithoutChangingTheDates() {
    var draft = draft(multiple: true)
    draft.stops.append(Destination.all[2].stop(nights: 1))
    let home = draft.returnDate
    draft.shiftNight(at: 0, by: 1)
    #expect(draft.stops.map(\.nights) == [4, 2, 1])
    draft.shiftNight(at: 0, by: 2)
    #expect(draft.stops.map(\.nights) == [5, 1, 1])
    #expect(!draft.canShiftNight(at: 0, by: 1))
    draft.shiftNight(at: 2, by: -1)
    #expect(draft.stops.map(\.nights) == [5, 1, 1])
    draft.shiftNight(at: 2, by: 1)
    #expect(draft.stops.map(\.nights) == [4, 1, 2])
    draft.shiftNight(at: 0, by: -1)
    #expect(draft.stops.map(\.nights) == [3, 2, 2])
    #expect(draft.returnDate == home)
  }

  @Test func nightsDefineTheReturnDate() throws {
    var draft = draft(multiple: true)
    draft.setNights(4, at: 1)
    #expect(draft.nights == 7)
    #expect(draft.days == 8)
    #expect(draft.returnDate == "2026-11-08")
    let trip = try draft.makeTrip()
    #expect(trip.days.count == 8)
    #expect(trip.endsOn == "2026-11-08")
    #expect(trip.legs.map(\.date) == ["2026-11-01", "2026-11-04", "2026-11-08"])
  }

  @Test func nightsStayWithinOneToAYearPerStop() {
    var draft = draft(multiple: true)
    draft.setNights(0, at: 0)
    #expect(draft.stops[0].nights == 1)
    draft.setNights(400, at: 1)
    #expect(draft.stops[1].nights == OnboardingDraft.maximumNights)
  }

  @Test func oneDestinationCanBeADayTrip() throws {
    var draft = draft()
    draft.setNights(0, at: 0)
    let trip = try draft.makeTrip()
    #expect(trip.days.count == 1)
    #expect(draft.nights == 0)
    #expect(trip.legs.first?.date == trip.legs.last?.date)
  }

  @Test func addingAStopLiftsADayTripToANight() {
    var draft = draft()
    draft.setNights(0, at: 0)
    draft.stops.append(Destination.all[1].stop())
    draft.reconcileRoute()
    #expect(draft.stops.map(\.nights) == [1, 3])
  }

  @Test func civilDateDurationIgnoresDaylightSavingClockChanges() throws {
    var draft = draft()
    draft.startsOn = "2026-03-28"
    draft.stops[0].timeZone = "Europe/London"
    #expect(
      try draft.makeTrip().days.map(\.date) == [
        "2026-03-28", "2026-03-29", "2026-03-30", "2026-03-31",
      ])
  }

  @Test func draftsFromTheReturnDateFlowResumeOnHowLong() throws {
    var original = draft(multiple: true)
    original.step = 7
    let data = try JSONEncoder().encode(original)
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["returnsOn"] = "2026-11-09"
    var stops = try #require(object["stops"] as? [[String: Any]])
    for index in stops.indices { stops[index].removeValue(forKey: "timeZone") }
    object["stops"] = stops
    var restored = try JSONDecoder().decode(
      OnboardingDraft.self, from: JSONSerialization.data(withJSONObject: object))
    restored.reconcileRoute()
    #expect(restored.step == 2)
    #expect(restored.returnDate == "2026-11-07")
    #expect(restored.stops.allSatisfy { $0.timeZone == nil })
    #expect(try restored.makeTrip().days.count == 7)
  }

  @Test func completedDraftKeepsItsPersistedStepIdentity() {
    var draft = draft()
    draft.step = 6
    draft.previousStep()
    #expect(draft.step == 6)
    #expect(draft.stepPosition == draft.totalSteps)
  }

  @Test func revisitingOnlyJumpsBackToAnsweredSteps() {
    var draft = draft()
    draft.step = 4
    draft.revisit(5)
    #expect(draft.step == 4)
    draft.revisit(1)
    #expect(draft.step == 1)
    draft.revisit(-1)
    #expect(draft.step == 1)
    draft.step = 6
    draft.revisit(0)
    #expect(draft.step == 6)
  }

  @Test func budgetSuggestionScalesWithDaysPeopleAndCurrency() {
    var draft = draft()
    draft.travellers.append(Traveller(name: "Maya"))
    // 4 days × 2 people × £75 = £600.
    #expect(draft.suggestedBudget(homePerGBP: 1) == 600)
    // £600 at 1.16 is 696, rounded to the nearest 50.
    #expect(draft.suggestedBudget(homePerGBP: 1.16) == 700)
    draft.stops[0].nights = 0
    #expect(draft.suggestedBudget(homePerGBP: 0.5) == 100)
  }

  @Test func freshDraftsLeaveTheBudgetToBeSuggested() {
    #expect(OnboardingDraft.newTrip().budget.isEmpty)
  }

  @Test func tripNamesListPlacesInOrder() {
    var draft = draft(multiple: true)
    let first = draft.stops[0].place
    let second = draft.stops[1].place
    #expect(draft.tripName == "\(first) & \(second)")
    draft.stops.append(Destination.all[2].stop())
    #expect(draft.tripName == "\(first), \(second) & \(draft.stops[2].place)")
    draft.name = "Big one"
    #expect(draft.tripName == "Big one")
  }
}
