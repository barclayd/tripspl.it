import Foundation
import TripSplitCompanion
import TripSplitDomain
import TripSplitWatchModel

public typealias Place = WatchGlance.Place

/// What the iPhone's widgets show at an instant: today's budget, a quick conversion, where you
/// are, the countdown, who owes who, daily spend and the departures board. Worked out from the
/// trips the app writes to the App Group, with the watch's maths, so every surface agrees.
@MainActor public struct PhoneWidgets {
  public let model: WatchModel
  public let settings: WidgetSettings

  public init(model: WatchModel, settings: WidgetSettings = .init()) {
    self.model = model
    self.settings = settings
  }

  /// Reads what the app last wrote to the App Group, at `date`.
  public static func shared(at date: Date = Date()) -> PhoneWidgets {
    let mirror = CompanionMirror.shared()
    let model = WatchModel(state: mirror.load(), mirror: mirror)
    model.now = date
    return PhoneWidgets(model: model, settings: WidgetSnapshot.settings(in: mirror))
  }

  public var now: Date { model.now }
  var timeline: TripTimeline { model.timeline }
  var today: String { CivilDate.string(now, timeZone: TimeZone.current.identifier) }

  /// Whether there's anything to show other than the no-trips state.
  public var hasTrips: Bool { !timeline.isEmpty }
  /// Trips the widgets can be pointed at, for the configuration picker.
  public var trips: [TripSnapshot] { timeline.now + timeline.upcoming + timeline.past }

  /// A picked trip, else the one under way, else the next departure.
  public func trip(_ id: String?) -> TripSnapshot? {
    if let id, let trip = model.trip(id), !trip.archived { return trip }
    return timeline.now.first ?? timeline.upcoming.first
  }

  /// Whether today's stop uses a currency other than home, which makes the convert and today
  /// widgets the ones worth surfacing in a Smart Stack.
  public var isAbroad: Bool { timeline.now.first?.localCurrency(at: now) != nil }

  /// The next local midnight, when the day and the countdown move on.
  public var nextMidnight: Date {
    let calendar = Calendar.current
    return calendar.nextDate(
      after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime)
      ?? now.addingTimeInterval(86_400)
  }

  func place(_ stop: Stop) -> Place {
    Place(flag: stop.flag, code: stop.countryCode.uppercased(), name: stop.place)
  }

  func place(_ trip: TripSnapshot) -> Place {
    trip.stops.first.map(place) ?? Place(flag: "", code: "", name: trip.name)
  }

  /// Where you are today on a trip under way, else its first stop.
  func place(_ trip: TripSnapshot, on day: TripDay?) -> Place {
    day.flatMap { trip.stop(for: .init(kind: .day, id: $0.id)) }.map(place) ?? place(trip)
  }
}

// MARK: Today

/// Spend against a budget, coloured green, pink once under a quarter is left and red once over.
public struct BudgetFigures: Hashable, Sendable {
  public enum Tone: Hashable, Sendable {
    case good, low, over
  }

  public var spent: Int64
  public var budget: Int64
  public var currency: String

  public init(spent: Int64, budget: Int64, currency: String) {
    self.spent = spent
    self.budget = budget
    self.currency = currency
  }

  public var left: Int64 { budget - spent }
  public var isOver: Bool { left < 0 }
  /// The share of the budget still left, from 0 to 1.
  public var fraction: Double {
    budget > 0 ? min(max(Double(left) / Double(budget), 0), 1) : 0
  }
  /// Spend against budget, from 0. Exceeds 1 once over.
  public var spentFraction: Double { budget > 0 ? Double(spent) / Double(budget) : 0 }
  public var tone: Tone { isOver ? .over : fraction < 0.25 ? .low : .good }

  /// Segments filled out of `count`: the share left, or every one once over.
  public func filled(_ count: Int) -> Int {
    isOver ? count : Int((fraction * Double(count)).rounded())
  }

  /// "£241", or "£34" once over: the words around it say which.
  public var hero: String { WatchCurrency.whole(abs(left), currency) }
  /// "£59 of £300 spent".
  public var caption: String {
    "\(WatchCurrency.whole(spent, currency)) of \(WatchCurrency.whole(budget, currency)) spent"
  }
  /// "80%", or "OVER" so an overspend never relies on colour alone.
  public var percent: String { isOver ? "OVER" : "\(Int((fraction * 100).rounded()))%" }
  /// A short amount left for a ring, e.g. "£241" or "£1.5k".
  public var compactLeft: String {
    (isOver ? "-" : "") + WatchGlance.compact(abs(left), currency)
  }
  /// A short amount spent for a ring, e.g. "£885".
  public var compactSpent: String { WatchGlance.compact(spent, currency) }
  /// The top of the range, e.g. "2.4k".
  public var compactBudget: String { WatchGlance.compact(budget, currency, symbol: false) }
}

