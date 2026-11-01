import Foundation

/// Every reference rate from one base on a day, for indicative conversions between any pair
/// offline. Expenses still cite an immutable `FXQuote`; a table is only for display.
public struct FXTable: Codable, Hashable, Sendable {
  public init(
    base: String, requestedDate: String, rateDate: String, source: String,
    rates: [String: String]
  ) {
    self.base = base
    self.requestedDate = requestedDate
    self.rateDate = rateDate
    self.source = source
    self.rates = rates
  }
  public var base: String
  public var requestedDate: String
  public var rateDate: String
  public var source: String
  /// Exact decimal rate from `base` to each currency, including the base itself.
  public var rates: [String: String]

  /// The rate between any two listed currencies, crossed through the base, e.g. EUR to JPY
  /// from a GBP table. Nil when either currency is missing.
  public func rate(from: String, to: String) -> String? {
    if from == to { return "1" }
    guard let source = Self.decimal(from == base ? "1" : rates[from]),
      let target = Self.decimal(to == base ? "1" : rates[to]), source > 0, target > 0
    else { return nil }
    return Money.rateString(target / source)
  }

  /// The currencies this table can convert between, base included.
  public var currencies: Set<String> { Set(rates.keys).union([base]) }

  private static func decimal(_ value: String?) -> Decimal? {
    guard let value, value.range(of: "^[0-9]+(\\.[0-9]+)?$", options: .regularExpression) != nil
    else { return nil }
    return Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
  }
}
