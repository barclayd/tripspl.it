import Foundation
import Testing
import TripSplitCompanion
import TripSplitDomain
import TripSplitWatchModel
import TripSplitWidgetModel

@testable import TripSplitApplication

@MainActor struct PhoneWidgetsTests {
  /// The demo trips with only some of them kept, e.g. to be between trips.
  func widgets(
    settings: WidgetSettings = .init(), editing edit: (inout [TripSnapshot], Date) -> Void = { _, _ in }
  ) throws -> PhoneWidgets {
    let demo = try WatchModel.demo()
    var trips = demo.trips
    edit(&trips, demo.now)
    let model = WatchModel(state: .init(context: .init(trips: trips, sentAt: demo.now)))
    model.now = demo.now
    for table in demo.tables.values { model.cache(table) }
    return PhoneWidgets(model: model, settings: settings)
  }

  func betweenTrips(_ trips: inout [TripSnapshot], _ now: Date) {
    trips.removeAll { $0.phase(at: now) == .now }
  }

  @Test func todayShowsWhatsLeftInPorto() throws {
    let widgets = try widgets()
    let trip = try #require(widgets.model.timeline.now.first)
    let day = try #require(trip.currentDay(at: widgets.now))
    let today = try #require(widgets.today(tripID: nil))
    let spending = trip.spending(on: day)
    #expect(today.tripID == trip.id)
    #expect(today.dayID == day.id)
    #expect(today.place == .init(flag: "🇵🇹", code: "PT", name: "Porto"))
    #expect(today.day == 4)
    #expect(today.dayLabel == "Day 4")
    #expect(today.title == "Porto · Day 4")
    #expect(today.budget.spent == spending.amount)
    #expect(today.budget.budget == 30000)
    #expect(today.label == "left today")
    #expect(today.budget.caption == WatchCurrency.whole(spending.amount, "GBP") + " of £300 spent")
    #expect(today.rate == "€1 = £0.86")
    #expect(today.trip.spent == Ledger(trip).total)
  }

  @Test func overBudgetSaysOverAndFillsEverySegment() throws {
    let widgets = try widgets { trips, now in
      let index = trips.firstIndex { $0.phase(at: now) == .now }!
      let trip = trips[index]
      let day = trip.currentDay(at: now)!
      trips[index].expenses.append(
        Expense(
          attachment: .init(kind: .day, id: day.id), title: "Port tasting", category: .food,
          amountMinor: "40000", currency: "GBP", status: .paid, paidOn: day.date,
          paidBy: trip.currentTravellerId, splitWith: [trip.currentTravellerId]))
    }
    let today = try #require(widgets.today(tripID: nil))
    #expect(today.budget.isOver)
    #expect(today.budget.tone == .over)
    #expect(today.label == "over today")
    #expect(today.budget.filled(12) == 12)
    #expect(today.budget.percent == "OVER")
    #expect(today.budget.hero == WatchCurrency.whole(-today.budget.left, "GBP"))
  }

  @Test func budgetSegmentsShowTheShareLeft() {
    let today = BudgetFigures(spent: 5900, budget: 30000, currency: "GBP")
    #expect(today.hero == "£241")
    #expect(today.caption == "£59 of £300 spent")
    #expect(today.filled(12) == 10)
    #expect(today.filled(10) == 8)
    #expect(today.percent == "80%")
    #expect(today.tone == .good)
    let trip = BudgetFigures(spent: 88500, budget: 240000, currency: "GBP")
    #expect(trip.hero == "£1,515")
    #expect(trip.filled(12) == 8)
    #expect(Int((trip.spentFraction * 10).rounded()) == 4)
    #expect(trip.compactSpent == "£885")
    #expect(trip.compactBudget == "2.4k")
    #expect(BudgetFigures(spent: 25000, budget: 30000, currency: "GBP").tone == .low)
  }

  @Test func wholeTripCountsTheTripBudget() throws {
    let widgets = try widgets()
    let today = try #require(widgets.today(tripID: nil, scope: .trip))
    #expect(today.label == "left this trip")
    #expect(today.budget == today.trip)
    #expect(today.budget.budget == 240000)
  }

  @Test func betweenTripsTodayGivesWayToTheCountdown() throws {
    let widgets = try widgets(editing: betweenTrips)
    #expect(widgets.today(tripID: nil) == nil)
    let countdown = try #require(widgets.countdown(tripID: nil))
    #expect(countdown.days == 49)
    #expect(countdown.line == "Tokyo in 49 days")
    #expect(countdown.unit == "days")
    #expect(countdown.caption.hasPrefix("Leaves "))
    #expect(countdown.greeting == "Itterasshai!")
    #expect(!countdown.isDepartureDay)
  }

