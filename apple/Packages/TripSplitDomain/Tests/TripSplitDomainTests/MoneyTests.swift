import Foundation
import Testing

@testable import TripSplitDomain

struct MoneyTests {
  struct Fixtures: Decodable {
    struct Allocation: Decodable {
      var name: String
      var amountMinor: String
      var travellerIds: [String]
      var expected: [String: String]
    }
    struct ConversionCase: Decodable {
      var name: String
      var amountMinor: String
      var from: String
      var fromExponent: Int
      var to: String
      var toExponent: Int
      var rate: String
      var expectedMinor: String
    }
    struct LedgerCase: Decodable {
      struct Item: Decodable {
        var id: String
        var status: String
        var homeAmountMinor: String?
        var paidBy: String
        var splitWith: [String]
      }
      struct Repay: Decodable {
        var fromTravellerId: String
        var toTravellerId: String
        var homeAmountMinor: String
      }
      struct Expected: Decodable {
        struct Settle: Decodable {
          var fromTravellerId: String
          var toTravellerId: String
          var amountMinor: String
        }
        var paidMinor: String
        var plannedMinor: String
        var expectedMinor: String
        var balances: [String: String]
        var paidShares: [String: String]
        var isComplete: Bool
        var settlements: [Settle]
      }
      var name: String
      var travellerIds: [String]
      var expenses: [Item]
      var repayments: [Repay]
      var expected: Expected
    }
    var allocationCases: [Allocation]
    var conversionCases: [ConversionCase]
    var ledgerCases: [LedgerCase]
  }
  private func apiData(_ relativePath: String) throws -> Data {
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while directory.path != "/" {
      let file = directory.appending(path: "api/" + relativePath)
      if FileManager.default.fileExists(atPath: file.path) {
        return try Data(contentsOf: file)
      }
      directory.deleteLastPathComponent()
    }
    throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: "api/" + relativePath])
  }
  func fixtures() throws -> Fixtures {
    try JSONDecoder().decode(Fixtures.self, from: apiData("contracts/fixtures/money-examples.json"))
  }
  @Test func requiredNullableKeysAreExplicitJSONNull() throws {
    var draft = OnboardingDraft()
    draft.stops = [Destination.all[0].stop()]
    let trip = try draft.makeTrip()
    let leg = try #require(
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(trip.legs[0])) as? [String: Any])
    #expect(leg["fromStopId"] is NSNull)
    let expense = Expense(
      attachment: .init(kind: .day, id: trip.days[0].id), title: "Later", category: .food,
      amountMinor: "100", currency: "GBP", status: .planned, paidBy: trip.ownerTravellerId,
      splitWith: [trip.ownerTravellerId])
    let item = try #require(
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(expense)) as? [String: Any])
    #expect(item["conversion"] is NSNull)
    #expect(item["paidOn"] is NSNull)
    let conversion = Conversion(
      homeAmountMinor: "100", rate: "1", rateDate: trip.startsOn, source: "Actual charge",
      kind: "manual", quoteId: nil)
    let encoded = try #require(
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(conversion)) as? [String: Any])
    #expect(encoded["quoteId"] is NSNull)
    let request = try #require(
      try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(SyncRequest(cursor: nil, syncEpoch: nil, operations: [])))
        as? [String: Any])
    #expect(request["cursor"] is NSNull)
    #expect(request["syncEpoch"] is NSNull)
  }
  @Test func repeatingManualRateFitsTransportPrecision() throws {
    let rate = Money.rateString(Decimal(1) / Decimal(3))
    #expect(rate == "0.333333333333333333")
    #expect(try Money.convert(3, from: "GBP", to: "EUR", rate: rate) == 1)
  }
  @Test func officialCurrencyMetadata() throws {
    struct Metadata: Decodable { var minorUnits: [String: Int] }
    let metadata = try JSONDecoder().decode(
      Metadata.self, from: apiData("src/data/currencies.json"))
    #expect(CurrencyMetadata.minorUnits == metadata.minorUnits)
  }
  @Test func sharedAllocationFixtures() throws {
    for example in try fixtures().allocationCases {
      let actual = Money.split(
        try #require(Int64(example.amountMinor)), among: example.travellerIds
      ).mapValues(String.init)
      #expect(actual == example.expected, "\(example.name)")
    }
  }
  @Test func sharedConversionFixtures() throws {
    for example in try fixtures().conversionCases {
      #expect(Money.precision(example.from) == example.fromExponent)
      #expect(Money.precision(example.to) == example.toExponent)
      #expect(
        String(
          try Money.convert(
            try #require(Int64(example.amountMinor)), from: example.from, to: example.to,
            rate: example.rate)) == example.expectedMinor, "\(example.name)")
    }
  }
  @Test func sharedLedgerFixtures() throws {
    for example in try fixtures().ledgerCases {
      var draft = OnboardingDraft()
      draft.stops = [Destination.all[0].stop()]
      draft.travellers = example.travellerIds.map { Traveller(id: $0, name: $0) }
      var trip = try draft.makeTrip()
      trip.homeCurrency = "GBP"
      trip.expenses = example.expenses.map { item in
        Expense(
          id: item.id, attachment: .init(kind: .day, id: trip.days[0].id), title: item.id,
          category: .food, amountMinor: item.homeAmountMinor ?? "100",
          currency: item.homeAmountMinor == nil ? "EUR" : "GBP",
          status: Expense.Status(rawValue: item.status)!, paidBy: item.paidBy,
          splitWith: item.splitWith)
      }
      trip.repayments = example.repayments.map {
        Repayment(
          fromTravellerId: $0.fromTravellerId, toTravellerId: $0.toTravellerId,
          amountMinor: $0.homeAmountMinor, currency: "GBP", paidOn: trip.startsOn, note: "")
      }
      let ledger = Ledger(trip)
      #expect(String(ledger.paid) == example.expected.paidMinor)
      #expect(String(ledger.planned) == example.expected.plannedMinor)
      #expect(String(ledger.total) == example.expected.expectedMinor)
      #expect(ledger.balances.mapValues(String.init) == example.expected.balances)
      #expect(ledger.shares.mapValues(String.init) == example.expected.paidShares)
      #expect((ledger.unresolved == 0) == example.expected.isComplete)
      #expect(
        ledger.settlements
          == example.expected.settlements.map {
            .init(from: $0.fromTravellerId, to: $0.toTravellerId, amount: Int64($0.amountMinor)!)
          })
      #expect(ledger.balances.values.reduce(0, +) == 0)
    }
  }
  @Test func preciseInputAndBounds() throws {
    #expect(try Money.parse("100000.01", currency: "IDR") == 10_000_001)
    #expect(try Money.parse("12.345", currency: "KWD") == 12345)
    #expect(throws: MoneyError.self) { try Money.parse("1.1", currency: "JPY") }
    #expect(throws: MoneyError.self) { try Money.parse("10000000000", currency: "GBP") }
    #expect(throws: MoneyError.self) {
      try Money.convert(999_999_999_999, from: "GBP", to: "JPY", rate: "999999999999999999")
    }
    #expect(throws: MoneyError.self) { try Money.parse("-2", currency: "GBP") }
  }
  @Test func civilDatesSurviveDSTAndFinalDay() throws {
    var draft = OnboardingDraft()
    draft.startsOn = "2026-10-24"
    draft.stops = [Destination.all[0].stop(nights: 2), Destination.all[1].stop(nights: 3)]
    let trip = try draft.makeTrip()
    #expect(trip.days.count == 6)
    #expect(trip.endsOn == "2026-10-29")
    #expect(Set(trip.days.map(\.id)).count == 6)
    #expect(trip.days.last?.stopId == trip.stops.last?.id)
  }
  @Test func plannedMissingRateDoesNotInvalidatePaidBalances() throws {
    var draft = OnboardingDraft()
    draft.stops = [Destination.all[0].stop()]
    var trip = try draft.makeTrip()
    trip.expenses = [
      .init(
        attachment: .init(kind: .day, id: trip.days[0].id), title: "Later", category: .food,
        amountMinor: "100", currency: "JPY", status: .planned, paidBy: trip.ownerTravellerId,
        splitWith: [trip.ownerTravellerId])
    ]
    let ledger = Ledger(trip)
    #expect(ledger.unresolved == 1)
    #expect(ledger.balancesComplete)
  }
}
