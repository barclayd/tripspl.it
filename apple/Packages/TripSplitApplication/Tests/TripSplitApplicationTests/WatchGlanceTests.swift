import Foundation
import Testing
import TripSplitCompanion
import TripSplitDomain
import TripSplitWatchModel

@testable import TripSplitApplication

@MainActor struct WatchGlanceTests {
  /// The demo trips with only some of them kept, e.g. to be between trips.
  func model(keeping keep: (TripTimeline) -> [TripSnapshot]) throws -> WatchModel {
    let demo = try WatchModel.demo()
    let model = WatchModel(state: .init(context: .init(trips: keep(demo.timeline), sentAt: demo.now)))
    model.now = demo.now
    for table in demo.tables.values { model.cache(table) }
    return model
  }

  @Test func onATripShowsTodayInPorto() throws {
    let model = try WatchModel.demo()
    let trip = try #require(model.timeline.now.first)
    let day = try #require(trip.currentDay(at: model.now))
    let glance = WatchGlance(model: model)
    #expect(glance.context == .onTrip)
    #expect(glance.symbol == "£")
    let today = try #require(glance.today)
    #expect(today.tripID == trip.id)
    #expect(today.place == .init(flag: "🇵🇹", code: "PT", name: "Porto"))
    #expect(today.title == "Porto · Day 4")
    #expect(today.bezel == "PORTO · DAY 4")
    #expect(today.progress == "4/\(trip.days.count)")
    let spending = trip.spending(on: day)
    #expect(today.daily.spent == spending.amount)
    #expect(today.daily.budget == trip.dailyBudget)
    #expect(today.leftLine == WatchCurrency.whole(spending.left, "GBP") + " left today")
    #expect(today.trip.spent == Ledger(trip).total)
    #expect(glance.total?.spent == Ledger(trip).total)
    #expect(glance.countdown?.tripID == model.timeline.upcoming.first?.id)
  }

  @Test func quickConvertShowsTheLastAmountAndItsResult() throws {
    let model = try WatchModel.demo()
    let conversion = try #require(WatchGlance(model: model).conversion)
    #expect(conversion.line == "€10 = £8.62")
    #expect(conversion.rate == "€1 = £0.86")
    #expect(conversion.place?.code == "PT")
    model.convertMemory.amount = "24"
    #expect(WatchGlance(model: model).conversion?.line == "€24 = £20.69")
  }

  @Test func lowValueCurrenciesStepUpTheirRate() throws {
    let model = try WatchModel.demo()
    model.convertMemory.pair = .init(from: "JPY", to: "GBP")
    #expect(WatchGlance(model: model).conversion?.rate == "¥100 = £0.50")
  }

