import Foundation
import Testing
import TripSplitDomain
import TripSplitNetworking

@testable import TripSplitApplication
@testable import TripSplitPersistence
@testable import TripSplitSync

private final class ExpenseFXProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> Data)?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      let data = try Self.handler!(request)
      client?.urlProtocol(self, didReceive: HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}

@Suite(.serialized) @MainActor struct ExpenseConversionTests {
  func setUp(online: Bool = false) throws -> (AppModel, TripSnapshot) {
    let store = try LocalStore(inMemory: true, installationID: "fx-test")
    var onboarding = OnboardingDraft()
    onboarding.currency = "GBP"
    onboarding.startsOn = CivilDate.adding(1, to: CivilDate.today(timeZone: "UTC"))
    onboarding.stops = [try #require(Destination.all.first { $0.currency == "TWD" }).stop()]
    let trip = try onboarding.makeTrip()
    try store.create(trip)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ExpenseFXProtocol.self]
    let sync = SyncCoordinator(store: store, api: APIClient(
      baseURL: online ? URL(string: "https://expense-fx.test") : nil,
      transport: URLSession(configuration: configuration)), sessionWriter: { _ in })
    sync.session = nil
    let model = AppModel(store: store, sync: sync)
    model.editExpense(trip: trip, attachment: .init(kind: .day, id: trip.days[0].id))
    model.expenseDraft?.amount = "45"
    return (model, trip)
  }

  func rates(date: String = "2026-10-01", twd: String = "50") -> FXTable {
    .init(base: "GBP", requestedDate: date, rateDate: date, source: "Test reference",
      rates: ["GBP": "1", "TWD": twd, "JPY": "200"])
  }

