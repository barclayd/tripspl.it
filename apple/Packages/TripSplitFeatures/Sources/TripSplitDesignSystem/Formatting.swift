import Foundation
import TripSplitDomain

extension Money {
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
  /// Each stop's flag once, in itinerary order.
  package var uniqueFlags: [String] {
    var seen = Set<String>()
    return stops.map(\.flag).filter { seen.insert($0).inserted }
  }

  /// Totals for every itinerary day, in order, counting planned and paid expenses.
  package var dayTotals: [Int64] {
    days.map { Ledger(self, expenses: expenses(for: .init(kind: .day, id: $0.id))).total }
  }
}
