import Foundation

/// A place Apple Maps suggests while you type, read as a city or a country so it can sit among the
/// catalogue's chips, e.g. "Bath" with "England, United Kingdom" beneath it.
public struct PlaceSuggestion: Identifiable, Hashable, Sendable {
  public init(title: String, subtitle: String) {
    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let subtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
    self.title = title
    self.subtitle = subtitle
    if subtitle.isEmpty, let code = CountryMetadata.code(named: title) {
      countryCode = code
      isCountry = true
    } else {
      // The country ends the line Maps gives, or the title itself when it has no subtitle.
      let context =
        subtitle.isEmpty ? Self.parts(title).dropFirst().last : Self.parts(subtitle).last
      countryCode = context.flatMap(CountryMetadata.code(named:))
      isCountry = false
    }
  }

  public let title: String
  public let subtitle: String
  public let countryCode: String?
  public let isCountry: Bool
  public var id: String { "\(title)|\(subtitle)" }
  /// The place without the region Maps adds to some names: "Portland" for "Portland, OR".
  public var name: String { Self.parts(title).first ?? title }
  public var flag: String { countryCode?.flag ?? "📍" }
  /// The same for two suggestions of the one place, like New York the city and the state.
  public var key: String {
    "\(isCountry)|\(Destination.normalise(name))|\(countryCode ?? Destination.normalise(subtitle))"
  }

  /// The grey words beside a city: its country, or what Maps said about it when that isn't one.
  public var context: String? {
    guard !isCountry else { return nil }
    if let countryCode, let country = CountryMetadata.country(countryCode) { return country.name }
    return subtitle.isEmpty ? nil : subtitle
  }

  /// Whether this is a place the catalogue already shows.
  public func duplicates(_ destination: Destination) -> Bool {
    guard let countryCode, destination.countryCode == countryCode,
      destination.isCountry == isCountry
    else { return false }
    if isCountry { return true }
    let name = Destination.normalise(name)
    return ([destination.city] + destination.aliases).map(Destination.normalise).contains(name)
  }

  private static func parts(_ text: String) -> [String] {
    text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }
}
