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
    _ = try await model.expenseConversion(4500, from: "TWD", to: "GBP")
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

  @Test func noRateSavesLocallyAndFillsWhenRatesReturn() async throws {
    let (model, trip) = try setUp()
    model.persistDraft()
    let saved = try await model.saveExpense()
    #expect(saved.conversion == nil)
    #expect(model.store.trip(trip.id)?.expenses.count == 1)
    #expect(model.store.read(ExpenseDraft.self, key: "expense:" + trip.id) == nil)
    #expect(Ledger(try #require(model.store.trip(trip.id))).unresolved == 1)
    let clock = model.store.envelopes[trip.id]?.pending.first?.operation.editedAt
    model.cacheReferenceRates(rates())
    await model.repairExpenseConversions()
    #expect(model.store.trip(trip.id)?.expenses.first?.conversion?.homeAmountMinor == "90")
    #expect(model.store.envelopes[trip.id]?.pending.first?.operation.editedAt == clock)
    #expect(Ledger(try #require(model.store.trip(trip.id))).unresolved == 0)
  }

  @Test func quickConvertPersistsFetchedRateAcrossRestartAndOfflineFailure() async throws {
    let (model, _) = try setUp(online: true)
    let date = "2026-10-30"
    ExpenseFXProtocol.handler = { _ in
      try JSONEncoder().encode(FXQuote(
        id: "saved-quote", from: "TWD", to: "GBP", rate: "0.025",
        requestedDate: date, rateDate: date, source: "Test reference"))
    }
    _ = try await model.conversionQuote(from: "TWD", to: "GBP", date: date)
    let cached = try #require(model.cachedConversionRate(from: "TWD", to: "GBP", date: date))
    #expect(cached.fetchedAt != nil)
    let restarted = AppModel(store: model.store, sync: model.sync)
    ExpenseFXProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
    await #expect(throws: URLError.self) {
      try await restarted.conversionQuote(from: "TWD", to: "GBP", date: "2026-11-01")
    }
    let offline = try #require(restarted.cachedConversionRate(from: "TWD", to: "GBP", date: "2026-11-01"))
    #expect(offline.fetchedAt == cached.fetchedAt)
    #expect(offline.quoteID == "saved-quote")
    #expect(try offline.conversion(6500).homeAmountMinor == "163")
    #expect(restarted.cachedConversionRate(from: "TWD", to: "GBP", date: "2026-10-29") == nil)
    #expect(restarted.cachedConversionRate(from: "JPY", to: "GBP", date: date) == nil)
  }

  @Test func legacyTableHasPublicationDateUntilARealFetchAndSupportsCrossRates() throws {
    let (model, _) = try setUp()
    try model.store.write(rates(), key: "referenceRates")
    let legacy = AppModel(store: model.store, sync: model.sync)
    let rate = try #require(legacy.cachedConversionRate(from: "TWD", to: "JPY", date: "2026-11-01"))
    #expect(rate.rate == "4")
    #expect(rate.rateDate == "2026-10-01")
    #expect(rate.fetchedAt == nil)
    let fetchedAt = Date(timeIntervalSince1970: 1_790_000_000)
    legacy.cacheReferenceRates(rates(), fetchedAt: fetchedAt)
    let restarted = AppModel(store: model.store, sync: model.sync)
    #expect(restarted.cachedConversionRate(from: "TWD", to: "JPY", date: "2026-11-01")?.fetchedAt == fetchedAt)
  }

  @Test func mismatchedFetchDoesNotReplaceSavedRateOrTimestamp() async throws {
    let (model, _) = try setUp(online: true)
    let fetchedAt = Date(timeIntervalSince1970: 1_790_000_000)
    model.cacheReferenceRates(rates(), fetchedAt: fetchedAt)
    ExpenseFXProtocol.handler = { _ in
      try JSONEncoder().encode(FXQuote(
        id: "wrong-pair", from: "USD", to: "GBP", rate: "0.8",
        requestedDate: "2026-11-01", rateDate: "2026-11-01", source: "Test"))
    }
    await #expect(throws: ServiceError.self) {
      try await model.conversionQuote(from: "TWD", to: "GBP", date: "2026-11-01")
    }
    let saved = model.cachedConversionRate(from: "TWD", to: "GBP", date: "2026-11-01")
    #expect(saved?.rate == "0.02")
    #expect(saved?.fetchedAt == fetchedAt)
    #expect(model.conversionRates.isEmpty)
  }
  func rateChangeEnvelope(before: Int64 = 450, after: Int64 = 462, currency: String = "GBP") throws
    -> TripEnvelope
  {
    let (_, original) = try setUp()
    var trip = original
    trip.homeCurrency = currency
    let cached = Conversion(
      homeAmountMinor: String(before), rate: "0.02", rateDate: "2026-10-01",
      source: "Cached reference", kind: "manual", estimateDate: "2026-10-05")
    trip.expenses = [
      .init(
        id: "coffee", revision: 1,
        attachment: .init(kind: .day, id: trip.days[0].id), title: "Coffee", category: .coffee,
        amountMinor: "4500", currency: "TWD", status: .planned,
        paidBy: trip.ownerTravellerId, splitWith: [trip.ownerTravellerId], conversion: cached)
    ]
    var updated = trip
    updated.expenses[0].revision = 2
    updated.expenses[0].conversion = .init(
      homeAmountMinor: String(after), rate: "0.021", rateDate: "2026-10-05",
      source: "Reference", kind: "reference", quoteId: "current")
    var envelope = TripEnvelope(confirmed: updated, installationID: "fx-test")
    envelope.recordRateChanges(from: trip)
    return envelope
  }

  @Test func significantRateChangesNotifyInBothDirectionsButOneMinorUnitDoesNot() throws {
    for currency in ["GBP", "USD", "JPY", "BHD"] {
      for difference in [Int64(-1), 0, 1] {
        #expect(
          try rateChangeEnvelope(after: 450 + difference, currency: currency).pendingRateChanges?
            .isEmpty != false)
      }
      for difference in [Int64(-2), 2] {
        let envelope = try rateChangeEnvelope(after: 450 + difference, currency: currency)
        #expect(envelope.pendingRateChanges?.count == 1)
        #expect(envelope.pendingRateChanges?.first?.beforeMinor == 450)
        #expect(envelope.pendingRateChanges?.first?.afterMinor == 450 + difference)
      }
    }
  }

  @Test func rateChangeNoticeSurvivesRestartAndWaitsForTheSaveToast() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".store")
    let store = try LocalStore(installationID: "fx-test", storeURL: url)
    var envelope = try rateChangeEnvelope()
    // Polling the same final snapshot cannot append another notice.
    envelope.recordRateChanges(from: envelope.confirmed)
    #expect(envelope.pendingRateChanges?.count == 1)
    try store.persist(envelope)
    let restarted = try LocalStore(installationID: "fx-test", storeURL: url)
    let model = AppModel(store: restarted)
    model.toast = "Expense saved"
    model.presentRateChanges()
    #expect(model.toast == "Expense saved")
    #expect(model.pendingRateChangeID != nil)
    model.toast = nil
    model.presentRateChanges()
    #expect(model.toast == "Rate updated · Coffee\n£4.50 → £4.62")
    #expect(model.pendingRateChangeID == nil)
    let again = try LocalStore(installationID: "fx-test", storeURL: url)
    #expect(again.envelopes[envelope.confirmed.id]?.pendingRateChanges == nil)
  }

  @Test func userEditsAndAccountChangesCannotShowStaleRateNotices() throws {
    let store = try LocalStore(inMemory: true, installationID: "fx-test")
    var envelope = try rateChangeEnvelope()
    envelope.accountID = "owner"
    try store.persist(envelope)
    let model = AppModel(store: store)
    model.presentRateChanges()
    #expect(model.toast == nil)
    store.activeAccountID = "owner"
    var expense = envelope.confirmed.expenses[0]
    expense.amountMinor = "5000"
    try store.saveExpense(expense, tripID: envelope.confirmed.id)
    model.presentRateChanges()
    #expect(model.toast == nil)
    #expect(model.pendingRateChangeID == nil)
  }

  @Test func manualAmountsAndUnrelatedEditsDoNotProduceRateNotices() throws {
    var envelope = try rateChangeEnvelope()
    var old = envelope.confirmed
    old.expenses[0].conversion?.homeAmountMinor = "450"
    // An already settled reference rate has no automatic-estimate marker.
    envelope.pendingRateChanges = nil
    envelope.recordRateChanges(from: old)
    #expect(envelope.pendingRateChanges == nil)
    old.expenses[0].conversion?.estimateDate = "2026-10-05"
    envelope.confirmed.expenses[0].conversion?.kind = "manual"
    envelope.recordRateChanges(from: old)
    #expect(envelope.pendingRateChanges == nil)
    envelope.confirmed.expenses[0].conversion?.kind = "reference"
    envelope.confirmed.expenses[0].amountMinor = "6000"
    envelope.recordRateChanges(from: old)
    #expect(envelope.pendingRateChanges == nil)
  }

}
