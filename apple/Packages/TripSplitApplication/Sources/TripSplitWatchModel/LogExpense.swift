import Foundation
import Observation
import TripSplitDomain

/// The watch's log flow: which trip (F1), which day for a trip still to come (F6), how much (F2),
/// what it was (F3), whether travel booked before you go is a return, split half before you go
/// and half on the way home, and, with others on the trip, who shares it (F4). Saves through the phone like any other watch change,
/// with an estimate from cached rates so the spend shows in the home currency straight away, even
/// offline. The phone swaps the estimate for a quoted rate when it applies the change.
@MainActor @Observable public final class LogExpense {
  public enum Step: Hashable, Sendable {
    case trip, day, amount, category, returnToo, split
  }

  @ObservationIgnored public let model: WatchModel
  /// The spend being changed, or nil when logging a new one. A return ticket is changed whole,
  /// from its half before you go.
  public let editing: Expense?
  /// The half on the way home of the return ticket being changed, so both halves change together.
  private let partner: Expense?
  public private(set) var tripID: String?
  public private(set) var attachment: Attachment?
  public private(set) var currency = ""
  /// The amount in major units of `currency`, e.g. 42.5.
  public var amount: Decimal = 0
  public var category: ExpenseCategory = .food
  /// Whether a ticket booked before you go covers getting home too, as most flights do. Only
  /// asked of travel there and back (`asksReturn`). A return is named "Return flight" and split
  /// across the trip like the phone does, half before you go and half on the way home.
  public var coversReturn = true
  /// Shared between travellers, or just for you.
  public var isShared = true
  public var paidBy = ""
  public var splitWith: Set<String> = []

  /// Starts from Trips with no trip chosen, inside a trip, or on a spend to change. From Trips
  /// with only one trip to log for, it starts on that trip, as there's nothing to choose.
  public init(model: WatchModel, trip: TripSnapshot? = nil, editing expense: Expense? = nil) {
    self.model = model
    editing = expense.map { trip?.wholeTicket($0) ?? $0 }
    partner = expense.flatMap { trip?.returnHalves(of: $0)?.back }
    let only = expense == nil && trips.count == 1 ? trips.first : nil
    if let trip = trip ?? only { choose(trip) }
    guard let expense = editing else { return }
    attachment = expense.attachment
    currency = expense.currency
    amount =
      Decimal(Money.minor(expense.amountMinor) ?? 0) / Decimal(Money.factor(expense.currency))
    category = expense.category
    coversReturn = partner != nil || expense.title == expense.category.returnTitle
    paidBy = expense.paidBy
    splitWith = Set(expense.splitWith)
    isShared = !(expense.splitWith == [expense.paidBy] && expense.paidBy == you)
  }

  /// Where the flow opens: the trip list from Trips, the day list for a trip still to come, else
  /// the amount.
  public var start: Step {
    if editing != nil { return .amount }
    if tripID == nil { return .trip }
    return attachment == nil ? .day : .amount
  }

  /// The step after `step`, or nil once there's nothing left to ask and the spend saves.
  public func step(after step: Step) -> Step? {
    switch step {
    case .trip: attachment == nil ? .day : .amount
    case .day: .amount
    case .amount: .category
    case .category: asksReturn ? .returnToo : asksSplit ? .split : nil
    case .returnToo: asksSplit ? .split : nil
    case .split: nil
    }
  }

  /// Who shares it is only asked when someone else is on the trip. On your own it's just yours.
  public var asksSplit: Bool { trip?.hasCompanions == true }

  /// Travel booked before you go that might be a return ticket: a flight, train or coach, not a
  /// taxi, deposit or gear.
  public var asksReturn: Bool {
    guard let trip, let attachment else { return false }
    return trip.asksReturn(category, on: attachment)
  }

  private var isReturnTicket: Bool { asksReturn && coversReturn }

  public var trip: TripSnapshot? { tripID.flatMap(model.trip) }
  public var home: String { trip?.homeCurrency ?? "GBP" }
  private var you: String { trip?.currentTravellerId ?? "" }

