import Foundation

/// The rules a trip's dates follow, shared by planning a trip and moving one: how nights are
/// shared between stops, and how days and legs fall from them.
public enum Itinerary {
  /// The longest trip the itinerary and the API accept, in nights.
  public static let maximumNights = 365

  /// A lone stop can be a day trip; every stop on a longer route needs at least a night.
  public static func nightRange(stops: Int) -> ClosedRange<Int> {
    (stops > 1 ? 1 : 0)...maximumNights
  }

  /// The shortest and longest trip a route allows: a night per stop on a longer route.
  public static func tripNights(stops: Int) -> ClosedRange<Int> {
    (stops > 1 ? stops : 0)...maximumNights
  }

  /// Shares `total` nights between stops in the proportions of their `current` nights, or evenly
  /// when they have none, giving each at least `floor`.
  public static func split(_ total: Int, across current: [Int], floor: Int) -> [Int] {
    guard !current.isEmpty else { return [] }
    let sum = current.reduce(0, +)
    let shares = current.map { nights in
      sum > 0 ? Double(total) * Double(nights) / Double(sum) : Double(total) / Double(current.count)
    }
    var split = shares.map { max(floor, Int($0.rounded(.down))) }
    // Hands any nights left over to the stops that lost the most to rounding, earliest first.
    let byRemainder = shares.indices.sorted {
      (shares[$0] - shares[$0].rounded(.down), -$0) > (shares[$1] - shares[$1].rounded(.down), -$1)
    }
    var spare = total - split.reduce(0, +)
    for index in byRemainder where spare > 0 {
      split[index] += 1
      spare -= 1
    }
    // A minimum of a night each can overshoot; takes the excess back from the longest stays.
    while spare < 0,
      let index = split.indices.filter({ split[$0] > floor }).max(by: { split[$0] < split[$1] })
    {
      split[index] -= 1
      spare += 1
    }
    return split
  }
}

/// A route's days: each stop's nights in turn from the first day, then the day home.
struct ItineraryLayout {
  /// Names the `night`th day at the `stop`th stop.
  init(
    startsOn: String, stops: [Stop],
    dayID: (_ stop: Int, _ night: Int) -> String = { _, _ in UUID().uuidString },
    homeID: String = UUID().uuidString
  ) {
    var offset = 0
    var stays: [[TripDay]] = []
    var arrivals: [String] = []
    for (index, stop) in stops.enumerated() {
      arrivals.append(CivilDate.adding(offset, to: startsOn))
      stays.append(
        (0..<stop.nights).map { night in
          TripDay(
            id: dayID(index, night), date: CivilDate.adding(offset + night, to: startsOn),
            stopId: stop.id)
        })
      offset += stop.nights
    }
    self.stops = stops
    self.stays = stays
    self.arrivals = arrivals
    home = TripDay(
      id: homeID, date: CivilDate.adding(offset, to: startsOn), stopId: stops.last?.id ?? "")
  }

  let stops: [Stop]
  /// Each stop's days, in order.
  let stays: [[TripDay]]
  /// The day each stop is reached.
  let arrivals: [String]
  /// The day home, which belongs to the last stop.
  let home: TripDay
  var days: [TripDay] { stays.flatMap { $0 } + [home] }

  /// The legs a new route starts with: out to the first stop, on to each next, then home.
  func legs() -> [TravelLeg] {
    let into = stops.indices.map { index in
      TravelLeg(
        kind: index == 0 ? .outbound : .transfer, date: home.date,
        fromStopId: index == 0 ? nil : stops[index - 1].id, toStopId: stops[index].id)
    }
    let back = TravelLeg(kind: .return, date: home.date, fromStopId: stops.last?.id)
    return (into + [back]).map { place($0) }
  }

  /// Dates a leg by the day it arrives at its stop, or the day home for the return. A leg into a
  /// stop that isn't on the route keeps its date, and `fallback` renames a day it points at.
  func place(_ leg: TravelLeg, fallback: (String) -> String = { $0 }) -> TravelLeg {
    var leg = leg
    if leg.kind == .return {
      leg.date = home.date
      leg.dayId = home.id
    } else if let index = stops.firstIndex(where: { $0.id == leg.toStopId }) {
      leg.date = arrivals[index]
      leg.dayId = stays[index].first?.id
    } else {
      leg.dayId = leg.dayId.map(fallback)
    }
    return leg
  }
}

/// New dates for a trip that keep where it goes. Sent as `trip.reschedule`.
public struct TripReschedule: Codable, Hashable, Sendable {
  public struct StopNights: Codable, Hashable, Sendable {
    public var id: String
    public var nights: Int
    public init(id: String, nights: Int) {
      self.id = id
      self.nights = nights
    }
  }
  /// A day leaving the trip, and the kept day its expenses move to.
  public struct DayMove: Codable, Hashable, Sendable {
    public var fromDayId: String
    public var toDayId: String
    public init(fromDayId: String, toDayId: String) {
      self.fromDayId = fromDayId
      self.toDayId = toDayId
    }
  }
  public var startsOn: String
  public var stops: [StopNights]
  public var days: [TripDay]
  public var legs: [TravelLeg]
  public var moves: [DayMove]
  public init(
    startsOn: String, stops: [StopNights], days: [TripDay], legs: [TravelLeg], moves: [DayMove]
  ) {
    self.startsOn = startsOn
    self.stops = stops
    self.days = days
    self.legs = legs
    self.moves = moves
  }
}

extension TripSnapshot {
  /// The trip moved to leave on `leaving` and get home on `home`, sharing its nights between
  /// stops in their current proportions, as planning a trip does.
  ///
  /// A stop keeps its days in order and adds or drops them at the end, so each day's expenses
  /// stay put while the day moves. Expenses on a dropped day go to the stop's last kept day, or
  /// the day home when none is left. Legs keep their IDs and arrive on their stop's first day.
  public func rescheduled(leaving: String, home: String) -> TripReschedule {
    let range = Itinerary.tripNights(stops: stops.count)
    let total = min(max(CivilDate.days(from: leaving, to: home), range.lowerBound), range.upperBound)
    let nights = Itinerary.split(
      total, across: stops.map(\.nights),
      floor: Itinerary.nightRange(stops: stops.count).lowerBound)
    var moved = stops
    for index in moved.indices { moved[index].nights = nights[index] }
    // The day home is always the last; each stop's own days come before it.
    let stays = stops.map { stop in days.dropLast().filter { $0.stopId == stop.id } }
    let layout = ItineraryLayout(
      startsOn: leaving, stops: moved,
      dayID: { stop, night in
        stays[stop].indices.contains(night) ? stays[stop][night].id : UUID().uuidString
      },
      homeID: days.last?.id ?? UUID().uuidString)
    let kept = Set(layout.days.map(\.id))
    var moves: [TripReschedule.DayMove] = []
    for day in days where !kept.contains(day.id) {
      let stop = stops.firstIndex { $0.id == day.stopId }
      let target = stop.flatMap { layout.stays[$0].last } ?? layout.home
      moves.append(.init(fromDayId: day.id, toDayId: target.id))
    }
    let destinations = Dictionary(
      moves.map { ($0.fromDayId, $0.toDayId) }, uniquingKeysWith: { first, _ in first })
    return TripReschedule(
      startsOn: leaving, stops: moved.map { .init(id: $0.id, nights: $0.nights) },
      days: layout.days,
      legs: legs.map { layout.place($0) { destinations[$0] ?? $0 } },
      moves: moves)
  }
}
