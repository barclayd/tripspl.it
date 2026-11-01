import Foundation
import TripSplitDomain

/// The figures behind a trip on the watch: today (D1), the budget (D2), who owes who (D3), the
/// days (D4) and each person (E1, E2). Derived from one snapshot so every page agrees.
public struct TripPages {
  public enum Page: Hashable, Sendable {
    case today, budget, balances, days
  }

  public let trip: TripSnapshot
  public let now: Date
  public let ledger: Ledger
  /// Expenses logged on the watch that the phone hasn't echoed back yet.
  public let unsynced: Set<String>

  public init(trip: TripSnapshot, now: Date, unsynced: Set<String> = []) {
    self.trip = trip
    self.now = now
    self.unsynced = unsynced
    ledger = Ledger(trip)
  }

  public var currency: String { trip.homeCurrency }
  public var you: String { trip.currentTravellerId }
  public var today: TripDay? { trip.currentDay(at: now) }

  /// Today only exists while the trip is happening, so other trips open on the budget. A past
  /// trip is just its budget and who owes who, as stamped in the passport.
  public var pages: [Page] {
    if today != nil { return [.today, .budget, .balances, .days] }
    return trip.phase(at: now) == .past ? [.budget, .balances] : [.budget, .balances, .days]
  }
  public var firstPage: Page { pages[0] }

  public func name(_ id: String) -> String {
    id == you ? "You" : trip.travellers.first { $0.id == id }?.name ?? "Someone"
  }

  public func traveller(_ id: String) -> Traveller? { trip.travellers.first { $0.id == id } }

  // MARK: Today

  /// "Day 4 of 8 · Sat 31 Oct".
  public func dayLine(_ day: TripDay) -> String {
    "Day \(trip.dayNumber(of: day)) of \(trip.days.count) · "
      + CivilDate.display(day.date, format: "EEE d MMM")
  }

  public func stop(_ day: TripDay) -> Stop? { trip.stop(for: .init(kind: .day, id: day.id)) }

  /// Everything attached to a day, paid first, newest logged last.
  public func items(_ day: TripDay) -> [Expense] {
    let items = trip.expenses(for: .init(kind: .day, id: day.id))
    return items.filter { $0.status == .paid } + items.filter { $0.status == .planned }
  }

  /// An expense's share of the trip in the home currency, when it has a conversion.
  public func homeAmount(_ expense: Expense) -> Int64? { expense.homeMinor(in: currency) }

  // MARK: Budget

  /// Paid and planned spend, as the phone's trip card counts it.
  public var spent: Int64 { ledger.total }
  public var budget: Int64 { trip.budget }
  public var budgetFraction: Double { budget > 0 ? Double(spent) / Double(budget) : 0 }
  public var each: Int64 { spent / Int64(max(1, trip.activeTravellers.count)) }

  // MARK: Who owes who

  /// The fewest transfers that settle the trip, as on the phone.
  public var settlements: [Settlement] { ledger.settlements }
  public var balancesComplete: Bool { ledger.balancesComplete }

  /// Who a row on the who-owes-who page opens: the other side when you're involved, else the payer.
  public func subject(of settlement: Settlement) -> String {
    settlement.from == you ? settlement.to : settlement.from
  }

  // MARK: Days

  public struct DayRow: Identifiable, Hashable, Sendable {
    public let day: TripDay
    public let number: Int
    public let place: String
    public let flag: String
    public let isToday: Bool
    public let hasStarted: Bool
    public let spending: DaySpending
    public let hasUnsynced: Bool
    public var id: String { day.id }
  }

  /// Days so far, newest first, then the days still to come in order.
  public var dayRows: (started: [DayRow], upcoming: [DayRow]) {
    let today = today
    let reached = today.map { trip.dayNumber(of: $0) } ?? (trip.phase(at: now) == .past ? trip.days.count : 0)
    let rows = trip.days.map { day in
      let number = trip.dayNumber(of: day)
      let stop = stop(day)
      return DayRow(
        day: day, number: number, place: stop?.place ?? trip.destination, flag: stop?.flag ?? "",
        isToday: day.id == today?.id, hasStarted: number <= reached,
        spending: trip.spending(on: day),
        hasUnsynced: items(day).contains { unsynced.contains($0.id) })
    }
    return (rows.filter(\.hasStarted).reversed(), rows.filter { !$0.hasStarted })
  }

  // MARK: People

  public struct PersonRow: Identifiable, Hashable, Sendable {
    public let traveller: Traveller
    public let isYou: Bool
    /// Positive when owed, negative when owing.
    public let balance: Int64
    public var id: String { traveller.id }
  }

