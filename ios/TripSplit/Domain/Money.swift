import Foundation

enum MoneyError: LocalizedError {
  case invalid, overflow, missingRate
  var errorDescription: String? {
    switch self {
    case .invalid: "Enter a valid amount for this currency."
    case .overflow: "That amount is too large."
    case .missingRate: "A conversion rate is needed. The original amount is saved."
    }
  }
}
enum Money {
  static let limit: Int64 = 999_999_999_999
  static func precision(_ currency: String) -> Int { CurrencyMetadata.minorUnits[currency] ?? 2 }
  static func factor(_ currency: String) -> Int64 {
    (0..<precision(currency)).reduce(1) { n, _ in n * 10 }
  }
  static func minor(_ raw: String?) -> Int64? {
    guard let raw, !raw.isEmpty, raw.allSatisfy({ $0.isASCII && $0.isNumber }),
      let value = Int64(raw), value <= limit
    else { return nil }
    return value
  }
  static func parse(_ value: String, currency: String) throws -> Int64 {
    guard CurrencyMetadata.minorUnits[currency] != nil else { throw MoneyError.invalid }
    let raw = value.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
    let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count <= 2, parts.contains(where: { !$0.isEmpty }),
      parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
      parts.count < 2 || parts[1].count <= precision(currency)
    else { throw MoneyError.invalid }
    let whole = parts[0].isEmpty ? "0" : String(parts[0])
    let fraction = parts.count == 2 ? String(parts[1]) : ""
    let digits =
      whole + fraction + String(repeating: "0", count: precision(currency) - fraction.count)
    guard let result = minor(digits) else { throw MoneyError.overflow }
    return result
  }
  static func input(_ minor: Int64, currency: String) -> String {
    let digits = precision(currency)
    let scale = factor(currency)
    guard digits > 0 else { return String(minor) }
    return "\(minor / scale).\(String(format: "%0*lld", digits, minor % scale))"
  }
  static func format(_ minor: Int64, _ currency: String, compact: Bool = false) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currency
    formatter.minimumFractionDigits =
      compact && minor % factor(currency) == 0 ? 0 : precision(currency)
    formatter.maximumFractionDigits = precision(currency)
    return formatter.string(
      from: NSDecimalNumber(decimal: Decimal(minor) / Decimal(factor(currency))))
      ?? "\(input(minor, currency: currency)) \(currency)"
  }
  static func rateString(_ rate: Decimal) -> String {
    let whole = NSDecimalNumber(decimal: rate).stringValue.split(separator: ".").first ?? "0"
    let digits = whole == "0" ? 0 : whole.count
    var source = rate
    var result = Decimal()
    NSDecimalRound(&result, &source, min(18, max(0, 18 - digits)), .plain)
    return NSDecimalNumber(decimal: result).stringValue
  }
  static func convert(_ minor: Int64, from: String, to: String, rate: String) throws -> Int64 {
    let rateParts = rate.split(separator: ".", omittingEmptySubsequences: false)
    let significant = rate.replacingOccurrences(of: ".", with: "").drop(while: { $0 == "0" }).count
    guard significant <= 18, (rateParts.last?.count ?? 0) <= 18 || rateParts.count == 1,
      CurrencyMetadata.minorUnits[from] != nil, CurrencyMetadata.minorUnits[to] != nil
    else { throw MoneyError.invalid }
    guard minor >= 0, minor <= limit,
      rate.range(of: "^[0-9]+(\\.[0-9]+)?$", options: .regularExpression) != nil,
      var exchange = Decimal(string: rate, locale: Locale(identifier: "en_US_POSIX")), exchange > 0
    else { throw MoneyError.invalid }
    var original = Decimal(minor)
    var result = Decimal()
    var divisor = Decimal(factor(from))
    var multiplier = Decimal(factor(to))
    guard NSDecimalMultiply(&result, &original, &exchange, .plain) == .noError else {
      throw MoneyError.overflow
    }
    original = result
    guard NSDecimalMultiply(&result, &original, &multiplier, .plain) == .noError else {
      throw MoneyError.overflow
    }
    original = result
    let division = NSDecimalDivide(&result, &original, &divisor, .plain)
    guard division == .noError else { throw MoneyError.overflow }
    original = result
    NSDecimalRound(&result, &original, 0, .plain)
    guard result >= 0, result <= Decimal(limit) else { throw MoneyError.overflow }
    return NSDecimalNumber(decimal: result).int64Value
  }
  static func split(_ amount: Int64, among ids: [String]) -> [String: Int64] {
    let sorted = Array(Set(ids)).sorted()
    guard !sorted.isEmpty else { return [:] }
    let count = Int64(sorted.count)
    let base = amount / count
    let remainder = amount % count
    return Dictionary(
      uniqueKeysWithValues: sorted.enumerated().map {
        ($0.element, base + (Int64($0.offset) < remainder ? 1 : 0))
      })
  }
}
struct Settlement: Identifiable, Hashable {
  var from: String
  var to: String
  var amount: Int64
  var id: String { from + to }
}
struct Ledger {
  var paid: Int64 = 0
  var planned: Int64 = 0
  var unresolved = 0
  var balancesComplete = true
  var balances: [String: Int64] = [:]
  var paidBy: [String: Int64] = [:]
  var shares: [String: Int64] = [:]
  var total: Int64 { paid + planned }
  init(_ trip: TripSnapshot, expenses: [Expense]? = nil) {
    for person in trip.travellers {
      balances[person.id] = 0
      shares[person.id] = 0
      paidBy[person.id] = 0
    }
    for expense in expenses ?? trip.expenses {
      guard let value = expense.homeMinor(in: trip.homeCurrency) else {
        unresolved += 1
        if expense.status == .paid { balancesComplete = false }
        continue
      }
      if expense.status == .planned {
        planned += value
        continue
      }
      paid += value
      paidBy[expense.paidBy, default: 0] += value
      balances[expense.paidBy, default: 0] += value
      for (id, share) in Money.split(value, among: expense.splitWith) {
        balances[id, default: 0] -= share
        shares[id, default: 0] += share
      }
    }
    if expenses == nil {
      for repayment in trip.repayments {
        guard
          let value = Money.minor(
            repayment.currency == trip.homeCurrency
              ? repayment.amountMinor : repayment.conversion?.homeAmountMinor)
        else {
          unresolved += 1
          balancesComplete = false
          continue
        }
        balances[repayment.fromTravellerId, default: 0] += value
        balances[repayment.toTravellerId, default: 0] -= value
      }
    }
  }
  var settlements: [Settlement] {
    guard balancesComplete else { return [] }
    var creditors = balances.filter { $0.value > 0 }.sorted {
      $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
    }.map { ($0.key, $0.value) }
    var debtors = balances.filter { $0.value < 0 }.sorted {
      $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value
    }.map { ($0.key, -$0.value) }
    var output: [Settlement] = []
    var i = 0
    var j = 0
    while i < debtors.count && j < creditors.count {
      let amount = min(debtors[i].1, creditors[j].1)
      output.append(.init(from: debtors[i].0, to: creditors[j].0, amount: amount))
      debtors[i].1 -= amount
      creditors[j].1 -= amount
      if debtors[i].1 == 0 { i += 1 }
      if creditors[j].1 == 0 { j += 1 }
    }
    return output
  }
}
enum CivilDate {
  static func calendar(_ zone: String = "UTC") -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: zone) ?? TimeZone(secondsFromGMT: 0)!
    return cal
  }
  static func date(_ value: String) -> Date {
    let formatter = DateFormatter()
    formatter.calendar = calendar()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: value) ?? Date(timeIntervalSince1970: 0)
  }
  static func string(_ date: Date, timeZone: String = "UTC") -> String {
    let f = DateFormatter()
    f.calendar = calendar(timeZone)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: timeZone)
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: date)
  }
  static func today(timeZone: String) -> String { string(Date(), timeZone: timeZone) }
  static func days(from start: String, to end: String) -> Int {
    calendar().dateComponents([.day], from: date(start), to: date(end)).day ?? 0
  }
  static func adding(_ days: Int, to value: String) -> String {
    string(calendar().date(byAdding: .day, value: days, to: date(value))!)
  }
  static func display(_ value: String, format: String = "d MMM") -> String {
    let f = DateFormatter()
    f.calendar = calendar()
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = format
    return f.string(from: date(value))
  }
}
