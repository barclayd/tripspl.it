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
  public var mapFilter = "All"
  public var inviteURL: URL?
  public var pendingInvitation: URL?
  /// The last reference rates from pounds, kept for indicative amounts such as a suggested
  /// budget, so they still show offline. Expenses never convert with these.
  public private(set) var referenceRates: FXTable?
  public var selectedTrip: TripSnapshot? { selectedTripID.flatMap { store.trip($0) } }
  public init(store: LocalStore, sync: SyncCoordinator? = nil) {
    self.store = store
    self.sync = sync ?? SyncCoordinator(store: store)
    onboarding = store.read(OnboardingDraft.self, key: "onboarding") ?? .newTrip()
    onboarding.reconcileRoute()
    if onboarding.step == 6 { selectedTripID = onboarding.createdTripID }
    referenceRates = store.read(FXTable.self, key: "referenceRates")
  }
  /// An indicative rate between any two currencies the cached table lists.
  public func indicativeRate(from: String, to: String) -> Double? {
    if from == to { return 1 }
    return referenceRates?.rate(from: from, to: to).flatMap(Double.init)
  }
  /// Fetches today's reference rates once a day when the cloud service is configured.
  public func refreshReferenceRates() async {
    let today = CivilDate.today(timeZone: TimeZone.current.identifier)
    guard sync.configured, referenceRates?.requestedDate != today,
      let table = try? await sync.api.rates(base: "GBP", date: today)
    else { return }
    cacheReferenceRates(table)
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
  public func toggleExpense(_ expense: Expense, trip: TripSnapshot) {
    perform {
      var edited = expense
      edited.status = expense.status == .paid ? .planned : .paid
      edited.paidOn = edited.status == .paid ? trip.today(for: edited.attachment) : nil
      try store.saveExpense(edited, tripID: trip.id)
      notify(edited.status == .paid ? "Ticked off as paid" : "Moved back to planned")
      changed()
    }
  }
  public func saveExpense() async throws -> Expense {
    guard let draft = expenseDraft, let trip = store.trip(draft.tripID) else {
      throw MoneyError.invalid
    }
    let amount = try Money.parse(draft.amount, currency: draft.currency)
    guard amount > 0, !draft.splitWith.isEmpty else { throw MoneyError.invalid }
    var conversion = draft.conversion
    let previous = trip.expenses.first(where: { $0.id == draft.expenseID })
    if let previous, previous.amountMinor != String(amount) || previous.currency != draft.currency {
      conversion = nil
    }
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
          source: "Actual card charge entered by traveller", kind: "manual", quoteId: nil)
      } else if var estimate = conversion {
        estimate.homeAmountMinor = String(
          try Money.convert(
            amount, from: draft.currency, to: trip.homeCurrency, rate: estimate.rate))
        conversion = estimate
      } else if conversion == nil, sync.configured,
        let quote = try? await sync.api.quote(
          from: draft.currency, to: trip.homeCurrency, date: trip.date(for: draft.attachment),
          token: nil)
      {
        let home = try Money.convert(
          amount, from: draft.currency, to: trip.homeCurrency, rate: quote.rate)
        conversion = .init(
          homeAmountMinor: String(home), rate: quote.rate, rateDate: quote.rateDate,
          source: quote.source, kind: "reference", quoteId: quote.id)
      }
    } else {
      conversion = nil
    }
    let expense = Expense(
      id: draft.expenseID ?? draft.id, revision: previous?.revision ?? 0,
      attachment: draft.attachment,
      title: draft.title.trimmingCharacters(in: .whitespaces).isEmpty
        ? draft.category.title : draft.title, category: draft.category, amountMinor: String(amount),
      currency: draft.currency, status: draft.status,
      paidOn: draft.status == .paid ? trip.date(for: draft.attachment) : nil, paidBy: draft.paidBy,
      splitWith: draft.splitWith.sorted(), conversion: conversion)
    try store.saveExpense(expense, tripID: trip.id)
    completedDraftID = draft.id
    try store.removeDocument("expense:" + trip.id)
    changed()
    return expense
  }
}