/// What Today shows: today's or the whole trip's budget, where you are and the local rate.
public struct TodayFigures: Hashable, Sendable {
  public enum Scope: String, Hashable, Sendable {
    case today, trip
  }

  public var tripID: String
  public var tripName: String
  /// Today's itinerary day, for the Log expense link. Nil outside the trip's dates.
  public var dayID: String?
  public var place: Place
  /// One-based, nil before the trip starts or after it ends.
  public var day: Int?
  public var days: Int
  public var currency: String
  public var scope: Scope
  public var budget: BudgetFigures
  /// The rest of the trip, shown beside today on the large widget.
  public var trip: BudgetFigures
  /// "€1 = £0.86", only while abroad.
  public var rate: String?

  /// "left today", "over this trip".
  public var label: String {
    "\(budget.isOver ? "over" : "left") \(scope == .today ? "today" : "this trip")"
  }
  /// "£241 left today", for the inline accessory and the rectangular one.
  public var line: String { "\(budget.hero) \(label)" }
  /// "Day 4", or empty outside the trip's dates.
  public var dayLabel: String { day.map { "Day \($0)" } ?? "" }
  /// "Day 4 of 8".
  public var dayOfDays: String { day.map { "Day \($0) of \(days)" } ?? "\(days) days" }
  /// "Porto · Day 4".
  public var title: String { day.map { "\(place.name) · Day \($0)" } ?? place.name }
}

extension PhoneWidgets {
  /// Today's budget on the trip under way, or the whole trip's. Nil when the trip hasn't
  /// started and today is asked for, so the widget can count down instead.
  public func today(tripID: String?, scope: TodayFigures.Scope = .today) -> TodayFigures? {
    guard let trip = trip(tripID) else { return nil }
    let day = trip.currentDay(at: now)
    if scope == .today, day == nil { return nil }
    // Paid and planned, as the trip's cost card counts it, so the widget never disagrees with it.
    let whole = BudgetFigures(
      spent: Ledger(trip).total, budget: trip.budget, currency: trip.homeCurrency)
    let budget: BudgetFigures
    if scope == .today, let day {
      let spending = trip.spending(on: day)
      budget = .init(spent: spending.amount, budget: spending.budget, currency: trip.homeCurrency)
    } else {
      budget = whole
    }
    return TodayFigures(
      tripID: trip.id, tripName: trip.name, dayID: day?.id, place: place(trip, on: day),
      day: day.map(trip.dayNumber(of:)), days: trip.days.count, currency: trip.homeCurrency,
      scope: scope, budget: budget, trip: whole, rate: localRate(trip))
  }

  /// One unit of today's local currency in home, e.g. "€1 = £0.86". Nil at home.
  func localRate(_ trip: TripSnapshot) -> String? {
    guard let local = trip.localCurrency(at: now) else { return nil }
    return model.rateText(from: local, to: trip.homeCurrency)
  }
}

// MARK: Where you are

/// A trip's days grouped by stop, with today picked out.
public struct ProgressFigures: Hashable, Sendable {
  public enum Kind: Hashable, Sendable {
    case past, today, future
  }

  public struct Group: Hashable, Sendable {
    public var stopID: String
    public var days: [Kind]
  }

  public var tripID: String
  public var place: Place
  public var day: Int
  public var days: Int
  public var groups: [Group]
  /// "Seville on Monday", "Seville tomorrow" or "Home on Wednesday".
  public var next: String

  /// Every day in order, without the stop breaks.
  public var segments: [Kind] { groups.flatMap(\.days) }
  /// "Day 4 of 8".
  public var dayOfDays: String { "Day \(day) of \(days)" }
  /// "4/8".
  public var fraction: String { "\(day)/\(days)" }
}

