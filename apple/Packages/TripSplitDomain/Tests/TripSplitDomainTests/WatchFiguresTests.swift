import Foundation
import Testing

@testable import TripSplitDomain

struct WatchFiguresTests {
  private func trip(startingIn offset: Int = -3, budget: String = "2400") throws -> TripSnapshot {
    var draft = OnboardingDraft()
    draft.stops = [
      try #require(Destination.search("Lisbon").first).stop(nights: 3),
      try #require(Destination.search("Porto").first).stop(nights: 2),
      try #require(Destination.search("Seville").first).stop(nights: 2),
    ]
    draft.currency = "GBP"
    draft.budget = budget
    draft.travellers += [Traveller(name: "Maya", hue: 250), Traveller(name: "Tom", hue: 75)]
    draft.startsOn = CivilDate.adding(offset, to: CivilDate.today(timeZone: "UTC"))
    return try draft.makeTrip()
  }

  private func expense(
    _ trip: TripSnapshot, day: Int, amount: String, status: Expense.Status = .paid,
    currency: String = "GBP"
  ) -> Expense {
    Expense(
      attachment: .init(kind: .day, id: trip.days[day].id), title: "Lunch", category: .food,
      amountMinor: amount, currency: currency, status: status, paidBy: trip.travellers[0].id,
      splitWith: trip.travellers.map(\.id))
  }

  @Test func dailyBudgetSpreadsTheBudgetAcrossTripDays() throws {
    let trip = try trip()
    #expect(trip.days.count == 8)
    #expect(trip.dailyBudget == 30_000)
    #expect(try self.trip(budget: "0").dailyBudget == 0)
  }

  @Test func dayNumberAndProgressFollowTheItinerary() throws {
    let trip = try trip()
    #expect(trip.dayNumber(of: trip.days[3]) == 4)
    #expect(trip.progress(through: trip.days[3]) == 0.5)
    #expect(trip.stop(for: .init(kind: .day, id: trip.days[3].id))?.place == "Porto")
  }

  @Test func daySpendingCountsOnlyPaidHomeValues() throws {
    var trip = try trip()
    trip.expenses = [
      expense(trip, day: 3, amount: "4800"),
      expense(trip, day: 3, amount: "1097"),
      expense(trip, day: 3, amount: "930", status: .planned),
      expense(trip, day: 2, amount: "9999"),
      expense(trip, day: 3, amount: "500", currency: "EUR"),
    ]
    let spending = trip.spending(on: trip.days[3])
    #expect(spending.amount == 5897)
    #expect(spending.count == 3)
    #expect(spending.unresolved == 1)
    #expect(spending.left == 30_000 - 5897)
    #expect(abs(spending.fraction - 5897.0 / 30_000) < 0.0001)
  }

  @Test func countdownAndRouteDescribeDepartures() throws {
    let trip = try trip(startingIn: 49)
    #expect(trip.daysUntilStart(from: CivilDate.today(timeZone: "UTC")) == 49)
    #expect(trip.routeCode == "LIS·OPO·SVQ")
    #expect(trip.destination == "Lisbon")
    #expect(trip.stopCurrencies == ["EUR"])
  }

  @Test func timelineGroupsTripsByPhase() throws {
    var past = try trip(startingIn: -200)
    var other = try trip(startingIn: -120)
    past.expenses = [expense(past, day: 0, amount: "1000")]
    other.expenses = [expense(other, day: 1, amount: "2500")]
    var archived = try trip(startingIn: 10)
    archived.archived = true
    let timeline = TripTimeline([try trip(startingIn: 49), try trip(), past, other, archived])
    #expect(timeline.now.count == 1)
    #expect(timeline.upcoming.count == 1)
    #expect(timeline.past.map(\.startsOn) == [other.startsOn, past.startsOn])
    #expect(timeline.pastTotal?.amount == 3500)
    #expect(timeline.pastTotal?.currency == "GBP")
    other.homeCurrency = "EUR"
    #expect(TripTimeline([past, other]).pastTotal == nil)
    #expect(TripTimeline([]).isEmpty)
  }

  @Test func localCurrencyIsNilAtHome() throws {
    let abroad = try trip()
    #expect(abroad.localCurrency() == "EUR")
    var home = abroad
    home.homeCurrency = "EUR"
    #expect(home.localCurrency() == nil)
    #expect(try trip(startingIn: 49).localCurrency() == nil)
  }
}

