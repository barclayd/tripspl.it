import Foundation

/// Catalogue points have exact source zones. Other coordinates receive a country
/// representative only; this lookup does not infer geographic time-zone boundaries.
enum DestinationTimeZones {
  static func identifier(countryCode: String, latitude: Double, longitude: Double) -> String? {
    let code = countryCode.uppercased()
    if let exact = byCoordinate[
      Coordinate(countryCode: code, latitude: latitude, longitude: longitude)]
    {
      return supported(exact)
    }
    return byCountry[code]?.defaultIdentifier.flatMap(supported)
  }

  /// Scoped IANA choices supported by this device's time-zone database.
  static func identifiers(countryCode: String) -> [String] {
    (byCountry[countryCode.uppercased()]?.identifiers ?? []).compactMap(supported)
  }

  private static func supported(_ identifier: String) -> String? {
    TimeZone(identifier: identifier) == nil ? nil : identifier
  }

  private struct Coordinate: Hashable, Sendable {
    let countryCode: String
    let latitude: Double
    let longitude: Double
  }
  private struct Country: Decodable, Sendable {
    let countryCode: String
    let identifiers: [String]
    let defaultIdentifier: String?
  }
  private struct Place: Decodable, Sendable {
    let countryCode: String
    let latitude: Double
    let longitude: Double
    let identifier: String
  }
  private struct Catalogue: Decodable, Sendable {
    let countries: [Country]
    let destinations: [Place]
  }
  private static let catalogue = DestinationData.decode(
    Catalogue.self, file: "DestinationTimeZones")
  private static let byCountry = Dictionary(
    uniqueKeysWithValues: catalogue.countries.map { ($0.countryCode, $0) })
  private static let byCoordinate = Dictionary(
    uniqueKeysWithValues: catalogue.destinations.map {
      (
        Coordinate(countryCode: $0.countryCode, latitude: $0.latitude, longitude: $0.longitude),
        $0.identifier
      )
    })
}
