import Foundation

/// A currency choice may carry a destination without assigning shared currencies to one country.
struct ConversionCurrency: Identifiable, Hashable, Sendable {
  let code: String
  let countryCode: String?
  let place: String?

  var id: String { "\(code)|\(countryCode ?? "")|\(place ?? "")" }
  var flag: String {
    if let countryCode { return countryCode.flag }
    switch code {
    case "EUR": return "🇪🇺"
    case "GBP": return "🇬🇧"
    default: return "🌐"
    }
  }
  var currencyName: String { Locale.current.localizedString(forCurrencyCode: code) ?? code }
  var title: String {
    place ?? countryCode.flatMap { CountryMetadata.country($0)?.name } ?? currencyName
  }

  private init(code: String, countryCode: String? = nil, place: String? = nil) {
    self.code = code
    self.countryCode = countryCode
    self.place = place
  }

  static func forCurrency(_ code: String, preferredCountryCode: String? = nil)
    -> ConversionCurrency
  {
    let code = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if let preferredCountryCode,
      let country = CountryMetadata.country(preferredCountryCode),
      country.currencies.contains(code)
    {
      return .init(code: code, countryCode: country.code)
    }
    // GBP is the app's familiar home-currency representative, not an inferred issuer rule.
    return .init(code: code, countryCode: code == "GBP" ? "GB" : nil)
  }

  static func forStop(_ stop: Stop) -> ConversionCurrency {
    let code = stop.currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard let country = CountryMetadata.country(stop.countryCode),
      country.currencies.contains(code)
    else {
      return forCurrency(code)
    }
    let place = stop.place.trimmingCharacters(in: .whitespacesAndNewlines)
    return .init(code: code, countryCode: country.code, place: place.isEmpty ? nil : place)
  }

  /// Empty searches browse countries alphabetically; currency searches also include generic choices.
  static func search(_ query: String, limit: Int = 60) -> [ConversionCurrency] {
    guard limit > 0 else { return [] }
    let flags = flagCountries(in: query)
    let query = Destination.normalise(query)
    if query.isEmpty && flags.isEmpty {
      return Array(countryEntries.prefix(limit).map(\.currency))
    }
    let tokens = query.split(separator: " ").map(String.init)
    return index.compactMap { entry -> (Int, Int, Entry)? in
      if !flags.isEmpty {
        guard let country = entry.currency.countryCode, flags.contains(country) else { return nil }
      }
      guard tokens.allSatisfy({ token in entry.fields.contains { $0.contains(token) } }) else {
        return nil
      }
      let score: Int
      if entry.names.contains(query) { score = 0 }
      else if entry.names.contains(where: { $0.hasPrefix(query) }) { score = 1 }
      else { score = 2 }
      let kind = entry.kind == .generic && entry.names.contains(query) ? -1 : entry.kind.rawValue
      return (kind, score, entry)
    }.sorted {
      if $0.0 != $1.0 { return $0.0 < $1.0 }
      if $0.1 != $1.1 { return $0.1 < $1.1 }
      return $0.2.order < $1.2.order
    }.prefix(limit).map { $0.2.currency }
  }

  private enum Kind: Int, Sendable { case country, generic, city }
  private struct Entry: Sendable {
    let currency: ConversionCurrency
    let kind: Kind
    let names: [String]
    let fields: [String]
    let order: Int
  }

  private static func entry(
    _ currency: ConversionCurrency, kind: Kind, names: [String], context: [String] = [], order: Int
  ) -> Entry {
    let currencyNames = [currency.code, currency.currencyName].map(Destination.normalise)
    let names = names.map(Destination.normalise)
    return .init(
      currency: currency, kind: kind, names: names,
      fields: names + context.map(Destination.normalise) + currencyNames, order: order)
  }

  private static let countryEntries: [Entry] = {
    var entries: [Entry] = []
    for country in CountryMetadata.all {
      for code in country.currencies {
        entries.append(entry(.init(code: code, countryCode: country.code), kind: .country,
          names: country.searchNames, order: entries.count))
      }
    }
    return entries
  }()

  private static let index: [Entry] = {
    var entries = countryEntries
    for code in CurrencyMetadata.codes {
      let currency = ConversionCurrency(code: code)
      entries.append(entry(currency, kind: .generic, names: [code, currency.currencyName],
        order: entries.count))
    }
    let cities = Destination.all.filter { !$0.isCountry }.sorted {
      let comparison = $0.city.localizedStandardCompare($1.city)
      return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
    }
    for city in cities {
      guard let country = CountryMetadata.country(city.countryCode) else { continue }
      for code in country.currencies {
        entries.append(entry(
          .init(code: code, countryCode: country.code, place: city.city), kind: .city,
          names: [city.city] + city.aliases, context: country.searchNames, order: entries.count))
      }
    }
    return entries
  }()

  /// Normalisation removes emoji, so preserve pairs of regional indicators before text matching.
  private static func flagCountries(in text: String) -> Set<String> {
    var countries = Set<String>()
    var first: UnicodeScalar?
    for scalar in text.unicodeScalars {
      guard (0x1F1E6...0x1F1FF).contains(scalar.value) else {
        first = nil
        continue
      }
      if let leading = first {
        let code = [leading, scalar].compactMap { UnicodeScalar($0.value - 0x1F1E6 + 65) }
          .map(String.init).joined()
        countries.insert(code)
        first = nil
      } else {
        first = scalar
      }
    }
    return countries
  }
}