struct CompanionTests {
  private func trip() throws -> TripSnapshot {
    var draft = OnboardingDraft()
    draft.stops = [try #require(Destination.search("Rome").first).stop(nights: 2)]
    draft.currency = "GBP"
    return try draft.makeTrip()
  }

  @Test func contextRoundTripsThroughTheCompressedCodec() throws {
    let context = CompanionContext(
      trips: [try trip()], sentAt: Date(timeIntervalSince1970: 1_800_000_000))
    let data = try CompanionCodec.encode(context)
    #expect(try CompanionCodec.decode(CompanionContext.self, from: data) == context)
    #expect(data.count < (try JSONEncoder().encode(context)).count)
  }

  @Test func commandsOverlayUntilThePhoneEchoesThem() throws {
    let trip = try trip()
    let expense = Expense(
      attachment: .init(kind: .day, id: trip.days[0].id), title: "Gelato", category: .food,
      amountMinor: "450", currency: "EUR", status: .paid, paidBy: trip.currentTravellerId,
      splitWith: [trip.currentTravellerId])
    let command = CompanionCommand.saveExpense(tripID: trip.id, expense: expense)
    var overlaid = trip
    command.apply(to: &overlaid)
    #expect(overlaid.expenses.count == 1)
    #expect(!command.isReflected(in: trip))
    var echoed = expense
    echoed.revision = 3
    echoed.conversion = .init(
      homeAmountMinor: "388", rate: "0.862", rateDate: "2026-11-01", source: "ECB",
      kind: "reference")
    var confirmed = trip
    confirmed.expenses = [echoed]
    #expect(command.isReflected(in: confirmed))
    var edited = echoed
    edited.amountMinor = "500"
    confirmed.expenses = [edited]
    #expect(!command.isReflected(in: confirmed))
    let decoded = try CompanionCodec.decode(
      CompanionCommand.self, from: try CompanionCodec.encode(command))
    #expect(decoded == command)
    #expect(decoded.tripID == trip.id)
  }

  @Test func commandsIgnoreOtherTrips() throws {
    let trip = try trip()
    let repayment = Repayment(
      fromTravellerId: "a", toTravellerId: "b", amountMinor: "1000", currency: "GBP",
      paidOn: trip.startsOn, note: "")
    var other = try self.trip()
    CompanionCommand.saveRepayment(tripID: trip.id, repayment: repayment).apply(to: &other)
    #expect(other.repayments.isEmpty)
  }
}

struct CompanionStateTests {
  private func trip() throws -> TripSnapshot {
    var draft = OnboardingDraft()
    draft.stops = [try #require(Destination.search("Rome").first).stop(nights: 2)]
    return try draft.makeTrip()
  }

  private func gelato(_ trip: TripSnapshot) -> Expense {
    Expense(
      attachment: .init(kind: .day, id: trip.days[0].id), title: "Gelato", category: .food,
      amountMinor: "450", currency: "EUR", status: .paid, paidBy: trip.currentTravellerId,
      splitWith: [trip.currentTravellerId])
  }

  @Test func pendingChangesOverlayUntilReflected() throws {
    let trip = try trip()
    let expense = gelato(trip)
    var state = CompanionState(context: .init(trips: [trip], sentAt: .init(timeIntervalSince1970: 1)))
    state.queue(.saveExpense(tripID: trip.id, expense: expense))
    #expect(state.trips[0].expenses.count == 1)
    state.receive(.init(trips: [trip], sentAt: .init(timeIntervalSince1970: 2)))
    #expect(state.pending.count == 1)
    var echoed = trip
    echoed.expenses = [expense]
    state.receive(.init(trips: [echoed], sentAt: .init(timeIntervalSince1970: 3)))
    #expect(state.pending.isEmpty)
    #expect(state.trips[0].expenses.count == 1)
  }

  @Test func staleContextsAreIgnored() throws {
    let trip = try trip()
    var state = CompanionState(context: .init(trips: [trip], sentAt: .init(timeIntervalSince1970: 5)))
    state.receive(.init(trips: [], sentAt: .init(timeIntervalSince1970: 4)))
    #expect(state.trips.count == 1)
  }

  @Test func rejectedAndOrphanedCommandsAreDropped() throws {
    let trip = try trip()
    let other = try self.trip()
    var state = CompanionState()
    let rejected = CompanionCommand.saveExpense(tripID: trip.id, expense: gelato(trip))
    state.queue(rejected)
    state.queue(.saveExpense(tripID: other.id, expense: gelato(other)))
    let reasons = state.receive(.init(trips: [trip], rejected: [rejected.id: "Waiting for sync"]))
    #expect(reasons == ["Waiting for sync"])
    #expect(state.pending.isEmpty)
  }
}
