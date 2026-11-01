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
}
