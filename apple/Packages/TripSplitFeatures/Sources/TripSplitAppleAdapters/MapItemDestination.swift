import MapKit
import TripSplitDomain

extension Destination {
  /// A place Apple Maps found, with its country from the address and its own time zone.
  package init?(mapItem item: MKMapItem) {
    guard let code = item.addressRepresentations?.region?.identifier,
      let country = CountryMetadata.country(code),
      let name = item.name, !name.isEmpty
    else { return nil }
    let coordinate = item.location.coordinate
    guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
    let isCountry = country.searchNames.map(Destination.normalise).contains(
      Destination.normalise(name))
    self.init(
      countryCode: country.code, country: country.name, city: name,
      currency: country.defaultCurrency ?? "", latitude: coordinate.latitude,
      longitude: coordinate.longitude,
      catalogID: isCountry
        ? "country:" + country.code
        : "maps:\(country.code):\(name):\(coordinate.latitude):\(coordinate.longitude)",
      isCountry: isCountry,
      detail: item.addressRepresentations?.cityWithContext(.full) ?? country.name,
      timeZone: item.timeZone?.identifier)
  }
}
