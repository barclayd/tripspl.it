import Foundation
import Testing
import TripSplitCompanion
import TripSplitCompanionHost
import TripSplitDomain
import TripSplitWatchModel

@testable import TripSplitApplication
@testable import TripSplitPersistence

@Suite(.serialized) @MainActor struct WatchCompanionTests {
  func trip() throws -> TripSnapshot {
    var draft = OnboardingDraft()
    draft.stops = [Destination.all[0].stop()]
    return try draft.makeTrip()
  }

  func expense(_ trip: TripSnapshot, amount: String = "601") -> Expense {
    .init(
      attachment: .init(kind: .day, id: trip.days[0].id), title: "Coffee", category: .coffee,
      amountMinor: amount, currency: trip.homeCurrency, status: .paid, paidOn: trip.startsOn,
      paidBy: trip.ownerTravellerId, splitWith: [trip.ownerTravellerId])
  }

  @Test func hostAppliesWatchChangesOnceAndPublishesThem() async throws {
    let store = try LocalStore(inMemory: true, installationID: "test")
    let trip = try trip()
    try store.create(trip)
    var published: [CompanionContext] = []
    let host = WatchCompanionHost(model: AppModel(store: store)) { published.append($0) }
    let command = CompanionCommand.saveExpense(tripID: trip.id, expense: expense(trip))
    await host.receive(command)
    #expect(store.trip(trip.id)?.expenses.count == 1)
    // WatchConnectivity may deliver a transfer twice; the repeat must not hit the pending guard.
    await host.receive(command)
    #expect(store.trip(trip.id)?.expenses.count == 1)
    #expect(published.last?.rejected.isEmpty == true)
    host.publish()
    #expect(published.last.map { command.isReflected(in: $0.trips[0]) } == true)
  }

  @Test func hostRejectsChangesForMissingTrips() async throws {
    let store = try LocalStore(inMemory: true, installationID: "test")
    var published: [CompanionContext] = []
    let host = WatchCompanionHost(model: AppModel(store: store)) { published.append($0) }
    let trip = try trip()
    let command = CompanionCommand.saveExpense(tripID: trip.id, expense: expense(trip))
    await host.receive(command)
    #expect(published.last?.rejected[command.id] != nil)
  }

  @Test func hostQueuesRepayments() async throws {
    let store = try LocalStore(inMemory: true, installationID: "test")
    let trip = try trip()
    try store.create(trip)
    let host = WatchCompanionHost(model: AppModel(store: store)) { _ in }
    let repayment = Repayment(
      fromTravellerId: trip.ownerTravellerId, toTravellerId: trip.ownerTravellerId,
      amountMinor: "1000", currency: trip.homeCurrency, paidOn: trip.startsOn, note: "")
    await host.receive(.saveRepayment(tripID: trip.id, repayment: repayment))
    #expect(store.trip(trip.id)?.repayments.map(\.id) == [repayment.id])
  }

  @Test func watchModelQueuesPersistsAndClearsOnEcho() throws {
    let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let mirror = CompanionMirror(directory: directory)
    let trip = try trip()
    var sent: [CompanionCommand] = []
    let model = WatchModel(mirror: mirror, send: { sent.append($0) })
    model.receive(.init(trips: [trip], sentAt: Date(timeIntervalSince1970: 1)))
    let expense = expense(trip)
    model.send(.saveExpense(tripID: trip.id, expense: expense))
    #expect(sent.count == 1)
    #expect(model.trip(trip.id)?.expenses.count == 1)
    #expect(mirror.load().pending.count == 1)
    var echoed = trip
    echoed.expenses = [expense]
    model.receive(.init(trips: [echoed], sentAt: Date(timeIntervalSince1970: 2)))
    #expect(model.pendingCount == 0)
    #expect(mirror.load().pending.isEmpty)
  }

