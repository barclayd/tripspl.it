import Foundation
import TripSplitDomain

/// What the complications and the Smart Stack card show at an instant (G0–G7): today's budget,
/// the trip so far, a quick conversion, the countdown to the next trip and who owes who. Worked
/// out from the same trips as the app, so the watch face never disagrees with it.
public struct WatchGlance: Hashable, Sendable {
  /// Which set of complications makes sense: none, the countdown set or the full trip set.
  public enum Context: Hashable, Sendable {
    case noTrips, between, onTrip
  }

  /// Green with plenty left, amber under a quarter, red once it's gone.
  public enum Level: Hashable, Sendable {
    case good, low, out
  }

  public var date: Date
  public var context: Context
  /// Whether amounts show as "£•••" while the wrist is down.
  public var hidesAmounts: Bool
  /// The home currency's symbol, for hidden amounts.
  public var symbol: String
  public var today: Today?
  public var total: Total?
  public var conversion: Conversion?
  public var countdown: Countdown?
  public var owed: Owed?
  public var balances: Balances?
  public var daily: DailySpend?

  /// An amount with its figures hidden, e.g. "£•••".
  public var masked: String { symbol + "•••" }

  /// Nothing to show yet, so every complication shows the placeholder.
  public init(date: Date, symbol: String = "£") {
    self.date = date
    context = .noTrips
    hidesAmounts = false
    self.symbol = symbol
  }

  /// Where a figure belongs: its flag, and the country code for when there is none.
  public struct Place: Hashable, Sendable {
    public var flag: String
    /// Two letters, e.g. "PT".
    public var code: String
    public var name: String

    public init(flag: String, code: String, name: String) {
      self.flag = flag
      self.code = code
      self.name = name
    }

    init(_ stop: Stop) {
      self.init(flag: stop.flag, code: stop.countryCode.uppercased(), name: stop.place)
    }
  }

  /// Spend against a budget, for the budget-left rings.
  public struct Remaining: Hashable, Sendable {
    public var spent: Int64
    public var budget: Int64
    public var currency: String

    public init(spent: Int64, budget: Int64, currency: String) {
      self.spent = spent
      self.budget = budget
      self.currency = currency
    }

    public var left: Int64 { budget - spent }
    /// The share of the budget still left, from 0 to 1.
    public var fraction: Double {
      budget > 0 ? min(max(Double(left) / Double(budget), 0), 1) : 0
    }
    public var level: Level { left <= 0 ? .out : fraction < 0.25 ? .low : .good }
    /// "£241", or "-£40" once over.
    public var amount: String { WatchCurrency.whole(left, currency) }
    /// "80%", or "OVER" so an overspend never relies on colour alone.
    public var percent: String { left < 0 ? "OVER" : "\(Int((fraction * 100).rounded()))%" }
  }

  /// G7 Today, the budget rings, where-you-are and the Smart Stack card.
  public struct Today: Hashable, Sendable {
    public var tripID: String
    public var place: Place
    public var day: Int
    public var days: Int
    public var currency: String
    /// Today's spend against the daily budget.
    public var daily: Remaining
    /// The trip's spend against its whole budget.
    public var trip: Remaining

    /// "Porto · Day 4".
    public var title: String { "\(place.name) · Day \(day)" }
    /// "PORTO · DAY 4", for the bezel.
    public var bezel: String { title.uppercased() }
    /// "4/8".
    public var progress: String { "\(day)/\(days)" }
    /// "£241 left today", or "£40 over today".
    public var leftLine: String {
      daily.left < 0
        ? "\(WatchCurrency.whole(-daily.left, currency)) over today"
        : "\(WatchCurrency.whole(daily.left, currency)) left today"
    }
    /// "£59", spent so far today.
    public var spent: String { WatchCurrency.whole(daily.spent, currency) }
  }

  /// Total spent on the trip against its budget, as an open range ring.
  public struct Total: Hashable, Sendable {
    public var tripID: String
    public var spent: Int64
    public var budget: Int64
    public var currency: String

    public init(tripID: String, spent: Int64, budget: Int64, currency: String) {
      self.tripID = tripID
      self.spent = spent
      self.budget = budget
      self.currency = currency
    }

    /// Spend against budget, from 0. Exceeds 1 once over.
    public var fraction: Double { budget > 0 ? Double(spent) / Double(budget) : 0 }
    public var isOver: Bool { budget > 0 && spent > budget }
    /// "£3.0k".
    public var amount: String { WatchGlance.compact(spent, currency) }
    /// "2.4k", the top of the range.
    public var budgetLabel: String { WatchGlance.compact(budget, currency, symbol: false) }
    /// "124%".
    public var percent: String { "\(Int((fraction * 100).rounded()))%" }
  }

  /// Quick convert: the last amount over its result.
  public struct Conversion: Hashable, Sendable {
    public var place: Place?
    /// "€10".
    public var from: String
    /// "£8.62".
    public var to: String
    /// One unit across, for the Smart Stack chip, e.g. "€1 = £0.86".
    public var rate: String?
    /// "€10 = £8.62".
    public var line: String { "\(from) = \(to)" }
  }

