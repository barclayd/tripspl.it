import Foundation
import Testing

@testable import TripSplitDomain

struct DestinationTimeZonesTests {
  @Test func everyCatalogueDestinationHasAScopedFoundationTimeZone() throws {
    let places = Destination.all.filter { !$0.isCountry }
    #expect(places.count == 500)
    for place in places {
      let identifier = try #require(
        DestinationTimeZones.identifier(
          countryCode: place.countryCode, latitude: place.latitude, longitude: place.longitude))
      #expect(TimeZone(identifier: identifier) != nil)
      #expect(DestinationTimeZones.identifiers(countryCode: place.countryCode).contains(identifier))
    }
  }

  @Test func citiesInTheSameCountryKeepTheirOwnZones() throws {
    for (name, expected) in [
      ("New York", "America/New_York"), ("Los Angeles", "America/Los_Angeles"),
      ("Sydney", "Australia/Sydney"), ("Perth", "Australia/Perth"),
      ("Bali", "Asia/Makassar"), ("Jakarta", "Asia/Jakarta"),
      ("Hanoi", "Asia/Bangkok"), ("Ho Chi Minh City", "Asia/Ho_Chi_Minh"),
      ("Taipei", "Asia/Taipei"), ("Santorini", "Europe/Athens"),
      ("Queenstown", "Pacific/Auckland"), ("Zermatt", "Europe/Zurich"),
      ("Amalfi", "Europe/Rome"),
    ] {
      let place = try #require(Destination.all.first { $0.city == name && !$0.isCountry })
      #expect(
        DestinationTimeZones.identifier(
          countryCode: place.countryCode, latitude: place.latitude, longitude: place.longitude)
          == expected)
    }
  }

  @Test func unmatchedCoordinatesUseTheCapitalRatherThanTheNearestCity() throws {
    let losAngeles = try #require(Destination.all.first { $0.city == "Los Angeles" })
    #expect(
      DestinationTimeZones.identifier(
        countryCode: "US", latitude: losAngeles.latitude + 0.000001,
        longitude: losAngeles.longitude) == "America/New_York")
    #expect(
      DestinationTimeZones.identifier(countryCode: "au", latitude: 0, longitude: 0)
        == "Australia/Sydney")
    #expect(
      DestinationTimeZones.identifier(countryCode: "ID", latitude: 0, longitude: 0)
        == "Asia/Jakarta")
    #expect(
      DestinationTimeZones.identifier(countryCode: "JP", latitude: 0, longitude: 0)
        == "Asia/Tokyo")
  }

  @Test func countryChoicesIncludeDistinctZonesWithoutEquivalentAliasDuplicates() {
    let us = DestinationTimeZones.identifiers(countryCode: "US")
    #expect(us.contains("America/New_York"))
    #expect(us.contains("America/Los_Angeles"))
    #expect(us.contains("Pacific/Honolulu"))
    #expect(!us.contains("Europe/London"))
    #expect(
      DestinationTimeZones.identifiers(countryCode: "VN")
        == ["Asia/Bangkok", "Asia/Ho_Chi_Minh"])
    #expect(DestinationTimeZones.identifiers(countryCode: "XK") == ["Europe/Belgrade"])
    for country in CountryMetadata.all {
      let identifiers = DestinationTimeZones.identifiers(countryCode: country.code)
      #expect(Set(identifiers).count == identifiers.count)
      #expect(identifiers == identifiers.sorted())
    }
  }

  @Test func countriesWithoutAnUnambiguousRepresentativeRequireAChoice() {
    for country in ["AQ", "UM", "PS", "BV", "HM", "ZZ"] {
      #expect(
        DestinationTimeZones.identifier(countryCode: country, latitude: 0, longitude: 0) == nil)
    }
    #expect(DestinationTimeZones.identifiers(countryCode: "AQ").count > 1)
    #expect(DestinationTimeZones.identifiers(countryCode: "UM").count > 1)
    #expect(DestinationTimeZones.identifiers(countryCode: "PS") == ["Asia/Gaza", "Asia/Hebron"])
    #expect(DestinationTimeZones.identifiers(countryCode: "BV").isEmpty)
    #expect(DestinationTimeZones.identifiers(countryCode: "HM").isEmpty)
    #expect(DestinationTimeZones.identifiers(countryCode: "ZZ").isEmpty)
  }

  @Test func bundledZoneNamesAreSupportedWithoutSilentlyDroppingChoices() throws {
    struct Source: Decodable {
      struct Country: Decodable { let identifiers: [String] }
      let countries: [Country]
    }
    let source = DestinationData.decode(Source.self, file: "DestinationTimeZones")
    for identifier in Set(source.countries.flatMap(\.identifiers)) {
      #expect(TimeZone(identifier: identifier) != nil)
    }
    let london = try #require(TimeZone(identifier: "Europe/London"))
    let january = CivilDate.date("2026-01-15")
    let july = CivilDate.date("2026-07-15")
    #expect(london.secondsFromGMT(for: january) == 0)
    #expect(london.secondsFromGMT(for: july) == 3600)
  }
}