  @Test func whoOwesWhoLeadsWithYou() throws {
    let model = try WatchModel.demo()
    let trip = try #require(model.timeline.now.first)
    let glance = WatchGlance(model: model)
    let ledger = Ledger(trip)
    #expect(glance.owed?.tripID == trip.id)
    #expect(glance.owed?.balance == ledger.balances[trip.currentTravellerId, default: 0])
    let lines = try #require(glance.balances?.lines)
    #expect((1...2).contains(lines.count))
    let you = trip.currentTravellerId
    let mine = ledger.settlements.contains { $0.from == you || $0.to == you }
    if mine { #expect(lines[0].tone != .others) }
  }

  @Test func dailySpendMarksTodayAgainstTheBudgetLine() throws {
    let model = try WatchModel.demo()
    let trip = try #require(model.timeline.now.first)
    let daily = try #require(WatchGlance(model: model).daily)
    #expect(daily.bars.count == min(trip.days.count, 10))
    #expect(daily.bars.filter { $0.kind == .today }.map(\.number) == [4])
    #expect(daily.bars.filter { $0.kind == .past }.map(\.number) == [1, 2, 3])
    #expect(daily.bars.filter { $0.kind == .future }.allSatisfy { $0.amount == 0 })
    #expect(daily.bars.allSatisfy { (0...1).contains($0.height) })
    #expect((0...1).contains(daily.budgetLine))
    #expect(daily.budgetLabel == WatchCurrency.whole(trip.dailyBudget, "GBP") + "/day")
  }

  @Test func betweenTripsCountsDownAndConvertsForTheNextOne() throws {
    let model = try model { $0.upcoming + $0.past }
    let next = try #require(model.timeline.upcoming.first)
    let glance = WatchGlance(model: model)
    #expect(glance.context == .between)
    #expect(glance.today == nil)
    #expect(glance.total == nil)
    #expect(glance.daily == nil)
    let countdown = try #require(glance.countdown)
    #expect(countdown.tripID == next.id)
    #expect(countdown.days == next.daysUntilStart(from: CivilDate.string(model.now)))
    #expect(countdown.unit == "DAYS")
    #expect(countdown.place.flag == next.stops.first?.flag)
    #expect(glance.conversion?.from.hasPrefix("¥") == true)
    // Owed falls back to the last trip still unsettled.
    let unsettled = model.timeline.past.first {
      Ledger($0).balances[$0.currentTravellerId, default: 0] != 0
    }
    #expect(glance.owed?.tripID == (unsettled ?? next).id)
  }

  @Test func withoutTripsThereIsNothingToShow() throws {
    let glance = WatchGlance(model: WatchModel())
    #expect(glance.context == .noTrips)
    #expect(glance.today == nil)
    #expect(glance.conversion == nil)
    #expect(glance.countdown == nil)
    #expect(glance.owed == nil)
    #expect(glance.masked == "£•••")
  }

  @Test func remainingTurnsAmberThenRedAndSaysOver() {
    let plenty = WatchGlance.Remaining(spent: 5_900, budget: 30_000, currency: "GBP")
    #expect(plenty.amount == "£241")
    #expect(plenty.percent == "80%")
    #expect(plenty.level == .good)
    let low = WatchGlance.Remaining(spent: 24_000, budget: 30_000, currency: "GBP")
    #expect(low.level == .low)
    let over = WatchGlance.Remaining(spent: 34_000, budget: 30_000, currency: "GBP")
    #expect(over.level == .out)
    #expect(over.fraction == 0)
    #expect(over.percent == "OVER")
    #expect(over.amount == "-£40")
  }

  @Test func totalShowsAPercentageOnceOver() {
    let total = WatchGlance.Total(tripID: "", spent: 297_600, budget: 240_000, currency: "GBP")
    #expect(total.isOver)
    #expect(total.amount == "£3.0k")
    #expect(total.budgetLabel == "2.4k")
    #expect(total.percent == "124%")
  }

  @Test func countdownSaysDayOnTheLastOne() {
    let place = WatchGlance.Place(flag: "🇨🇭", code: "CH", name: "Zurich")
    #expect(WatchGlance.Countdown(tripID: "", place: place, days: 45).unit == "DAYS")
    #expect(WatchGlance.Countdown(tripID: "", place: place, days: 1).unit == "DAY")
  }

  @Test func owedSaysWhichWayItRuns() {
    #expect(WatchGlance.Owed(tripID: "", balance: 6_600, currency: "GBP").label == "OWED")
    #expect(WatchGlance.Owed(tripID: "", balance: -3_000, currency: "GBP").amount == "£30")
    #expect(WatchGlance.Owed(tripID: "", balance: -3_000, currency: "GBP").corner == "YOU OWE")
    #expect(WatchGlance.Owed(tripID: "", balance: 0, currency: "GBP").label == "EVEN")
    #expect(WatchGlance.Owed(tripID: "", balance: 6_600, currency: "GBP").corner == "OWES YOU")
  }

  @Test func compactAmountsFitARing() {
    #expect(WatchGlance.compact(24_100, "GBP") == "£241")
    #expect(WatchGlance.compact(300_000, "GBP") == "£3.0k")
    #expect(WatchGlance.compact(240_000, "GBP", symbol: false) == "2.4k")
    #expect(WatchGlance.compact(2_400_000, "GBP") == "£24k")
    #expect(WatchGlance.compact(120_000_000, "GBP") == "£1.2m")
    #expect(WatchGlance.compact(1_200_000, "JPY", symbol: false) == "1.2m")
  }

  @Test func flagsSpellTheirCountry() {
    #expect(WatchGlance.regionCode("🇵🇹") == "PT")
    #expect(WatchGlance.regionCode("🇨🇭") == "CH")
    #expect(WatchGlance.regionCode("€") == nil)
  }

  @Test func hidingAmountsIsKeptOnTheWatch() throws {
    let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
    var changes = 0
    let model = WatchModel(mirror: CompanionMirror(directory: directory))
    model.onChange = { changes += 1 }
    model.preferences.hidesAmountsWhenWristDown = true
    #expect(changes == 1)
    #expect(WatchGlance(model: model).hidesAmounts)
    let reopened = WatchModel(mirror: CompanionMirror(directory: directory))
    #expect(reopened.preferences.hidesAmountsWhenWristDown)
  }
}

struct WatchLinkTests {
  @Test func linksRoundTrip() {
    let links: [WatchLink] = [
      .trips, .trip("abc"), .trip("abc", page: .budget), .trip("abc", page: .balances), .convert,
      .log(), .log(trip: "abc"), .localConvert(trip: "abc"), .day(trip: "abc", day: "d1"),
    ]
    for link in links { #expect(WatchLink(url: link.url) == link) }
  }

  @Test func linksReadAsURLs() {
    #expect(WatchLink.trip("abc", page: .today).url.absoluteString == "tripsplit://trip/abc?page=today")
    #expect(WatchLink.convert.url.absoluteString == "tripsplit://convert")
  }

  @Test func otherURLsAreIgnored() throws {
    #expect(WatchLink(url: try #require(URL(string: "https://tripspl.it/trip/abc"))) == nil)
    #expect(WatchLink(url: try #require(URL(string: "tripsplit://nowhere"))) == nil)
    #expect(WatchLink(url: try #require(URL(string: "tripsplit://trip/"))) == nil)
    #expect(
      WatchLink(url: try #require(URL(string: "tripsplit://trip/abc?page=nope"))) == .trip("abc"))
  }
}
