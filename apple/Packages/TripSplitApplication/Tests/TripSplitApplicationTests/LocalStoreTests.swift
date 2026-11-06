import Foundation
import Testing
import TripSplitDomain
import TripSplitNetworking

@testable import TripSplitApplication
@testable import TripSplitConversion
@testable import TripSplitPersistence
@testable import TripSplitSync

@Suite(.serialized) @MainActor struct LocalStoreTests {
  func trip() throws -> TripSnapshot {
    var draft = OnboardingDraft()
    draft.stops = [Destination.all[0].stop()]
    return try draft.makeTrip()
  }
  func expense(_ trip: TripSnapshot) -> Expense {
    .init(
      attachment: .init(kind: .day, id: trip.days[0].id), title: "Coffee", category: .coffee,
      amountMinor: "601", currency: trip.homeCurrency, status: .paid, paidOn: trip.startsOn,
      paidBy: trip.ownerTravellerId, splitWith: [trip.ownerTravellerId])
  }
  @Test func converterQuoteTransfersToExpenseAndRecomputesEditedAmount() async throws {
    let store = try LocalStore(inMemory: true, installationID: "test")
    let trip = try trip()
    try store.create(trip)
    let model = AppModel(store: store)
    var draft = ExpenseDraft(trip: trip, attachment: .init(kind: .day, id: trip.days[0].id))
    draft.currency = "EUR"
    draft.amount = "20.00"
    draft.conversion = Conversion(
      homeAmountMinor: "860", rate: "0.86", rateDate: trip.startsOn, source: "Reference provider",
      kind: "reference", quoteId: "quote-id")
    model.expenseDraft = draft
    let saved = try await model.saveExpense()
    #expect(saved.conversion?.quoteId == "quote-id")
    #expect(saved.conversion?.homeAmountMinor == "1720")
  }
  @Test func converterManualRateRecomputesWhenExpenseAmountChanges() async throws {
    let store = try LocalStore(inMemory: true, installationID: "test")
    let trip = try trip()
    try store.create(trip)
    let converter = ConversionModel(
      from: .forCurrency("EUR"), to: .forCurrency(trip.homeCurrency), date: trip.startsOn,
      loadQuote: { _, _, _ in throw URLError(.notConnectedToInternet) })
    converter.enterManualRate("0.8")
    var draft = try converter.expenseDraft(
      trip: trip, attachment: .init(kind: .day, id: trip.days[0].id))
    #expect(draft.actualHomeAmount.isEmpty)
    #expect(draft.conversion?.homeAmountMinor == "800")
    draft.amount = "20"
    let model = AppModel(store: store)
    model.expenseDraft = draft
    let saved = try await model.saveExpense()
    #expect(saved.conversion?.homeAmountMinor == "1600")
    #expect(saved.conversion?.rate == "0.8")
    #expect(saved.conversion?.kind == "manual")
    #expect(saved.conversion?.quoteId == nil)
  }

  @Test func explicitCardChargeOverridesConverterEstimate() async throws {
    let store = try LocalStore(inMemory: true, installationID: "test")
    let trip = try trip()
    try store.create(trip)
    var draft = ExpenseDraft(trip: trip, attachment: .init(kind: .day, id: trip.days[0].id))
    draft.currency = "EUR"
    draft.amount = "20"
    draft.conversion = Conversion(
      homeAmountMinor: "800", rate: "0.8", rateDate: trip.startsOn,
      source: "Manual exchange rate", kind: "manual", quoteId: nil)
    draft.actualHomeAmount = "17.25"
    let model = AppModel(store: store)
    model.expenseDraft = draft
    let saved = try await model.saveExpense()
    #expect(saved.conversion?.homeAmountMinor == "1725")
    #expect(saved.conversion?.source == "Actual card charge entered by traveller")
  }

