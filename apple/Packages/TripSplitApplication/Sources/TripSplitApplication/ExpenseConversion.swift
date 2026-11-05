import Foundation
import TripSplitDomain

extension AppModel {
  /// Uses today's latest published quote, including for future trip days. The API's calendar
  /// is UTC, so a traveller ahead of UTC never asks it for tomorrow's unavailable rate.
  public func expenseConversion(_ amount: Int64, from: String, to: String) async throws -> Conversion? {
    guard from != to else { return nil }
    let today = CivilDate.today(timeZone: "UTC")
    let key = "\(from)/\(to)"
    if expenseQuotes[key]?.requestedDate != today, sync.configured,
      let quote = try? await sync.api.quote(from: from, to: to, date: today, token: nil),
      quote.from == from, quote.to == to, quote.requestedDate == today, quote.rateDate <= today,
      !quote.id.isEmpty, (try? Money.convert(0, from: from, to: to, rate: quote.rate)) != nil
    {
      expenseQuotes[key] = quote
      try? store.write(expenseQuotes, key: "expenseQuotes")
    }
    return try cachedExpenseConversion(amount, from: from, to: to)
  }

  /// A stored quote or the latest cached table. Table estimates use the existing unquoted
  /// conversion format, with their provider/date retained; they never claim a server quote ID.
  public func cachedExpenseConversion(_ amount: Int64, from: String, to: String) throws -> Conversion? {
    guard from != to else { return nil }
    var conversions = store.trips.filter { $0.homeCurrency == to }.flatMap(\.expenses)
      .filter { $0.currency == from }.compactMap(\.conversion)
      .filter { $0.kind == "reference" && $0.quoteId != nil }
    if let quote = expenseQuotes["\(from)/\(to)"] {
      conversions.append(.init(
        homeAmountMinor: "0", rate: quote.rate, rateDate: quote.rateDate,
        source: quote.source, kind: "reference", quoteId: quote.id))
    }
    if let table = referenceRates, let rate = table.rate(from: from, to: to) {
      conversions.append(.init(
        homeAmountMinor: "0", rate: rate, rateDate: table.rateDate,
        source: "Cached " + table.source, kind: "manual"))
    }
    let today = CivilDate.today(timeZone: "UTC")
    // Prefer a direct quote when the table and quote have the same publication date.
    guard var conversion = conversions.filter({ $0.rateDate <= today }).max(by: {
      $0.rateDate == $1.rateDate ? $0.kind != "reference" && $1.kind == "reference" : $0.rateDate < $1.rateDate
    }) else { return nil }
    conversion.homeAmountMinor = String(try Money.convert(amount, from: from, to: to, rate: conversion.rate))
    return conversion
  }

  /// Repairs expenses saved by older versions without a conversion, without changing bank
  /// charges or rewriting any sync operation that has already been sent.
  public func repairExpenseConversions() async {
    guard !repairingConversions else { return }
    repairingConversions = true
    defer { repairingConversions = false }
    var repaired = false
    for trip in store.trips where store.envelopes[trip.id]?.restoreReview == false {
      for expense in trip.expenses where expense.currency != trip.homeCurrency && expense.conversion == nil {
        guard !conversionEditBlocked(expense.id, tripID: trip.id),
          let amount = Money.minor(expense.amountMinor),
          let conversion = try? await expenseConversion(amount, from: expense.currency, to: trip.homeCurrency),
          let current = store.trip(trip.id), current.homeCurrency == trip.homeCurrency,
          current.expenses.first(where: { $0.id == expense.id }) == expense,
          !conversionEditBlocked(expense.id, tripID: trip.id)
        else { continue }
        var converted = expense
        converted.conversion = conversion
        do {
          try store.saveExpense(converted, tripID: trip.id)
          repaired = true
        } catch { continue }
      }
    }
    if repaired { changed() }
  }

  private func conversionEditBlocked(_ expenseID: String, tripID: String) -> Bool {
    guard let envelope = store.envelopes[tripID], !envelope.restoreReview else { return true }
    return expenseDraft?.expenseID == expenseID || envelope.pending.contains {
      $0.operation.entityId == expenseID && ($0.attempted || $0.problem != nil)
    }
  }
}
