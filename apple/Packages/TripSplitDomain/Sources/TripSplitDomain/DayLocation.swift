import Foundation

/// An explicit per-day edit. Null restores the itinerary location; older snapshots omit the field.
public struct DayLocationUpdate: Codable, Hashable, Sendable {
  public var location: TripOrigin?
  public init(location: TripOrigin?) { self.location = location }
  private enum CodingKeys: String, CodingKey { case location }
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    location = try values.decode(TripOrigin?.self, forKey: .location)
  }
  public func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(location, forKey: .location)
  }
}

extension TripSnapshot {
  public func location(for day: TripDay) -> TripOrigin? {
    if let location = day.location { return location }
    return stops.first { $0.id == day.stopId }.map {
      TripOrigin(place: $0.place, countryCode: $0.countryCode,
                 latitude: $0.latitude, longitude: $0.longitude)
    }
  }

  /// Settings from older clients and date changes cannot erase a day's independent location edit.
  public func preservingDayLocations(in proposed: [TripDay]) -> [TripDay] {
    let existing = Dictionary(days.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return proposed.map { day in
      var result = day
      result.location = existing[day.id]?.location
      result.locationRevision = existing[day.id]?.locationRevision
      return result
    }
  }
}
