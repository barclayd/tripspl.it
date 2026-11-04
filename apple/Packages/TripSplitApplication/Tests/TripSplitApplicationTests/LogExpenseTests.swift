import Foundation
import Testing
import TripSplitCompanion
import TripSplitDomain
import TripSplitWatchModel

@testable import TripSplitApplication

@MainActor struct LogExpenseTests {
  /// The demo trips, with whatever the watch sends captured.
  func model() throws -> (WatchModel, () -> [CompanionCommand]) {
    let demo = try WatchModel.demo()
    var sent: [CompanionCommand] = []
    let model = WatchModel(
      state: .init(context: .init(trips: demo.trips, sentAt: demo.now)),
      send: { sent.append($0) })
    model.now = demo.now
    for table in demo.tables.values { model.cache(table) }
    return (model, { sent })
  }

  func saved(_ commands: [CompanionCommand]) throws -> Expense {
    guard case .saveExpense(_, let expense) = commands.last else {
      Issue.record("Expected a saved expense, got \(commands)")
      throw CancellationError()
    }
    return expense
  }

  @Test func tripHappeningNowLogsAgainstToday() throws {
    let (model, _) = try model()
    let log = LogExpense(model: model)
    #expect(log.start == .trip)
    let now = try #require(model.timeline.now.first)
    let upcoming = try #require(model.timeline.upcoming.first)
    #expect(log.trips.map(\.id) == [now.id, upcoming.id])
    #expect(log.suggestedTripID == now.id)
    #expect(log.detail(for: now) == "Now · Day 4")
    #expect(log.detail(for: upcoming).hasPrefix("From "))
    log.choose(now)
    #expect(log.start == .amount)
    #expect(log.attachment == now.currentAttachment(at: model.now))
    #expect(log.currency == "EUR")
    #expect(log.currencies == ["EUR", "GBP"])
    #expect(log.info("EUR").flag == "🇵🇹")
    #expect(log.sharers.count == 3)
  }

  @Test(arguments: [true, false])
  func onlyTripSkipsLogFor(happeningNow: Bool) throws {
    let demo = try WatchModel.demo()
    let phase: TripSnapshot.Phase = happeningNow ? .now : .upcoming
    let trip = try #require(demo.trips.first { $0.phase(at: demo.now) == phase })
    let past = demo.trips.filter { $0.phase(at: demo.now) == .past }
    let model = WatchModel(
      state: .init(context: .init(trips: [trip] + past, sentAt: demo.now)), send: { _ in })
    model.now = demo.now
    let log = LogExpense(model: model)
    #expect(log.trips.map(\.id) == [trip.id])
    #expect(log.trip?.id == trip.id)
    #expect(log.start == (happeningNow ? .amount : .day))
  }

