import Foundation

/// Figures the watch app, its complications and the phone companion derive from a trip.
/// Pure functions over a snapshot, so every surface shows the same numbers.
extension TripSnapshot {
  /// The trip budget spread evenly across the trip's days.
  public var dailyBudget: Int64 {
    (Money.minor(budgetMinor) ?? 0) / Int64(max(1, days.count))
  }

  public var budget: Int64 { Money.minor(budgetMinor) ?? 0 }

  /// One-based position of a day in the itinerary.
  public func dayNumber(of day: TripDay) -> Int {
    (days.firstIndex(where: { $0.id == day.id }) ?? 0) + 1
  }

  /// Share of the trip's days reached by `day`, from 0 to 1.
  public func progress(through day: TripDay) -> Double {
    Double(dayNumber(of: day)) / Double(max(1, days.count))
  }

  /// Paid expenses attached to a day, in the home currency. Travel legs are excluded
  /// because they are usually booked ahead and would swamp a daily budget.
  public func spending(on day: TripDay) -> DaySpending {
    let items = expenses(for: .init(kind: .day, id: day.id))
    let ledger = Ledger(self, expenses: items.filter { $0.status == .paid })
    return .init(
      amount: ledger.paid, count: items.filter { $0.status == .paid }.count,
      budget: dailyBudget, unresolved: ledger.unresolved)
  }

  /// Whole days from `today` until the trip starts. Negative once it has begun.
  public func daysUntilStart(from today: String) -> Int {
    CivilDate.days(from: today, to: startsOn)
  }

  /// Departure-board style route, e.g. `LIS·OPO·SVQ`.
  public var routeCode: String { stops.map(\.code).joined(separator: "·") }

  /// The first stop's place, used as the trip's headline destination.
  public var destination: String { stops.first?.place ?? name }

  /// Stop currencies in itinerary order, without repeats.
  public var stopCurrencies: [String] {
    stops.map(\.currency).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
  }

  /// The local currency today when it differs from home. Nil when at home or not travelling.
  public func localCurrency(at instant: Date = Date()) -> String? {
    guard let day = currentDay(at: instant),
      let stop = stop(for: .init(kind: .day, id: day.id)), stop.currency != homeCurrency
    else { return nil }
    return stop.currency
  }
}

public struct DaySpending: Hashable, Sendable {
  public init(amount: Int64, count: Int, budget: Int64, unresolved: Int = 0) {
    self.amount = amount
    self.count = count
    self.budget = budget
    self.unresolved = unresolved
  }
  public var amount: Int64
  public var count: Int
  public var budget: Int64
  public var unresolved: Int
  /// Remaining daily budget. Negative when over.
  public var left: Int64 { budget - amount }
  /// Spend against the daily budget, from 0. Exceeds 1 when over.
  public var fraction: Double { budget > 0 ? Double(amount) / Double(budget) : 0 }
}

/// How the watch groups trips on its root list.
public struct TripTimeline: Sendable {
  public var now: [TripSnapshot]
  public var upcoming: [TripSnapshot]
  public var past: [TripSnapshot]

  public init(_ trips: [TripSnapshot], at instant: Date = Date()) {
    let active = trips.filter { !$0.archived }
    now = active.filter { $0.phase(at: instant) == .now }.sorted { $0.startsOn < $1.startsOn }
    upcoming = active.filter { $0.phase(at: instant) == .upcoming }.sorted {
      $0.startsOn < $1.startsOn
    }
    past = active.filter { $0.phase(at: instant) == .past }.sorted { $0.startsOn > $1.startsOn }
  }

  public var isEmpty: Bool { now.isEmpty && upcoming.isEmpty && past.isEmpty }

  /// Total spent across past trips when they share a home currency.
  public var pastTotal: (amount: Int64, currency: String)? {
    guard let currency = past.first?.homeCurrency,
      past.allSatisfy({ $0.homeCurrency == currency })
    else { return nil }
    return (past.reduce(0) { $0 + Ledger($1).total }, currency)
  }
}