  /// Everyone on the trip, plus anyone archived with money still involved. Whoever owes most
  /// comes first, then whoever is owed most.
  public var people: [PersonRow] {
    trip.travellers
      .map { PersonRow(traveller: $0, isYou: $0.id == you, balance: ledger.balances[$0.id, default: 0]) }
      .filter { !$0.traveller.archived || $0.balance != 0 }
      .sorted { a, b in
        let rank = { (row: PersonRow) in row.balance < 0 ? 0 : row.balance > 0 ? 1 : 2 }
        if rank(a) != rank(b) { return rank(a) < rank(b) }
        if abs(a.balance) != abs(b.balance) { return abs(a.balance) > abs(b.balance) }
        return a.traveller.name < b.traveller.name
      }
  }

  /// "owes £158", "is owed £92", "are owed £66" or "all square".
  public func status(_ row: PersonRow) -> String {
    let amount = WatchCurrency.whole(abs(row.balance), currency)
    if row.balance < 0 { return "\(row.isYou ? "owe" : "owes") \(amount)" }
    if row.balance > 0 { return "\(row.isYou ? "are" : "is") owed \(amount)" }
    return "all square"
  }

  /// One person's page: what they owe or are owed, leading with anything between them and you.
  public func person(_ id: String) -> Person {
    // As on the phone, nobody settles up until every paid spend has a conversion.
    guard balancesComplete else {
      return .init(
        id: id, headline: "Conversions pending",
        detail: "Settle up once everything's converted", settlement: nil)
    }
    let theirs = settlements.filter { $0.from == id || $0.to == id }
      .sorted { a, b in
        let mine = { (s: Settlement) in s.from == you || s.to == you }
        return mine(a) != mine(b) ? mine(a) : a.amount > b.amount
      }
    guard let lead = theirs.first else {
      return .init(
        id: id, headline: id == you ? "You're all square" : "\(name(id)) is all square",
        detail: "Nothing to settle", settlement: nil)
    }
    let rest = theirs.dropFirst().filter { (lead.from == id) == ($0.from == id) }
    let detail =
      lead.from == id
      ? rest.map { "\(object($0.to)) \(WatchCurrency.whole($0.amount, currency))" }
      : rest.map { "\(WatchCurrency.whole($0.amount, currency)) from \(object($0.from))" }
    return .init(
      id: id, headline: sentence(lead),
      detail: detail.isEmpty ? nil : (lead.from == id ? "and " : "plus ") + detail.joined(separator: ", "),
      settlement: lead.from == you || lead.to == you ? lead : nil)
  }

  public struct Person: Hashable {
    public let id: String
    /// "Tom owes you £66".
    public let headline: String
    /// "and Maya £92".
    public let detail: String?
    /// The transfer between this person and you, which "Mark paid" settles.
    public let settlement: Settlement?
  }

  /// "Tom owes you £66", "You owe Maya £30" or "Tom owes Maya £92".
  public func sentence(_ settlement: Settlement) -> String {
    let amount = WatchCurrency.whole(settlement.amount, currency)
    return settlement.from == you
      ? "You owe \(object(settlement.to)) \(amount)"
      : "\(name(settlement.from)) owes \(object(settlement.to)) \(amount)"
  }

  private func object(_ id: String) -> String { id == you ? "you" : name(id) }

  /// A repayment that settles a transfer in full, dated today on the trip.
  public func repayment(for settlement: Settlement) -> Repayment {
    Repayment(
      fromTravellerId: settlement.from, toTravellerId: settlement.to,
      amountMinor: String(settlement.amount), currency: currency,
      paidOn: trip.today(for: trip.currentAttachment(at: now), at: now), note: "")
  }
}

extension WatchModel {
  public func pages(for trip: TripSnapshot) -> TripPages {
    let unsynced = state.pending.compactMap { command -> String? in
      guard case .saveExpense(let id, let expense) = command, id == trip.id else { return nil }
      return expense.id
    }
    return TripPages(trip: trip, now: now, unsynced: Set(unsynced))
  }

  /// Records that a transfer has been paid, through the phone's normal sync.
  public func markPaid(_ settlement: Settlement, in trip: TripSnapshot) {
    send(.saveRepayment(tripID: trip.id, repayment: pages(for: trip).repayment(for: settlement)))
  }
}

extension WatchCurrency {
  /// A total rounded to whole units, e.g. "£1,240" or "¥12,000".
  public static func whole(_ minor: Int64, _ code: String) -> String {
    let factor = Money.factor(code)
    let half = minor >= 0 ? factor / 2 : -factor / 2
    return format(factor > 1 ? (minor + half) / factor * factor : minor, code, compact: true)
  }
}
