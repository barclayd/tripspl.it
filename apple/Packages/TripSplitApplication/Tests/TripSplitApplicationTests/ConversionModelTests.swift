import Foundation
import Testing
import TripSplitDomain
import TripSplitNetworking

@testable import TripSplitApplication
@testable import TripSplitConversion
@testable import TripSplitPersistence
@testable import TripSplitSync

private actor ControlledConversionQuotes {
  struct Request: Sendable {
    let from: String
    let to: String
    let date: String
    let continuation: CheckedContinuation<FXQuote, any Error>
  }
  private var requests: [Request] = []
  private var observers: [(Int, CheckedContinuation<Void, Never>)] = []
  func load(_ from: String, _ to: String, _ date: String) async throws -> FXQuote {
    try await withCheckedThrowingContinuation { continuation in
      requests.append(.init(from: from, to: to, date: date, continuation: continuation))
      let ready = observers.filter { requests.count >= $0.0 }
      observers.removeAll { requests.count >= $0.0 }
      ready.forEach { $0.1.resume() }
    }
  }
  func waitForCount(_ count: Int) async {
    if requests.count >= count { return }
    await withCheckedContinuation { observers.append((count, $0)) }
  }
  func resolve(_ index: Int, rate: String, overrideFrom: String? = nil, overrideDate: String? = nil)
  {
    let request = requests[index]
    request.continuation.resume(
      returning: FXQuote(
        id: "quote-\(index)", from: overrideFrom ?? request.from, to: request.to, rate: rate,
        requestedDate: overrideDate ?? request.date, rateDate: request.date, source: "Test provider"
      ))
  }
  var count: Int { requests.count }
  func date(_ index: Int) -> String { requests[index].date }
}

