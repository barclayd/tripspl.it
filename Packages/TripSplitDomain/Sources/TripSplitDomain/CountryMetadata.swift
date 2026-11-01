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
