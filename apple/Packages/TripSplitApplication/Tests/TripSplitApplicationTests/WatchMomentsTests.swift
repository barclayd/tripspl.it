import Foundation
import Testing
import TripSplitCompanion
import TripSplitDomain
import TripSplitWatchModel

@MainActor struct WatchMomentsTests {
  /// Noon, local time, `days` after the trip's last day.
  func after(_ trip: TripSnapshot, days: Int) throws -> Date {
    let day = CivilDate.adding(days, to: trip.endsOn)
    let parts = day.split(separator: "-").compactMap { Int($0) }
    return try #require(
      Calendar.current.date(
        from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)))
  }

  @Test func firstSyncWelcomesTheCurrentTripOnce() throws {
    let demo = try WatchModel.demo()
    let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = WatchModel(mirror: CompanionMirror(directory: directory))
    model.now = demo.now
    #expect(model.moment == nil)
    model.receive(.init(trips: demo.trips, sentAt: demo.now))
    let current = try #require(model.currentTrip)
    #expect(model.moment == .arrived(tripID: current.id))
    // Trips that were over before the watch knew about them are never stamped.
    #expect(model.moments.stamped == Set(demo.timeline.past.map(\.id)))
    let mirror = CompanionMirror(directory: directory)
    let reopened = WatchModel(state: mirror.load(), mirror: mirror)
    reopened.now = demo.now
    #expect(reopened.moment == .arrived(tripID: current.id))
    model.dismiss(.arrived(tripID: current.id))
    #expect(model.moment == nil)
    model.receive(.init(trips: demo.trips, sentAt: demo.now.addingTimeInterval(1)))
    #expect(model.moment == nil)
  }

  @Test func aWatchWithTripsAlreadyHasItsWelcome() throws {
    let demo = try WatchModel.demo()
    #expect(demo.moments.welcomed)
    #expect(demo.moment == nil)
  }

  @Test func tripsAreStampedOnceTheMorningAfter() throws {
    let model = try WatchModel.demo()
    let trip = try #require(model.timeline.now.first)
    model.now = try after(trip, days: 0)
    #expect(model.moment == nil)
    model.now = try after(trip, days: 1)
    #expect(model.moment == .stamped(tripID: trip.id))
    model.dismiss(.stamped(tripID: trip.id))
    #expect(model.moment == nil)
  }

  @Test func oldTripsAreNotStamped() throws {
    let model = try WatchModel.demo()
    let trip = try #require(model.timeline.now.first)
    model.now = try after(trip, days: 3)
    #expect(model.moment == .stamped(tripID: trip.id))
    model.now = try after(trip, days: 4)
    #expect(model.moment == nil)
  }

  @Test func wrapUpSaysWhatTheTripCameToAndWhoStillOwes() throws {
    let model = try WatchModel.demo()
    let trip = try #require(model.timeline.now.first)
    let pages = model.pages(for: trip)
    let wrap = TripWrapUp(pages: pages)
    #expect(wrap.headline == "Stamped. \(WatchCurrency.whole(pages.spent, "GBP")) all in.")
    #expect(wrap.places == trip.stops.map { $0.place.uppercased() }.joined(separator: "·"))
    #expect(wrap.flags == trip.stops.map(\.flag).reduce(into: []) { if !$0.contains($1) { $0.append($1) } })
    let balances = pages.ledger.balances
    if let yours = balances[pages.you], yours < 0 {
      #expect(wrap.detail.hasPrefix("You still owe "))
    } else if let debtor = balances.min(by: { $0.value < $1.value }), debtor.value < 0 {
      #expect(wrap.detail == "\(pages.name(debtor.key)) still owes \(WatchCurrency.whole(-debtor.value, "GBP")) in total.")
    }
    let owed = pages.settlements.filter { $0.to == pages.you }.max { $0.amount < $1.amount }
    #expect(wrap.debtor?.id == owed?.from)
  }

  @Test func dateRangesDropWhatRepeats() throws {
    var trip = try #require(try WatchModel.demo().timeline.now.first)
    trip.startsOn = "2026-10-28"
    trip.days[trip.days.count - 1].date = "2026-11-04"
    #expect(trip.dateRange() == "28 Oct – 4 Nov")
    #expect(trip.dateRange(withYear: true) == "28 Oct – 4 Nov 2026")
    trip.startsOn = "2026-11-01"
    #expect(trip.dateRange() == "1 – 4 Nov")
    trip.startsOn = "2026-12-28"
    trip.days[trip.days.count - 1].date = "2027-01-04"
    #expect(trip.dateRange() == "28 Dec 2026 – 4 Jan 2027")
  }
}