  @Test func countdownFillsFromWhenTheTripWasFirstSeen() throws {
    let unseen = try widgets()
    let next = try #require(unseen.model.timeline.upcoming.first)
    // Never seen before, nothing has filled yet.
    #expect(unseen.countdown(tripID: next.id)?.filled(10) == 0)
    let today = CivilDate.string(unseen.model.now, timeZone: TimeZone.current.identifier)
    let seen = CivilDate.adding(-49, to: today)
    let widgets = PhoneWidgets(model: unseen.model, settings: .init(firstSeen: [next.id: seen]))
    let countdown = try #require(widgets.countdown(tripID: next.id))
    #expect(countdown.fraction == 0.5)
    #expect(countdown.filled(10) == 5)
  }

  @Test func departureDayWishesYouAGoodTrip() throws {
    let widgets = try widgets { trips, now in
      let today = CivilDate.string(now, timeZone: TimeZone.current.identifier)
      let index = trips.firstIndex { $0.phase(at: now) == .now }!
      let shift = CivilDate.days(from: trips[index].startsOn, to: today)
      trips[index].startsOn = today
      for day in trips[index].days.indices {
        trips[index].days[day].date = CivilDate.adding(shift, to: trips[index].days[day].date)
      }
      for leg in trips[index].legs.indices {
        trips[index].legs[leg].date = CivilDate.adding(shift, to: trips[index].legs[leg].date)
      }
    }
    let countdown = try #require(widgets.countdown(tripID: nil))
    #expect(countdown.isDepartureDay)
    #expect(countdown.greeting == "Boa viagem!")
    #expect(countdown.filled(10) == 10)
    #expect(countdown.firstLeg == "Flights to Lisbon")
  }

  @Test func whereYouAreGroupsDaysByStop() throws {
    let widgets = try widgets()
    let progress = try #require(widgets.progress(tripID: nil))
    #expect(progress.place.name == "Porto")
    #expect(progress.dayOfDays == "Day 4 of \(progress.days)")
    #expect(progress.groups.count == 3)
    #expect(progress.groups.map(\.days.count).prefix(2) == [3, 2])
    #expect(progress.segments.firstIndex(of: .today) == 3)
    #expect(progress.segments.prefix(3).allSatisfy { $0 == .past })
    #expect(progress.next.hasPrefix("Seville on "))
  }

  @Test func whoOwesWhoLeadsWithYou() throws {
    let widgets = try widgets()
    let trip = try #require(widgets.model.timeline.now.first)
    let balances = try #require(widgets.balances(tripID: nil))
    let pages = TripPages(trip: trip, now: widgets.now)
    #expect(balances.tripID == trip.id)
    #expect(balances.balance == pages.ledger.balances[pages.you, default: 0])
    let yours = try #require(balances.yours)
    #expect(balances.rows.first == yours)
    #expect(yours.text.hasSuffix("owes you") || yours.text.hasPrefix("You owe"))
    #expect(balances.label == (balances.balance > 0 ? "OWED" : "OWE"))
  }

  @Test func soloTripsHaveNoBalances() throws {
    let widgets = try widgets { trips, now in
      trips = trips.filter { $0.phase(at: now) == .past }
    }
    #expect(widgets.balances(tripID: nil) == nil)
  }

  @Test func dailySpendComparesDaysWithTheBudget() throws {
    let widgets = try widgets()
    let trip = try #require(widgets.model.timeline.now.first)
    let daily = try #require(widgets.daily(tripID: nil))
    #expect(daily.columns.count == min(trip.days.count, 8))
    #expect(daily.columns.map(\.kind).firstIndex(of: .today) == 3)
    #expect(daily.budgetLabel == "£300 a day")
    #expect(daily.scale >= 40000)
    #expect(daily.columns[4].planned > 0, "Train to Porto is planned for day 5")
    #expect(daily.columns[4].spent == 0)
    #expect(daily.columns[3].spent == trip.spending(on: trip.days[3]).amount)
    #expect(daily.columns.allSatisfy { $0.letter.count == 1 })
  }

