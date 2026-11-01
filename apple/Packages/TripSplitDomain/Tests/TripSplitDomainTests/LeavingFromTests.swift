import Foundation
import Testing

@testable import TripSplitDomain

struct LeavingFromTests {
  private let dublin = TripOrigin(
    place: "Dublin", countryCode: "IE", latitude: 53.3498, longitude: -6.2603)

  private func draft() -> OnboardingDraft {
    var draft = OnboardingDraft()
    draft.startsOn = "2026-11-01"
    draft.stops = [Destination.all[0].stop(nights: 3)]
    return draft
  }

  @Test func leavingFromSitsBetweenWhereAndWhenAndNeedsAnOrigin() {
    var draft = draft()
    draft.advanceStep()
    #expect(draft.step == 8)
    #expect(draft.stepPosition == 2)
    #expect(!draft.canAdvance)
    draft.advanceStep()
    #expect(draft.step == 8)
    draft.setOrigin(dublin)
    draft.advanceStep()
    #expect(draft.step == 1)
    draft.previousStep()
    #expect(draft.step == 8)
    draft.previousStep()
    #expect(draft.step == 0)
  }

  @Test func leavingFromCountsAsHalfAStep() {
    var draft = draft()
    draft.stops.append(Destination.all[1].stop(nights: 3))
    #expect(draft.progress == 0.05)
    draft.step = 8
    #expect(draft.progress == 0.5 / 6)
    draft.step = 1
    #expect(draft.progress == 1.0 / 6)
    draft.step = 6
    #expect(draft.progress == 1)
  }

  @Test func stepsCompareByTheOrderTheyAreAsked() {
    var draft = draft()
    draft.step = 8
    #expect(draft.reached(0) && draft.reached(8))
    #expect(!draft.reached(1))
    draft.step = 3
    draft.revisit(8)
    #expect(draft.step == 8)
    draft.revisit(1)
    #expect(draft.step == 8)
  }

  @Test func anOriginBecomesHomeCurrencyAndIsSavedOnTheTrip() throws {
    var draft = draft()
    draft.setOrigin(dublin)
    #expect(draft.currency == "EUR")
    draft.currency = "GBP"
    #expect(try draft.makeTrip().origin == dublin)
    #expect(try draft.makeTrip().homeCurrency == "GBP")
  }

  @Test func draftsSavedBeforeTheStepStillOpen() throws {
    var object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(draft())) as? [String: Any])
    object.removeValue(forKey: "origin")
    object["step"] = 3
    let restored = try JSONDecoder().decode(
      OnboardingDraft.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(restored.origin == nil)
    #expect(restored.reached(8))
    #expect(try restored.makeTrip().origin == nil)
  }

  @Test func popularOriginsStartAtHomeThenTheNearestNeighbour() {
    let uk = Destination.origins(region: "gb")
    #expect(uk.count == 7)
    #expect(uk.first?.city == "London")
    #expect(uk.prefix(4).allSatisfy { $0.countryCode == "GB" })
    #expect(uk[4].city == "Dublin", "\(uk.map(\.city))")
    #expect(uk.allSatisfy { !$0.isCountry })
    #expect(Set(uk.map(\.id)).count == uk.count)
    #expect(Destination.origins(region: nil).count == 7)
    #expect(uk.first?.origin.currency == "GBP")
  }

  @Test func originsRoundTripToThePlaceTheyWerePickedFrom() throws {
    let london = try #require(Destination.origins(region: "GB").first)
    #expect(Destination(origin: london.origin) == london)
    let here = TripOrigin(place: "Bath", countryCode: "GB", latitude: 51.4, longitude: -2.4)
    let rebuilt = Destination(origin: here)
    #expect(rebuilt.city == "Bath")
    #expect(rebuilt.country == "United Kingdom")
    #expect(rebuilt.currency == "GBP")
    #expect(rebuilt.origin == here)
  }
}