extension PhoneWidgets {
  /// Where you are on the trip under way. Nil outside its dates.
  public func progress(tripID: String?) -> ProgressFigures? {
    guard let trip = trip(tripID), let day = trip.currentDay(at: now) else { return nil }
    let number = trip.dayNumber(of: day)
    var groups: [ProgressFigures.Group] = []
    for (index, item) in trip.days.enumerated() {
      let kind: ProgressFigures.Kind =
        index + 1 < number ? .past : index + 1 == number ? .today : .future
      if groups.last?.stopID == item.stopId {
        groups[groups.count - 1].days.append(kind)
      } else {
        groups.append(.init(stopID: item.stopId, days: [kind]))
      }
    }
    return ProgressFigures(
      tripID: trip.id, place: place(trip, on: day), day: number, days: trip.days.count,
      groups: groups, next: next(trip, after: day))
  }

  /// The next stop and when you get there, else when you head home.
  private func next(_ trip: TripSnapshot, after day: TripDay) -> String {
    let later = trip.days.drop { $0.id != day.id }.dropFirst()
    if let move = later.first(where: { $0.stopId != day.stopId }),
      let stop = trip.stops.first(where: { $0.id == move.stopId })
    {
      return "\(stop.place) \(when(move.date))"
    }
    let home = trip.legs.first { $0.kind == .return }?.date ?? trip.endsOn
    return "Home \(when(home))"
  }

  /// "today", "tomorrow", "on Monday" within the week, else "on 12 Nov".
  func when(_ date: String) -> String {
    let days = CivilDate.days(from: today, to: date)
    switch days {
    case ...0: return "today"
    case 1: return "tomorrow"
    case 2...6: return "on " + CivilDate.display(date, format: "EEEE")
    default: return "on " + CivilDate.display(date, format: "d MMM")
    }
  }
}

// MARK: Countdown

/// Days until a trip, and how far along the wait is since it was booked.
public struct CountdownFigures: Hashable, Sendable {
  public var tripID: String
  public var place: Place
  /// Zero on departure day.
  public var days: Int
  public var startsOn: String
  /// From when the trip was booked to departure, from 0 to 1.
  public var fraction: Double
  /// "Gute Reise!", in the language of the first stop.
  public var greeting: String
  /// The first outbound booking, e.g. "Swiss to Geneva 10:40", for departure day.
  public var firstLeg: String?

  public var isDepartureDay: Bool { days == 0 }
  /// "days", or "day" on the last one.
  public var unit: String { days == 1 ? "day" : "days" }
  /// "Zermatt in 49 days", or "Zermatt today".
  public var line: String {
    isDepartureDay ? "\(place.name) today" : "\(place.name) in \(days) \(unit)"
  }
  /// "Leaves Sat 19 Dec".
  public var caption: String { "Leaves " + CivilDate.display(startsOn, format: "EEE d MMM") }
  /// Segments filled out of `count`.
  public func filled(_ count: Int) -> Int {
    isDepartureDay ? count : Int((fraction * Double(count)).rounded())
  }
}

extension PhoneWidgets {
  /// The countdown to a picked trip, else the one leaving today, else the next departure.
  public func countdown(tripID: String?) -> CountdownFigures? {
    let trip: TripSnapshot?
    if let tripID, let picked = model.trip(tripID), picked.startsOn >= today {
      trip = picked
    } else {
      trip = timeline.now.first { $0.startsOn == today } ?? timeline.upcoming.first
    }
    guard let trip else { return nil }
    let days = max(CivilDate.days(from: today, to: trip.startsOn), 0)
    let outbound = trip.legs.first { $0.kind == .outbound }
    let firstLeg = outbound.flatMap { trip.expenses(for: .init(kind: .leg, id: $0.id)).first }
    return CountdownFigures(
      tripID: trip.id, place: place(trip), days: days, startsOn: trip.startsOn,
      fraction: waited(trip), greeting: Greeting.departure(countryCode: trip.stops.first?.countryCode),
      firstLeg: firstLeg?.title)
  }

  /// How far through the wait from booking to departure. The trip doesn't record when it was
  /// booked, so this starts from the earlier of when this phone first saw it and its first payment.
  private func waited(_ trip: TripSnapshot) -> Double {
    let starts = [settings.firstSeen[trip.id]] + trip.expenses.map(\.paidOn)
    guard let booked = starts.compactMap({ $0 }).filter({ $0 <= today }).min() else { return 0 }
    let total = CivilDate.days(from: booked, to: trip.startsOn)
    guard total > 0 else { return 1 }
    return min(max(Double(CivilDate.days(from: booked, to: today)) / Double(total), 0), 1)
  }
}

