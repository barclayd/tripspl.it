import Foundation
import Observation
import TripSplitCompanion
import TripSplitDomain

/// Watch side of the companion: the phone's trips, the changes the watch has queued, and the
/// reference rates used for quick conversions. The phone remains the source of truth.
@MainActor @Observable public final class WatchModel {
  public private(set) var state: CompanionState
  public private(set) var rates: [String: FXQuote]
  /// The latest reference table per base currency, for conversions between any pair offline.
  public private(set) var tables: [String: FXTable]
  /// What quick convert reopens with: the last amount, a custom pair and recent currencies.
  public var convertMemory: ConvertMemory {
    didSet { try? mirror?.write(convertMemory, key: "convert") }
  }
  /// Settings kept on the watch, such as hiding amounts on the watch face.
  public var preferences: WatchPreferences {
    didSet {
      guard preferences != oldValue else { return }
      try? mirror?.write(preferences, key: "preferences")
      onChange?()
    }
  }
  /// The one-off moments already shown, such as the first trip's welcome.
  public internal(set) var moments: MomentsMemory {
    didSet { try? mirror?.write(moments, key: "moments") }
  }
  /// A short message for the user, such as a change the phone could not apply.
  public var message: String?
  /// The instant the UI treats as now. Refreshed when the app becomes active.
  public var now = Date()

  @ObservationIgnored private let mirror: CompanionMirror?
  @ObservationIgnored private let transport: (@MainActor (CompanionCommand) throws -> Void)?
  @ObservationIgnored private let loadQuote:
    (@Sendable (String, String, String) async throws -> FXQuote)?
  @ObservationIgnored private let loadTable: (@Sendable (String, String) async throws -> FXTable)?
  @ObservationIgnored private var retained: AnyObject?
  /// Whether the phone can be reached right now. Nil assumes it can, as in previews and tests.
  @ObservationIgnored var reachability: (@MainActor () -> Bool)?
  /// Called after trips change, for widget timeline reloads.
  @ObservationIgnored public var onChange: (@MainActor () -> Void)?

  public init(
    state: CompanionState = .init(), mirror: CompanionMirror? = nil,
    send: (@MainActor (CompanionCommand) throws -> Void)? = nil,
    loadQuote: (@Sendable (String, String, String) async throws -> FXQuote)? = nil,
    loadTable: (@Sendable (String, String) async throws -> FXTable)? = nil
  ) {
    self.state = state
    self.mirror = mirror
    transport = send
    self.loadQuote = loadQuote
    self.loadTable = loadTable
    rates = mirror?.read([String: FXQuote].self, key: "rates") ?? [:]
    tables = mirror?.read([String: FXTable].self, key: "tables") ?? [:]
    convertMemory = mirror?.read(ConvertMemory.self, key: "convert") ?? .init()
    preferences = mirror?.read(WatchPreferences.self, key: "preferences") ?? .init()
    // A watch that already has trips has had its welcome.
    moments =
      mirror?.read(MomentsMemory.self, key: "moments") ?? .init(welcomed: !state.trips.isEmpty)
  }

  public var trips: [TripSnapshot] { state.trips }
  public var timeline: TripTimeline { TripTimeline(state.trips, at: now) }
  public var hasSynced: Bool { state.hasSynced }
  public var lastSynced: Date? { state.context?.sentAt }
  public var pendingCount: Int { state.pending.count }

  public func trip(_ id: String) -> TripSnapshot? { trips.first { $0.id == id } }

  /// The trip the watch leads with: the one happening now, else the next departure.
  public var currentTrip: TripSnapshot? { timeline.now.first ?? timeline.upcoming.first }

  public func receive(_ context: CompanionContext) {
    let hadTrips = !trips.isEmpty
    let reasons = state.receive(context)
    welcomeIfFirst(hadTrips: hadTrips)
    if let reason = reasons.last { message = reason }
    persist()
  }

  /// Whether changes reach the phone straight away, or wait on the watch until it's back.
  public var isPhoneReachable: Bool { reachability?() ?? true }

  /// Removes a spend through the phone. A save the phone hasn't seen yet is dropped instead.
  public func deleteExpense(_ expense: Expense, in trip: TripSnapshot) {
    send(.deleteExpense(tripID: trip.id, expenseID: expense.id))
  }

  public func send(_ command: CompanionCommand) {
    state.queue(command)
    persist()
    do { try transport?(command) } catch { message = error.localizedDescription }
  }

  private func persist() {
    try? mirror?.save(state)
    onChange?()
  }

  // MARK: Rates

  /// The best known rate: the freshest cached reference quote or table rate, else the latest
  /// rate recorded on an expense.
  public func rate(from: String, to: String) -> String? { reference(from: from, to: to)?.rate }

