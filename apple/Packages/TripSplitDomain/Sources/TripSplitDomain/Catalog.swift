import Foundation

public struct Destination: Identifiable, Hashable, Sendable {
  public init(
    countryCode: String,
    country: String,
    city: String,
    currency: String,
    latitude: Double,
    longitude: Double,
    catalogID: String? = nil,
    aliases: [String] = [],
    isCountry: Bool = false,
    detail: String? = nil,
    timeZone: String? = nil
  ) {
    self.countryCode = countryCode
    self.country = country
    self.city = city
    self.currency = currency
    self.latitude = latitude
    self.longitude = longitude
    self.catalogID = catalogID
    self.aliases = aliases
    self.isCountry = isCountry
    self.detail = detail
    self.timeZone = timeZone
  }
  public var countryCode: String
  public var country: String
  public var city: String
  public var currency: String
  public var latitude: Double
  public var longitude: Double
  public var catalogID: String? = nil
  public var aliases: [String] = []
  public var isCountry = false
  public var detail: String? = nil
  public var timeZone: String? = nil
  public var id: String { catalogID ?? "\(countryCode):\(isCountry ? "country" : "place"):\(city)" }
  public var flag: String { countryCode.flag }
  public var resolvedTimeZone: String? {
    if let timeZone, TimeZone(identifier: timeZone) != nil { return timeZone }
    return DestinationTimeZones.identifier(
      countryCode: countryCode, latitude: latitude, longitude: longitude)
  }
  public var currencies: [String] { CountryMetadata.country(countryCode)?.currencies ?? [] }
  public var requiresCurrencySelection: Bool { currency.isEmpty }
  public var secondaryLabel: String {
    if isCountry { return "Country" }
    let context = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return context.isEmpty ? country : context
  }

  public func stop(nights: Int = 3) -> Stop {
    .init(
      countryCode: countryCode, place: city, nights: nights, currency: currency,
      latitude: latitude, longitude: longitude, timeZone: resolvedTimeZone)
  }

  /// The first entries retain the original demo itinerary's order.
  public static let all: [Destination] = {
    let places = DestinationData.decode([Place].self, file: "Destinations")
    return places.map { place in
      guard let country = CountryMetadata.country(place.countryCode) else {
        preconditionFailure("Destination country is absent from the bundled catalogue")
      }
      return Destination(
        countryCode: country.code, country: country.name, city: place.name,
        currency: country.defaultCurrency ?? "", latitude: place.latitude,
        longitude: place.longitude, catalogID: place.id, aliases: place.aliases)
    } + CountryMetadata.all.map(makeCountry)
  }()

  public static var suggestions: [Destination] { Array(all.prefix(12)) }
  public static func country(_ code: String) -> Destination? {
    CountryMetadata.country(code).map(makeCountry)
  }
  /// The catalogue's leading city for a region, standing in for home until people set one.
  public static func home(region: String?) -> Destination? {
    guard let region = region?.uppercased() else { return nil }
    return all.first { $0.countryCode == region && !$0.isCountry }
  }

  /// Exact names and aliases precede prefixes; country-name matches include their cities.
  public static func search(_ query: String, limit: Int = 40) -> [Destination] {
    let query = normalise(query)
    guard !query.isEmpty else { return Array(suggestions.prefix(max(0, limit))) }
    let tokens = query.split(separator: " ").map(String.init)
    return index.compactMap { entry -> (Int, Int, Destination)? in
      let score: Int
      if entry.names.contains(query) {
        score = entry.destination.isCountry ? 0 : 1
      } else if entry.names.contains(where: { $0.hasPrefix(query) }) {
        score = 2
      } else if entry.names.contains(where: { $0.contains(query) }) {
        score = 3
      } else if tokens.allSatisfy({ token in entry.fields.contains { $0.contains(token) } }) {
        score = 4
      } else {
        return nil
      }
      return (score, entry.order, entry.destination)
    }.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
      .prefix(max(0, limit)).map(\.2)
  }

