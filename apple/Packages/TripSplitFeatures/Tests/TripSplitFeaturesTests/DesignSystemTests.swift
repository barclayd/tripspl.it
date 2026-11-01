import Testing
import TripSplitDomain

@testable import TripSplitDesignSystem
@testable import TripSplitSharedUI

struct BoardingPassContentTests {
  private func stop(_ place: String, _ country: String, nights: Int) -> Stop {
    Stop(
      countryCode: country, place: place, nights: nights, currency: "EUR", latitude: 0,
      longitude: 0)
  }

  @Test func emptyItineraryAsksWhereTo() {
    let passes = BoardingPassContent.itinerary(stops: [], start: nil, homeCurrency: "GBP")
    #expect(passes.count == 1)
    #expect(passes[0].placeholder)
    #expect(passes[0].from == "HOME")
    #expect(passes[0].to == "???")
    #expect(passes[0].toName == "Where to?")
    #expect(passes[0].fields.first == .init("DATE", "—"))
  }

  @Test func itineraryChainsLegsAndDatesByNights() {
    let passes = BoardingPassContent.itinerary(
      stops: [stop("Lisbon", "PT", nights: 3), stop("Porto", "PT", nights: 1)],
      start: "2026-10-28", homeCurrency: "GBP"
    ) { _ in [.init("PAX", "2")] }

    #expect(passes.map(\.from) == ["HOME", "LIS", "OPO"])
    #expect(passes.map(\.to) == ["LIS", "OPO", "HOME"])
    #expect(passes.map(\.leg) == ["LEG 1 OF 3", "LEG 2 OF 3", "LEG 3 OF 3"])
    #expect(passes.map { $0.fields[0].value } == ["28 OCT", "31 OCT", "1 NOV"])
    #expect(passes.map(\.stubLabel) == ["NIGHTS", "NIGHT", "WELCOME"])
    #expect(passes.map(\.stubValue) == ["3", "1", "HOME"])
    #expect(passes[2].flag == ConversionCurrency.forCurrency("GBP").flag)
    #expect(passes[0].fields[1] == .init("PAX", "2"))
  }

  @Test func passCodesPreferCitiesThenCountryHubs() {
    #expect(stop("Kyoto", "JP", nights: 1).passCode == "KYO")
    #expect(stop("Valencia", "ES", nights: 1).passCode == "VAL")
    if let japan = CountryMetadata.country("JP")?.name {
      #expect(stop(japan, "JP", nights: 1).passCode == "TYO")
    }
  }
}

struct NumberPadTests {
  @Test func replacesLeadingZero() {
    #expect(NumberPad.next("0", key: "5", precision: 2) == "5")
  }

  @Test func capsDecimalsAtCurrencyPrecision() {
    #expect(NumberPad.next("12.3", key: "4", precision: 2) == "12.34")
    #expect(NumberPad.next("12.34", key: "5", precision: 2) == nil)
    #expect(NumberPad.next("12", key: ".", precision: 0) == nil)
    #expect(NumberPad.next("", key: ".", precision: 2) == "0.")
    #expect(NumberPad.next("1.", key: ".", precision: 2) == nil)
  }

  @Test func capsIntegerDigitsAtSeven() {
    #expect(NumberPad.next("1234567", key: "8", precision: 2) == nil)
    #expect(NumberPad.next("1234567", key: ".", precision: 2) == "1234567.")
  }

  @Test func deletesLastCharacter() {
    #expect(NumberPad.next("12.3", key: "⌫", precision: 2) == "12.")
    #expect(NumberPad.next("", key: "⌫", precision: 2) == "")
  }
}

struct WholeMoneyTests {
  @Test func roundsHalfAwayFromZero() {
    #expect(Money.wholeUnits(93_258, "GBP") == 93_300)
    #expect(Money.wholeUnits(93_249, "GBP") == 93_200)
    #expect(Money.wholeUnits(-1_250, "GBP") == -1_300)
    #expect(Money.wholeUnits(1_234, "JPY") == 1_234)
  }

  @Test func formatsWithATrueMinus() {
    #expect(Money.whole(-1_250, "GBP") == "−" + Money.format(1_300, "GBP", compact: true))
    #expect(Money.whole(0, "GBP") == Money.format(0, "GBP", compact: true))
  }
}