  /// Days until the next trip, and where it starts.
  public struct Countdown: Hashable, Sendable {
    public var tripID: String
    public var place: Place
    public var days: Int

    public init(tripID: String, place: Place, days: Int) {
      self.tripID = tripID
      self.place = place
      self.days = days
    }

    /// "DAYS", or "DAY" on the last one.
    public var unit: String { days == 1 ? "DAY" : "DAYS" }
    /// "Kyoto in 49 days".
    public var line: String { "\(place.name) in \(days) \(days == 1 ? "day" : "days")" }
  }

  /// Your balance on the trip, positive when you're owed.
  public struct Owed: Hashable, Sendable {
    public var tripID: String
    public var balance: Int64
    public var currency: String

    public init(tripID: String, balance: Int64, currency: String) {
      self.tripID = tripID
      self.balance = balance
      self.currency = currency
    }

    /// "£66".
    public var amount: String { WatchCurrency.whole(abs(balance), currency) }
    /// "OWED", "OWE" or "EVEN", over the amount.
    public var label: String { balance > 0 ? "OWED" : balance < 0 ? "OWE" : "EVEN" }
    /// Along the bezel on a corner, kept short so it never truncates: "OWES YOU", "YOU OWE" or "SQUARE".
    public var corner: String {
      balance > 0 ? "OWES YOU" : balance < 0 ? "YOU OWE" : "SQUARE"
    }
  }

  /// Who owes who: your balance first, then the biggest other one.
  public struct Balances: Hashable, Sendable {
    public enum Tone: Hashable, Sendable {
      case owedToYou, youOwe, others
    }

    public struct Line: Hashable, Sendable {
      /// "Tom owes you".
      public var text: String
      /// "£66", or empty for a line without an amount.
      public var amount: String
      public var tone: Tone
    }

    public var tripID: String
    public var place: Place?
    public var lines: [Line]
  }

  /// Days so far against the daily budget line.
  public struct DailySpend: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
      case past, today, future
    }

    public struct Bar: Identifiable, Hashable, Sendable {
      public var number: Int
      public var amount: Int64
      /// Height against the tallest of the budget and the busiest day, from 0 to 1.
      public var height: Double
      public var kind: Kind
      public var id: Int { number }
    }

    public var tripID: String
    public var place: Place
    public var budget: Int64
    public var currency: String
    public var bars: [Bar]
    /// Where the daily budget line sits, from 0 to 1.
    public var budgetLine: Double

    /// "£300/day".
    public var budgetLabel: String { WatchCurrency.whole(budget, currency) + "/day" }

    /// The days shown: every day of a short trip, else ten around today.
    static let window = 10
  }
}

extension WatchGlance {
  /// The glance at the model's `now`, with its trips, cached rates and preferences.
  @MainActor public init(model: WatchModel) {
    let now = model.now
    let timeline = model.timeline
    let lead = timeline.now.first ?? timeline.upcoming.first ?? timeline.past.first
    date = now
    context = !timeline.now.isEmpty ? .onTrip : timeline.isEmpty ? .noTrips : .between
    hidesAmounts = model.preferences.hidesAmountsWhenWristDown
    symbol = WatchCurrency(code: lead?.homeCurrency ?? "GBP").symbol

    if let trip = timeline.now.first, let day = trip.currentDay(at: now) {
      let stop = trip.stop(for: .init(kind: .day, id: day.id))
      let place = stop.map(Place.init) ?? Self.place(trip)
      let spending = trip.spending(on: day)
      let ledger = Ledger(trip)
      today = Today(
        tripID: trip.id, place: place, day: trip.dayNumber(of: day), days: trip.days.count,
        currency: trip.homeCurrency,
        daily: .init(spent: spending.amount, budget: spending.budget, currency: trip.homeCurrency),
        trip: .init(spent: ledger.total, budget: trip.budget, currency: trip.homeCurrency))
      total = Total(
        tripID: trip.id, spent: ledger.total, budget: trip.budget, currency: trip.homeCurrency)
      daily = Self.daily(trip, today: day, place: place)
    }

    if let next = timeline.upcoming.first {
      countdown = Countdown(
        tripID: next.id, place: Self.place(next),
        days: max(next.daysUntilStart(from: CivilDate.string(now)), 1))
    }

    if context != .noTrips {
      conversion = Self.conversion(model)
      let trip = timeline.now.first ?? Self.lastUnsettled(timeline) ?? lead
      if let trip, trip.hasCompanions {
        let pages = TripPages(trip: trip, now: now)
        owed = Owed(
          tripID: trip.id, balance: pages.ledger.balances[pages.you, default: 0],
          currency: trip.homeCurrency)
        balances = Self.balances(pages)
      }
    }
  }

  /// The most recent past trip where you still owe or are owed something.
  private static func lastUnsettled(_ timeline: TripTimeline) -> TripSnapshot? {
    timeline.past.first { trip in
      let ledger = Ledger(trip)
      return ledger.balances[trip.currentTravellerId, default: 0] != 0
    }
  }

