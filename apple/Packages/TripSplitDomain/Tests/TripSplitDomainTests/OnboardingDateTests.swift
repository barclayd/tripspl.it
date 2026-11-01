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

  @Test func singleDestinationVisitsReturnCalendarAndSkipsAllocation() {
    var draft = draft()
    #expect(draft.flowSteps == [0, 1, 7, 3, 4, 5, 6])
    #expect(draft.totalSteps == 6)
    draft.step = 1
    draft.advanceStep()
    #expect(draft.step == 7)
    draft.advanceStep()
    #expect(draft.step == 3)
    draft.previousStep()
    #expect(draft.step == 7)
    draft.previousStep()
    #expect(draft.step == 1)
  }

  @Test func multipleDestinationsAllocateAfterChoosingReturn() {
    var draft = draft(multiple: true)
    #expect(draft.flowSteps == [0, 1, 7, 2, 3, 4, 5, 6])
    #expect(draft.totalSteps == 7)
    draft.step = 7
    draft.setReturn("2026-11-09")
    draft.advanceStep()
    #expect(draft.step == 2)
    #expect(draft.stops.map(\.nights) == [3, 5])
    draft.setNights(2, at: 0)
    #expect(draft.unallocatedNights == 1)
    #expect(!draft.canAdvance)
    draft.advanceStep()
    #expect(draft.step == 2)
    draft.setNights(6, at: 1)
    #expect(draft.canAdvance)
    draft.advanceStep()
    #expect(draft.step == 3)
    draft.previousStep()
    #expect(draft.step == 2)
    #expect(draft.stops.map(\.nights) == [2, 6])
  }

  @Test func returnDateDefinesTheCompleteItinerary() throws {
    var draft = draft()
    draft.setReturn("2026-11-08")
    let trip = try draft.makeTrip()
    #expect(draft.stops[0].nights == 7)
    #expect(trip.days.count == 8)
    #expect(trip.days.first?.date == "2026-11-01")
    #expect(trip.endsOn == "2026-11-08")
    #expect(trip.legs.last?.date == "2026-11-08")
  }

  @Test func oneDestinationCanBeADayTrip() throws {
    var draft = draft()
    draft.setReturn(draft.startsOn)
    let trip = try draft.makeTrip()
    #expect(trip.days.count == 1)
    #expect(draft.nights == 0)
    #expect(trip.legs.first?.date == trip.legs.last?.date)
  }

  @Test func dateChangesAndRouteChangesKeepNightsWithinTheChosenDates() {
    var draft = draft(multiple: true)
    draft.setReturn("2026-11-06")
    draft.setDeparture("2026-11-10")
    #expect(draft.returnDate == "2026-11-12")
    #expect(draft.stops.map(\.nights) == [1, 1])
    draft.step = 2
    draft.stops.removeLast()
    draft.reconcileRoute()
    #expect(draft.step == 7)
    #expect(draft.stops[0].nights == 2)
    #expect(draft.returnDate == "2026-11-12")
  }

  @Test func allocationCannotSilentlyExtendTheTrip() throws {
    var draft = draft(multiple: true)
    draft.setReturn("2026-11-07")
    draft.setNights(100, at: 0)
    #expect(draft.nights == 6)
    #expect(draft.returnDate == "2026-11-07")
    draft.setNights(2, at: 0)
    #expect(throws: MoneyError.self) { try draft.makeTrip() }
    let preview = try draft.previewTrip()
    #expect(preview.endsOn == "2026-11-07")
    #expect(draft.unallocatedNights == 1)
  }

  @Test func civilDateDurationIgnoresDaylightSavingClockChanges() throws {
    var draft = draft()
    draft.startsOn = "2026-03-28"
    draft.stops[0].timeZone = "Europe/London"
    draft.setReturn("2026-03-31")
    #expect(draft.totalNights == 3)
    #expect(
      try draft.makeTrip().days.map(\.date) == [
        "2026-03-28", "2026-03-29", "2026-03-30", "2026-03-31",
      ])
  }

  @Test func oldDraftsDecodeWithoutReturnDateOrTimeZones() throws {
    let original = draft(multiple: true)
    let data = try JSONEncoder().encode(original)
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object.removeValue(forKey: "returnsOn")
    var stops = try #require(object["stops"] as? [[String: Any]])
    for index in stops.indices { stops[index].removeValue(forKey: "timeZone") }
    object["stops"] = stops
    let restored = try JSONDecoder().decode(
      OnboardingDraft.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(restored.returnsOn == nil)
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
}