  // MARK: Trip and day

  /// Trips a spend can be logged against: the one happening now, then those still to come.
  public var trips: [TripSnapshot] { model.timeline.now + model.timeline.upcoming }

  /// The trip highlighted first: the one happening now.
  public var suggestedTripID: String? { trips.first?.id }

  /// Chooses the trip. The trip happening now logs against today; others ask which day.
  public func choose(_ trip: TripSnapshot) {
    tripID = trip.id
    paidBy = trip.currentTravellerId
    splitWith = Set(trip.activeTravellers.map(\.id))
    attachment = nil
    if trip.phase(at: model.now) == .now { choose(trip.currentAttachment(at: model.now)) }
  }

  /// Chooses the day, or the trip's outbound leg for costs before you go. Those default to the
  /// home currency, as on the phone.
  public func choose(_ attachment: Attachment) {
    self.attachment = attachment
    guard let trip else { return }
    if attachment.kind == .leg {
      currency = trip.homeCurrency
      category = .flight
    } else {
      currency = trip.stop(for: attachment)?.currency ?? trip.homeCurrency
      category = .food
    }
    amount = 0
  }

  /// "Now · Day 4" for the trip happening now, else "From 19 Dec".
  public func detail(for trip: TripSnapshot) -> String {
    if trip.phase(at: model.now) == .now, let day = trip.currentDay(at: model.now) {
      return "Now · Day \(trip.dayNumber(of: day))"
    }
    return "From " + CivilDate.display(trip.startsOn, format: "d MMM")
  }

  /// Today's stop flag for the trip happening now, else the first stop's.
  public func flag(for trip: TripSnapshot) -> String {
    let stop =
      trip.currentDay(at: model.now).flatMap { trip.stop(for: .init(kind: .day, id: $0.id)) }
      ?? trip.stops.first
    return stop?.countryCode.flag ?? ""
  }

  public struct DayOption: Identifiable, Hashable, Sendable {
    public let attachment: Attachment
    /// "Before you go", "Day 1 · Sat 19 Dec" or "Return from trip".
    public let title: String
    /// "Flights, deposits, gear", the stop, e.g. "Zermatt", or "Flights, taxi home".
    public let detail: String
    public var id: String { attachment.kind.rawValue + ":" + attachment.id }
    /// Getting there or home rather than a day of the trip.
    public var isTravel: Bool { attachment.kind == .leg }
  }

  /// Costs before you go, against the outbound leg, then each day of the trip, then getting home,
  /// against the return leg.
  public var dayOptions: [DayOption] {
    guard let trip else { return [] }
    let before = trip.legs.first { $0.kind == .outbound }.map {
      DayOption(
        attachment: .init(kind: .leg, id: $0.id), title: "Before you go",
        detail: "Flights, deposits, gear")
    }
    let after = trip.legs.first { $0.kind == .return }.map {
      DayOption(
        attachment: .init(kind: .leg, id: $0.id), title: "Return from trip",
        detail: "Flights, taxi home")
    }
    let days = trip.days.map { day in
      let attachment = Attachment(kind: .day, id: day.id)
      return DayOption(
        attachment: attachment,
        title: "Day \(trip.dayNumber(of: day)) · "
          + CivilDate.display(day.date, format: "EEE d MMM"),
        detail: trip.stop(for: attachment)?.place ?? trip.destination)
    }
    return [before].compactMap { $0 } + days + [after].compactMap { $0 }
  }

  // MARK: Amount

  /// The stop's currency and home, e.g. EUR and GBP. One currency hides the toggle.
  public var currencies: [String] {
    guard let trip else { return [] }
    var codes: [String] = []
    if let editing { codes.append(editing.currency) }
    if let attachment, let local = trip.stop(for: attachment)?.currency { codes.append(local) }
    codes.append(trip.homeCurrency)
    return codes.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
  }

