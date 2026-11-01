import Foundation
import Observation
import TripSplitDomain

public enum ConversionSide: String, Identifiable {
  case from, to
  public var id: String { rawValue }
  public var title: String { self == .from ? "Convert from" : "Convert to" }
}

@MainActor @Observable public final class ConversionModel {
  public typealias QuoteLoader = @Sendable (String, String, String) async throws -> FXQuote

  public var amount = "10"
  public private(set) var from: ConversionCurrency
  public private(set) var to: ConversionCurrency
  public private(set) var quote: FXQuote?
  public private(set) var rateInput = ""
  public private(set) var usesManualRate = false
  public private(set) var message: String?
  public private(set) var isLoading = false
  public let quoteDate: String
  @ObservationIgnored private let loadQuote: QuoteLoader
  @ObservationIgnored private var requestID = UUID()
  @ObservationIgnored private var request: Task<Void, Never>?
  @ObservationIgnored private var started = false

  public init(
    from: ConversionCurrency, to: ConversionCurrency, date: String,
    today: String = CivilDate.today(timeZone: "UTC"), loadQuote: @escaping QuoteLoader
  ) {
    self.from = from
    self.to = to
    quoteDate = min(date, today)
    self.loadQuote = loadQuote
  }

  public var isIdentity: Bool { from.code == to.code }
  public var parsedAmount: Int64? { try? Money.parse(amount, currency: from.code) }
  public var result: Int64? {
    guard let value = parsedAmount else { return nil }
    if isIdentity { return value }
    guard let rate = effectiveRate else { return nil }
    return try? Money.convert(value, from: from.code, to: to.code, rate: rate)
  }
  public var amountIssue: String? {
    guard !amount.isEmpty else { return nil }
    do {
      _ = try Money.parse(amount, currency: from.code)
      return nil
    } catch {
      if let problem = error as? MoneyError, case .overflow = problem {
        return problem.localizedDescription
      }
      let digits = Money.precision(from.code)
      return digits == 0
        ? "\(from.code) uses whole amounts. Remove the decimal places."
        : "Enter an amount with up to \(digits) decimal places for \(from.code)."
    }
  }
  public var conversionIssue: String? {
    guard !isIdentity, parsedAmount != nil else { return nil }
    if usesManualRate, !rateInput.isEmpty, effectiveRate == nil {
      return "Enter a positive exchange rate, using up to 18 significant digits."
    }
    guard effectiveRate != nil, result == nil else { return nil }
    return "The converted amount is too large. Try a smaller amount."
  }
  private var effectiveRate: String? {
    if usesManualRate {
      let rate = rateInput.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: ",", with: ".")
      return validRate(rate) ? rate : nil
    }
    guard let quote, quote.from == from.code, quote.to == to.code,
      quote.requestedDate == quoteDate, validRate(quote.rate)
    else { return nil }
    return quote.rate
  }

  @discardableResult public func start() -> Task<Void, Never>? {
    guard !started else { return nil }
    started = true
    return refresh()
  }
  @discardableResult public func select(_ currency: ConversionCurrency, for side: ConversionSide)
    -> Task<Void, Never>?
  {
    let previous = (from.code, to.code)
    if side == .from { from = currency } else { to = currency }
    guard previous != (from.code, to.code) else { return nil }
    return refresh()
  }
  @discardableResult public func swap() -> Task<Void, Never>? {
    let previousFrom = from
    from = to
    to = previousFrom
    return refresh()
  }
  @discardableResult public func reset(from: ConversionCurrency, to: ConversionCurrency)
    -> Task<Void, Never>?
  {
    self.from = from
    self.to = to
    return refresh()
  }
  public func enterManualRate(_ value: String = "") {
    cancel()
    quote = nil
    message = nil
    usesManualRate = true
    rateInput = value
  }
  public func cancel() {
    requestID = UUID()
    request?.cancel()
    request = nil
    isLoading = false
  }
  @discardableResult public func refresh() -> Task<Void, Never>? {
    cancel()
    quote = nil
    rateInput = ""
    usesManualRate = false
    message = nil
    guard !isIdentity else { return nil }
    let id = requestID
    let requestedFrom = from.code
    let requestedTo = to.code
    let date = quoteDate
    isLoading = true
    let loader = loadQuote
    let task = Task { [weak self] in
      do {
        let response = try await loader(requestedFrom, requestedTo, date)
        guard let self, self.requestID == id, !Task.isCancelled else { return }
        guard response.from == requestedFrom, response.to == requestedTo,
          response.requestedDate == date, self.validRate(response.rate)
        else {
          throw ServiceError(
            code: "fx_mismatch",
            message: "The returned quote didn’t match this conversion. Try again or enter a rate.")
        }
        self.quote = response
        self.message = nil
      } catch {
        guard let self, self.requestID == id, !Task.isCancelled else { return }
        self.message = error.localizedDescription
      }
      guard let self, self.requestID == id else { return }
      self.isLoading = false
      self.request = nil
    }
    request = task
    return task
  }
  public func canLogExpense(homeCurrency: String) -> Bool {
    to.code == homeCurrency && (parsedAmount ?? 0) > 0 && conversionIssue == nil
  }
  public func expenseDraft(trip: TripSnapshot, attachment: Attachment) throws -> ExpenseDraft {
    guard canLogExpense(homeCurrency: trip.homeCurrency) else { throw MoneyError.invalid }
    var draft = ExpenseDraft(trip: trip, attachment: attachment)
    draft.amount = amount
    draft.currency = from.code
    if !isIdentity, let result {
      if let quote, !usesManualRate, effectiveRate != nil {
        draft.conversion = Conversion(
          homeAmountMinor: String(result), rate: quote.rate, rateDate: quote.rateDate,
          source: quote.source, kind: "reference", quoteId: quote.id)
      } else if usesManualRate, let rate = effectiveRate {
        draft.conversion = Conversion(
          homeAmountMinor: String(result), rate: rate, rateDate: quoteDate,
          source: "Manual exchange rate", kind: "manual", quoteId: nil)
      }
    }
    return draft
  }
  private func validRate(_ rate: String) -> Bool {
    (try? Money.convert(0, from: from.code, to: to.code, rate: rate)) != nil
  }
}