  @Test func tripStillToComeAsksWhichDayAndStartsBeforeYouGo() throws {
    let (model, _) = try model()
    let trip = try #require(model.timeline.upcoming.first)
    let log = LogExpense(model: model, trip: trip)
    #expect(log.start == .day)
    let options = log.dayOptions
    #expect(options.first?.title == "Before you go")
    #expect(options.first?.detail == "Flights, deposits, gear")
    #expect(options.count == trip.days.count + 2)
    #expect(options[1].title.hasPrefix("Day 1 · "))
    #expect(options.map(\.isTravel) == [true] + trip.days.map { _ in false } + [true])
    log.choose(try #require(options.first).attachment)
    #expect(log.currency == "GBP")
    #expect(log.category == .flight)
    #expect(log.currencies == ["JPY", "GBP"])
    log.choose(options[1].attachment)
    #expect(log.currency == "JPY")
    #expect(log.currencies == ["JPY", "GBP"])
  }

  @Test func logsAndReceiptsUseTheWatchLocalDay() throws {
    let now = try #require(ISO8601DateFormatter().date(from: "2026-10-31T17:30:00Z"))
    let local = CivilDate.string(now, timeZone: TimeZone.current.identifier)
    var draft = OnboardingDraft()
    draft.startsOn = CivilDate.adding(-1, to: local)
    var stop = try #require(Destination.search("Taipei").first).stop(nights: 4)
    // Keep the destination on a different date regardless of the test machine's time zone.
    stop.timeZone = CivilDate.string(now, timeZone: "Asia/Taipei") != local
      ? "Asia/Taipei" : "America/Los_Angeles"
    draft.stops = [stop]
    let trip = try draft.makeTrip()
    var sent: [CompanionCommand] = []
    let model = WatchModel(
      state: .init(context: .init(trips: [trip], sentAt: now)),
      send: { sent.append($0) })
    model.now = now
    let log = LogExpense(model: model, trip: trip)
    log.amount = 42
    let receipt = try #require(log.save())
    let expense = try saved(sent)
    #expect(trip.date(for: expense.attachment) == local)
    #expect(expense.paidOn == local)
    #expect(receipt.heading == "Taipei · " + CivilDate.display(local, format: "EEE d MMM"))
    #expect(log.detail(for: trip) == "Now · Day 2")
  }

  @Test func savesAnEstimateThePhoneQuotesAgain() throws {
    let (model, sent) = try model()
    let trip = try #require(model.timeline.now.first)
    let log = LogExpense(model: model, trip: trip)
    log.amount = 42
    log.category = .food
    #expect(log.homeMinor == 3621)
    #expect(log.each?.minor == 1207)
    let receipt = try #require(log.save())
    let expense = try saved(sent())
    #expect(expense.amountMinor == "4200")
    #expect(expense.currency == "EUR")
    #expect(expense.title == "Food")
    #expect(expense.status == .paid)
    #expect(expense.paidBy == trip.currentTravellerId)
    #expect(expense.paidOn == trip.date(for: expense.attachment))
    #expect(expense.splitWith == trip.activeTravellers.map(\.id).sorted())
    #expect(expense.conversion?.kind == "reference")
    #expect(expense.conversion?.quoteId == nil)
    #expect(expense.conversion?.homeAmountMinor == "3621")
    #expect(receipt.heading == "Porto · " + CivilDate.display(CivilDate.string(model.now), format: "EEE d MMM"))
    #expect(receipt.amount == "€42.00")
    #expect(receipt.home == "£36.21")
    #expect(receipt.people == ["You", "Maya", "Tom"])
    #expect(receipt.each == "£12.07")
    #expect(LogExpense.rateNote(receipt.rateDate, now: model.now) == "Rates from today.")
    // It shows on the watch before the phone confirms it.
    #expect(model.trip(trip.id)?.expenses.contains { $0.id == expense.id } == true)
  }

  @Test func justMeIsPaidAndSharedByYouAlone() throws {
    let (model, sent) = try model()
    let trip = try #require(model.timeline.now.first)
    let log = LogExpense(model: model, trip: trip)
    log.amount = 6.4
    log.select(currency: "GBP")
    log.paidBy = try #require(trip.travellers.last).id
    log.isShared = false
    #expect(log.each?.minor == 640)
    log.save()
    let expense = try saved(sent())
    #expect(expense.amountMinor == "640")
    #expect(expense.paidBy == trip.currentTravellerId)
    #expect(expense.splitWith == [trip.currentTravellerId])
    #expect(expense.conversion == nil)
  }

  @Test func soloTripSkipsWhoSharesIt() throws {
    let demo = try WatchModel.demo()
    var trip = try #require(demo.trips.first { $0.phase(at: demo.now) == .now })
    trip.travellers = trip.travellers.filter { $0.id == trip.currentTravellerId }
    var sent: [CompanionCommand] = []
    let model = WatchModel(
      state: .init(context: .init(trips: [trip], sentAt: demo.now)), send: { sent.append($0) })
    model.now = demo.now
    let log = LogExpense(model: model)
    #expect(!log.asksSplit)
    #expect(log.step(after: .category) == nil)
    log.amount = 20
    let receipt = try #require(log.save())
    let expense = try saved(sent)
    #expect(expense.paidBy == trip.currentTravellerId)
    #expect(expense.splitWith == [trip.currentTravellerId])
    #expect(receipt.people == ["You"])
    #expect(receipt.each == nil)
  }

  @Test func sharedTripAsksWhoSharesIt() throws {
    let (model, _) = try model()
    let log = LogExpense(model: model, trip: model.timeline.now.first)
    #expect(log.asksSplit)
    #expect(log.step(after: .category) == .split)
    #expect(log.step(after: .split) == nil)
  }

  @Test func returnFromTripComesLastAndIsntAskedAgain() throws {
    let (model, sent) = try model()
    let trip = try #require(model.timeline.upcoming.first)
    let back = try #require(trip.legs.first { $0.kind == .return })
    let log = LogExpense(model: model, trip: trip)
    let option = try #require(log.dayOptions.last)
    #expect(option.title == "Return from trip")
    #expect(option.detail == "Flights, taxi home")
    #expect(option.attachment == Attachment(kind: .leg, id: back.id))
    log.choose(option.attachment)
    #expect(log.currency == "GBP")
    #expect(log.category == .flight)
    #expect(!log.asksReturn)
    #expect(log.step(after: .category) == .split)
    log.amount = 180
    let receipt = try #require(log.save())
    #expect(try saved(sent()).title == "Flight")
    #expect(receipt.heading.hasPrefix("Return from trip · "))
  }

  @Test func aReturnBeforeYouGoIsSplitWithTheWayHome() throws {
    let (model, sent) = try model()
    let trip = try #require(model.timeline.upcoming.first)
    let out = try #require(trip.legs.first { $0.kind == .outbound })
    let back = try #require(trip.legs.first { $0.kind == .return })
    let log = LogExpense(model: model, trip: trip)
    log.choose(Attachment(kind: .leg, id: out.id))
    #expect(log.asksReturn)
    #expect(log.coversReturn)
    #expect(log.step(after: .category) == .returnToo)
    #expect(log.step(after: .returnToo) == .split)
    log.amount = try #require(Decimal(string: "420.01"))
    let receipt = try #require(log.save())
    let halves = saves(sent())
    #expect(halves.map(\.attachment.id) == [out.id, back.id])
    #expect(halves.map(\.amountMinor) == ["21001", "21000"])
    #expect(halves.allSatisfy { $0.title == "Return flight" && $0.returnPairId == halves[0].id })
    #expect(receipt.category == "Return flight")
    #expect(receipt.amount == "£420.01")
    #expect(receipt.heading.hasPrefix("Before you go · "))

    // Either half changes the whole ticket, and it stays a return until you say it's one way.
    let editing = LogExpense(model: model, trip: model.trip(trip.id), editing: halves[1])
    #expect(editing.editing?.id == halves[0].id)
    #expect(editing.attachment?.id == out.id)
    #expect(editing.amount == Decimal(string: "420.01"))
    #expect(editing.coversReturn)
    editing.amount = 400
    editing.save()
    let edited = saves(sent()).suffix(2)
    #expect(edited.map(\.id) == halves.map(\.id))
    #expect(edited.map(\.amountMinor) == ["20000", "20000"])
    #expect(model.pendingCount == 2)

    let oneWay = LogExpense(model: model, trip: model.trip(trip.id), editing: halves[0])
    oneWay.coversReturn = false
    oneWay.save()
    let flight = try saved(Array(sent().dropLast()))
    #expect(flight.id == halves[0].id && flight.title == "Flight" && flight.returnPairId == nil)
    #expect(flight.amountMinor == "40000")
    guard case .deleteExpense(_, let dropped) = sent().last else {
      Issue.record("Expected the way home to go, got \(sent())")
      return
    }
    #expect(dropped == halves[1].id)
    #expect(model.trip(trip.id)?.expenses.filter { $0.attachment.id == back.id }.isEmpty == true)
  }

  @Test func deletingEitherHalfDeletesTheReturn() throws {
    let (model, sent) = try model()
    let trip = try #require(model.timeline.upcoming.first)
    let log = LogExpense(model: model, trip: trip)
    log.choose(try #require(log.dayOptions.first).attachment)
    log.amount = 300
    log.save()
    let halves = saves(sent())
    model.deleteExpense(halves[1], in: try #require(model.trip(trip.id)))
    let deleted = sent().compactMap { command -> String? in
      guard case .deleteExpense(_, let id) = command else { return nil }
      return id
    }
    #expect(Set(deleted) == Set(halves.map(\.id)))
    #expect(model.trip(trip.id)?.expenses.contains { $0.returnPairId != nil } == false)
  }

  func saves(_ commands: [CompanionCommand]) -> [Expense] {
    commands.compactMap { command in
      guard case .saveExpense(_, let expense) = command else { return nil }
      return expense
    }
  }

  @Test(arguments: [ExpenseCategory.taxi, .stay, .shopping, .other])
  func oneWayCostsBeforeYouGoArentAsked(category: ExpenseCategory) throws {
    let (model, sent) = try model()
    let trip = try #require(model.timeline.upcoming.first)
    let log = LogExpense(model: model, trip: trip)
    log.choose(try #require(log.dayOptions.first).attachment)
    log.category = category
    #expect(!log.asksReturn)
    #expect(log.step(after: .category) == .split)
    log.amount = 50
    log.save()
    #expect(try saved(sent()).title == category.title)
  }

  @Test func travelOnADayIsntAsked() throws {
    let (model, _) = try model()
    let trip = try #require(model.timeline.upcoming.first)
    let log = LogExpense(model: model, trip: trip)
    log.choose(log.dayOptions[1].attachment)
    log.category = .train
    #expect(!log.asksReturn)
  }

  @Test func onlyTravelThereAndBackHasAReturn() {
    #expect(ExpenseCategory.flight.returnTitle == "Return flight")
    #expect(ExpenseCategory.train.returnTitle == "Return train")
    #expect(ExpenseCategory.transport.returnTitle == "Return journey")
    #expect(ExpenseCategory.taxi.returnTitle == nil)
    #expect(ExpenseCategory.stay.returnTitle == nil)
  }

  @Test func plannedForATripStillToCome() throws {
    let (model, sent) = try model()
    let trip = try #require(model.timeline.upcoming.first)
    let log = LogExpense(model: model, trip: trip)
    log.choose(log.dayOptions[1].attachment)
    log.amount = 12_000
    log.save()
    let expense = try saved(sent())
    #expect(expense.status == .planned)
    #expect(expense.paidOn == nil)
    #expect(expense.currency == "JPY")
    #expect(expense.amountMinor == "12000")
  }

  @Test func editingKeepsTheSpendAndItsQuoteWhileTheAmountHolds() throws {
    let (model, sent) = try model()
    let trip = try #require(model.timeline.now.first)
    let original = try #require(trip.expenses.first { $0.title == "Lunch by the river" })
    let log = LogExpense(model: model, trip: trip, editing: original)
    #expect(log.start == .amount)
    #expect(log.amount == 48)
    #expect(log.currency == "EUR")
    #expect(log.isShared)
    log.category = .coffee
    log.save()
    let kept = try saved(sent())
    #expect(kept.id == original.id)
    #expect(kept.revision == original.revision)
    #expect(kept.title == "Lunch by the river")
    #expect(kept.category == .coffee)
    #expect(kept.conversion == original.conversion)
    log.amount = 50
    log.save()
    let changed = try saved(sent())
    #expect(changed.conversion?.kind == "reference")
    #expect(changed.conversion?.homeAmountMinor == "4310")
  }

  @Test func switchingCurrencyTrimsToWhatItHolds() throws {
    let (model, _) = try model()
    let trip = try #require(model.timeline.upcoming.first)
    let log = LogExpense(model: model, trip: trip)
    log.choose(log.dayOptions[1].attachment)
    log.select(currency: "GBP")
    log.amount = 12.5
    log.select(currency: "JPY")
    #expect(log.amount == 13)
  }

  @Test func crownDialsFromNothingThroughTheLadder() throws {
    let (model, _) = try model()
    let log = LogExpense(model: model, trip: try #require(model.timeline.now.first))
    #expect(log.amountDetent == 0)
    log.dial(to: 1)
    #expect(log.amount == 1)
    log.dial(to: LogExpense.detentCount - 1)
    #expect(log.amount > 1000)
    log.dial(to: 0)
    #expect(log.amount == 0)
    #expect(!log.canSave)
  }

  @Test func deletingReplacesAPendingSave() throws {
    let (model, sent) = try model()
    let trip = try #require(model.timeline.now.first)
    let log = LogExpense(model: model, trip: trip)
    log.amount = 3
    log.save()
    let expense = try saved(sent())
    #expect(model.pendingCount == 1)
    model.deleteExpense(expense, in: try #require(model.trip(trip.id)))
    #expect(model.pendingCount == 1)
    #expect(model.trip(trip.id)?.expenses.contains { $0.id == expense.id } == false)
    guard case .deleteExpense(_, let id) = sent().last else {
      Issue.record("Expected a delete, got \(sent())")
      return
    }
    #expect(id == expense.id)
  }

  @Test func categoriesUseShortLabelsOnTheWatch() {
    #expect(ExpenseCategory.watchOrder.count == ExpenseCategory.allCases.count)
    #expect(ExpenseCategory.transport.watchTitle == "Transport")
    #expect(ExpenseCategory.activity.watchTitle == "Activity")
    #expect(ExpenseCategory.food.watchTitle == "Food")
  }
}
