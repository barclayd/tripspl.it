import Foundation

public enum CountryMetadata {
  public struct Country: Decodable, Identifiable, Sendable {
    public var code: String
    private var sourceName: String
    public var currencies: [String]
    public var latitude: Double
    public var longitude: Double
    public var aliases: [String]
    public var id: String { code }
    public var name: String { Locale.current.localizedString(forRegionCode: code) ?? sourceName }
    public var defaultCurrency: String? { currencies.first }
    public var searchNames: [String] { [name, sourceName, code] + aliases }
    private enum CodingKeys: String, CodingKey {
      case code, currencies, latitude, longitude, aliases
      case sourceName = "name"
    }
  }

  public static let all: [Country] = DestinationData.decode([Country].self, file: "Countries")
    .sorted {
      let comparison = $0.name.localizedStandardCompare($1.name)
      return comparison == .orderedSame ? $0.code < $1.code : comparison == .orderedAscending
    }
  private static let byCode = Dictionary(uniqueKeysWithValues: all.map { ($0.code, $0) })
  public static func country(_ code: String) -> Country? { byCode[code.uppercased()] }

  /// The country a name refers to, in English, the device's language or a common alias, e.g.
  /// "Deutschland" or "UK". The UK's nations count as the UK, since that's how Maps can describe
  /// a place in it.
  public static func code(named name: String) -> String? {
    let key = Destination.normalise(name)
    return key.isEmpty ? nil : byName[key]
  }
  private static let byName: [String: String] = {
    let english = Locale(identifier: "en")
    let nations = ["England", "Scotland", "Wales", "Northern Ireland"].map { ($0, "GB") }
    let names = all.flatMap { country in
      let english = english.localizedString(forRegionCode: country.code)
      return (country.searchNames + [english].compactMap { $0 }).map { ($0, country.code) }
    }
    return Dictionary(
      (names + nations).map { (Destination.normalise($0.0), $0.1) }.filter { !$0.0.isEmpty },
      uniquingKeysWith: { first, _ in first })
  }()
}

public enum DestinationData {
  private static var bundle: Bundle {
    Bundle.module
  }
  static func decode<T: Decodable>(_ type: T.Type, file: String) -> T {
    guard let url = bundle.url(forResource: file, withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let result = try? JSONDecoder().decode(type, from: data)
    else {
      preconditionFailure("Missing or invalid bundled destination catalogue: \(file)")
    }
    return result
  }
  public static var acknowledgements: String {
    guard let url = bundle.url(forResource: "DestinationDataLicenses", withExtension: "txt"),
      let text = try? String(contentsOf: url, encoding: .utf8)
    else {
      return "Destination data: GeoNames, Google DSPL and Unicode CLDR."
    }
    return text
  }
}