  /// The best known rate with the day it was fetched for, so the watch can say how fresh it is.
  public func reference(from: String, to: String) -> (rate: String, date: String)? {
    if from == to { return ("1", CivilDate.string(now)) }
    let quote = rates[Self.key(from, to)]
    let table = tables.values.sorted { $0.requestedDate > $1.requestedDate }
      .first { $0.rate(from: from, to: to) != nil }
    if let quote, quote.requestedDate >= table?.requestedDate ?? "" {
      return (quote.rate, quote.requestedDate)
    }
    if let table, let rate = table.rate(from: from, to: to) { return (rate, table.requestedDate) }
    let expenses = trips.filter { $0.homeCurrency == to }.flatMap(\.expenses)
      .filter { $0.currency == from && $0.conversion != nil }
    return expenses.last?.conversion.map { ($0.rate, $0.rateDate) }
  }

  /// How many units one Crown detent counts in: 1 for most currencies, more for low-value ones
  /// so a step is worth something, e.g. ×100 for yen into pounds.
  public func detentScale(from: String, to: String) -> Decimal {
    var units: Int64 = 1
    while units < 1_000_000,
      let converted = convert(10 * units * Money.factor(from), from: from, to: to),
      converted < Money.factor(to)
    {
      units *= 10
    }
    return Decimal(units)
  }

  /// Fetches a fresh reference rate when online. Keeps the cached rate when the fetch fails.
  public func refreshRate(from: String, to: String) async {
    guard from != to, let loadQuote else { return }
    let today = CivilDate.today(timeZone: TimeZone.current.identifier)
    if let cached = rates[Self.key(from, to)], cached.requestedDate == today { return }
    guard let quote = try? await loadQuote(from, to, today) else { return }
    cache(quote)
  }

  /// Stores a reference rate for offline conversions.
  public func cache(_ quote: FXQuote) {
    rates[Self.key(quote.from, quote.to)] = quote
    try? mirror?.write(rates, key: "rates")
    onChange?()
  }

  /// Converts whole or fractional amounts for display, e.g. €10 to £8.62.
  public func convert(_ minor: Int64, from: String, to: String) -> Int64? {
    guard let rate = rate(from: from, to: to) else { return nil }
    return try? Money.convert(minor, from: from, to: to, rate: rate)
  }

  /// Stores a reference table, replacing the older one for its base.
  public func cache(_ table: FXTable) {
    tables[table.base] = table
    try? mirror?.write(tables, key: "tables")
    onChange?()
  }

  /// Refreshes today's table for the home currency of the trip the watch leads with, so quick
  /// convert works between any pair offline. Falls back to a single quote for the local currency.
  public func refreshRates() async {
    guard let trip = currentTrip else { return }
    let today = CivilDate.today(timeZone: TimeZone.current.identifier)
    if tables[trip.homeCurrency]?.requestedDate == today { return }
    if let loadTable, let table = try? await loadTable(trip.homeCurrency, today) {
      cache(table)
    } else if let local = trip.localCurrency(at: now) {
      await refreshRate(from: local, to: trip.homeCurrency)
    }
  }

  /// Currencies quick convert can offer: those in a cached table, else every supported one.
  public var convertibleCurrencies: [String] {
    let listed = tables.values.reduce(into: Set<String>()) { $0.formUnion($1.currencies) }
    let supported = CurrencyMetadata.codes
    return listed.isEmpty ? supported : supported.filter(listed.contains)
  }

  /// A ready-made conversion for today's stop, e.g. €10 = £8.62. Nil at home or without a rate.
  public func quickConversion(for trip: TripSnapshot) -> QuickConversion? {
    guard let day = trip.currentDay(at: now),
      let stop = trip.stop(for: .init(kind: .day, id: day.id)), stop.currency != trip.homeCurrency
    else { return nil }
    var amount = 10 * Money.factor(stop.currency)
    guard var converted = convert(amount, from: stop.currency, to: trip.homeCurrency) else {
      return nil
    }
    // Low-value currencies step up so the result is worth at least one home unit, e.g. ¥1,000.
    while converted < Money.factor(trip.homeCurrency), amount < 10_000_000 {
      amount *= 10
      guard let next = convert(amount, from: stop.currency, to: trip.homeCurrency) else { break }
      converted = next
    }
    return .init(
      flag: stop.flag, amount: amount, currency: stop.currency, converted: converted,
      homeCurrency: trip.homeCurrency)
  }

  private static func key(_ from: String, _ to: String) -> String { from + ">" + to }

  func retain(_ object: AnyObject) { retained = object }
}

/// Settings kept on the watch.
public struct WatchPreferences: Codable, Hashable, Sendable {
  public init(hidesAmountsWhenWristDown: Bool = false) {
    self.hidesAmountsWhenWristDown = hidesAmountsWhenWristDown
  }
  /// Shows amounts on the watch face as "£•••" while the wrist is down.
  public var hidesAmountsWhenWristDown: Bool
}

/// A sample conversion in today's local currency, shown on the convert capsule.
public struct QuickConversion: Hashable, Sendable {
  public var flag: String
  public var amount: Int64
  public var currency: String
  public var converted: Int64
  public var homeCurrency: String
}