  private static func place(_ trip: TripSnapshot) -> Place {
    trip.stops.first.map(Place.init) ?? .init(flag: "", code: "", name: trip.name)
  }

  /// Whatever quick convert opens with: its pair and last amount.
  @MainActor private static func conversion(_ model: WatchModel) -> Conversion? {
    let convert = QuickConvert(model: model)
    let pair = convert.pair
    guard let result = convert.result else { return nil }
    let currency = convert.currency(pair.from)
    let place = currency.flag.isEmpty ? nil : Place(
      flag: currency.flag, code: regionCode(currency.flag) ?? "", name: currency.name)
    return Conversion(
      place: place, from: WatchCurrency.format(convert.amountMinor, pair.from, compact: true),
      to: WatchCurrency.format(result, pair.to), rate: rate(model, from: pair.from, to: pair.to))
  }

  /// One unit across, stepping up for low-value currencies so it reads, e.g. "¥100 = £0.53".
  @MainActor private static func rate(_ model: WatchModel, from: String, to: String) -> String? {
    var unit = Money.factor(from)
    while let converted = model.convert(unit, from: from, to: to) {
      if converted * 10 >= Money.factor(to) || unit >= 1_000_000 * Money.factor(from) {
        return WatchCurrency.format(unit, from, compact: true) + " = "
          + WatchCurrency.format(converted, to)
      }
      unit *= 10
    }
    return nil
  }

  private static func balances(_ pages: TripPages) -> Balances {
    let place = pages.trip.stops.first.map(Place.init)
    guard pages.balancesComplete else {
      return .init(
        tripID: pages.trip.id, place: place,
        lines: [.init(text: "Conversions pending", amount: "", tone: .others)])
    }
    let you = pages.you
    let yours = pages.settlements.filter { $0.from == you || $0.to == you }
      .sorted { $0.amount > $1.amount }
    let others = pages.settlements.filter { $0.from != you && $0.to != you }
      .sorted { $0.amount > $1.amount }
    let lines = (yours + others).prefix(2).map { settlement -> Balances.Line in
      let amount = WatchCurrency.whole(settlement.amount, pages.currency)
      if settlement.to == you {
        return .init(text: "\(pages.name(settlement.from)) owes you", amount: amount, tone: .owedToYou)
      }
      if settlement.from == you {
        return .init(text: "You owe \(pages.name(settlement.to))", amount: amount, tone: .youOwe)
      }
      return .init(
        text: "\(pages.name(settlement.from)) owes \(pages.name(settlement.to))", amount: amount,
        tone: .others)
    }
    return .init(
      tripID: pages.trip.id, place: place,
      lines: lines.isEmpty ? [.init(text: "All square", amount: "", tone: .others)] : Array(lines))
  }

  private static func daily(_ trip: TripSnapshot, today: TripDay, place: Place) -> DailySpend {
    let number = trip.dayNumber(of: today)
    let count = trip.days.count
    let window = DailySpend.window
    let first = count <= window ? 1 : min(max(number - window / 2 + 1, 1), count - window + 1)
    let days = trip.days.dropFirst(first - 1).prefix(window)
    let amounts = days.map { trip.dayNumber(of: $0) <= number ? trip.spending(on: $0).amount : 0 }
    let budget = trip.dailyBudget
    let scale = Double(max(budget, amounts.max() ?? 0, 1))
    let bars = zip(days, amounts).map { day, amount in
      let index = trip.dayNumber(of: day)
      return DailySpend.Bar(
        number: index, amount: amount, height: Double(amount) / scale,
        kind: index < number ? .past : index == number ? .today : .future)
    }
    return .init(
      tripID: trip.id, place: place, budget: budget, currency: trip.homeCurrency, bars: bars,
      budgetLine: Double(budget) / scale)
  }

  /// A short amount for a ring, e.g. "£241", "£3.0k" or "£24k".
  public static func compact(_ minor: Int64, _ code: String, symbol: Bool = true) -> String {
    let major = abs(Double(minor) / Double(Money.factor(code)))
    let sign = minor < 0 ? "-" : ""
    let prefix = symbol ? WatchCurrency(code: code).symbol : ""
    let text: String
    switch major.rounded() {
    case ..<1000:
      return symbol
        ? WatchCurrency.whole(minor, code) : sign + String(Int(major.rounded()))
    case ..<9950:
      text = (major / 1000).formatted(.number.precision(.fractionLength(1))) + "k"
    case ..<999_500:
      text = String(Int((major / 1000).rounded())) + "k"
    default:
      text = (major / 1_000_000).formatted(.number.precision(.fractionLength(1))) + "m"
    }
    return sign + prefix + text
  }

  /// The country code a flag spells, e.g. "PT" for 🇵🇹.
  public static func regionCode(_ flag: String) -> String? {
    let base: UInt32 = 0x1F1E6
    let letters = flag.unicodeScalars.compactMap { scalar -> Character? in
      guard (base...base + 25).contains(scalar.value),
        let letter = Unicode.Scalar(scalar.value - base + 65)
      else { return nil }
      return Character(letter)
    }
    return letters.count == 2 ? String(letters) : nil
  }
}
