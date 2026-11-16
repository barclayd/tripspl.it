import Foundation
import TripSplitDomain

extension AppModel {
  /// Quick convert shares the durable rates already available to expenses and the home screen.
  public func cachedConversionRate(from: String, to: String, date: String) -> CachedFXRate? {
    var candidates = Array(conversionRates.values)
    if let quote = expenseQuotes["\(from)/\(to)"] {
      candidates.append(CachedFXRate(quote: quote))
    }
    if let table = referenceRates, let rate = table.rate(from: from, to: to) {
      candidates.append(.init(
        from: from, to: to, rate: rate, rateDate: table.rateDate, source: table.source,
        fetchedAt: referenceRatesFetchedAt))
    }
    for trip in store.trips + store.archivedTrips where trip.homeCurrency == to {
      for expense in trip.expenses where expense.currency == from {
        guard let conversion = expense.conversion, conversion.kind == "reference",
          let quoteID = conversion.quoteId else { continue }
        candidates.append(.init(
          from: from, to: to, rate: conversion.rate, rateDate: conversion.rateDate,
          source: conversion.source, quoteID: quoteID))
      }
    }
    return CachedFXRate.newest(candidates.filter { $0.matches(from: from, to: to, date: date) })
  }

  /// Only a validated network response can advance a saved rate's fetch time.
  public func conversionQuote(from: String, to: String, date: String) async throws -> FXQuote {
    let quote = try await sync.api.quote(from: from, to: to, date: date, token: nil)
    let cached = CachedFXRate(quote: quote, fetchedAt: .now)
    guard quote.requestedDate == date, !quote.id.isEmpty,
      cached.matches(from: from, to: to, date: date)
    else {
      throw ServiceError(code: "fx_mismatch", message: "The returned quote didn’t match this conversion. Try again or enter a rate.")
    }
    conversionRates["\(from)/\(to)/\(date)"] = cached
    try? store.write(conversionRates, key: "conversionRates")
    return quote
  }

  /// Uses today's latest published quote, including for future trip days. The API's calendar
  /// is UTC, so a traveller ahead of UTC never asks it for tomorrow's unavailable rate.
  public func expenseConversion(_ amount: Int64, from: String, to: String) async throws -> Conversion? {
    guard from != to else { return nil }
    let today = CivilDate.today(timeZone: "UTC")
    let key = "\(from)/\(to)"
    if expenseQuotes[key]?.requestedDate != today, sync.configured,
      let quote = try? await conversionQuote(from: from, to: to, date: today),
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
    return try cachedConversionRate(
      from: from, to: to, date: CivilDate.today(timeZone: "UTC"))?.conversion(amount)
  }

  /// Fills expenses saved offline without a conversion, without changing bank
  /// charges or rewriting any sync operation that has already been sent.
  public func repairExpenseConversions() async {
    guard !repairingConversions else { return }
    repairingConversions = true
    defer { repairingConversions = false }
    var repaired = false
    for trip in store.trips + store.archivedTrips
    where store.envelopes[trip.id]?.restoreReview == false {
      for expense in trip.expenses where expense.currency != trip.homeCurrency && expense.conversion == nil {
        guard !Task.isCancelled else { return }
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
          try store.saveExpenseConversion(converted, tripID: trip.id)
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
