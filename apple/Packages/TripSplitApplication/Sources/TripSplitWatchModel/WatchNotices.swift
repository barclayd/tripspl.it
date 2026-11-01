import Foundation
import TripSplitDomain

/// A local notification the watch schedules from the trips it holds: H1 Landed on the first day
/// in a new country, and the optional H2 Evening wrap at 21:30 each trip day. Nudges arrive as
/// pushes on the phone instead, and the watch only shows them.
public struct WatchNotice: Hashable, Sendable {
  public enum Kind: String, CaseIterable, Sendable {
    case landed
    case eveningWrap = "evening-wrap"
    /// Someone on the trip asked you to pay them back, pushed by the API to your phone.
    case nudge

    /// The notification category, which picks the actions and the long look.
    public var category: String { "tripsplit." + rawValue }

    public init?(category: String) {
      guard let kind = Self.allCases.first(where: { $0.category == category }) else { return nil }
      self = kind
    }
  }

  /// Buttons on a notice. The system adds Dismiss on its own.
  public enum Action: String, CaseIterable, Sendable {
    case convert, log, day

    public var title: String {
      switch self {
      case .convert: "Quick convert"
      case .log: "Add something"
      case .day: "See day"
      }
    }

    public static func actions(for kind: Kind) -> [Action] {
      switch kind {
      case .landed: [.convert]
      case .eveningWrap: [.log, .day]
      case .nudge: []
      }
    }
  }

  /// Stable per trip day, so rescheduling replaces a notice rather than adding another.
  public let id: String
  public let kind: Kind
  public let title: String
  public let body: String
  /// The start of the body the long look sets in bold, e.g. the evening wrap's "£58.97".
  public let lead: String?
  public let fireDate: Date
  public let tripID: String
  public let dayID: String

  /// The keys a scheduled notification carries, so a tap can route without the model.
  public var userInfo: [String: String] {
    var info = ["trip": tripID, "day": dayID]
    info["lead"] = lead
    return info
  }

  /// Where a button opens the app. Tapping the notice itself opens quick convert after a
  /// landing, the day after an evening wrap, and who owes who after a nudge.
  public static func link(
    kind: Kind, action: String, userInfo: [AnyHashable: Any]
  ) -> WatchLink? {
    guard let trip = userInfo["trip"] as? String else { return nil }
    if kind == .nudge { return .trip(trip, page: .balances) }
    let day = userInfo["day"] as? String
    switch Action(rawValue: action) ?? (kind == .landed ? .convert : .day) {
    case .convert: return .localConvert(trip: trip)
    case .log: return .log(trip: trip)
    case .day: return day.map { .day(trip: trip, day: $0) } ?? .trip(trip, page: .today)
    }
  }
}

extension WatchModel {
  /// How far ahead notices are scheduled. watchOS keeps 64 pending per app, so a long trip's
  /// later days are added as the watch reschedules along the way.
  static let noticeLimit = 40
  /// When the evening wrap goes out, in the day's local time.
  static let wrapTime = (hour: 21, minute: 30)
  /// When a landing is assumed, in the stop's local time: watchOS has no location triggers.
  static let landingTime = (hour: 12, minute: 0)

  /// Every notice still to come for trips happening now or soon, soonest first.
  public var notices: [WatchNotice] {
    let trips = timeline.now + timeline.upcoming
    let all = trips.flatMap { trip in
      landings(trip) + (preferences.eveningWrap ? wraps(trip) : [])
    }
    return Array(all.filter { $0.fireDate > now }.sorted { $0.fireDate < $1.fireDate }
      .prefix(Self.noticeLimit))
  }

  /// H1 · the first day of each stop in a country the trip wasn't already in, while abroad.
  private func landings(_ trip: TripSnapshot) -> [WatchNotice] {
    var previous: Stop?
    return trip.days.compactMap { day in
      guard let stop = trip.stop(for: .init(kind: .day, id: day.id)) else { return nil }
      defer { previous = stop }
      guard stop.countryCode != previous?.countryCode, stop.currency != trip.homeCurrency,
        let date = fireDate(trip, day, Self.landingTime)
      else { return nil }
      let landed = Landed(model: self, trip: trip, stop: stop, previous: previous)
      return WatchNotice(
        id: "landed.\(trip.id).\(day.id)", kind: .landed, title: landed.title, body: landed.body,
        lead: nil, fireDate: date, tripID: trip.id, dayID: day.id)
    }
  }

