import Foundation
import Testing
import TripSplitDomain
@testable import TripSplitApplication
@testable import TripSplitPersistence

@Suite(.serialized) @MainActor struct MultiDaySaveTests {
  func setup() async throws -> (AppModel, TripSnapshot) {
    let store = try LocalStore(inMemory: true, installationID: "test")
    var draft = OnboardingDraft()
    draft.stops = [Destination.all[0].stop(nights: 3)]
    let trip = try draft.makeTrip()
    try store.create(trip)
    let model = AppModel(store: store)
    model.editExpense(trip: trip, attachment: .init(kind: .day, id: trip.days[0].id))
    model.expenseDraft?.amount = "100.01"
    model.expenseDraft?.currency = trip.homeCurrency
    model.expenseDraft?.category = .stay
    model.expenseDraft?.select(.init(kind: .day, id: trip.days[1].id), in: trip)
    model.expenseDraft?.select(.init(kind: .day, id: trip.days[2].id), in: trip)
    _ = try await model.saveExpense()
    return (model, try #require(store.trip(trip.id)))
  }

  @Test func saveReopenEditAndCollapseKeepOneRecord() async throws {
    let (model, trip) = try await setup()
    #expect(trip.expenses.count == 1)
    #expect(Ledger(trip).total == 10001)
    let portion = try #require(trip.expenses(for: .init(kind: .day, id: trip.days[1].id)).first)
    model.editExpense(trip: trip, attachment: portion.attachment, expense: portion)
    #expect(model.expenseDraft?.amount == "100.01")
    model.expenseDraft?.amount = "120"
    model.expenseDraft?.select(.init(kind: .day, id: trip.days[0].id), in: trip)
    model.expenseDraft?.select(.init(kind: .day, id: trip.days[2].id), in: trip)
    let saved = try await model.saveExpense()
    #expect(saved.id == portion.id && saved.dayIds == nil)
    #expect(saved.attachment == portion.attachment)
    #expect(try #require(model.store.trip(trip.id)).expenses.count == 1)
    #expect(saved.amountMinor == "12000")
  }

  @Test func statusAndDeletionFromAShareUseTheWholeRecord() async throws {
    let (model, trip) = try await setup()
    let portion = try #require(trip.expenses(for: .init(kind: .day, id: trip.days[2].id)).first)
    model.toggleExpense(portion, trip: trip)
    let updated = try #require(model.store.trip(trip.id))
    #expect(updated.expenses[0].amountMinor == "10001")
    #expect(updated.expenses[0].dayIds?.count == 3)
    #expect(updated.expenses[0].status != trip.expenses[0].status)
    try model.deleteExpense(portion, trip: updated)
    #expect(try #require(model.store.trip(trip.id)).expenses.isEmpty)
  }

  @Test func movingAShareMovesTheWholeExpenseToOneDay() async throws {
    let (model, trip) = try await setup()
    let portion = try #require(trip.expenses(for: .init(kind: .day, id: trip.days[1].id)).first)
    let target = Attachment(kind: .day, id: trip.days[3].id)
    model.moveExpenses([portion], to: target, trip: trip)
    let moved = try #require(model.store.trip(trip.id)).expenses
    #expect(moved.count == 1 && moved[0].amountMinor == "10001")
    #expect(moved[0].attachment == target && moved[0].dayIds == nil)
  }

  @Test func persistedDraftKeepsItsSelectedDays() async throws {
    let (model, trip) = try await setup()
    model.expenseDraft = ExpenseDraft(trip: trip, attachment: trip.expenses[0].attachment,
      expense: trip.expenses[0])
    model.persistDraft()
    let reopened = AppModel(store: model.store)
    reopened.editExpense(trip: trip, attachment: .init(kind: .day, id: trip.days[3].id))
    #expect(reopened.expenseDraft?.selectedDayIDs == Set(trip.days.prefix(3).map(\.id)))
  }
}
