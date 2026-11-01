import Foundation
import TripSplitDomain

extension Money {
  /// "£1,234.5" as typed on a keypad: the whole part grouped, plus the decimals typed so far.
  package static func typed(_ amount: String, currency: String) -> String {
    let parts = amount.split(separator: ".", omittingEmptySubsequences: false)
    let whole = Int64(parts.first.map(String.init) ?? "") ?? 0
    var text = format(whole * factor(currency), currency, compact: true)
    if parts.count > 1, text.last?.isNumber == true { text += "." + parts[1] }
    return text
  }

  /// Rounds to whole units, half away from zero, for card totals that drop the pennies.
  package static func wholeUnits(_ minor: Int64, _ currency: String) -> Int64 {
    let factor = factor(currency)
    guard factor > 1 else { return minor }
    let half = minor >= 0 ? factor / 2 : -factor / 2
    return (minor + half) / factor * factor
  }

  /// A total in whole units with a true minus sign, e.g. "£1,240" or "−£12".
  package static func whole(_ minor: Int64, _ currency: String) -> String {
    let rounded = wholeUnits(minor, currency)
    let text = format(abs(rounded), currency, compact: true)
    return rounded < 0 ? "−" + text : text
  }
}

extension TripSnapshot {
  /// Totals for every itinerary day, in order, counting planned and paid expenses.
  package var dayTotals: [Int64] {
    days.map { Ledger(self, expenses: expenses(for: .init(kind: .day, id: $0.id))).total }
  }
}

extension TripSnapshot {
  /// The latest rate an expense locked in from `currency` to home, so stop rates work offline.
  package func knownRate(from currency: String) -> String? {
    expenses.lazy.filter { $0.currency == currency }
      .compactMap(\.conversion)
      .max { $0.rateDate < $1.rateDate }?.rate
  }

  /// "€1 = £0.86" for a foreign currency with a known rate, in thousands for zero-decimal
  /// currencies (¥1,000 rather than ¥1), or nil.
  package func rateLabel(for currency: String) -> String? {
    guard currency != homeCurrency, let rate = knownRate(from: currency) else { return nil }
    let unit = Money.factor(currency) * (Money.precision(currency) == 0 ? 1000 : 1)
    guard let value = try? Money.convert(unit, from: currency, to: homeCurrency, rate: rate)
    else { return nil }
    return "\(Money.format(unit, currency, compact: true)) = \(Money.format(value, homeCurrency))"
  }

  /// The home value of `minor` in `currency` at the known rate, or nil without one.
  package func estimate(_ minor: Int64, from currency: String) -> Int64? {
    if currency == homeCurrency { return minor }
    guard let rate = knownRate(from: currency) else { return nil }
    return try? Money.convert(minor, from: currency, to: homeCurrency, rate: rate)
  }

  /// "You" for the current traveller, otherwise their name.
  package func displayName(_ travellerID: String) -> String {
    if travellerID == currentTravellerId { return "You" }
    return travellers.first { $0.id == travellerID }?.name ?? "Traveller"
  }

  /// "Day 4" for an itinerary day, or the leg's title.
  package func shortTitle(for attachment: Attachment) -> String {
    guard attachment.kind == .day else { return title(for: attachment) }
    return "Day \((days.firstIndex { $0.id == attachment.id } ?? 0) + 1)"
  }
}