  /// H2 · 21:30 on every day of the trip.
  private func wraps(_ trip: TripSnapshot) -> [WatchNotice] {
    trip.days.compactMap { day in
      guard let date = fireDate(trip, day, Self.wrapTime),
        let wrap = EveningWrap(pages: pages(for: trip), dayID: day.id)
      else { return nil }
      return WatchNotice(
        id: "wrap.\(trip.id).\(day.id)", kind: .eveningWrap, title: wrap.title, body: wrap.body,
        lead: wrap.spent, fireDate: date, tripID: trip.id, dayID: day.id)
    }
  }

  /// A wall-clock time on a trip day, in that day's stop's time zone.
  private func fireDate(
    _ trip: TripSnapshot, _ day: TripDay, _ time: (hour: Int, minute: Int)
  ) -> Date? {
    let parts = day.date.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    let zone = trip.timeZone(for: .init(kind: .day, id: day.id))
    return CivilDate.calendar(zone).date(
      from: DateComponents(
        year: parts[0], month: parts[1], day: parts[2], hour: time.hour, minute: time.minute))
  }
}

/// H1 · Landed. "Welcome to Zermatt 🇨🇭" / "CHF 1 = £0.93. Convert is set to francs."
public struct Landed: Hashable, Sendable {
  public let place: String
  public let flag: String
  /// One detent of the local currency in home, e.g. "CHF 1 = £0.93". Nil without a rate.
  public let rate: String?
  /// What quick convert is set to, e.g. "Convert is set to francs."
  public let convert: String

  @MainActor public init(model: WatchModel, trip: TripSnapshot, stop: Stop, previous: Stop?) {
    place = stop.place
    flag = stop.flag
    rate = model.rateText(from: stop.currency, to: trip.homeCurrency)
    let name = Self.plural(stop.currency)
    convert =
      previous?.currency == stop.currency
      ? "Convert stays on \(name)." : "Convert is set to \(name)."
  }

  public var title: String { "Welcome to \(place) \(flag)" }
  public var body: String { [rate.map { $0 + "." }, convert].compactMap(\.self).joined(separator: " ") }

  /// The everyday plural for a currency, e.g. "francs", "euros" or "yen": its full name for
  /// two, with the number and country taken off.
  static func plural(_ code: String) -> String {
    let text = (2.0).formatted(
      .currency(code: code).presentation(.fullName).locale(Locale(identifier: "en_GB")))
    guard let word = text.split(separator: " ").last, word.first?.isLetter == true else {
      return code
    }
    return word.lowercased()
  }
}

/// H2 · Evening wrap. "Day 4 in Porto 🇵🇹" / "£58.97 spent. £241 under today's budget."
public struct EveningWrap: Hashable, Sendable {
  public let title: String
  /// What the day came to, e.g. "£58.97", shown in bold. Nil before anything's logged.
  public let spent: String?
  /// The rest of the line, e.g. "spent. £241 under today's budget."
  public let detail: String

  public init?(pages: TripPages, dayID: String) {
    let trip = pages.trip
    guard let day = trip.days.first(where: { $0.id == dayID }),
      let stop = pages.stop(day)
    else { return nil }
    title = "Day \(trip.dayNumber(of: day)) in \(stop.place) \(stop.flag)"
    let spending = trip.spending(on: day)
    let currency = trip.homeCurrency
    guard spending.amount > 0 else {
      spent = nil
      detail = "Nothing logged today. Anything to add while it's fresh?"
      return
    }
    spent = WatchCurrency.format(spending.amount, currency)
    if spending.budget <= 0 {
      detail = "spent today."
    } else if spending.left >= 0 {
      detail = "spent. \(WatchCurrency.whole(spending.left, currency)) under today's budget."
    } else {
      detail = "spent. \(WatchCurrency.whole(-spending.left, currency)) over today's budget."
    }
  }

  public var body: String { [spent, detail].compactMap(\.self).joined(separator: " ") }
}