  public static func normalise(_ text: String) -> String {
    text.folding(
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    )
    .components(separatedBy: .alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
  }

  private static func makeCountry(_ country: CountryMetadata.Country) -> Destination {
    .init(
      countryCode: country.code, country: country.name, city: country.name,
      currency: country.defaultCurrency ?? "", latitude: country.latitude,
      longitude: country.longitude, catalogID: "country:" + country.code,
      aliases: country.searchNames, isCountry: true)
  }
  private struct Place: Decodable {
    var id: String
    var name: String
    var countryCode: String
    var latitude: Double
    var longitude: Double
    var aliases: [String]
  }
  private struct Entry: Sendable {
    var destination: Destination
    var order: Int
    var names: [String]
    var fields: [String]
  }
  private static let index: [Entry] = all.enumerated().map { order, destination in
    let names = ([destination.city] + destination.aliases).map(normalise)
    let country = CountryMetadata.country(destination.countryCode)
    return Entry(
      destination: destination, order: order, names: names,
      fields: names + (country?.searchNames ?? [destination.country]).map(normalise))
  }
}

public struct OnboardingDraft: Codable, Equatable, Sendable {
  public init(
    createdTripID: String? = nil,
    step: Int = 0,
    stops: [Stop] = [],
    startsOn: String = CivilDate.today(timeZone: TimeZone.current.identifier),
    timeZone: String = TimeZone.current.identifier,
    travellers: [Traveller] = [Traveller(name: "You")],
    currency: String = "GBP",
    budget: String = "2400",
    name: String = ""
  ) {
    self.createdTripID = createdTripID
    self.step = step
    self.stops = stops
    self.startsOn = startsOn
    self.timeZone = timeZone
    self.travellers = travellers
    self.currency = currency
    self.budget = budget
    self.name = name
  }
  /// A fresh draft for the new-trip flow, with the budget left for the flow to suggest.
  public static func newTrip() -> OnboardingDraft { OnboardingDraft(budget: "") }

  public static let maximumStops = 6
  public static let maximumTravellers = 8
  public static let maximumNightsPerStop = 30
  /// The budget suggested per person per day, in pounds, before converting to the home currency.
  public static let suggestedDailySpendGBP = 75