  @Test func savedReceiptDoesNotRestoreDuplicateDraft() async throws {
    let store = try LocalStore(inMemory: true, installationID: "test")
    let trip = try trip()
    try store.create(trip)
    let model = AppModel(store: store)
    var draft = ExpenseDraft(trip: trip, attachment: .init(kind: .day, id: trip.days[0].id))
    draft.amount = "6.01"
    draft.currency = trip.homeCurrency
    model.expenseDraft = draft
    model.persistDraft()
    let saved = try await model.saveExpense()
    #expect(saved.id == draft.id)
    model.persistDraft()
    #expect(store.read(ExpenseDraft.self, key: "expense:" + trip.id) == nil)
    #expect(store.trip(trip.id)?.expenses.count == 1)
  }
  @Test func realInstallationIdentityAllowsLocalStartupWithoutCredentials() throws {
    let first = try LocalStore(inMemory: true)
    let second = try LocalStore(inMemory: true)
    #expect(!first.installationID.isEmpty)
    #expect(first.installationID == second.installationID)
    #expect(first.trips.isEmpty)
  }
  @Test func editAndOutboxSurviveRestartTogether() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".store")
    let first = try LocalStore(installationID: "device-a", storeURL: url)
    let trip = try trip()
    try first.create(trip)
    var expense = expense(trip)
    expense.dayIds = Array(trip.days.prefix(2).map(\.id))
    try first.saveExpense(expense, tripID: trip.id)
    let second = try LocalStore(installationID: "device-a", storeURL: url)
    #expect(second.trip(trip.id)?.expenses.first == expense)
    #expect(
      second.envelopes[trip.id]?.pending.first?.id == first.envelopes[trip.id]?.pending.first?.id)
    #expect(second.envelopes[trip.id]?.confirmed.expenses.isEmpty == true)
  }
  @Test func restoredInstallationRequiresReviewAndKeepsOperationIdentity() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".store")
    let first = try LocalStore(installationID: "device-a", storeURL: url)
    let trip = try trip()
    try first.create(trip)
    try first.saveExpense(expense(trip), tripID: trip.id)
    let second = try LocalStore(installationID: "device-b", storeURL: url)
    #expect(second.envelopes[trip.id]?.restoreReview == true)
    #expect(
      second.envelopes[trip.id]?.pending.first?.id == first.envelopes[trip.id]?.pending.first?.id)
  }
  @Test func neverSentEditsCoalesceAndNewDeleteCancels() throws {
    let store = try LocalStore(inMemory: true, installationID: "test")
    let trip = try trip()
    try store.create(trip)
    var expense = expense(trip)
    try store.saveExpense(expense, tripID: trip.id)
    expense.amountMinor = "702"
    try store.saveExpense(expense, tripID: trip.id)
    #expect(store.envelopes[trip.id]?.pending.count == 1)
    #expect(store.envelopes[trip.id]?.pending.first?.operation.expectedRevision == nil)
    try store.deleteExpense(expense, tripID: trip.id)
    #expect(store.envelopes[trip.id]?.pending.isEmpty == true)
    #expect(store.trip(trip.id)?.expenses.isEmpty == true)
  }
  @Test func attemptedOperationIsImmutableAndNewDraftPersists() throws {
    let store = try LocalStore(inMemory: true, installationID: "test")
    let trip = try trip()
    try store.create(trip)
    var expense = expense(trip)
    try store.saveExpense(expense, tripID: trip.id)
    var envelope = try #require(store.envelopes[trip.id])
    envelope.pending[0].attempted = true
    try store.persist(envelope)
    var draft = ExpenseDraft(trip: trip, attachment: expense.attachment, expense: expense)
    draft.amount = "9.00"
    try store.write(draft, key: "expense:" + trip.id)
    expense.amountMinor = "900"
    #expect(throws: ServiceError.self) { try store.saveExpense(expense, tripID: trip.id) }
    #expect(store.envelopes[trip.id]?.pending[0].operation == envelope.pending[0].operation)
    #expect(store.read(ExpenseDraft.self, key: "expense:" + trip.id)?.amount == "9.00")
  }
  @Test func accountBoundTripsHiddenFromOtherAccounts() throws {
    let store = try LocalStore(inMemory: true, installationID: "test")
    let trip = try trip()
    var envelope = TripEnvelope(confirmed: trip, accountID: "account-a", installationID: "test")
    try store.persist(envelope)
    store.activeAccountID = "account-b"
    #expect(store.trips.isEmpty)
    #expect(store.trip(trip.id) == nil)
    store.activeAccountID = "account-a"
    #expect(store.trips.count == 1)
    envelope.accountID = nil
    try store.persist(envelope)
    store.activeAccountID = nil
    #expect(store.trips.count == 1)
  }
  @Test func successfulAppleExpiryUsesFractionalTimestamp() {
    #expect(SyncCoordinator.expiry("2026-10-31T23:59:59.123Z") != nil)
    #expect(SyncCoordinator.expiry("2026-10-31T23:59:59Z") != nil)
  }
}