  @Test func tomorrowInTaiwanUsesLatestUTCRateAndCountsInTotals() async throws {
    let (model, trip) = try setUp(online: true)
    let today = CivilDate.today(timeZone: "UTC")
    ExpenseFXProtocol.handler = { request in
      let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
      #expect(query.first { $0.name == "date" }?.value == today)
      #expect(query.first { $0.name == "from" }?.value == "TWD")
      #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
      return try JSONEncoder().encode(FXQuote(
        id: "twd-gbp", from: "TWD", to: "GBP", rate: "0.02263",
        requestedDate: today, rateDate: today, source: "Test reference"))
    }
    model.cacheReferenceRates(rates())
    let expense = try await model.saveExpense()
    #expect(expense.conversion?.homeAmountMinor == "102")
    #expect(expense.conversion?.quoteId == "twd-gbp")
    let ledger = Ledger(try #require(model.store.trip(trip.id)))
    #expect(ledger.total == 102)
    #expect(ledger.unresolved == 0)
    #expect(model.store.read([String: FXQuote].self, key: "expenseQuotes")?["TWD/GBP"]?.rate == "0.02263")
  }

  @Test func offlineSaveUsesCachedRateWithItsOriginalDate() async throws {
    let (model, trip) = try setUp(online: true)
    ExpenseFXProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
    model.cacheReferenceRates(rates())
    let expense = try await model.saveExpense()
    #expect(expense.conversion?.homeAmountMinor == "90")
    #expect(expense.conversion?.rateDate == "2026-10-01")
    #expect(expense.conversion?.source == "Cached Test reference")
    #expect(expense.conversion?.quoteId == nil)
    #expect(expense.conversion?.kind == "manual")
    #expect(Ledger(try #require(model.store.trip(trip.id))).unresolved == 0)
  }

  @Test func newestCachedRateWinsAndHandlesZeroDecimalCurrency() async throws {
    let (model, _) = try setUp()
    model.expenseQuotes["JPY/GBP"] = .init(
      id: "old-quote", from: "JPY", to: "GBP", rate: "0.01",
      requestedDate: "2026-09-01", rateDate: "2026-09-01", source: "Test reference")
    model.cacheReferenceRates(rates())
    model.expenseDraft?.currency = "JPY"
    model.expenseDraft?.amount = "450"
    let expense = try await model.saveExpense()
    #expect(expense.conversion?.homeAmountMinor == "225")
    #expect(expense.conversion?.rateDate == "2026-10-01")
  }

  @Test func bankChargeReopensExactlyAndSurvivesLaterRateRefresh() async throws {
    let (model, trip) = try setUp()
    model.cacheReferenceRates(rates())
    let estimate = try await model.saveExpense()
    model.editExpense(trip: trip, attachment: estimate.attachment, expense: estimate)
    model.expenseDraft?.actualHomeAmount = "1.07"
    var charged = try await model.saveExpense()
    #expect(charged.conversion?.homeAmountMinor == "107")
    // The server adds this prefix to unquoted conversions.
    charged.conversion?.source = "Manual: " + Conversion.bankChargeSource
    try model.store.saveExpense(charged, tripID: trip.id)
    model.cacheReferenceRates(rates(date: "2026-10-02", twd: "40"))
    await model.refreshReferenceRates()
    model.editExpense(trip: trip, attachment: charged.attachment, expense: charged)
    #expect(model.expenseDraft?.actualHomeAmount == "1.07")
    model.expenseDraft?.title = "Coffee"
    let edited = try await model.saveExpense()
    #expect(edited.conversion?.homeAmountMinor == "107")
    #expect(edited.conversion?.isBankCharge == true)
    #expect(Ledger(try #require(model.store.trip(trip.id))).total == 107)
  }

  @Test func clearingBankChargeRestoresAutomaticConversion() async throws {
    let (model, trip) = try setUp()
    model.expenseDraft?.actualHomeAmount = "1.07"
    let charged = try await model.saveExpense()
    model.editExpense(trip: trip, attachment: charged.attachment, expense: charged)
    model.expenseDraft?.actualHomeAmount = ""
    model.cacheReferenceRates(rates())
    let expense = try await model.saveExpense()
    #expect(expense.conversion?.homeAmountMinor == "90")
    #expect(expense.conversion?.isBankCharge == false)
  }

  @Test func existingUnconvertedExpenseRepairsWithoutChangingSavedEstimates() async throws {
    let (model, trip) = try setUp()
    var expense = Expense(
      attachment: .init(kind: .day, id: trip.days[0].id), title: "Coffee", category: .coffee,
      amountMinor: "4500", currency: "TWD", status: .paid, paidOn: trip.startsOn,
      paidBy: trip.ownerTravellerId, splitWith: [trip.ownerTravellerId])
    try model.store.saveExpense(expense, tripID: trip.id)
    model.cacheReferenceRates(rates())
    await model.refreshReferenceRates()
    expense = try #require(model.store.trip(trip.id)?.expenses.first)
    #expect(expense.conversion?.homeAmountMinor == "90")
    model.cacheReferenceRates(rates(date: "2026-10-02", twd: "40"))
    await model.refreshReferenceRates()
    #expect(model.store.trip(trip.id)?.expenses.first == expense)
  }

  @Test func repairLeavesAttemptedSyncOperationsAndRestoreReviewAlone() async throws {
    let (model, trip) = try setUp()
    let expense = Expense(
      attachment: .init(kind: .day, id: trip.days[0].id), title: "Coffee", category: .coffee,
      amountMinor: "4500", currency: "TWD", status: .paid, paidOn: trip.startsOn,
      paidBy: trip.ownerTravellerId, splitWith: [trip.ownerTravellerId])
    try model.store.saveExpense(expense, tripID: trip.id)
    var envelope = try #require(model.store.envelopes[trip.id])
    envelope.pending[0].attempted = true
    try model.store.persist(envelope)
    model.cacheReferenceRates(rates())
    await model.refreshReferenceRates()
    #expect(model.store.envelopes[trip.id]?.pending[0].operation == envelope.pending[0].operation)
    #expect(model.store.trip(trip.id)?.expenses.first?.conversion == nil)
    envelope.pending[0].attempted = false
    envelope.restoreReview = true
    try model.store.persist(envelope)
    await model.refreshReferenceRates()
    #expect(model.store.trip(trip.id)?.expenses.first?.conversion == nil)
  }

  @Test func noRateKeepsDraftUntilConnectedOrBankChargeEntered() async throws {
    let (model, trip) = try setUp()
    model.persistDraft()
    await #expect(throws: ServiceError.self) { try await model.saveExpense() }
    #expect(model.store.trip(trip.id)?.expenses.isEmpty == true)
    #expect(model.store.read(ExpenseDraft.self, key: "expense:" + trip.id)?.amount == "45")
    model.expenseDraft?.actualHomeAmount = "1.07"
    #expect(try await model.saveExpense().conversion?.homeAmountMinor == "107")
  }
}
