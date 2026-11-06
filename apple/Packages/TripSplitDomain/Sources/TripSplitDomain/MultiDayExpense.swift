import Foundation

extension Expense {
  /// A display-only share of this expense. Resolve its ID against the trip before editing it.
  /// Remainders go to the earliest selected days, independently for each currency, preserving
  /// both the original total and the exact bank charge even when a day's share rounds to zero.
  public func portion(on attachment: Attachment, in trip: TripSnapshot) -> Expense? {
    guard let dayIds, self.attachment.kind == .day else {
      return self.attachment == attachment ? self : nil
    }
    guard attachment.kind == .day, dayIds.contains(attachment.id) else { return nil }
    let selected = Set(dayIds)
    let ordered = trip.days.map(\.id).filter { selected.contains($0) }
    guard let index = ordered.firstIndex(of: attachment.id), !ordered.isEmpty else { return nil }
    func share(_ total: Int64) -> String {
      let count = Int64(ordered.count)
      return String(total / count + (Int64(index) < total % count ? 1 : 0))
    }
    var portion = self
    portion.attachment = attachment
    portion.amountMinor = share(Money.minor(amountMinor) ?? 0)
    if let home = conversion.flatMap({ Money.minor($0.homeAmountMinor) }) {
      portion.conversion?.homeAmountMinor = share(home)
    }
    return portion
  }
}
