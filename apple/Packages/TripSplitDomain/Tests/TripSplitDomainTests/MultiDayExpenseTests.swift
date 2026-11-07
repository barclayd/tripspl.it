import Foundation
import Testing
@testable import TripSplitDomain

struct MultiDayExpenseTests {
  func trip() throws -> TripSnapshot {
    var draft = OnboardingDraft()
    draft.stops = [Destination.all[0].stop(nights: 3)]
    return try draft.makeTrip()
  }

  func stay(_ trip: TripSnapshot, amount: String = "10001") -> Expense {
    Expense(
      attachment: .init(kind: .day, id: trip.days[0].id), title: "Hotel", category: .stay,
      amountMinor: amount, currency: "JPY", status: .paid, paidOn: trip.startsOn,
      paidBy: trip.currentTravellerId, splitWith: [trip.currentTravellerId],
      conversion: .init(homeAmountMinor: "101", rate: "0.01", rateDate: trip.startsOn,
        source: Conversion.bankChargeSource, kind: "manual"),
      dayIds: Array(trip.days.prefix(3).map(\.id)))
  }

  @Test func dailySharesPreserveBothTotalsAndTripBalances() throws {
    var trip = try trip()
    trip.expenses = [stay(trip)]
    let portions = trip.days.flatMap { trip.expenses(for: .init(kind: .day, id: $0.id)) }
    #expect(portions.map(\.amountMinor) == ["3334", "3334", "3333"])
    #expect(portions.map { $0.conversion?.homeAmountMinor } == ["34", "34", "33"])
    #expect(trip.days.map { trip.spending(on: $0).amount } == [34, 34, 33, 0])
    #expect(Ledger(trip).total == 101)
    #expect(Ledger(trip).balances[trip.currentTravellerId] == 0)
    #expect(trip.expenses.count == 1)
  }

  @Test func nonconsecutiveDaysAndTinyAmountsAreExact() throws {
    var trip = try trip()
    var expense = stay(trip, amount: "1")
    expense.dayIds = [trip.days[3].id, trip.days[0].id]
    expense.conversion?.homeAmountMinor = "1"
    trip.expenses = [expense]
    #expect(trip.expenses(for: .init(kind: .day, id: trip.days[1].id)).isEmpty)
    let portions = trip.days.flatMap { trip.expenses(for: .init(kind: .day, id: $0.id)) }
    #expect(portions.map(\.amountMinor) == ["1", "0"])
    #expect(portions.map { $0.conversion?.homeAmountMinor } == ["1", "0"])
    #expect(portions.map(\.id) == [expense.id, expense.id])
  }

  @Test func togglesKeepOneDayAndTravelIsExclusive() throws {
    let trip = try trip()
    let first = Attachment(kind: .day, id: trip.days[0].id)
    let third = Attachment(kind: .day, id: trip.days[2].id)
    var draft = ExpenseDraft(trip: trip, attachment: first)
    draft.select(third, in: trip)
    #expect(draft.selectedDayIDs == [first.id, third.id])
    draft.select(first, in: trip)
    #expect(draft.attachment == third && draft.dayIds == nil)
    draft.select(third, in: trip)
    #expect(draft.selectedDayIDs == [third.id])
    draft.select(.init(kind: .leg, id: trip.legs[0].id), in: trip)
    #expect(draft.selectedDayIDs.isEmpty && draft.dayIds == nil)
    draft.select(first, in: trip)
    #expect(draft.selectedDayIDs == [first.id])
  }

  @Test func everyDayOpensTheWholeExpenseAndBankCharge() throws {
    var trip = try trip()
    let expense = stay(trip)
    trip.expenses = [expense]
    for day in trip.days.prefix(3) {
      let portion = try #require(trip.expenses(for: .init(kind: .day, id: day.id)).first)
      let draft = ExpenseDraft(trip: trip, attachment: portion.attachment, expense: portion)
      #expect(draft.amount == "10001")
      #expect(draft.actualHomeAmount == "1.01")
      #expect(draft.dayIds == expense.dayIds)
      #expect(trip.ticket(of: portion) == [expense])
    }
  }

  @Test func legacyExpenseAndDraftStillDecode() throws {
    let trip = try trip()
    var expense = stay(trip)
    expense.dayIds = nil
    let data = try JSONEncoder().encode(expense)
    #expect(!String(decoding: data, as: UTF8.self).contains("dayIds"))
    #expect(try JSONDecoder().decode(Expense.self, from: data).dayIds == nil)
    let draft = ExpenseDraft(trip: trip, attachment: expense.attachment)
    let decoded = try JSONDecoder().decode(ExpenseDraft.self, from: JSONEncoder().encode(draft))
    #expect(decoded.selectedDayIDs == [expense.attachment.id])
  }

  @Test func selectedDaysSurviveWireAndCompanionEncoding() throws {
    let trip = try trip()
    let expense = stay(trip)
    #expect(try JSONDecoder().decode(Expense.self, from: JSONEncoder().encode(expense)) == expense)
    #expect(try CompanionCodec.decode(Expense.self, from: CompanionCodec.encode(expense)) == expense)
  }

  @Test func rescheduleMergesSelectedDaysWithoutChangingTheCharge() throws {
    var trip = try trip()
    trip.expenses = [stay(trip)]
    let first = trip.days[0], last = trip.days[3]
    let payload = TripReschedule(
      startsOn: trip.startsOn, stops: [.init(id: trip.stops[0].id, nights: 1)],
      days: [first, .init(id: last.id, date: CivilDate.adding(1, to: first.date), stopId: last.stopId)],
      legs: trip.legs,
      moves: trip.days[1...2].map { .init(fromDayId: $0.id, toDayId: first.id) })
    Operation(syncEpoch: trip.syncEpoch, type: "trip.reschedule", entityId: trip.id,
      expectedRevision: trip.revision, payload: .reschedule(payload)).apply(to: &trip)
    #expect(trip.expenses[0].dayIds == nil)
    #expect(trip.expenses[0].amountMinor == "10001")
    #expect(trip.spending(on: first).amount == 101)
  }
}
