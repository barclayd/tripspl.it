import Foundation
import Observation
import Synchronization
import TripSplitDomain

/// A direction between two currencies, e.g. EUR → GBP.
public struct CurrencyPair: Codable, Hashable, Sendable {
  public init(from: String, to: String) {
    self.from = from
    self.to = to
  }
  public var from: String
  public var to: String
  public var reversed: CurrencyPair { .init(from: to, to: from) }
}

/// What quick convert reopens with.
public struct ConvertMemory: Codable, Hashable, Sendable {
  public init() {}
  /// The last amount in major units of the from currency, e.g. "24.5". Nil until first used.
  public var amount: String?
  /// A pair chosen by hand. Nil follows the trip: today's stop currency to home.
  public var pair: CurrencyPair?
  /// Whether the trip pair runs home to local instead.
  public var flipped = false
  /// Currencies chosen recently, most recent first.
  public var recents: [String] = []
}

/// The watch's quick convert: an amount the Crown dials, between today's stop currency and home
/// by default, or any pair. Display only; expenses still record a reference quote.
@MainActor @Observable public final class QuickConvert {
  public enum Side: Hashable, Sendable {
    case from, to
    public var other: Side { self == .from ? .to : .from }
  }

  /// A Crown stop when changing a currency: a currency, then "All currencies…" at the end.
  public enum CycleItem: Hashable, Sendable {
    case currency(String)
    case all
  }

  @ObservationIgnored public let model: WatchModel
  /// The currency the Crown is changing. Nil when the Crown dials the amount.
  public var focus: Side? {
    didSet {
      guard focus != oldValue else { return }
      if let oldValue { remember(code(oldValue)) }
      cycleItems = focus.map(cycle(for:)) ?? []
    }
  }
  /// The Crown stops for the focused currency, fixed while it has focus so they don't reorder.
  public private(set) var cycleItems: [CycleItem] = []
  /// The side whose currency last changed, with a count that ticks on each change.
  public private(set) var changed: Change?

  public struct Change: Equatable, Sendable {
    public let side: Side
    public let count: Int
  }

  public init(model: WatchModel) {
    self.model = model
  }

  private var memory: ConvertMemory {
    get { model.convertMemory }
    set { model.convertMemory = newValue }
  }

  // MARK: Pair

  /// Today's stop currency to home on the trip the watch leads with, else that trip's first
  /// foreign stop. Nil without a trip abroad.
  public var tripPair: CurrencyPair? {
    guard let trip = model.currentTrip,
      let local = trip.localCurrency(at: model.now)
        ?? trip.stopCurrencies.first(where: { $0 != trip.homeCurrency })
    else { return nil }
    return .init(from: local, to: trip.homeCurrency)
  }

  public var pair: CurrencyPair {
    if let custom = memory.pair { return custom }
    let home = model.currentTrip?.homeCurrency ?? model.trips.first?.homeCurrency ?? "GBP"
    let trip = tripPair ?? .init(from: home == "EUR" ? "USD" : "EUR", to: home)
    return memory.flipped ? trip.reversed : trip
  }

  public func code(_ side: Side) -> String { side == .from ? pair.from : pair.to }

  /// Whether the pair was chosen by hand rather than following the trip.
  public var isCustom: Bool { memory.pair != nil }
  /// Whether the trip pair runs home to local.
  public var isFlipped: Bool { memory.pair == nil && memory.flipped }

  /// Reverses the direction, e.g. £20 → CHF rather than CHF → £.
  public func swap() {
    if let custom = memory.pair {
      memory.pair = custom.reversed
    } else {
      memory.flipped.toggle()
    }
  }

  /// Returns to today's stop currency and home.
  public func resetToTrip() {
    var memory = memory
    memory.pair = nil
    memory.flipped = false
    self.memory = memory
  }

  /// Sets one side's currency. Choosing the other side's currency swaps them, and a pair that
  /// matches the trip goes back to following it.
  public func choose(_ code: String, for side: Side, remembering: Bool = true) {
    var next = pair
    if code == self.code(side.other) {
      next = next.reversed
    } else if side == .from {
      next.from = code
    } else {
      next.to = code
    }
    var memory = memory
    if let trip = tripPair, next == trip || next == trip.reversed {
      memory.pair = nil
      memory.flipped = next != trip
    } else {
      memory.pair = next
    }
    if remembering { memory.recents = Self.recents(adding: code, to: memory.recents) }
    self.memory = memory
    changed = Change(side: side, count: (changed?.count ?? 0) + 1)
  }

  private func remember(_ code: String) {
    memory.recents = Self.recents(adding: code, to: memory.recents)
  }

  private static func recents(adding code: String, to recents: [String]) -> [String] {
    Array(([code] + recents.filter { $0 != code }).prefix(6))
  }

  // MARK: Amount

  /// How many units one Crown detent counts in: 1 for most currencies, more for low-value ones
  /// so a step is worth something, e.g. ×100 for yen into pounds.
  public var scale: Decimal { scale(from: pair.from, to: pair.to) }