// MARK: Who owes who

/// Who owes who on a shared trip: your balance first, then the biggest other one.
public struct BalanceFigures: Hashable, Sendable {
  public enum Tone: Hashable, Sendable {
    case owedToYou, youOwe, others
  }

  public struct Row: Hashable, Sendable {
    /// The other person's initial and hue, for the avatar.
    public var initial: String
    public var hue: Double
    /// "Tom owes you".
    public var text: String
    /// "£66".
    public var amount: String
    public var tone: Tone
    /// "Tom owes you £66".
    public var line: String { "\(text) \(amount)" }
  }

  public var tripID: String
  public var place: Place
  public var currency: String
  /// Up to two settlements, yours first. Empty once everyone's square.
  public var rows: [Row]
  /// Your net balance, positive when you're owed.
  public var balance: Int64
  /// Some conversions are still pending, so the balances aren't final.
  public var pending: Bool

  /// The settlement involving you, for the hero.
  public var yours: Row? { rows.first { $0.tone != .others } }
  /// The biggest balance between other people, for the caption.
  public var others: Row? { rows.first { $0.tone == .others } }
  /// "OWED", "OWE" or "EVEN", over the amount on the circular.
  public var label: String { balance > 0 ? "OWED" : balance < 0 ? "OWE" : "EVEN" }
  /// "£66".
  public var amount: String { WatchCurrency.whole(abs(balance), currency) }
}

extension PhoneWidgets {
  /// Balances on a picked shared trip, else the one under way, else the latest still unsettled,
  /// else the next. Nil without a shared trip.
  public func balances(tripID: String?) -> BalanceFigures? {
    let shared = { (trip: TripSnapshot) in trip.hasCompanions }
    let unsettled = timeline.past.first { trip in
      shared(trip) && Ledger(trip).balances[trip.currentTravellerId, default: 0] != 0
    }
    let picked = tripID.flatMap(model.trip).flatMap { shared($0) && !$0.archived ? $0 : nil }
    guard
      let trip = picked ?? timeline.now.first(where: shared) ?? unsettled
        ?? timeline.upcoming.first(where: shared)
    else { return nil }
    let pages = TripPages(trip: trip, now: now)
    let you = pages.you
    let currency = trip.homeCurrency
    let yours = pages.settlements.filter { $0.from == you || $0.to == you }
      .sorted { $0.amount > $1.amount }
    let others = pages.settlements.filter { $0.from != you && $0.to != you }
      .sorted { $0.amount > $1.amount }
    let rows = (yours.prefix(1) + others.prefix(yours.isEmpty ? 2 : 1)).map { settlement in
      let amount = WatchCurrency.whole(settlement.amount, currency)
      let counterpart = settlement.to == you ? settlement.from : settlement.to
      let person = pages.traveller(settlement.from == you || settlement.to == you
        ? counterpart : settlement.from)
      let initial = String((person?.name ?? "?").prefix(1)).uppercased()
      let hue = person?.hue ?? 350
      if settlement.to == you {
        return BalanceFigures.Row(
          initial: initial, hue: hue, text: "\(pages.name(settlement.from)) owes you",
          amount: amount, tone: .owedToYou)
      }
      if settlement.from == you {
        return .init(
          initial: initial, hue: hue, text: "You owe \(pages.name(settlement.to))", amount: amount,
          tone: .youOwe)
      }
      return .init(
        initial: initial, hue: hue,
        text: "\(pages.name(settlement.from)) owes \(pages.name(settlement.to))", amount: amount,
        tone: .others)
    }
    return BalanceFigures(
      tripID: trip.id, place: place(trip, on: trip.currentDay(at: now)), currency: currency,
      rows: pages.balancesComplete ? Array(rows) : [],
      balance: pages.ledger.balances[you, default: 0], pending: !pages.balancesComplete)
  }
}

// MARK: Daily spend

/// Each day's spending against the daily budget, around today.
public struct DailyFigures: Hashable, Sendable {
  public enum Kind: Hashable, Sendable {
    case past, today, future
  }

  public struct Column: Identifiable, Hashable, Sendable {
    public var number: Int
    /// "S".
    public var letter: String
    /// Paid so far, in home minor units.
    public var spent: Int64
    /// Still planned, shown as an outline on days to come.
    public var planned: Int64
    public var kind: Kind
    public var id: Int { number }
  }