  /// Switches currency, trimming the amount to what the new one can hold, e.g. ¥12 not ¥12.50.
  public func select(currency code: String) {
    guard code != currency else { return }
    currency = code
    var value = amount
    var rounded = Decimal()
    NSDecimalRound(&rounded, &value, Money.precision(code), .plain)
    amount = rounded
  }

  /// A currency's flag and symbol, using the trip's country for shared ones, e.g. 🇵🇹 for euros.
  public func info(_ code: String) -> WatchCurrency {
    let stop = attachment.flatMap { trip?.stop(for: $0) }
    let stops = [stop].compactMap { $0 } + (trip?.stops ?? [])
    return WatchCurrency(code: code, countryCode: stops.first { $0.currency == code }?.countryCode)
  }

  /// Crown stops: nothing, then the same ladder as quick convert.
  public static let detentCount = AmountLadder.count + 1

  /// How many units one Crown detent counts in, e.g. ×100 for yen.
  public var scale: Decimal { model.detentScale(from: currency, to: home) }

  public var amountDetent: Int {
    amount <= 0 ? 0 : AmountLadder.index(for: amount / scale) + 1
  }

  public func dial(to detent: Int) {
    amount = detent <= 0 ? 0 : Decimal(AmountLadder.value(at: detent - 1)) * scale
  }

  public var amountMinor: Int64 { QuickConvert.minor(amount, currency) }

  /// The amount in the home currency, or nil without a rate.
  public var homeMinor: Int64? {
    currency == home ? amountMinor : model.convert(amountMinor, from: currency, to: home)
  }

  // MARK: Split

  /// Who shares the spend, in trip order. Just me is you alone.
  public var sharers: [String] {
    guard let trip else { return [] }
    guard isShared else { return [you] }
    return trip.activeTravellers.map(\.id).filter(splitWith.contains)
  }

  /// Who paid. Just me is always you.
  public var payer: String { isShared ? paidBy : you }

  public func toggle(_ traveller: String) {
    if splitWith.contains(traveller) {
      splitWith.remove(traveller)
    } else {
      splitWith.insert(traveller)
    }
  }

  /// Each person's share in the home currency, or in the spend's own without a rate.
  public var each: (minor: Int64, currency: String)? {
    let count = Int64(sharers.count)
    guard count > 0, amountMinor > 0 else { return nil }
    if let home = homeMinor { return (home / count, self.home) }
    return (amountMinor / count, currency)
  }

  public func name(_ id: String) -> String {
    id == you ? "You" : trip?.travellers.first { $0.id == id }?.name ?? "Someone"
  }

  public var canSave: Bool {
    trip != nil && attachment != nil && amountMinor > 0 && !sharers.isEmpty && !payer.isEmpty
  }

  // MARK: Save

  /// Queues the spend for the phone and returns what the receipt prints. A return ticket queues
  /// both halves, and one changed to one way drops its half on the way home.
  @discardableResult public func save() -> Receipt? {
    guard canSave, let trip, let attachment else { return nil }
    let minor = amountMinor
    let status = editing?.status ?? (trip.phase(at: model.now) == .upcoming ? .planned : .paid)
    let estimate = conversion(minor, in: trip)
    let expense = Expense(
      id: editing?.id ?? UUID().uuidString, revision: editing?.revision ?? 0,
      attachment: attachment, title: title, category: category, amountMinor: String(minor),
      currency: currency, status: status,
      paidOn: status == .paid ? trip.date(for: attachment) : nil, paidBy: payer,
      splitWith: sharers.sorted(), conversion: estimate.conversion,
      returnPairId: isReturnTicket ? editing?.returnPairId : nil)
    if isReturnTicket, let halves = trip.splitReturn(expense, back: partner) {
      for half in halves { model.send(.saveExpense(tripID: trip.id, expense: half)) }
    } else {
      model.send(.saveExpense(tripID: trip.id, expense: expense))
      if let partner { model.send(.deleteExpense(tripID: trip.id, expenseID: partner.id)) }
    }
    return receipt(expense, in: trip, rateDate: estimate.date)
  }