  /// The amount in major units of the from currency. Opens at the last amount used.
  public var amount: Decimal {
    get {
      memory.amount.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
        ?? 10 * scale
    }
    set { memory.amount = "\(max(newValue, 0))" }
  }

  /// The amount in minor units of the from currency, rounded to its precision.
  public var amountMinor: Int64 { Self.minor(amount, pair.from) }

  /// The converted amount, or nil without a rate.
  public var result: Int64? { model.convert(amountMinor, from: pair.from, to: pair.to) }

  /// The rate for one detent, e.g. "€1 = £0.86" or "¥100 = £0.50".
  public var rateLine: String? { rateText(from: pair.from, to: pair.to) }

  /// One detent of `from` in `to`, e.g. "£1 = $1.33". Nil without a rate.
  public func rateText(from: String, to: String, separator: String = " = ") -> String? {
    let unit = Self.minor(scale(from: from, to: to), from)
    guard let converted = model.convert(unit, from: from, to: to) else { return nil }
    return WatchCurrency.format(unit, from, compact: true) + separator
      + WatchCurrency.format(converted, to)
  }

  private func scale(from: String, to: String) -> Decimal {
    var units: Int64 = 1
    while units < 1_000_000,
      let converted = model.convert(10 * units * Money.factor(from), from: from, to: to),
      converted < Money.factor(to)
    {
      units *= 10
    }
    return Decimal(units)
  }

  /// The Crown detent for the amount.
  public var amountDetent: Int { AmountLadder.index(for: amount / scale) }

  /// Moves the amount to a Crown detent.
  public func dial(to detent: Int) {
    amount = Decimal(AmountLadder.value(at: detent)) * scale
  }

  static func minor(_ amount: Decimal, _ currency: String) -> Int64 {
    var value = amount * Decimal(Money.factor(currency))
    var rounded = Decimal()
    NSDecimalRound(&rounded, &value, 0, .plain)
    guard rounded > 0 else { return 0 }
    return rounded >= Decimal(Money.limit)
      ? Money.limit : NSDecimalNumber(decimal: rounded).int64Value
  }

  // MARK: Currencies

  /// Crown order for a side: this trip's currencies, the next trip's, recents, then A–Z, ending
  /// with "All currencies…". Skips the other side's currency, which would swap the pair.
  public func cycle(for side: Side) -> [CycleItem] {
    let other = code(side.other)
    var codes: [String] = []
    func add(_ list: [String]) {
      for code in list where code != other && !codes.contains(code) { codes.append(code) }
    }
    add(tripCurrencies)
    add(memory.recents)
    add([code(side)])
    add(model.convertibleCurrencies)
    return codes.map(CycleItem.currency) + [.all]
  }

  /// Where the focused currency sits in its Crown stops.
  public var cycleDetent: Int {
    guard let focus else { return 0 }
    return cycleItems.firstIndex(of: .currency(code(focus))) ?? 0
  }

  /// Moves the focused currency to a Crown stop. Returns true at "All currencies…".
  @discardableResult public func turn(to detent: Int) -> Bool {
    guard let focus, cycleItems.indices.contains(detent) else { return false }
    switch cycleItems[detent] {
    case .currency(let code):
      if code != self.code(focus) { choose(code, for: focus, remembering: false) }
      return false
    case .all:
      return true
    }
  }

  /// Up to three currencies to pick in one tap: this trip's, the next trip's, then recents.
  public func quickPicks(for side: Side) -> [String] {
    let other = code(side.other)
    let codes = tripCurrencies.filter { $0 != model.currentTrip?.homeCurrency } + memory.recents
    var picks: [String] = []
    for code in codes where code != other && !picks.contains(code) { picks.append(code) }
    return Array(picks.prefix(3))
  }

  /// Every currency the picker lists, A–Z, including the current pair.
  public var allCurrencies: [String] {
    Array(Set(model.convertibleCurrencies + [pair.from, pair.to])).sorted()
  }

  private var tripCurrencies: [String] {
    let trip = model.currentTrip
    let next = model.timeline.upcoming.first { $0.id != trip?.id }
    return [trip, next].compactMap { $0 }.flatMap { $0.stopCurrencies + [$0.homeCurrency] }
  }

  /// A currency's flag, symbol and name, using the trip's country for shared currencies, e.g.
  /// 🇵🇹 for euros in Porto.
  public func currency(_ code: String) -> WatchCurrency {
    let trip = model.currentTrip
    let today = trip.flatMap { trip in
      trip.currentDay(at: model.now).flatMap { trip.stop(for: .init(kind: .day, id: $0.id)) }
    }
    let stops =
      [today].compactMap { $0 } + (trip?.stops ?? []) + model.timeline.upcoming.flatMap(\.stops)
    return WatchCurrency(code: code, countryCode: stops.first { $0.currency == code }?.countryCode)
  }

