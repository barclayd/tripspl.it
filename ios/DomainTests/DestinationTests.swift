import Foundation
import Testing

#if canImport(TripSplitDomain)
  @testable import TripSplitDomain
#else
  @testable import TripSplit
#endif

struct DestinationTests {
  @Test func missingMapsContextStillShowsTheCountry() throws {
    var destination = try #require(Destination.search("Taipei").first)
    destination.detail = " \n"
    #expect(destination.secondaryLabel == destination.country)
    destination.detail = "Taipei, Taiwan"
    #expect(destination.secondaryLabel == "Taipei, Taiwan")
  }

  @Test func countriesFollowTheirDisplayedNames() throws {
    let countries = CountryMetadata.all
    #expect(countries.count >= 249)
    #expect(Set(countries.map(\.code)).count == countries.count)
    for (previous, next) in zip(countries, countries.dropFirst()) {
      #expect(previous.name.localizedStandardCompare(next.name) != .orderedDescending)
    }
    let taiwan = try #require(countries.firstIndex { $0.code == "TW" })
    #expect(taiwan > 0 && taiwan < countries.count - 1)
    #expect(
      CountryMetadata.country("tw")?.name == Locale.current.localizedString(forRegionCode: "TW"))
    #expect(CountryMetadata.country("AN") == nil)
    #expect(CountryMetadata.country("CS") == nil)
  }

  @Test func currenciesAreCurrentAndScopedToTheCountry() throws {
    #expect(CountryMetadata.country("TW")?.currencies == ["TWD"])
    #expect(CountryMetadata.country("GB")?.currencies == ["GBP"])
    #expect(Set(try #require(CountryMetadata.country("PA")).currencies) == ["PAB", "USD"])
    #expect(Set(try #require(CountryMetadata.country("BT")).currencies) == ["BTN", "INR"])
    #expect(CountryMetadata.country("AQ")?.currencies.isEmpty == true)
    #expect(Destination.country("AQ")?.requiresCurrencySelection == true)
    #expect(CountryMetadata.country("HR")?.currencies == ["EUR"])
    #expect(CountryMetadata.country("BG")?.currencies == ["EUR"])
    #expect(CountryMetadata.country("CW")?.currencies == ["XCG"])
    #expect(CountryMetadata.country("SX")?.currencies == ["XCG"])
    for country in CountryMetadata.all {
      #expect(country.currencies.allSatisfy { CurrencyMetadata.codes.contains($0) })
      #expect(Set(country.currencies).count == country.currencies.count)
    }
  }

  @Test func citiesHaveReliableCountryCurrencyAndCoordinates() throws {
    let cities = Destination.all.filter { !$0.isCountry }
    #expect(cities.count == 500)
    #expect(Set(Destination.all.map(\.id)).count == Destination.all.count)
    for destination in Destination.all {
      let country = try #require(CountryMetadata.country(destination.countryCode))
      #expect(destination.flag == country.code.flag)
      #expect(destination.currency == country.defaultCurrency ?? "")
      #expect(destination.latitude.isFinite && (-90...90).contains(destination.latitude))
      #expect(destination.longitude.isFinite && (-180...180).contains(destination.longitude))
    }
    // Keep the existing demo itinerary valid when the bundled catalogue grows.
    #expect(Array(cities.prefix(4).map(\.city)) == ["Lisbon", "Porto", "Seville", "Barcelona"])
    #expect(cities[6].city == "Tokyo")
    #expect(cities[21].city == "Auckland")
  }

  @Test func searchesCitiesCountriesAndAliasesOffline() throws {
    let taipei = try #require(Destination.search("  TAIPEI  ").first)
    #expect(taipei.city == "Taipei")
    #expect(taipei.countryCode == "TW")
    #expect(taipei.flag == "🇹🇼")
    #expect(taipei.currency == "TWD")
    #expect(Destination.search("台北").contains { $0.id == taipei.id })
    #expect(Destination.search("Taiwan").first?.isCountry == true)
    #expect(Destination.search("Taiwan").contains { $0.city == "Taipei" })
    #expect(Destination.search("France").first?.countryCode == "FR")
    #expect(Destination.search("France").first?.isCountry == true)
    #expect(Destination.search("France").contains { $0.city == "Paris" })
    #expect(Destination.search("UK").first?.countryCode == "GB")
    #expect(Destination.search("USA").first?.countryCode == "US")
    #expect(Destination.search("Sao Paulo").first?.countryCode == "BR")
    #expect(Destination.search("München").first?.countryCode == "DE")
    #expect(Destination.search("Paris France").first?.city == "Paris")
    #expect(Destination.search("a place that does not exist 28492").isEmpty)
    #expect(Destination.search("Taiwan", limit: 2).count == 2)
    #expect(Destination.search("Taipei", limit: 0).isEmpty)
    #expect(Destination.search("   ") == Destination.suggestions)
  }
}
