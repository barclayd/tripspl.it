import Foundation
import Testing

#if canImport(TripSplitDomain)
  @testable import TripSplitDomain
#else
  @testable import TripSplit
#endif

struct ConversionCurrencyTests {
  @Test func destinationContextSurvivesChoosingItsCurrency() throws {
    let rome = try #require(Destination.all.first { $0.city == "Rome" })
    let choice = ConversionCurrency.forStop(rome.stop())
    #expect(choice.code == "EUR")
    #expect(choice.countryCode == "IT")
    #expect(choice.place == "Rome")
    #expect(choice.title == "Rome")
    #expect(choice.flag == "🇮🇹")
    #expect(ConversionCurrency.search("Rome").first == choice)
  }

  @Test func genericSharedCurrenciesDoNotInventACountry() {
    let euro = ConversionCurrency.forCurrency("eur")
    #expect(euro.code == "EUR")
    #expect(euro.countryCode == nil)
    #expect(euro.place == nil)
    #expect(euro.flag == "🇪🇺")
    #expect(euro.title == euro.currencyName)
    #expect(ConversionCurrency.forCurrency("EUR", preferredCountryCode: "IT").flag == "🇮🇹")
    #expect(ConversionCurrency.forCurrency("EUR", preferredCountryCode: "GB") == euro)
    #expect(ConversionCurrency.forCurrency("USD").countryCode == nil)
    #expect(ConversionCurrency.forCurrency("GBP").flag == "🇬🇧")
    #expect(ConversionCurrency.search("GBP").first?.flag == "🇬🇧")
  }

  @Test func countryContextMustSupportTheSelectedCurrency() throws {
    var rome = try #require(Destination.all.first { $0.city == "Rome" }).stop()
    rome.currency = "USD"
    let choice = ConversionCurrency.forStop(rome)
    #expect(choice.code == "USD")
    #expect(choice.countryCode == nil)
    #expect(choice.place == nil)
    #expect(choice.flag == "🌐")
    #expect(ConversionCurrency.forCurrency("USD", preferredCountryCode: "PA").flag == "🇵🇦")
  }

  @Test func countrySearchFindsLocalTenderBeforeCities() throws {
    for (query, countryCode, code) in [("Philippines", "PH", "PHP"), ("Malaysia", "MY", "MYR")] {
      let matches = ConversionCurrency.search(query)
      let first = try #require(matches.first)
      #expect(first.countryCode == countryCode)
      #expect(first.code == code)
      #expect(first.place == nil)
      #expect(matches.contains { $0.place != nil })
      #expect(matches.allSatisfy {
        ($0.countryCode == countryCode || $0.countryCode == nil) && $0.code == code
      })
    }
  }

  @Test func flagsRemainSearchableAlongsideCurrencyTokens() throws {
    let taiwan = ConversionCurrency.search("🇹🇼")
    #expect(try #require(taiwan.first).place == nil)
    #expect(taiwan.allSatisfy { $0.countryCode == "TW" && $0.code == "TWD" })
    #expect(taiwan.contains { $0.place == "Taipei" })
    for query in ["🇹🇼 TWD", "twd 🇹🇼", "🇹🇼 Taiwan"] {
      #expect(ConversionCurrency.search(query) == taiwan)
    }
    #expect(ConversionCurrency.search("🇹🇼 USD").isEmpty)
    #expect(ConversionCurrency.search("🇵🇭 PHP").first?.flag == "🇵🇭")
    #expect(ConversionCurrency.search("🇵🇭 MYR").isEmpty)
    #expect(ConversionCurrency.search("🇿🇿").isEmpty)
  }

  @Test func multiTenderCountriesOfferSeparateScopedChoices() throws {
    let panama = ConversionCurrency.search("Panama")
    let countries = panama.filter { $0.countryCode == "PA" && $0.place == nil }
    #expect(countries.map(\.code) == ["PAB", "USD"])
    #expect(Set(countries.map(\.id)).count == 2)
    #expect(panama.allSatisfy {
      ($0.countryCode == "PA" || $0.countryCode == nil) && ["PAB", "USD"].contains($0.code)
    })
    #expect(ConversionCurrency.search("🇵🇦 USD").allSatisfy { $0.code == "USD" && $0.flag == "🇵🇦" })
    #expect(ConversionCurrency.search("Panama EUR").isEmpty)
    #expect(ConversionCurrency.search("Antarctica").isEmpty)
  }

  @Test func currencyNamesCodesAndDestinationAliasesAreSearchable() throws {
    let ringgit = ConversionCurrency.forCurrency("MYR")
    let nameMatches = ConversionCurrency.search(ringgit.currencyName)
    #expect(try #require(nameMatches.first).code == "MYR")
    #expect(nameMatches.contains { $0.countryCode == "MY" && $0.place == nil })
    #expect(ConversionCurrency.search("php").first?.code == "PHP")
    #expect(ConversionCurrency.search("UK").contains { $0.countryCode == "GB" && $0.place == nil })
    #expect(ConversionCurrency.search("USA").contains { $0.countryCode == "US" && $0.place == nil })
    for query in ["台北", "臺北"] {
      #expect(ConversionCurrency.search(query).first?.place == "Taipei")
    }
    #expect(ConversionCurrency.search("München").first?.place == "Munich")
    #expect(ConversionCurrency.search("Sao Paulo").first?.place == "São Paulo")
  }

  @Test func emptySearchBrowsesEveryCountryAlphabetically() {
    let choices = ConversionCurrency.search("", limit: Int.max)
    #expect(choices.count == CountryMetadata.all.reduce(0) { $0 + $1.currencies.count })
    #expect(choices.allSatisfy { $0.countryCode != nil && $0.place == nil })
    #expect(Set(choices.map(\.id)).count == choices.count)
    for (previous, next) in zip(choices, choices.dropFirst()) {
      #expect(previous.title.localizedStandardCompare(next.title) != .orderedDescending)
    }
    #expect(ConversionCurrency.search(" ").count == 60)
    #expect(ConversionCurrency.search("", limit: 1) == Array(choices.prefix(1)))
    #expect(ConversionCurrency.search("EUR", limit: 0).isEmpty)
    #expect(ConversionCurrency.search("", limit: -1).isEmpty)
  }

  @Test func everySupportedCurrencyHasAGenericSearchResult() {
    for code in CurrencyMetadata.codes {
      let matches = ConversionCurrency.search(code, limit: Int.max)
      #expect(matches.contains { $0.code == code && $0.countryCode == nil && $0.place == nil })
      #expect(Set(matches.map(\.id)).count == matches.count)
    }
  }
}