  @Test func quickConvertShowsTheMiddlePresets() throws {
    let widgets = try widgets(settings: .init(ratesFetchedAt: Date(timeIntervalSince1970: 0)))
    let convert = try #require(widgets.convert(pair: nil))
    #expect(convert.title == "€ to £")
    #expect(convert.flag == "🇵🇹")
    #expect(convert.code == "PT")
    #expect(convert.rows.map(\.from) == ["€5", "€10", "€20", "€50"])
    #expect(convert.rows.map(\.to) == ["£4.31", "£8.62", "£17.24", "£43.10"])
    #expect(convert.sample == .init(from: "€10", to: "£8.62"))
    #expect(convert.rate == "€1 = £0.862")
    #expect(convert.fetchedAt == Date(timeIntervalSince1970: 0))
  }

  @Test func quickConvertStepsUpForLowValueCurrencies() throws {
    let widgets = try widgets()
    let convert = try #require(widgets.convert(pair: .init(from: "JPY", to: "GBP")))
    #expect(convert.rows.map(\.from) == ["¥500", "¥1,000", "¥2,000", "¥5,000"])
    #expect(convert.rate.hasPrefix("¥100 = £0.50"))
  }

  @Test func swapTurnsThePairAround() throws {
    let widgets = try widgets()
    widgets.model.convertMemory.flipped = true
    #expect(widgets.convert(pair: nil)?.title == "£ to €")
    #expect(widgets.convert(pair: .init(from: "CHF", to: "GBP"))?.title == "£ to CHF")
  }

  @Test func departuresListsTheTripUnderWayThenWhatsNext() throws {
    let widgets = try widgets()
    let board = widgets.departures
    #expect(!board.addTrip)
    #expect(board.rows.first?.destination == "LISBON +2")
    #expect(board.rows.first?.status == "ON TRIP")
    #expect(board.rows.first?.kind == .onTrip)
    #expect(board.rows.last?.status == "IN 49D")
    #expect(board.rows.last?.destination == "TOKYO +1")
  }

  @Test func betweenTripsTheBoardInvitesANewOne() throws {
    let board = try widgets(editing: betweenTrips).departures
    #expect(board.addTrip)
    #expect(board.rows.count == 1)
    #expect(board.rows[0].kind == .upcoming)
  }

  @Test func noTripsLeavesEveryWidgetEmpty() throws {
    let widgets = try widgets { trips, _ in trips = [] }
    #expect(!widgets.hasTrips)
    #expect(widgets.today(tripID: nil) == nil)
    #expect(widgets.countdown(tripID: nil) == nil)
    #expect(widgets.departures.rows.isEmpty)
  }

  @Test func snapshotRoundTripsThroughTheAppGroup() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let mirror = CompanionMirror(directory: directory)
    let demo = try WatchModel.demo()
    let table = try #require(demo.tables["GBP"])
    let fetched = Date(timeIntervalSince1970: 1_000)
    let first = try WidgetSnapshot.write(
      trips: demo.trips, rates: table, ratesFetchedAt: fetched, hidesAmountsWhenLocked: true,
      to: mirror, at: demo.now)
    let today = CivilDate.string(demo.now, timeZone: TimeZone.current.identifier)
    #expect(first.firstSeen.count == demo.trips.count)
    #expect(first.firstSeen.values.allSatisfy { $0 == today })

    // A later write keeps the day each trip was first seen and drops deleted ones.
    let later = try WidgetSnapshot.write(
      trips: Array(demo.trips.dropFirst()), rates: nil, ratesFetchedAt: nil,
      hidesAmountsWhenLocked: false, to: mirror, at: demo.now.addingTimeInterval(86_400 * 3))
    #expect(later.firstSeen.count == demo.trips.count - 1)
    #expect(later.firstSeen.values.allSatisfy { $0 == today })
    #expect(later.ratesFetchedAt == fetched)
    #expect(!later.hidesAmountsWhenLocked)

    let model = WatchModel(state: mirror.load(), mirror: mirror)
    model.now = demo.now
    let widgets = PhoneWidgets(model: model, settings: WidgetSnapshot.settings(in: mirror))
    #expect(widgets.model.trips.count == demo.trips.count - 1)
    #expect(widgets.convert(pair: .init(from: "EUR", to: "GBP"))?.rate == "€1 = £0.862")
  }

  @Test func oldSettingsKeepTheirDefaults() throws {
    let settings = try JSONDecoder().decode(
      WidgetSettings.self, from: Data(#"{"hidesAmountsWhenLocked":true}"#.utf8))
    #expect(settings.hidesAmountsWhenLocked)
    #expect(settings.firstSeen.isEmpty)
    #expect(settings.ratesFetchedAt == nil)
  }
}
