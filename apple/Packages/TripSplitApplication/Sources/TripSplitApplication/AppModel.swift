import Foundation
import Observation
import TripSplitDomain
import TripSplitNetworking
import TripSplitPersistence
import TripSplitSync

@MainActor @Observable public final class AppModel {
  public let store: LocalStore
  public let sync: SyncCoordinator
  public var selectedTab = 0
  public var selectedTripID: String?
  public var selectedAttachment: Attachment?
  public var fullScreenDay = false
  public var showOnboarding = false
  public var showSettings = false
  public var showConverter = false
  public var showTripSettings = false
  public var expenseDraft: ExpenseDraft?
  private var completedDraftID: String?
  public var onboarding: OnboardingDraft
  public var toast: String?
  public var error: String?
  public var globeFilter = GlobeFilter.all {
    didSet { if globeFilter != oldValue { globeTripID = nil } }
  }
  /// The trip highlighted on the globe, kept across tab switches.
  public var globeTripID: String?
  public var inviteURL: URL?
  public var pendingInvitation: URL?
  /// The last reference rates from pounds, also used to save expense estimates offline.
  public private(set) var referenceRates: FXTable?
  var expenseQuotes: [String: FXQuote] = [:]
  var repairingConversions = false
  public var selectedTrip: TripSnapshot? { selectedTripID.flatMap { store.trip($0) } }
  public init(store: LocalStore, sync: SyncCoordinator? = nil) {
    self.store = store
    self.sync = sync ?? SyncCoordinator(store: store)
    onboarding = store.read(OnboardingDraft.self, key: "onboarding") ?? .newTrip()
    onboarding.reconcileRoute()
    if onboarding.step == 6 { selectedTripID = onboarding.createdTripID }
    referenceRates = store.read(FXTable.self, key: "referenceRates")
    expenseQuotes = store.read([String: FXQuote].self, key: "expenseQuotes") ?? [:]
  }
  /// An indicative rate between any two currencies the cached table lists.
  /// The currency most trips are kept in, for totals that span trips.
  public var displayCurrency: String {
    let counts = Dictionary(grouping: store.trips, by: \.homeCurrency).mapValues(\.count)
    return counts.max { $0.value < $1.value || $0.value == $1.value && $0.key > $1.key }?.key
      ?? Locale.current.currency?.identifier ?? "GBP"
  }
  /// What trips that have started cost, converted at reference rates. Nil while a rate is missing.
  public func spentSoFar(in currency: String) -> Int64? {
    var total: Int64 = 0
    for trip in store.trips where trip.phase != .upcoming {
      let amount = Ledger(trip).total
      guard
        let rate = trip.homeCurrency == currency
          ? "1" : referenceRates?.rate(from: trip.homeCurrency, to: currency),
        let converted = try? Money.convert(amount, from: trip.homeCurrency, to: currency, rate: rate)
      else { return nil }
      total += converted
    }
    return total
  }
  public func indicativeRate(from: String, to: String) -> Double? {
    if from == to { return 1 }
    return referenceRates?.rate(from: from, to: to).flatMap(Double.init)
  }
  /// Fetches today's reference rates once a day when the cloud service is configured.
  public func refreshReferenceRates() async {
    let today = CivilDate.today(timeZone: "UTC")
    if sync.configured, referenceRates?.requestedDate != today,
      let table = try? await sync.api.rates(base: "GBP", date: today)
    {
      cacheReferenceRates(table)
    }
    await repairExpenseConversions()
  }
  public func cacheReferenceRates(_ table: FXTable) {
    referenceRates = table
    try? store.write(table, key: "referenceRates")
  }
  public func open(_ trip: TripSnapshot) {
    selectedTripID = trip.id
    selectedAttachment = nil
    selectedTab = 0
  }
  public func openDay(_ attachment: Attachment) { selectedAttachment = attachment }
  public func editExpense(trip: TripSnapshot, attachment: Attachment, expense: Expense? = nil) {
    if expense == nil, let saved = store.read(ExpenseDraft.self, key: "expense:" + trip.id) {
      expenseDraft = saved
    } else {
      expenseDraft = ExpenseDraft(trip: trip, attachment: attachment, expense: expense)
    }
  }
  public func persistDraft() {
    guard let draft = expenseDraft, completedDraftID != draft.id else { return }
    do { try store.write(draft, key: "expense:" + draft.tripID) } catch {
      self.error = error.localizedDescription
    }
  }
  public func saveOnboarding() {
    do { try store.write(onboarding, key: "onboarding") } catch {
      self.error = error.localizedDescription
    }
  }
  public func notify(_ text: String) {
    toast = text
    Task {
      try? await Task.sleep(for: .seconds(3))
      if toast == text { toast = nil }
    }
  }
  public func changed() { Task { await sync.syncAll() } }
  public func perform(_ action: () throws -> Void) {
    do { try action() } catch { self.error = error.localizedDescription }
  }
  public func createTrip() throws -> TripSnapshot {
    let trip = try onboarding.makeTrip()
    try store.create(trip)
    selectedTripID = trip.id
    onboarding.step = 6
    onboarding.createdTripID = trip.id
    saveOnboarding()
    changed()
    return trip
  }
  public func finishOnboarding(planTravel: Bool) {
    showOnboarding = false
    if planTravel, let trip = selectedTrip, let leg = trip.legs.first {
      selectedAttachment = .init(kind: .leg, id: leg.id)
    }
    onboarding = .newTrip()
    saveOnboarding()
  }
  /// Deletes a trip for everyone on it. Only its owner can.
  public func deleteTrip(_ trip: TripSnapshot) async {
    do {
      try await sync.deleteTrip(trip.id)
      if selectedTripID == trip.id {
        selectedAttachment = nil
        selectedTripID = nil
      }
      if globeTripID == trip.id { globeTripID = nil }
      notify("Deleted \(trip.name)")
    } catch { self.error = error.localizedDescription }
  }
  /// Moves expenses to another day or leg. Paid ones count as paid on its date. A half of a return
  /// ticket moves on its own, so both halves become plain expenses.
  public func moveExpenses(_ items: [Expense], to attachment: Attachment, trip: TripSnapshot) {
    let moving = items.filter { $0.attachment != attachment }
    guard !moving.isEmpty else { return }
    perform {
      let ids = Set(moving.map(\.id))
      for partner in moving.flatMap(trip.ticket(of:)) where !ids.contains(partner.id) {
        var unlinked = partner
        unlinked.returnPairId = nil
        try store.saveExpense(unlinked, tripID: trip.id)
      }
      for item in moving {
        var moved = item
        moved.attachment = attachment
        moved.returnPairId = nil
        if moved.status == .paid { moved.paidOn = trip.date(for: attachment) }
        try store.saveExpense(moved, tripID: trip.id)
      }
      let what = moving.count == 1 ? moving[0].title : "\(moving.count) expenses"
      notify("Moved \(what) to \(trip.title(for: attachment))")
      changed()
    }
  }
  /// Deletes every expense on a day or leg, and the other half of any return ticket on it.
  public func clearDay(_ attachment: Attachment, trip: TripSnapshot) {
    perform {
      for item in trip.expenses(for: attachment).flatMap(trip.ticket(of:)) {
        try store.deleteExpense(item, tripID: trip.id)
      }
      changed()
    }
  }
  /// Deletes an expense, both halves of a return ticket.
  public func deleteExpense(_ expense: Expense, trip: TripSnapshot) throws {
    for item in trip.ticket(of: expense) { try store.deleteExpense(item, tripID: trip.id) }
  }
  /// Ticks an expense off as paid, or back to planned, both halves of a return ticket together.
  public func toggleExpense(_ expense: Expense, trip: TripSnapshot) {
    perform {
      let status: Expense.Status = expense.status == .paid ? .planned : .paid
      for item in trip.ticket(of: expense) {
        var edited = item
        edited.status = status
        edited.paidOn = status == .paid ? trip.today(for: expense.attachment) : nil
        try store.saveExpense(edited, tripID: trip.id)
      }
      notify(status == .paid ? "Ticked off as paid" : "Moved back to planned")
      changed()
    }
  }
  /// Saves the draft, and returns the expense as it was entered. A return ticket saves as two
  /// halves, getting there and getting home; one changed to one way drops its half getting home.
  public func saveExpense() async throws -> Expense {
    guard let draft = expenseDraft, let trip = store.trip(draft.tripID) else {
      throw MoneyError.invalid
    }
    let amount = try Money.parse(draft.amount, currency: draft.currency)
    guard amount > 0, !draft.splitWith.isEmpty else { throw MoneyError.invalid }
    var conversion = draft.conversion
    let saved = trip.expenses.first(where: { $0.id == draft.expenseID })
    let previous = saved.map(trip.wholeTicket)
    let partner = saved.flatMap { trip.returnHalves(of: $0)?.back }
    let isReturn = draft.isReturn && trip.asksReturn(draft.category, on: draft.attachment)
    if let previous, previous.amountMinor != String(amount) || previous.currency != draft.currency {
      conversion = nil
    }
    // Clearing a saved bank charge opts back into automatic conversion.
    if conversion?.isBankCharge == true, draft.actualHomeAmount.isEmpty { conversion = nil }
    if draft.currency != trip.homeCurrency {
      if !draft.actualHomeAmount.isEmpty {
        let home = try Money.parse(draft.actualHomeAmount, currency: trip.homeCurrency)
        guard home > 0 else { throw MoneyError.invalid }
        let rate =
          (Decimal(home) * Decimal(Money.factor(draft.currency)))
          / (Decimal(amount) * Decimal(Money.factor(trip.homeCurrency)))
        conversion = .init(
          homeAmountMinor: String(home), rate: Money.rateString(rate),
          rateDate: trip.date(for: draft.attachment),
          source: Conversion.bankChargeSource, kind: "manual", quoteId: nil)
      } else if var estimate = conversion {
        estimate.homeAmountMinor = String(
          try Money.convert(
            amount, from: draft.currency, to: trip.homeCurrency, rate: estimate.rate))
        conversion = estimate
      } else {
        conversion = try await expenseConversion(amount, from: draft.currency, to: trip.homeCurrency)
      }
      guard conversion != nil else {
        throw ServiceError(
          code: "fx_unavailable",
          message: "Connect to get an exchange rate, or enter the amount charged in \(trip.homeCurrency). Your draft is saved.")
      }
    } else {
      conversion = nil
    }
    // A title the app filled in follows the ticket, e.g. "Return flight" back to "Flight".
    let typed = draft.title.trimmingCharacters(in: .whitespaces)
    let named =
      !typed.isEmpty && typed != draft.category.title
      && !ExpenseCategory.allCases.contains { $0.returnTitle == typed }
    let expense = Expense(
      id: draft.expenseID ?? draft.id, revision: previous?.revision ?? 0,
      attachment: draft.attachment,
      title: named
        ? draft.title
        : isReturn ? draft.category.returnTitle ?? draft.category.title : draft.category.title,
      category: draft.category, amountMinor: String(amount),
      currency: draft.currency, status: draft.status,
      paidOn: draft.status == .paid ? trip.date(for: draft.attachment) : nil, paidBy: draft.paidBy,
      splitWith: draft.splitWith.sorted(), conversion: conversion,
      returnPairId: isReturn ? previous?.returnPairId : nil)
    if isReturn, let halves = trip.splitReturn(expense, back: partner) {
      for half in halves { try store.saveExpense(half, tripID: trip.id) }
    } else {
      try store.saveExpense(expense, tripID: trip.id)
      if let partner { try store.deleteExpense(partner, tripID: trip.id) }
    }
    completedDraftID = draft.id
    try store.removeDocument("expense:" + trip.id)
    changed()
    return expense
  }
}
