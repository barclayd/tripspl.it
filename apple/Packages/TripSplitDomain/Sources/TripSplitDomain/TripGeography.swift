import Foundation

public struct GeoPoint: Hashable, Sendable {
  public init(latitude: Double, longitude: Double) {
    self.latitude = latitude
    self.longitude = longitude
  }
  public var latitude: Double
  public var longitude: Double
  /// Great-circle distance in metres.
  public func distance(to other: GeoPoint) -> Double {
    let (lat1, lat2) = (latitude.radians, other.latitude.radians)
    let dLat = lat2 - lat1
    let dLon = (other.longitude - longitude).radians
    let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
    return 2 * 6_371_000 * atan2(a.squareRoot(), (1 - a).squareRoot())
  }
}

extension Stop {
  public var point: GeoPoint { .init(latitude: latitude, longitude: longitude) }
}

extension TripOrigin {
  public var point: GeoPoint { .init(latitude: latitude, longitude: longitude) }
}

extension Destination {
  public var point: GeoPoint { .init(latitude: latitude, longitude: longitude) }
}

extension TripSnapshot {
  /// Each country's flag once, in route order.
  public var uniqueFlags: [String] {
    var seen = Set<String>()
    return stops.map(\.flag).filter { seen.insert($0).inserted }
  }
  /// The spherical mean of the stops, so routes across the antimeridian centre correctly.
  public var centre: GeoPoint? {
    guard !stops.isEmpty else { return nil }
    var (x, y, z) = (0.0, 0.0, 0.0)
    for stop in stops {
      let (lat, lon) = (stop.latitude.radians, stop.longitude.radians)
      x += cos(lat) * cos(lon)
      y += cos(lat) * sin(lon)
      z += sin(lat)
    }
    return .init(
      latitude: atan2(z, (x * x + y * y).squareRoot()).degrees, longitude: atan2(y, x).degrees)
  }
  /// How far in metres the furthest stop sits from the centre.
  public var reach: Double {
    guard let centre else { return 0 }
    return stops.map { centre.distance(to: $0.point) }.max() ?? 0
  }
  /// Today's position in the itinerary while the trip is under way, such as day 4 of 8.
  public func dayProgress(at instant: Date = Date()) -> (day: Int, of: Int)? {
    guard let day = currentDay(at: instant), let index = days.firstIndex(of: day) else {
      return nil
    }
    return (index + 1, days.count)
  }
}

extension Double {
  fileprivate var radians: Double { self * .pi / 180 }
  fileprivate var degrees: Double { self * 180 / .pi }
}
