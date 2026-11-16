import Foundation

/// A locally retained rate, with its publication date and actual fetch time kept separately.
/// Older stores may know the publication date without knowing when the rate was fetched.
public struct CachedFXRate: Codable, Sendable {
  public var from: String
  public var to: String
  public var rate: String
  public var rateDate: String
  public var source: String
  public var quoteID: String?
  public var fetchedAt: Date?

  public init(
    from: String, to: String, rate: String, rateDate: String, source: String,
    quoteID: String? = nil, fetchedAt: Date? = nil
  ) {
    self.from = from
    self.to = to
    self.rate = rate
    self.rateDate = rateDate
    self.source = source
    self.quoteID = quoteID
    self.fetchedAt = fetchedAt
  }

  public init(quote: FXQuote, fetchedAt: Date? = nil) {
    self.init(
      from: quote.from, to: quote.to, rate: quote.rate, rateDate: quote.rateDate,
      source: quote.source, quoteID: quote.id, fetchedAt: fetchedAt)
  }

  public func matches(from: String, to: String, date: String) -> Bool {
    self.from == from && self.to == to && rateDate <= date
      && (try? Money.convert(0, from: from, to: to, rate: rate)) != nil
  }

  public static func newest(_ rates: [Self]) -> Self? {
    rates.max {
      if $0.rateDate != $1.rateDate { return $0.rateDate < $1.rateDate }
      if ($0.quoteID == nil) != ($1.quoteID == nil) { return $0.quoteID == nil }
      return ($0.fetchedAt ?? .distantPast) < ($1.fetchedAt ?? .distantPast)
    }
  }

  public func conversion(_ amount: Int64) throws -> Conversion {
    Conversion(
      homeAmountMinor: String(try Money.convert(amount, from: from, to: to, rate: rate)),
      rate: rate, rateDate: rateDate, source: quoteID == nil ? "Cached " + source : source,
      kind: quoteID == nil ? "manual" : "reference", quoteId: quoteID)
  }
}
