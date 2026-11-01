import Foundation
import Testing
import TripSplitDomain

@testable import TripSplitApplication
@testable import TripSplitPersistence

/// A return booked on the phone splits across getting there and getting home, as on the watch.
@Suite(.serialized) @MainActor struct ReturnTicketSaveTests {
  func setUp() throws -> (AppModel, LocalStore, TripSnapshot) {
    let store = try LocalStore(inMemory: true, installationID: "test")
    var draft = OnboardingDraft()
    draft.stops = [Destination.all[0].stop()]
    draft.travellers += [Traveller(name: "Maya", hue: 250)]
    let trip = try draft.makeTrip()
    try store.create(trip)
    return (AppModel(store: store), store, trip)
  }

  func leg(_ trip: TripSnapshot, _ kind: TravelLeg.Kind) throws -> TripSplitDomain.Attachment {
    .init(kind: .leg, id: try #require(trip.legs.first { $0.kind == kind }).id)
  }

  func book(_ model: AppModel, _ trip: TripSnapshot, amount: String) async throws -> [Expense] {
    model.editExpense(trip: trip, attachment: try leg(trip, .outbound))
    #expect(model.expenseDraft?.isReturn == true)
    model.expenseDraft?.amount = amount
    _ = try await model.saveExpense()
    return try halves(model, trip)
  }

  func halves(_ model: AppModel, _ trip: TripSnapshot) throws -> [Expense] {
    let saved = try #require(model.store.trip(trip.id))
    let order = [try leg(trip, .outbound).id, try leg(trip, .return).id]
    return saved.expenses.sorted {
      (order.firstIndex(of: $0.attachment.id) ?? 2) < (order.firstIndex(of: $1.attachment.id) ?? 2)
    }
  }

  @Test func aReturnSavesHalfGettingThereAndHalfGettingHome() async throws {
    let (model, _, trip) = try setUp()
    let saved = try await book(model, trip, amount: "420.01")
    #expect(saved.map(\.attachment) == [try leg(trip, .outbound), try leg(trip, .return)])
    #expect(saved.map(\.amountMinor) == ["21001", "21000"])
    #expect(saved.allSatisfy { $0.title == "Return flight" && $0.returnPairId == saved[0].id })
    #expect(saved[0].splitWith == saved[1].splitWith && saved[0].splitWith.count == 2)
  }

  @Test func eitherHalfEditsTheWholeTicketUntilItsOneWay() async throws {
    let (model, store, trip) = try setUp()
    let saved = try await book(model, trip, amount: "420.01")
    model.editExpense(
      trip: try #require(store.trip(trip.id)), attachment: saved[1].attachment, expense: saved[1])
    let draft = try #require(model.expenseDraft)
    #expect(draft.expenseID == saved[0].id)
    #expect(draft.attachment == saved[0].attachment)
    #expect(try Money.parse(draft.amount, currency: draft.currency) == 42001)
    #expect(draft.isReturn)

    model.expenseDraft?.amount = "500"
    _ = try await model.saveExpense()
    let edited = try halves(model, trip)
    #expect(edited.map(\.id) == saved.map(\.id))
    #expect(edited.map(\.amountMinor) == ["25000", "25000"])

    model.editExpense(
      trip: try #require(store.trip(trip.id)), attachment: edited[0].attachment, expense: edited[0])
    model.expenseDraft?.coversReturn = false
    _ = try await model.saveExpense()
    let oneWay = try halves(model, trip)
    #expect(oneWay.count == 1)
    #expect(oneWay.first?.id == saved[0].id)
    #expect(oneWay.first?.amountMinor == "50000")
    #expect(oneWay.first?.title == "Flight")
    #expect(oneWay.first?.returnPairId == nil)
  }

  @Test func aNameYouTypedStaysAndOneWayTravelIsntSplit() async throws {
    let (model, _, trip) = try setUp()
    model.editExpense(trip: trip, attachment: try leg(trip, .outbound))
    model.expenseDraft?.amount = "80"
    model.expenseDraft?.title = "Eurostar"
    model.expenseDraft?.category = .train
    _ = try await model.saveExpense()
    #expect(try halves(model, trip).map(\.title) == ["Eurostar", "Eurostar"])

    let (other, _, another) = try setUp()
    other.editExpense(trip: another, attachment: try leg(another, .outbound))
    other.expenseDraft?.amount = "35"
    other.expenseDraft?.category = .taxi
    _ = try await other.saveExpense()
    let taxi = try halves(other, another)
    #expect(taxi.count == 1)
    #expect(taxi.first?.returnPairId == nil)
    #expect(taxi.first?.amountMinor == "3500")
  }

  @Test func deletingClearingAndTickingOffTakeBothHalves() async throws {
    let (model, store, trip) = try setUp()
    var saved = try await book(model, trip, amount: "300")
    let flipped: Expense.Status = saved[1].status == .paid ? .planned : .paid
    model.toggleExpense(saved[1], trip: try #require(store.trip(trip.id)))
    let ticked = try halves(model, trip)
    #expect(ticked.map(\.status) == [flipped, flipped])
    #expect(ticked[0].paidOn == ticked[1].paidOn)

    try model.deleteExpense(saved[1], trip: try #require(store.trip(trip.id)))
    #expect(try halves(model, trip).isEmpty)

    saved = try await book(model, trip, amount: "300")
    model.clearDay(try leg(trip, .outbound), trip: try #require(store.trip(trip.id)))
    #expect(try halves(model, trip).isEmpty)
  }

  @Test func movingAHalfLeavesTwoPlainExpenses() async throws {
    let (model, store, trip) = try setUp()
    let saved = try await book(model, trip, amount: "300")
    let day = TripSplitDomain.Attachment(kind: .day, id: trip.days[0].id)
    model.moveExpenses([saved[1]], to: day, trip: try #require(store.trip(trip.id)))
    let moved = try halves(model, trip)
    #expect(moved.count == 2)
    #expect(moved.allSatisfy { $0.returnPairId == nil })
    #expect(moved.map(\.attachment) == [saved[0].attachment, day])
  }
}
