import Foundation
import Testing

@testable import TripSplitDomain

struct FXTableTests {
  let table = FXTable(
    base: "GBP", requestedDate: "2026-10-01", rateDate: "2026-10-01",
    source: "Frankfurter reference",
    rates: ["GBP": "1", "EUR": "1.16", "JPY": "198.67", "USD": "1.3365"])

  @Test func readsDirectRatesFromTheBase() {
    #expect(table.rate(from: "GBP", to: "EUR") == "1.16")
    #expect(table.rate(from: "EUR", to: "EUR") == "1")
  }

  @Test func invertsAndCrossesRatesThroughTheBase() throws {
    #expect(table.rate(from: "EUR", to: "GBP") == "0.862068965517241379")
    #expect(table.rate(from: "EUR", to: "JPY") == "171.267241379310345")
    let rate = try #require(table.rate(from: "USD", to: "EUR"))
    #expect(try Money.convert(5000, from: "USD", to: "EUR", rate: rate) == 4340)
  }

  @Test func returnsNilForCurrenciesItDoesNotList() {
    #expect(table.rate(from: "CHF", to: "GBP") == nil)
    #expect(table.currencies == ["GBP", "EUR", "JPY", "USD"])
  }
}
