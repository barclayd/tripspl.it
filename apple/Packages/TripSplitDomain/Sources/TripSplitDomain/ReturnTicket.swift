import Foundation

extension ExpenseCategory {
  /// What a ticket there and back is called, for travel that's often booked as a return: a flight,
  /// train or coach. Nil for a taxi, a stay, a deposit or gear, which only go one way.
  public var returnTitle: String? {
    switch self {
    case .flight: "Return flight"
    case .train: "Return train"
    case .transport: "Return journey"
    default: nil
    }
  }
}

/// A return ticket is split across the trip's travel: half before you go, on the outbound leg, and
/// half on the way home, on the return leg. The halves share a `returnPairId`, so they edit and
/// delete together, and the odd minor unit stays on the way out so they always add up to what was
/// paid. The halves sync one at a time, so either may briefly stand alone; a lone half is a plain
/// expense.
extension TripSnapshot {
  /// Whether a spend in `category` on `attachment` might be a return ticket: travel there and back,
  /// booked before you go, on a trip with a way home.
  public func asksReturn(_ category: ExpenseCategory, on attachment: Attachment) -> Bool {
    guard category.returnTitle != nil, attachment.kind == .leg,
      legs.contains(where: { $0.kind == .return })
    else { return false }
    return legs.first { $0.id == attachment.id }?.kind == .outbound
  }

  /// Both halves of the return ticket `expense` belongs to, or nil for a plain expense or a half
  /// whose partner has gone.
  public func returnHalves(of expense: Expense) -> (out: Expense, back: Expense)? {
    guard let pair = expense.returnPairId else { return nil }
    let halves = expenses.filter { $0.returnPairId == pair }
    func half(_ kind: TravelLeg.Kind) -> Expense? {
      halves.first { $0.attachment.kind == .leg && legKind($0.attachment.id) == kind }
    }
    guard halves.count == 2, let out = half(.outbound), let back = half(.return) else { return nil }
    return (out, back)
  }

  /// Every expense in the ticket `expense` belongs to: both halves of a return, else just it, e.g.
  /// to delete them together.
  public func ticket(of expense: Expense) -> [Expense] {
    returnHalves(of: expense).map { [$0.out, $0.back] }
      ?? [expenses.first { $0.id == expense.id } ?? expense]
  }

  /// A return ticket as one spend before you go, both halves added back together, e.g. to edit.
  /// Any other expense comes back as it is.
  public func wholeTicket(_ expense: Expense) -> Expense {
    let expense = expenses.first { $0.id == expense.id } ?? expense
    guard let (out, back) = returnHalves(of: expense) else { return expense }
    var whole = out
    whole.amountMinor = String((Money.minor(out.amountMinor) ?? 0) + (Money.minor(back.amountMinor) ?? 0))
    if let outHome = out.conversion?.homeAmountMinor, let backHome = back.conversion?.homeAmountMinor {
      whole.conversion?.homeAmountMinor = String(
        (Money.minor(outHome) ?? 0) + (Money.minor(backHome) ?? 0))
    } else {
      whole.conversion = nil
    }
    return whole
  }

  /// Splits `whole`, a return ticket saved before you go, into its two halves: the way out keeps
  /// its ID and the odd minor unit, and the way home reuses `back`'s ID when it's already saved.
  /// Nil when the trip has no way home.
  public func splitReturn(_ whole: Expense, back existing: Expense? = nil) -> [Expense]? {
    guard let home = legs.first(where: { $0.kind == .return }),
      let total = Money.minor(whole.amountMinor)
    else { return nil }
    var out = whole
    out.returnPairId = whole.returnPairId ?? whole.id
    out.amountMinor = String(total - total / 2)
    var back = out
    back.id = existing?.id ?? UUID().uuidString
    back.revision = existing?.revision ?? 0
    back.attachment = .init(kind: .leg, id: home.id)
    back.amountMinor = String(total / 2)
    if let homeTotal = whole.conversion.flatMap({ Money.minor($0.homeAmountMinor) }) {
      out.conversion?.homeAmountMinor = String(homeTotal - homeTotal / 2)
      back.conversion?.homeAmountMinor = String(homeTotal / 2)
    }
    return [out, back]
  }

  private func legKind(_ id: String) -> TravelLeg.Kind? { legs.first { $0.id == id }?.kind }
}
