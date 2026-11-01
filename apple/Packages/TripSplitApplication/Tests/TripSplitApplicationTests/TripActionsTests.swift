import Foundation
import Testing
import TripSplitApplication
import TripSplitDomain
import TripSplitNetworking
import TripSplitPersistence
import TripSplitSync

@MainActor struct TripActionsTests {
  private func app() throws -> (AppModel, TripSnapshot) {
    let store = try LocalStore(inMemory: true, installationID: "actions-test")
    let app = AppModel(store: store, sync: SyncCoordinator(store: store, api: APIClient(baseURL: nil)))
    app.onboarding = OnboardingDraft.newTrip()
    app.onboarding.stops = [try #require(Destination.country("PT")).stop(nights: 3)]
    app.onboarding.budget = "500"
    var trip = try app.createTrip()
    for (index, status) in [Expense.Status.paid, .planned].enumerated() {
      try store.saveExpense(
        Expense(
          attachment: .init(kind: .day, id: trip.days[0].id), title: "Expense \(index)",
          category: .food, amountMinor: "1000", currency: trip.homeCurrency, status: status,
          paidOn: status == .paid ? trip.days[0].date : nil, paidBy: trip.ownerTravellerId,
          splitWith: [trip.ownerTravellerId]), tripID: trip.id)
    }
    trip = try #require(store.trip(trip.id))
    return (app, trip)
  }

  @Test func movingExpensesRedatesThePaidOnes() throws {
    let (app, trip) = try app()
    let to = Attachment(kind: .day, id: trip.days[2].id)
    app.moveExpenses(trip.expenses, to: to, trip: trip)
    let moved = try #require(app.store.trip(trip.id)).expenses(for: to)
    #expect(moved.count == 2)
    #expect(moved.first { $0.status == .paid }?.paidOn == trip.days[2].date)
    #expect(moved.first { $0.status == .planned }?.paidOn == nil)
    #expect(app.toast?.hasPrefix("Moved 2 expenses") == true)
  }

  @Test func clearingADayLeavesTheRestOfTheTrip() throws {
    let (app, trip) = try app()
    let other = Attachment(kind: .day, id: trip.days[1].id)
    app.moveExpenses([trip.expenses[0]], to: other, trip: trip)
    app.clearDay(.init(kind: .day, id: trip.days[0].id), trip: try #require(app.store.trip(trip.id)))
    let after = try #require(app.store.trip(trip.id))
    #expect(after.expenses.map(\.attachment) == [other])
  }

  @Test func deletingAnOfflineTripClosesIt() async throws {
    let (app, trip) = try app()
    app.selectedTripID = trip.id
    app.selectedAttachment = .init(kind: .day, id: trip.days[0].id)
    app.globeTripID = trip.id
    await app.deleteTrip(trip)
    #expect(app.store.trip(trip.id) == nil)
    #expect(app.selectedTripID == nil)
    #expect(app.selectedAttachment == nil)
    #expect(app.globeTripID == nil)
    #expect(app.error == nil)
  }
}