@MainActor struct ConversionModelTests {
  private func model(
    _ server: ControlledConversionQuotes, from: String = "EUR", to: String = "GBP",
    date: String = "2026-10-01"
  ) -> ConversionModel {
    ConversionModel(from: .forCurrency(from), to: .forCurrency(to), date: date, today: "2026-11-01")
    {
      try await server.load($0, $1, $2)
    }
  }
  @Test func lateOldPairQuoteCannotReplaceNewPair() async throws {
    let server = ControlledConversionQuotes()
    let model = model(server)
    let first = model.start()
    await server.waitForCount(1)
    let second = model.select(.forCurrency("JPY"), for: .from)
    await server.waitForCount(2)
    await server.resolve(1, rate: "0.005")
    await second?.value
    await server.resolve(0, rate: "0.8")
    await first?.value
    #expect(model.from.code == "JPY")
    #expect(model.quote?.from == "JPY")
    #expect(model.result == 5)
    #expect(!model.isLoading)
  }
  @Test func manualRateWinsOverLateQuoteAndClearsOnPairChange() async {
    let server = ControlledConversionQuotes()
    let model = model(server)
    let pending = model.start()
    await server.waitForCount(1)
    model.enterManualRate("0.8")
    await server.resolve(0, rate: "0.9")
    await pending?.value
    #expect(model.result == 800)
    #expect(model.quote == nil)
    #expect(model.usesManualRate)
    let next = model.select(.forCurrency("USD"), for: .to)
    await server.waitForCount(2)
    #expect(model.rateInput.isEmpty)
    #expect(!model.usesManualRate)
    #expect(model.result == nil)
    await server.resolve(1, rate: "1.1")
    await next?.value
    #expect(model.result == 1100)
  }
  @Test func identityWorksOfflineAndMakesNoRequest() async {
    let server = ControlledConversionQuotes()
    let model = model(server, from: "KWD", to: "KWD")
    model.amount = "12.345"
    #expect(model.start() == nil)
    #expect(model.result == 12345)
    #expect(model.quote == nil)
    #expect(!model.isLoading)
    #expect(await server.count == 0)
  }
  @Test func returningFromPickerDoesNotResetOverrideOrManualRate() async {
    let server = ControlledConversionQuotes()
    let model = model(server)
    let first = model.start()
    await server.waitForCount(1)
    await server.resolve(0, rate: "0.8")
    await first?.value
    let changed = model.select(.forCurrency("JPY"), for: .from)
    await server.waitForCount(2)
    model.enterManualRate("0.005")
    #expect(model.start() == nil)
    #expect(model.from.code == "JPY")
    #expect(model.rateInput == "0.005")
    await server.resolve(1, rate: "0.004")
    await changed?.value
    #expect(model.rateInput == "0.005")
    #expect(model.result == 5)
  }
  @Test func swapPreservesAmountAndRevalidatesMinorUnits() async {
    let server = ControlledConversionQuotes()
    let model = model(server, from: "KWD", to: "JPY")
    model.amount = "12.345"
    model.enterManualRate("400")
    #expect(model.result == 4938)
    let pending = model.swap()
    await server.waitForCount(1)
    #expect(model.amount == "12.345")
    #expect(model.from.code == "JPY")
    #expect(model.to.code == "KWD")
    #expect(model.amountIssue != nil)
    #expect(model.result == nil)
    #expect(model.rateInput.isEmpty)
    await server.resolve(0, rate: "0.0025")
    await pending?.value
  }
  @Test func futureDatesUseTodayAndHistoricalDatesRemainHistorical() async {
    let server = ControlledConversionQuotes()
    let future = model(server, date: "2027-03-12")
    let first = future.start()
    await server.waitForCount(1)
    #expect(await server.date(0) == "2026-11-01")
    await server.resolve(0, rate: "0.8")
    await first?.value
    let historical = model(server, date: "2025-07-10")
    let second = historical.start()
    await server.waitForCount(2)
    #expect(await server.date(1) == "2025-07-10")
    await server.resolve(1, rate: "0.8")
    await second?.value
  }
  @Test func mismatchedQuoteIsRejected() async {
    let server = ControlledConversionQuotes()
    let model = model(server)
    let pending = model.start()
    await server.waitForCount(1)
    await server.resolve(0, rate: "0.8", overrideFrom: "USD")
    await pending?.value
    #expect(model.quote == nil)
    #expect(model.result == nil)
    #expect(model.message?.contains("didn’t match") == true)
  }
  @Test func resetRestoresTripChoicesButPreservesAmount() async {
    let server = ControlledConversionQuotes()
    let model = model(server, from: "JPY", to: "USD")
    model.amount = "500"
    model.enterManualRate("0.006")
    let request = model.reset(
      from: .forCurrency("EUR", preferredCountryCode: "PT"), to: .forCurrency("GBP"))
    await server.waitForCount(1)
    #expect(model.from.code == "EUR")
    #expect(model.from.countryCode == "PT")
    #expect(model.to.code == "GBP")
    #expect(model.amount == "500")
    #expect(model.rateInput.isEmpty)
    await server.resolve(0, rate: "0.8")
    await request?.value
  }
  @Test func handoffRequiresHomeTargetAndPreservesVerifiedRate() async throws {
    var onboarding = OnboardingDraft()
    onboarding.stops = [Destination.all[0].stop()]
    let trip = try onboarding.makeTrip()
    let attachment = Attachment(kind: .day, id: trip.days[0].id)
    let server = ControlledConversionQuotes()
    let model = model(server)
    let pending = model.start()
    await server.waitForCount(1)
    await server.resolve(0, rate: "0.8")
    await pending?.value
    let draft = try model.expenseDraft(trip: trip, attachment: attachment)
    #expect(draft.amount == "10")
    #expect(draft.currency == "EUR")
    #expect(draft.conversion?.quoteId == "quote-0")
    #expect(draft.conversion?.homeAmountMinor == "800")
    let changed = model.select(.forCurrency("USD"), for: .to)
    await server.waitForCount(2)
    #expect(!model.canLogExpense(homeCurrency: "GBP"))
    #expect(throws: MoneyError.self) { try model.expenseDraft(trip: trip, attachment: attachment) }
    await server.resolve(1, rate: "1.1")
    await changed?.value
  }
  @Test func manualHandoffRetainsRateInsteadOfClaimingAnActualCharge() throws {
    var onboarding = OnboardingDraft()
    onboarding.stops = [Destination.all[0].stop()]
    let trip = try onboarding.makeTrip()
    let server = ControlledConversionQuotes()
    let model = model(server)
    model.enterManualRate("0,8")
    let draft = try model.expenseDraft(
      trip: trip, attachment: .init(kind: .day, id: trip.days[0].id))
    #expect(draft.actualHomeAmount.isEmpty)
    #expect(draft.conversion?.rate == "0.8")
    #expect(draft.conversion?.kind == "manual")
    #expect(draft.conversion?.homeAmountMinor == "800")
    #expect(draft.conversion?.source == "Manual exchange rate")
  }
  @Test func invalidManualRateAndOverflowCannotBecomeAnotherRateDuringHandoff() throws {
    var onboarding = OnboardingDraft()
    onboarding.stops = [Destination.all[0].stop()]
    let trip = try onboarding.makeTrip()
    let attachment = Attachment(kind: .day, id: trip.days[0].id)
    let model = model(ControlledConversionQuotes())
    model.enterManualRate("0")
    #expect(model.conversionIssue != nil)
    #expect(!model.canLogExpense(homeCurrency: "GBP"))
    #expect(throws: MoneyError.self) { try model.expenseDraft(trip: trip, attachment: attachment) }
    model.amount = "9999999999.99"
    model.enterManualRate("2")
    #expect(model.parsedAmount != nil)
    #expect(model.result == nil)
    #expect(!model.canLogExpense(homeCurrency: "GBP"))
    #expect(throws: MoneyError.self) { try model.expenseDraft(trip: trip, attachment: attachment) }
  }
  @Test func missingRateStillAllowsAnHonestPendingExpense() throws {
    var onboarding = OnboardingDraft()
    onboarding.stops = [Destination.all[0].stop()]
    let trip = try onboarding.makeTrip()
    let model = model(ControlledConversionQuotes())
    #expect(model.canLogExpense(homeCurrency: "GBP"))
    let draft = try model.expenseDraft(
      trip: trip, attachment: .init(kind: .day, id: trip.days[0].id))
    #expect(draft.conversion == nil)
    #expect(draft.actualHomeAmount.isEmpty)
    #expect(draft.amount == "10")
  }

}
