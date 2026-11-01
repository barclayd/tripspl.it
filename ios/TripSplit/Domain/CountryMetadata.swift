import Foundation

enum CountryMetadata {
  struct Country: Decodable, Identifiable, Sendable {
    var code: String
    private var sourceName: String
    var currencies: [String]
    var latitude: Double
    var longitude: Double
    var aliases: [String]
    var id: String { code }
    var name: String { Locale.current.localizedString(forRegionCode: code) ?? sourceName }
    var defaultCurrency: String? { currencies.first }
    var searchNames: [String] { [name, sourceName, code] + aliases }
    private enum CodingKeys: String, CodingKey {
      case code, currencies, latitude, longitude, aliases
      case sourceName = "name"
    }
  }

  static let all: [Country] = DestinationData.decode([Country].self, file: "Countries").sorted {
    let comparison = $0.name.localizedStandardCompare($1.name)
    return comparison == .orderedSame ? $0.code < $1.code : comparison == .orderedAscending
  }
  private static let byCode = Dictionary(uniqueKeysWithValues: all.map { ($0.code, $0) })
  static func country(_ code: String) -> Country? { byCode[code.uppercased()] }
}

enum DestinationData {
  private static var bundle: Bundle {
    #if SWIFT_PACKAGE
      Bundle.module
    #else
      Bundle.main
    #endif
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
  static var acknowledgements: String {
    guard let url = bundle.url(forResource: "DestinationDataLicenses", withExtension: "txt"),
      let text = try? String(contentsOf: url, encoding: .utf8)
    else {
      return "Destination data: GeoNames, Google DSPL and Unicode CLDR."
    }
    return text
  }
}