  /// Fetches a rate for a pair the cached tables don't cover, when online.
  public func loadRateIfNeeded() async {
    let pair = pair
    guard model.rate(from: pair.from, to: pair.to) == nil else { return }
    await model.refreshRate(from: pair.from, to: pair.to)
  }
}

/// A currency as the watch shows it: flag, narrow symbol and name, e.g. 🇺🇸 $ US dollar.
public struct WatchCurrency: Identifiable, Hashable, Sendable {
  public let code: String
  public let flag: String
  /// The narrow symbol, e.g. "$" or "€", or the code when there is none, e.g. "CHF".
  public let symbol: String
  public var id: String { code }
  public var name: String { Locale.current.localizedString(forCurrencyCode: code) ?? code }
  /// Symbol and code, e.g. "$ USD", or the code alone when it is the symbol.
  public var label: String { symbol == code ? code : "\(symbol) \(code)" }

  public init(code: String, countryCode: String? = nil) {
    self.code = code
    let cached = Self.cached(code)
    flag = countryCode?.flag ?? cached.flag
    symbol = cached.symbol
  }

  /// Symbols and flags need a currency formatter and a country scan, so each code is worked out
  /// once and kept for the picker's rows.
  private static let cache = Mutex<[String: Traits]>([:])

  private struct Traits: Sendable {
    let narrow: String
    let symbol: String
    let flag: String
  }

  private static func cached(_ code: String) -> Traits {
    if let traits = cache.withLock({ $0[code] }) { return traits }
    let narrow = narrowSymbol(code)
    let traits = Traits(narrow: narrow, symbol: symbol(code, narrow: narrow), flag: flag(code))
    cache.withLock { $0[code] = traits }
    return traits
  }

  /// Formats an amount with the narrow symbol, e.g. "$50", "A$50" or "£20.69".
  public static func format(_ minor: Int64, _ code: String, compact: Bool = false) -> String {
    let factor = Money.factor(code)
    let digits = compact && minor % factor == 0 ? 0 : Money.precision(code)
    let text = (Decimal(minor) / Decimal(factor)).formatted(
      .currency(code: code).presentation(.narrow).precision(.fractionLength(digits)))
    let traits = cached(code), narrow = traits.narrow, symbol = traits.symbol
    guard narrow != symbol, let range = text.range(of: narrow) else { return text }
    return text.replacingCharacters(in: range, with: symbol)
  }

  /// The narrow symbol, except that dollars other than the US dollar keep their prefix, e.g.
  /// A$ and MX$, so a pair of dollar currencies stays readable.
  static func symbol(_ code: String) -> String { cached(code).symbol }

  private static func symbol(_ code: String, narrow: String) -> String {
    guard narrow == "$", code != "USD" else { return narrow }
    let standard = symbol(
      in: Decimal(0).formatted(
        .currency(code: code).precision(.fractionLength(0)).locale(Locale(identifier: "en_US"))))
    return standard.contains("$") ? standard : code
  }

  private static func narrowSymbol(_ code: String) -> String {
    let sample = Decimal(0).formatted(
      .currency(code: code).presentation(.narrow).precision(.fractionLength(0)))
    let symbol = symbol(in: sample)
    return symbol.isEmpty ? code : symbol
  }

  private static func symbol(in sample: String) -> String {
    String(
      sample.filter { character in
        !character.isNumber && !character.isWhitespace
          && !character.unicodeScalars.allSatisfy { $0.properties.generalCategory == .format }
      })
  }

  /// The issuing country's flag: ISO 4217 codes start with the country code, e.g. JPY is 🇯🇵.
  static func flag(_ code: String) -> String {
    if code == "EUR" { return "🇪🇺" }
    let prefix = String(code.prefix(2))
    if CountryMetadata.country(prefix)?.currencies.contains(code) == true { return prefix.flag }
    let users = CountryMetadata.all.filter { $0.currencies.contains(code) }
    return users.count == 1 ? users[0].code.flag : "🌐"
  }
}

/// Crown detents for amounts, in units of the convert scale: 1 to 50 in ones, 55 to 200 in
/// fives, then tens up to 10,000.
public enum AmountLadder {
  public static let count = 1060

  public static func value(at detent: Int) -> Int {
    let detent = min(max(detent, 0), count - 1)
    if detent < 50 { return detent + 1 }
    if detent < 80 { return 50 + 5 * (detent - 49) }
    return 200 + 10 * (detent - 79)
  }

  /// The detent at or below a value, so turning from a typed 24.5 lands on 24 or 25.
  public static func index(for value: Decimal) -> Int {
    let value = NSDecimalNumber(decimal: value).doubleValue
    let detent: Int
    if value < 1 {
      detent = 0
    } else if value <= 50 {
      detent = Int(value) - 1
    } else if value <= 200 {
      detent = 49 + Int((value - 50) / 5)
    } else {
      detent = 79 + Int((value - 200) / 10)
    }
    return min(detent, count - 1)
  }
}