  public var tripID: String
  public var place: Place
  public var budget: Int64
  public var currency: String
  public var columns: [Column]
  /// The top of the chart, a third above the budget unless a day goes higher.
  public var scale: Int64

  /// Where the budget line sits, from 0 to 1.
  public var budgetLine: Double { scale > 0 ? Double(budget) / Double(scale) : 0 }
  /// "£300 a day".
  public var budgetLabel: String { WatchCurrency.whole(budget, currency) + " a day" }
  /// "£300".
  public var budgetAmount: String { WatchCurrency.whole(budget, currency) }
  public func height(_ amount: Int64) -> Double {
    scale > 0 ? min(Double(amount) / Double(scale), 1) : 0
  }

  /// The days shown: every day of a short trip, else eight around today.
  public static let window = 8
}

extension PhoneWidgets {
  public func daily(tripID: String?) -> DailyFigures? {
    guard let trip = trip(tripID), !trip.days.isEmpty else { return nil }
    let current = trip.currentDay(at: now).map(trip.dayNumber(of:))
    let number =
      current ?? (trip.phase(at: now) == .past ? trip.days.count + 1 : 0)
    let count = trip.days.count
    let window = DailyFigures.window
    let first =
      count <= window ? 1 : min(max((current ?? 1) - window / 2 + 1, 1), count - window + 1)
    let columns = trip.days.dropFirst(first - 1).prefix(window).map { day in
      let index = trip.dayNumber(of: day)
      let items = trip.expenses(for: .init(kind: .day, id: day.id))
      let planned = Ledger(trip, expenses: items.filter { $0.status == .planned }).planned
      return DailyFigures.Column(
        number: index, letter: CivilDate.display(day.date, format: "EEEEE"),
        spent: index <= number ? trip.spending(on: day).amount : 0,
        planned: index > number ? planned : 0,
        kind: index < number ? .past : index == number ? .today : .future)
    }
    let budget = trip.dailyBudget
    let tallest = columns.map { max($0.spent, $0.planned) }.max() ?? 0
    return DailyFigures(
      tripID: trip.id, place: place(trip, on: trip.currentDay(at: now)), budget: budget,
      currency: trip.homeCurrency, columns: Array(columns),
      scale: max(budget * 4 / 3, tallest, 1))
  }
}

// MARK: Quick convert

/// A few handy amounts converted, the rate and when it was fetched.
public struct ConvertFigures: Hashable, Sendable {
  public struct Row: Hashable, Sendable {
    /// "€10".
    public var from: String
    /// "£8.62".
    public var to: String

    public init(from: String, to: String) {
      self.from = from
      self.to = to
    }
  }

  public var pair: CurrencyPair
  /// The flag of the place the money's from: today's stop, else the currency's.
  public var flag: String
  public var code: String
  /// "€", "£".
  public var fromSymbol: String
  public var toSymbol: String
  /// The middle four of the currency's presets, e.g. €5, €10, €20, €50.
  public var rows: [Row]
  /// The ×10 preset, for the circular, inline and StandBy.
  public var sample: Row
  /// "€1 = £0.862".
  public var rate: String
  /// When the rate was fetched, nil when unknown.
  public var fetchedAt: Date?

  /// "€ to £".
  public var title: String { "\(fromSymbol) to \(toSymbol)" }
}

extension PhoneWidgets {
  /// The pair the widget converts: a picked one, else today's local currency to home, either way
  /// turned around by Swap.
  public func pair(_ configured: CurrencyPair?) -> CurrencyPair {
    guard let configured else { return QuickConvert(model: model).pair }
    return model.convertMemory.flipped ? configured.reversed : configured
  }