  @Test func watchModelFallsBackToRecordedRates() throws {
    var trip = try trip()
    var spend = expense(trip, amount: "1000")
    spend.currency = "EUR"
    spend.conversion = .init(
      homeAmountMinor: "862", rate: "0.862", rateDate: trip.startsOn, source: "Demo",
      kind: "manual", quoteId: nil)
    trip.expenses = [spend]
    let model = WatchModel(state: .init(context: .init(trips: [trip])))
    #expect(model.rate(from: "EUR", to: "GBP") == "0.862")
    #expect(model.convert(1000, from: "EUR", to: "GBP") == 862)
    #expect(model.rate(from: "JPY", to: "GBP") == nil)
  }

  @Test func demoMatchesTheDesignFixtures() throws {
    let model = try WatchModel.demo()
    let timeline = model.timeline
    #expect(timeline.now.first?.name == "Lisbon, Porto & Seville")
    #expect(timeline.upcoming.first?.name == "Tokyo & Kyoto")
    #expect(timeline.past.count == 2)
    #expect(timeline.pastTotal?.amount == 482_600)
    #expect(model.currentTrip?.localCurrency(at: model.now) == "EUR")
    #expect(model.convert(1000, from: "EUR", to: "GBP") == 862)
    let quick = model.currentTrip.flatMap(model.quickConversion(for:))
    #expect(quick?.amount == 1000)
    #expect(quick?.converted == 862)
  }

  @Test func quickConversionStepsUpForLowValueCurrencies() throws {
    var trip = try trip()
    trip.stops[0].currency = "JPY"
    trip.homeCurrency = "GBP"
    let model = WatchModel(state: .init(context: .init(trips: [trip])))
    model.now = CivilDate.date(trip.startsOn).addingTimeInterval(12 * 3600)
    let quote = FXQuote(
      id: "q", from: "JPY", to: "GBP", rate: "0.0052", requestedDate: trip.startsOn,
      rateDate: trip.startsOn, source: "Test")
    model.cache(quote)
    let quick = model.quickConversion(for: trip)
    #expect(quick?.amount == 1000)
    #expect(quick?.converted == 520)
  }

