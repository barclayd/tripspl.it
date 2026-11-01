import MapKit
import Observation
import SwiftUI

@MainActor @Observable final class AppModel {
  let store: LocalStore
  let sync: SyncCoordinator
  var selectedTab = 0
  var selectedTripID: String?
  var selectedAttachment: Attachment?
  var fullScreenDay = false
  var showOnboarding = false
  var showSettings = false
  var showConverter = false
  var showTripSettings = false
  var expenseDraft: ExpenseDraft?
  private var completedDraftID: String?
  var onboarding: OnboardingDraft
  var toast: String?
  var error: String?
  var mapPosition: MapCameraPosition = .camera(
    MapCamera(centerCoordinate: .init(latitude: 30, longitude: 0), distance: 30_000_000))
  var mapFilter = "All"
  var inviteURL: URL?
  var pendingInvitation: URL?
  @ObservationIgnored private var connectivity: Connectivity?
  var selectedTrip: TripSnapshot? { selectedTripID.flatMap { store.trip($0) } }
  init(store: LocalStore) {
    self.store = store
    self.sync = SyncCoordinator(store: store)
    onboarding = store.read(OnboardingDraft.self, key: "onboarding") ?? OnboardingDraft()
    if onboarding.step == 6 { selectedTripID = onboarding.createdTripID }
    connectivity = Connectivity { [weak self] in Task { await self?.sync.syncAll() } }
  }
  func open(_ trip: TripSnapshot) {
    selectedTripID = trip.id
    selectedAttachment = nil
    selectedTab = 0
  }
  func openDay(_ attachment: Attachment) { selectedAttachment = attachment }
  func editExpense(trip: TripSnapshot, attachment: Attachment, expense: Expense? = nil) {
    if expense == nil, let saved = store.read(ExpenseDraft.self, key: "expense:" + trip.id) {
      expenseDraft = saved
    } else {
      expenseDraft = ExpenseDraft(trip: trip, attachment: attachment, expense: expense)
    }
  }
  func persistDraft() {
    guard let draft = expenseDraft, completedDraftID != draft.id else { return }
    do { try store.write(draft, key: "expense:" + draft.tripID) } catch {
      self.error = error.localizedDescription
    }
  }
  func saveOnboarding() {
    do { try store.write(onboarding, key: "onboarding") } catch {
      self.error = error.localizedDescription
    }
  }
  func notify(_ text: String) {
    toast = text
    Task {
      try? await Task.sleep(for: .seconds(3))
      if toast == text { toast = nil }
    }
  }
  func changed() { Task { await sync.syncAll() } }
  func perform(_ action: () throws -> Void) {
    do { try action() } catch { self.error = error.localizedDescription }
  }
  func createTrip() throws -> TripSnapshot {
    let trip = try onboarding.makeTrip()
    try store.create(trip)
    selectedTripID = trip.id
    onboarding.step = 6
    onboarding.createdTripID = trip.id
    saveOnboarding()
    changed()
    return trip
  }
  func finishOnboarding(planTravel: Bool) {
    showOnboarding = false
    if planTravel, let trip = selectedTrip, let leg = trip.legs.first {
      selectedAttachment = .init(kind: .leg, id: leg.id)
    }
    onboarding = OnboardingDraft()
    saveOnboarding()
  }
  func toggleExpense(_ expense: Expense, trip: TripSnapshot) {
    perform {
      var edited = expense
      edited.status = expense.status == .paid ? .planned : .paid
      edited.paidOn = edited.status == .paid ? trip.today : nil
      try store.saveExpense(edited, tripID: trip.id)
      notify(edited.status == .paid ? "Ticked off as paid" : "Moved back to planned")
      changed()
    }
  }
  func saveExpense() async throws -> Expense {
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