  /// Nil without a rate for the pair.
  public func convert(pair configured: CurrencyPair?) -> ConvertFigures? {
    let pair = pair(configured)
    let scale = model.detentScale(from: pair.from, to: pair.to)
    let unit = QuickConvert.minor(scale, pair.from)
    guard let rate = model.rate(from: pair.from, to: pair.to), let perUnit = Decimal(string: rate)
    else { return nil }
    let presets: [Int64] = [1, 5, 10, 20, 50, 100]
    let rows = presets.compactMap { preset -> ConvertFigures.Row? in
      let amount = unit * preset
      guard let converted = model.convert(amount, from: pair.from, to: pair.to) else { return nil }
      return .init(
        from: WatchCurrency.format(amount, pair.from, compact: true),
        to: WatchCurrency.format(converted, pair.to))
    }
    guard rows.count == presets.count else { return nil }
    let units = scale
    let unitText = WatchCurrency.format(unit, pair.from, compact: true)
    let rateText = WatchCurrency.format(perUnit * units, pair.to, digits: 3)
    let fromCurrency = WatchCurrency(code: pair.from)
    let trip = timeline.now.first
    let local = trip?.localCurrency(at: now)
    let foreign = pair.from == trip?.homeCurrency ? pair.to : pair.from
    let stop = trip?.currentDay(at: now).flatMap { trip?.stop(for: .init(kind: .day, id: $0.id)) }
    let flag =
      foreign == local ? stop?.flag ?? fromCurrency.flag : WatchCurrency(code: foreign).flag
    let code =
      foreign == local
      ? stop?.countryCode.uppercased() ?? String(foreign.prefix(2)) : String(foreign.prefix(2))
    return ConvertFigures(
      pair: pair, flag: flag, code: code, fromSymbol: fromCurrency.symbol,
      toSymbol: WatchCurrency(code: pair.to).symbol, rows: Array(rows[1...4]), sample: rows[2],
      rate: "\(unitText) = \(rateText)", fetchedAt: settings.ratesFetchedAt)
  }
}

// MARK: Departures

/// The departures board: the trip under way, then upcoming departures.
public struct DeparturesFigures: Hashable, Sendable {
  public enum Status: Hashable, Sendable {
    case onTrip, today, upcoming
  }

  public struct Row: Identifiable, Hashable, Sendable {
    public var tripID: String
    public var flag: String
    /// "LISBON +2", ten cells at most.
    public var destination: String
    /// "28 OCT".
    public var date: String
    /// "ON TRIP", "TODAY" or "IN 49D".
    public var status: String
    public var kind: Status
    /// "Zermatt, 19 December, departs in 49 days".
    public var accessibilityLabel: String
    public var id: String { tripID }
  }

  public var rows: [Row]
  /// Between trips the last row invites a new one.
  public var addTrip: Bool
}

extension PhoneWidgets {
  public var departures: DeparturesFigures {
    let live = Array(timeline.now.prefix(1))
    let room = live.isEmpty ? 2 : 3
    let trips = Array((live + timeline.upcoming).prefix(room))
    let rows = trips.map { trip in
      let days = CivilDate.days(from: today, to: trip.startsOn)
      let onTrip = trip.phase(at: now) == .now
      let status: DeparturesFigures.Status = onTrip ? .onTrip : days <= 0 ? .today : .upcoming
      let when =
        onTrip
        ? "on trip now" : days <= 0 ? "departs today" : "departs in \(days) \(days == 1 ? "day" : "days")"
      return DeparturesFigures.Row(
        tripID: trip.id, flag: trip.stops.first?.flag ?? "🌍", destination: destination(trip),
        date: CivilDate.display(trip.startsOn).uppercased(),
        status: onTrip ? "ON TRIP" : days <= 0 ? "TODAY" : "IN \(min(days, 999))D", kind: status,
        accessibilityLabel:
          "\(trip.name), \(CivilDate.display(trip.startsOn, format: "d MMMM")), \(when)")
    }
    return DeparturesFigures(rows: rows, addTrip: live.isEmpty)
  }

  /// "LISBON", or the first stop and a count of the rest: "LISBON +2".
  func destination(_ trip: TripSnapshot) -> String {
    let first = (trip.stops.first?.place ?? trip.name).uppercased()
    let others = Set(trip.stops.map(\.place)).count - 1
    return others > 0 ? "\(first.prefix(7)) +\(others)" : String(first.prefix(10))
  }
}

// MARK: Controls

extension PhoneWidgets {
  /// Today's place for the Log expense control, e.g. "Porto".
  public var logPlace: String? {
    guard let trip = timeline.now.first else { return timeline.upcoming.first?.destination }
    return place(trip, on: trip.currentDay(at: now)).name
  }

  /// "€ to £" for the Quick convert control.
  public var convertTitle: String? {
    let pair = QuickConvert(model: model).pair
    guard model.rate(from: pair.from, to: pair.to) != nil else { return nil }
    return "\(WatchCurrency(code: pair.from).symbol) to \(WatchCurrency(code: pair.to).symbol)"
  }
}