  @Test func watchModelPrefersTheFreshestQuoteOrTable() throws {
    let model = WatchModel()
    model.cache(
      FXTable(
        base: "GBP", requestedDate: "2026-10-01", rateDate: "2026-10-01", source: "Test",
        rates: ["GBP": "1", "EUR": "1.16", "USD": "1.33"]))
    #expect(model.convert(5000, from: "USD", to: "EUR") == 4361)
    model.cache(
      FXQuote(
        id: "q", from: "EUR", to: "GBP", rate: "0.9", requestedDate: "2026-10-02",
        rateDate: "2026-10-02", source: "Test"))
    #expect(model.rate(from: "EUR", to: "GBP") == "0.9")
    model.cache(
      FXTable(
        base: "GBP", requestedDate: "2026-10-03", rateDate: "2026-10-03", source: "Test",
        rates: ["GBP": "1", "EUR": "1.25"]))
    #expect(model.rate(from: "EUR", to: "GBP") == "0.8")
    #expect(model.rate(from: "USD", to: "GBP") == nil)
    #expect(model.convertibleCurrencies == ["EUR", "GBP"])
  }
  @Test func refreshRatesFallsBackToAQuoteWithoutATable() async throws {
    var trip = try trip()
    trip.stops[0].currency = "EUR"
    trip.homeCurrency = "GBP"
    struct Unavailable: Error {}
    let quote = FXQuote(
      id: "q", from: "EUR", to: "GBP", rate: "0.86", requestedDate: "2026-10-01",
      rateDate: "2026-10-01", source: "Test")
    let offline = WatchModel(
      state: .init(context: .init(trips: [trip])), loadQuote: { _, _, _ in quote },
      loadTable: { _, _ in throw Unavailable() })
    offline.now = CivilDate.date(trip.startsOn).addingTimeInterval(12 * 3600)
    await offline.refreshRates()
    #expect(offline.tables.isEmpty)
    #expect(offline.rate(from: "EUR", to: "GBP") == "0.86")
    let online = WatchModel(
      state: .init(context: .init(trips: [trip])),
      loadTable: { base, date in
        FXTable(base: base, requestedDate: date, rateDate: date, source: "Test", rates: ["EUR": "1.16"])
      })
    await online.refreshRates()
    #expect(online.tables["GBP"]?.rates["EUR"] == "1.16")
  }
  @Test func quickConvertFollowsTheTripUntilAPairIsChosen() throws {
    let convert = QuickConvert(model: try WatchModel.demo())
    #expect(convert.pair == .init(from: "EUR", to: "GBP"))
    #expect(convert.amount == 10)
    #expect(convert.result == 862)
    convert.amount = 24
    #expect(convert.result == 2069)
    #expect(convert.rateLine == "€1 = £0.86")
    convert.swap()
    #expect(convert.pair == .init(from: "GBP", to: "EUR"))
    #expect(convert.isFlipped && !convert.isCustom)
    convert.choose("USD", for: .from)
    #expect(convert.pair == .init(from: "USD", to: "EUR"))
    #expect(convert.isCustom)
    convert.amount = 50
    #expect(convert.result == 4361)
    #expect(convert.rateLine == "$1 = €0.87")
    #expect(convert.changed?.side == .from && convert.changed?.count == 1)
    convert.choose("EUR", for: .from)
    #expect(convert.pair == .init(from: "EUR", to: "USD"))
    convert.choose("GBP", for: .to)
    #expect(convert.pair == .init(from: "EUR", to: "GBP"))
    #expect(!convert.isCustom && !convert.isFlipped)
    convert.choose("CHF", for: .to)
    convert.resetToTrip()
    #expect(convert.pair == .init(from: "EUR", to: "GBP"))
    #expect(convert.model.convertMemory.recents.prefix(3) == ["CHF", "GBP", "EUR"])
  }
  @Test func quickConvertCyclesTripCurrenciesThenEverythingElse() throws {
    let convert = QuickConvert(model: try WatchModel.demo())
    convert.focus = .from
    #expect(convert.cycleItems.prefix(2) == [.currency("EUR"), .currency("JPY")])
    #expect(convert.cycleItems.last == .all)
    #expect(!convert.cycleItems.contains(.currency("GBP")))
    #expect(convert.cycleDetent == 0)
    #expect(!convert.turn(to: 1))
    #expect(convert.pair == .init(from: "JPY", to: "GBP"))
    #expect(convert.scale == 100)
    #expect(convert.rateLine == "¥100 = £0.50")
    #expect(convert.turn(to: convert.cycleItems.count - 1))
    convert.focus = nil
    #expect(convert.model.convertMemory.recents == ["JPY"])
    #expect(convert.quickPicks(for: .from) == ["EUR", "JPY"])
    convert.dial(to: 23)
    #expect(convert.amount == 2400)
    #expect(convert.amountDetent == 23)
  }
  @Test func amountLadderStepsInOnesFivesThenTens() {
    #expect(
      [0, 49, 50, 79, 80, 1059, 5000].map(AmountLadder.value(at:))
        == [1, 50, 55, 200, 210, 10_000, 10_000])
    #expect(
      [Decimal(string: "24.5")!, 0.5, 55, 57, 200, 10_000, 99_999].map(AmountLadder.index(for:))
        == [23, 0, 50, 50, 79, 1059, 1059])
  }
  @Test func watchCurrenciesUseTheTripsCountryForSharedCurrencies() throws {
    let convert = QuickConvert(model: try WatchModel.demo())
    #expect(convert.currency("EUR").flag == "🇵🇹")
    #expect(convert.currency("JPY").flag == "🇯🇵")
    #expect(WatchCurrency(code: "EUR").flag == "🇪🇺")
    #expect(WatchCurrency(code: "USD").label == "$ USD")
    #expect(WatchCurrency(code: "AUD").label == "A$ AUD")
    #expect(WatchCurrency(code: "CHF").label == "CHF")
    #expect(WatchCurrency.format(2140, "CHF") == "CHF\u{a0}21.40")
    #expect(WatchCurrency.format(5000, "AUD", compact: true) == "A$50")
  }
}