  /// A name typed on the phone stays; otherwise the title follows the category, e.g. "Flight", or
  /// "Return flight" for a ticket that covers getting home too.
  private var title: String {
    if let editing, editing.title != editing.category.title,
      editing.title != editing.category.returnTitle
    {
      return editing.title
    }
    return isReturnTicket ? category.returnTitle ?? category.title : category.title
  }

  /// Keeps the phone's conversion while the amount is unchanged, else estimates from cached
  /// rates. The estimate carries no quote, so the phone quotes it again before syncing.
  private func conversion(_ minor: Int64, in trip: TripSnapshot) -> (
    conversion: Conversion?, date: String?
  ) {
    guard currency != trip.homeCurrency else { return (nil, nil) }
    if let editing, editing.currency == currency, Money.minor(editing.amountMinor) == minor,
      let conversion = editing.conversion
    {
      return (conversion, conversion.rateDate)
    }
    guard let reference = model.reference(from: currency, to: trip.homeCurrency),
      let home = try? Money.convert(
        minor, from: currency, to: trip.homeCurrency, rate: reference.rate)
    else { return (nil, nil) }
    return (
      Conversion(
        homeAmountMinor: String(home), rate: reference.rate, rateDate: reference.date,
        source: "Estimated on Apple Watch", kind: "reference"),
      reference.date
    )
  }

  /// What the receipt prints once a spend is saved (F5).
  public struct Receipt: Hashable, Sendable {
    /// "Porto · Sat 31 Oct".
    public let heading: String
    public let category: String
    /// "€42.00".
    public let amount: String
    /// "£36.21", or nil when the spend is in the home currency or has no rate yet.
    public let home: String?
    public let people: [String]
    /// "£12.07", or nil for a spend that's just yours.
    public let each: String?
    /// The day the rates came from, for the offline note.
    public let rateDate: String?
  }

  private func receipt(_ expense: Expense, in trip: TripSnapshot, rateDate: String?) -> Receipt {
    let place: String
    if expense.attachment.kind == .leg {
      place =
        switch trip.legs.first(where: { $0.id == expense.attachment.id })?.kind {
        case .outbound: "Before you go"
        case .return: "Return from trip"
        default: trip.title(for: expense.attachment)
        }
    } else {
      place = trip.stop(for: expense.attachment)?.place ?? trip.destination
    }
    let date = CivilDate.display(trip.date(for: expense.attachment), format: "EEE d MMM")
    let minor = Money.minor(expense.amountMinor) ?? 0
    let home = expense.homeMinor(in: trip.homeCurrency)
    let shares = Int64(expense.splitWith.count)
    let each = home.map { ($0 / shares, trip.homeCurrency) } ?? (minor / shares, expense.currency)
    return Receipt(
      heading: "\(place) · \(date)",
      category: expense.title == expense.category.returnTitle
        ? expense.title : expense.category.watchTitle,
      amount: WatchCurrency.format(minor, expense.currency),
      home: expense.currency == trip.homeCurrency
        ? nil : home.map { WatchCurrency.format($0, trip.homeCurrency) },
      people: trip.hasCompanions ? sharers.map(name) : [],
      each: trip.hasCompanions && shares > 1 ? WatchCurrency.format(each.0, each.1) : nil,
      rateDate: rateDate)
  }

  /// "Rates from today." for the offline note, or nil for a spend in the home currency.
  public static func rateNote(_ date: String?, now: Date) -> String? {
    guard let date else { return nil }
    if date == CivilDate.string(now) { return "Rates from today." }
    return "Rates from " + CivilDate.display(date, format: "EEE d MMM") + "."
  }
}

extension ExpenseCategory {
  /// The watch's grid order: everyday spends first, the Crown scrolls on to travel and other.
  public static let watchOrder: [ExpenseCategory] = [
    .food, .coffee, .transport, .activity, .shopping, .stay, .taxi, .flight, .train, .other,
  ]

  /// A one-word label for the watch's category grid and receipt.
  public var watchTitle: String {
    switch self {
    case .transport: "Transport"
    case .activity: "Activity"
    case .other: "Other"
    default: title
    }
  }
}
