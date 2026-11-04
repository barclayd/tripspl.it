import Foundation
import TripSplitDomain

/// One-off moments the watch shows in place of the trips list: the first trip arriving (A2) and
/// a finished trip being stamped into the passport (H5). Each shows once.
public enum WatchMoment: Hashable, Sendable {
  case arrived(tripID: String)
  case stamped(tripID: String)

  public var tripID: String {
    switch self {
    case .arrived(let id), .stamped(let id): id
    }
  }

  public var isStamp: Bool {
    if case .stamped = self { true } else { false }
  }
}

/// Which moments the watch has shown, kept in the App Group.
public struct MomentsMemory: Codable, Hashable, Sendable {
  public init(welcomed: Bool = false, arrival: String? = nil, stamped: Set<String> = []) {
    self.welcomed = welcomed
    self.arrival = arrival
    self.stamped = stamped
  }
  /// Whether the first sync with trips has happened, so the welcome never repeats.
  public var welcomed: Bool
  /// The trip that came with the first sync, until it's been welcomed.
  public var arrival: String?
  /// Trips already stamped, or that were over before the watch knew about them.
  public var stamped: Set<String>
}

extension WatchModel {
  /// How long after its last day a trip can still be stamped, so a watch that's been off for
  /// a while doesn't open on old news.
  static let stampWindow = 1...3

  /// The moment to show now, if any: a welcome for the first trip, else the most recent trip
  /// that ended in the last few days and hasn't been stamped.
  public var moment: WatchMoment? {
    if let id = moments.arrival, trip(id) != nil { return .arrived(tripID: id) }
    let today = CivilDate.string(now, timeZone: TimeZone.current.identifier)
    let done = timeline.past
      .filter { !moments.stamped.contains($0.id) }
      .filter { Self.stampWindow.contains(CivilDate.days(from: $0.endsOn, to: today)) }
      .max { $0.endsOn < $1.endsOn }
    return done.map { .stamped(tripID: $0.id) }
  }

  /// Records that a moment has been seen.
  public func dismiss(_ moment: WatchMoment) {
    switch moment {
    case .arrived: moments.arrival = nil
    case .stamped(let id): moments.stamped.insert(id)
    }
  }

  /// Notes the first sync that brings trips: the current trip gets a welcome, and trips that
  /// were already over are never stamped.
  func welcomeIfFirst(hadTrips: Bool) {
    guard !hadTrips, !moments.welcomed, !trips.isEmpty else { return }
    moments.welcomed = true
    moments.arrival = currentTrip?.id
    moments.stamped.formUnion(timeline.past.map(\.id))
  }
}

/// H5 · Trip's done. What the trip came to and who still owes, for the passport stamp.
public struct TripWrapUp: Sendable {
  public let tripID: String
  /// Each country once, in itinerary order.
  public let flags: [String]
  /// "LISBON·PORTO·SEVILLE".
  public let places: String
  /// "28 OCT – 4 NOV 2026".
  public let dates: String
  /// "Stamped. £2,984 all in."
  public let headline: String
  /// "Tom still owes £158 in total."
  public let detail: String
  /// Whoever owes you the most, for a nudge.
  public let debtor: Traveller?

  public init(pages: TripPages) {
    let trip = pages.trip
    tripID = trip.id
    flags = trip.uniqueFlags
    places = trip.stops.map(\.place).reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } }
      .joined(separator: "·").uppercased()
    dates = trip.dateRange(withYear: true).uppercased()
    headline = "Stamped. \(WatchCurrency.whole(pages.spent, pages.currency)) all in."
    let owed = (trip.hasCompanions ? pages.settlements : []).filter { $0.to == pages.you }.max { $0.amount < $1.amount }
    debtor = owed.flatMap { pages.traveller($0.from) }
    detail = Self.detail(pages)
  }

  /// Leads with what you owe, else whoever owes the most in total.
  private static func detail(_ pages: TripPages) -> String {
    guard pages.balancesComplete else { return "Some spends still need converting." }
    guard pages.trip.hasCompanions else { return "Saved in your passport." }
    let balances = pages.ledger.balances
    if let yours = balances[pages.you], yours < 0 {
      return "You still owe \(WatchCurrency.whole(-yours, pages.currency)) in total."
    }
    guard let debtor = balances.filter({ $0.value < 0 }).min(by: { $0.value < $1.value }) else {
      return "Everyone's square."
    }
    return
      "\(pages.name(debtor.key)) still owes \(WatchCurrency.whole(-debtor.value, pages.currency)) in total."
  }
}

extension TripSnapshot {
  /// "28 Oct – 4 Nov", "4 – 9 Nov" within a month, with the year when asked or when it changes.
  public func dateRange(withYear: Bool = false) -> String {
    let start = CivilDate.date(startsOn), end = CivilDate.date(endsOn)
    let calendar = CivilDate.calendar()
    let crossesYear = calendar.component(.year, from: start) != calendar.component(.year, from: end)
    let sameMonth = !crossesYear && calendar.component(.month, from: start) == calendar.component(.month, from: end)
    let year = withYear || crossesYear ? " yyyy" : ""
    let from = CivilDate.display(startsOn, format: sameMonth ? "d" : "d MMM" + (crossesYear ? year : ""))
    let to = CivilDate.display(endsOn, format: "d MMM" + year)
    return startsOn == endsOn ? to : "\(from) – \(to)"
  }
}