  public var createdTripID: String?
  public var step = 0
  public var stops: [Stop] = []
  public var startsOn = CivilDate.today(timeZone: TimeZone.current.identifier)
  public var timeZone = TimeZone.current.identifier
  public var travellers = [Traveller(name: "You")]
  public var currency = "GBP"
  public var budget = "2400"
  public var name = ""
  public var nights: Int { stops.reduce(0) { $0 + $1.nights } }
  public var days: Int { nights + 1 }
  public var returnDate: String { CivilDate.adding(nights, to: startsOn) }
  /// A lone stop can be a day trip; every stop on a longer route needs at least a night.
  public var nightRange: ClosedRange<Int> {
    (stops.count > 1 ? 1 : 0)...Self.maximumNightsPerStop
  }
  /// Where, when, how long, who, home currency, budget, then done. Step 7 (a since-removed return
  /// date step) is no longer part of the flow.
  public var flowSteps: [Int] { [0, 1, 2, 3, 4, 5, 6] }
  public var totalSteps: Int { flowSteps.count - 1 }
  public var stepPosition: Int { min((flowSteps.firstIndex(of: step) ?? 0) + 1, totalSteps) }
  public var canAdvance: Bool {
    switch step {
    case 0: return !stops.isEmpty
    case 1: return stops.allSatisfy { $0.resolvedTimeZone != nil }
    case 2: return !stops.isEmpty && stops.allSatisfy { nightRange.contains($0.nights) }
    case 5: return ((try? Money.parse(budget, currency: currency)) ?? 0) > 0
    default: return true
    }
  }
  public mutating func setDeparture(_ date: String) { startsOn = date }
  /// Keeps nights within range after the route changes and moves a stale step back into the flow.
  public mutating func reconcileRoute() {
    for index in stops.indices {
      stops[index].nights = min(max(stops[index].nights, nightRange.lowerBound), nightRange.upperBound)
    }
    if !flowSteps.contains(step) { step = 2 }
  }
  public mutating func setNights(_ value: Int, at index: Int) {
    guard stops.indices.contains(index) else { return }
    stops[index].nights = min(max(value, nightRange.lowerBound), nightRange.upperBound)
  }
  public mutating func advanceStep() {
    guard canAdvance, let index = flowSteps.firstIndex(of: step), index + 1 < flowSteps.count
    else { return }
    step = flowSteps[index + 1]
  }
  public mutating func previousStep() {
    guard let index = flowSteps.firstIndex(of: step), index > 0, step != 6 else { return }
    step = flowSteps[index - 1]
  }
  /// Jumps back to an answered step to change it; never forward, and never once the trip exists.
  public mutating func revisit(_ target: Int) {
    guard step != 6, flowSteps.contains(target), target < step else { return }
    step = target
  }
  /// Days × people × £75, in the home currency at `homePerGBP`, rounded to 50 and at least 100.
  public func suggestedBudget(homePerGBP: Double) -> Int {
    let value =
      Double(days * max(1, travellers.count) * Self.suggestedDailySpendGBP) * homePerGBP
    return max(100, Int((value / 50).rounded()) * 50)
  }
  /// The chosen name, or the places in order: "Lisbon, Porto & Seville".
  public var tripName: String {
    let chosen = name.trimmingCharacters(in: .whitespaces)
    guard chosen.isEmpty else { return chosen }
    let places = Array(NSOrderedSet(array: stops.map(\.place))).compactMap { $0 as? String }
    guard places.count > 1, let last = places.last else { return places.first ?? "" }
    return places.dropLast().joined(separator: ", ") + " & " + last
  }
  public func previewTrip() throws -> TripSnapshot {
    var preview = self
    preview.reconcileRoute()
    if (try? Money.parse(preview.budget, currency: preview.currency)) == nil {
      preview.budget = "0"
    }
    return try preview.makeTrip()
  }
  public func makeTrip() throws -> TripSnapshot {
    guard let owner = travellers.first, !stops.isEmpty,
      stops.allSatisfy({ (0...365).contains($0.nights) }), nights <= 365,
      stops.count == 1 || stops.allSatisfy({ $0.nights > 0 })
    else { throw MoneyError.invalid }
    var days: [TripDay] = []
    var legs: [TravelLeg] = []
    var offset = 0
    for (index, stop) in stops.enumerated() {
      let day = CivilDate.adding(offset, to: startsOn)
      for i in 0..<stop.nights {
        days.append(.init(date: CivilDate.adding(offset + i, to: startsOn), stopId: stop.id))
      }
      legs.append(
        .init(
          kind: index == 0 ? .outbound : .transfer, date: day,
          fromStopId: index == 0 ? nil : stops[index - 1].id, toStopId: stop.id,
          dayId: days.last(where: { $0.date == day })?.id))
      offset += stop.nights
    }
    let lastDate = CivilDate.adding(offset, to: startsOn)
    days.append(.init(date: lastDate, stopId: stops.last!.id))
    legs.append(
      .init(
        kind: .return, date: lastDate, fromStopId: stops.last!.id, toStopId: nil,
        dayId: days.last?.id))
    return TripSnapshot(
      name: tripName, startsOn: startsOn, timeZone: stops.first?.resolvedTimeZone ?? timeZone,
      homeCurrency: currency,
      budgetMinor: String(try Money.parse(budget, currency: currency)), ownerTravellerId: owner.id,
      currentTravellerId: owner.id, travellers: travellers, stops: stops, days: days, legs: legs)
  }
}
