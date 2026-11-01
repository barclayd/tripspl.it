import Foundation
import Testing
import TripSplitDomain
@testable import TripSplitWatchModel

@MainActor struct WatchNoticesTests {
  /// The demo with the clock at 10:00 on the current trip's fourth day, in Porto.
  func porto() throws -> (WatchModel, TripSnapshot) {
    let model = try WatchModel.demo()
    let trip = try #require(model.timeline.now.first)
    model.now = try at(trip, trip.days[3], hour: 10)
    return (model, trip)
  }

  func at(_ trip: TripSnapshot, _ day: TripDay, hour: Int, minute: Int = 0) throws -> Date {
    let parts = day.date.split(separator: "-").compactMap { Int($0) }
    let zone = trip.timeZone(for: .init(kind: .day, id: day.id))
    return try #require(
      CivilDate.calendar(zone).date(
        from: DateComponents(
          year: parts[0], month: parts[1], day: parts[2], hour: hour, minute: minute)))
  }

  @Test func landingsAreForNewCountriesAtMidday() throws {
    let (model, trip) = try porto()
    let next = try #require(model.timeline.upcoming.first)
    let landings = model.notices.filter { $0.kind == .landed }
    // Lisbon has passed and Porto is the same country, so Seville then Tokyo. Kyoto isn't new.
    let seville = try #require(trip.stops.last)
    let sevilleDay = try #require(trip.days.first { trip.stop(for: .init(kind: .day, id: $0.id)) == seville })
    let tokyo = try #require(next.stops.first)
    #expect(landings.map(\.dayID) == [sevilleDay.id, next.days[0].id])
    #expect(landings[0].title == "Welcome to \(seville.place) \(seville.flag)")
    #expect(landings[0].body == "€1 = £0.86. Convert stays on euros.")
    #expect(landings[0].fireDate == (try at(trip, sevilleDay, hour: 12)))
    #expect(landings[1].title == "Welcome to \(tokyo.place) \(tokyo.flag)")
    #expect(landings[1].body.hasSuffix("Convert is set to yen."))
    #expect(landings[1].fireDate == (try at(next, next.days[0], hour: 12)))
  }

  @Test func wrapsGoOutEachEveningLeft() throws {
    let (model, trip) = try porto()
    let next = try #require(model.timeline.upcoming.first)
    let wraps = model.notices.filter { $0.kind == .eveningWrap }
    #expect(wraps.count == trip.days.count - 3 + next.days.count)
    #expect(wraps[0].id == "wrap.\(trip.id).\(trip.days[3].id)")
    #expect(wraps[0].fireDate == (try at(trip, trip.days[3], hour: 21, minute: 30)))
    let notices = model.notices
    #expect(notices.allSatisfy { $0.fireDate > model.now })
    #expect(notices.map(\.fireDate) == notices.map(\.fireDate).sorted())
  }

  @Test func tonightsWrapIsDroppedOnceItsGone() throws {
    let (model, trip) = try porto()
    model.now = try at(trip, trip.days[3], hour: 21, minute: 31)
    #expect(!model.notices.contains { $0.dayID == trip.days[3].id })
    #expect(model.notices.first?.dayID == trip.days[4].id)
  }

  @Test func eveningWrapCanBeTurnedOff() throws {
    let (model, _) = try porto()
    model.preferences.eveningWrap = false
    #expect(model.notices.map(\.kind) == [.landed, .landed])
  }

  @Test func noticesStopAtTheLimit() throws {
    let model = try WatchModel.demo()
    let trip = try #require(model.timeline.now.first)
    // Six copies of the trip, a fortnight apart, make well over 40 evenings.
    let copies = (1...6).map { index in
      var copy = trip
      copy.id = "\(trip.id)-\(index)"
      copy.startsOn = CivilDate.adding(14 * index, to: trip.startsOn)
      copy.days = trip.days.map {
        var day = $0
        day.date = CivilDate.adding(14 * index, to: $0.date)
        return day
      }
      return copy
    }
    model.receive(.init(trips: model.trips + copies, sentAt: model.now))
    #expect(model.notices.count == 40)
  }

  @Test func wrapSaysWhatTheDayCameTo() throws {
    let (model, trip) = try porto()
    let pages = model.pages(for: trip)
    let day = trip.days[3]
    let wrap = try #require(EveningWrap(pages: pages, dayID: day.id))
    let stop = try #require(pages.stop(day))
    #expect(wrap.title == "Day 4 in \(stop.place) \(stop.flag)")
    let spending = trip.spending(on: day)
    #expect(wrap.spent == WatchCurrency.format(spending.amount, trip.homeCurrency))
    #expect(
      wrap.detail
        == "spent. \(WatchCurrency.whole(spending.left, trip.homeCurrency)) under today's budget.")
    #expect(wrap.body == "\(wrap.spent ?? "") \(wrap.detail)")
    let notice = try #require(model.notices.first { $0.dayID == day.id })
    #expect(notice.lead == wrap.spent)
    #expect(notice.userInfo["lead"] == wrap.spent)
  }

  @Test func wrapAsksWhenNothingsLogged() throws {
    let (model, trip) = try porto()
    let day = try #require(trip.days.last)
    let wrap = try #require(EveningWrap(pages: model.pages(for: trip), dayID: day.id))
    #expect(wrap.spent == nil)
    #expect(wrap.body == "Nothing logged today. Anything to add while it's fresh?")
  }

  @Test func currenciesReadAsEverydayPlurals() {
    #expect(Landed.plural("CHF") == "francs")
    #expect(Landed.plural("EUR") == "euros")
    #expect(Landed.plural("JPY") == "yen")
    #expect(Landed.plural("USD") == "dollars")
  }

  @Test func buttonsOpenTheRightPlace() {
    let info: [AnyHashable: Any] = ["trip": "t", "day": "d"]
    #expect(WatchNotice.link(kind: .landed, action: "convert", userInfo: info) == .localConvert(trip: "t"))
    #expect(WatchNotice.link(kind: .eveningWrap, action: "log", userInfo: info) == .log(trip: "t"))
    #expect(WatchNotice.link(kind: .eveningWrap, action: "day", userInfo: info) == .day(trip: "t", day: "d"))
    // Tapping the notice itself.
    let tap = "com.apple.UNNotificationDefaultActionIdentifier"
    #expect(WatchNotice.link(kind: .landed, action: tap, userInfo: info) == .localConvert(trip: "t"))
    #expect(WatchNotice.link(kind: .eveningWrap, action: tap, userInfo: info) == .day(trip: "t", day: "d"))
    #expect(WatchNotice.link(kind: .eveningWrap, action: tap, userInfo: ["trip": "t"]) == .trip("t", page: .today))
    #expect(WatchNotice.link(kind: .landed, action: tap, userInfo: [:]) == nil)
    // A nudge pushed from the API opens who owes who.
    #expect(WatchNotice.link(kind: .nudge, action: tap, userInfo: ["trip": "t", "traveller": "a"]) == .trip("t", page: .balances))
    #expect(WatchNotice.Kind(category: "tripsplit.nudge") == .nudge)
  }

  @Test func categoriesRoundTrip() {
    for kind in WatchNotice.Kind.allCases {
      #expect(WatchNotice.Kind(category: kind.category) == kind)
    }
    #expect(WatchNotice.Kind(category: "other") == nil)
  }

  @Test func landingFollowsTheTripCurrency() throws {
    let (model, _) = try porto()
    model.convertMemory.pair = .init(from: "USD", to: "GBP")
    model.convertMemory.flipped = true
    model.followTripCurrency()
    #expect(model.convertMemory.pair == nil)
    #expect(!model.convertMemory.flipped)
  }

  @Test func preferencesSavedBeforeTheWrapStillLoad() throws {
    let old = Data(#"{"hidesAmountsWhenWristDown":true}"#.utf8)
    let preferences = try JSONDecoder().decode(WatchPreferences.self, from: old)
    #expect(preferences.hidesAmountsWhenWristDown)
    #expect(preferences.eveningWrap)
  }
}
