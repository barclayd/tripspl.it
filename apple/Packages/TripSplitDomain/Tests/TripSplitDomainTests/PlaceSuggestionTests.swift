import Testing

@testable import TripSplitDomain

struct PlaceSuggestionTests {
  @Test func readsTheCountryFromTheEndOfTheSubtitle() {
    let bath = PlaceSuggestion(title: "Bath", subtitle: "England, United Kingdom")
    #expect(bath.countryCode == "GB")
    #expect(!bath.isCountry)
    #expect(bath.name == "Bath")
    #expect(bath.flag == "🇬🇧")
    #expect(bath.context == CountryMetadata.country("GB")?.name)
  }

  @Test func treatsTheUKsNationsAsTheUK() {
    #expect(PlaceSuggestion(title: "Cardiff", subtitle: "Wales").countryCode == "GB")
    #expect(PlaceSuggestion(title: "Belfast", subtitle: "Northern Ireland").countryCode == "GB")
  }

  @Test func readsACountryOnItsOwnAsTheCountry() {
    let portugal = PlaceSuggestion(title: "Portugal", subtitle: "")
    #expect(portugal.isCountry)
    #expect(portugal.countryCode == "PT")
    #expect(portugal.context == nil)
    #expect(PlaceSuggestion(title: "Deutschland", subtitle: "").countryCode == "DE")
  }

  @Test func dropsTheRegionFromTheNameButKeepsTheCountry() {
    let portland = PlaceSuggestion(title: "Portland, OR", subtitle: "United States")
    #expect(portland.name == "Portland")
    #expect(portland.countryCode == "US")
    #expect(PlaceSuggestion(title: "Hobart, Tasmania, Australia", subtitle: "").countryCode == "AU")
  }

  @Test func keepsWhatMapsSaidWhenItIsNotACountry() {
    let unknown = PlaceSuggestion(title: "Somewhere", subtitle: "Atlantis")
    #expect(unknown.countryCode == nil)
    #expect(unknown.flag == "📍")
    #expect(unknown.context == "Atlantis")
  }

  @Test func sharesAKeyWithOtherSuggestionsOfTheSamePlace() {
    let city = PlaceSuggestion(title: "New York, NY", subtitle: "United States")
    #expect(city.key == PlaceSuggestion(title: "New York", subtitle: "United States").key)
    #expect(city.key != PlaceSuggestion(title: "York", subtitle: "England").key)
    #expect(
      PlaceSuggestion(title: "Cardiff", subtitle: "Wales").key
        != PlaceSuggestion(title: "Cardiff, AB", subtitle: "Canada").key)
  }

  @Test func spotsPlacesTheCatalogueAlreadyShows() throws {
    let lisbon = try #require(Destination.catalogued(city: "lisbon", countryCode: "PT"))
    let portugal = try #require(Destination.country("PT"))
    #expect(PlaceSuggestion(title: "Lisbon", subtitle: "Portugal").duplicates(lisbon))
    #expect(!PlaceSuggestion(title: "Lisbon", subtitle: "Portugal").duplicates(portugal))
    #expect(!PlaceSuggestion(title: "Porto", subtitle: "Portugal").duplicates(lisbon))
    #expect(PlaceSuggestion(title: "Portugal", subtitle: "").duplicates(portugal))
    #expect(!PlaceSuggestion(title: "Lisbon", subtitle: "Spain").duplicates(lisbon))
  }

  @Test func findsCataloguedCitiesByAnyOfTheirNames() {
    #expect(Destination.catalogued(city: "LONDON", countryCode: "GB")?.city == "London")
    #expect(Destination.catalogued(city: "London", countryCode: "CA") == nil)
    #expect(Destination.catalogued(city: "Portugal", countryCode: "PT") == nil)
  }
}
