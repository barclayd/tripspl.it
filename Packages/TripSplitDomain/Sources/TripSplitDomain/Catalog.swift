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
    name: String = "",
    returnsOn: String? = nil
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
    self.returnsOn = returnsOn
  }
  public var createdTripID: String?
  public var step = 0
  public var stops: [Stop] = []
  public var startsOn = CivilDate.today(timeZone: TimeZone.current.identifier)
  public var timeZone = TimeZone.current.identifier
  public var travellers = [Traveller(name: "You")]
  public var currency = "GBP"
  public var budget = "2400"
  public var name = ""
  public var returnsOn: String?
  public var nights: Int { stops.reduce(0) { $0 + $1.nights } }
  public var returnDate: String { returnsOn ?? CivilDate.adding(nights, to: startsOn) }
  public var totalNights: Int { CivilDate.days(from: startsOn, to: returnDate) }
  public var unallocatedNights: Int { totalNights - nights }
  public var minimumReturnDate: String {
    CivilDate.adding(stops.count > 1 ? stops.count : 0, to: startsOn)
  }
  public var maximumReturnDate: String { CivilDate.adding(365, to: startsOn) }
  // Preserve the original persisted step IDs; return date is the new step 7.
  public var flowSteps: [Int] { [0, 1, 7] + (stops.count > 1 ? [2] : []) + [3, 4, 5, 6] }
  public var totalSteps: Int { flowSteps.count - 1 }
  public var stepPosition: Int { min((flowSteps.firstIndex(of: step) ?? 0) + 1, totalSteps) }
  public var canAdvance: Bool {
    switch step {
    case 0: return !stops.isEmpty
    case 1: return stops.allSatisfy { $0.resolvedTimeZone != nil }
    case 7: return returnDate >= minimumReturnDate && returnDate <= maximumReturnDate
    case 2: return unallocatedNights == 0 && stops.allSatisfy { (1...365).contains($0.nights) }
    case 5: return ((try? Money.parse(budget, currency: currency)) ?? 0) > 0
    default: return true
    }
  }
  public mutating func setDeparture(_ date: String) {
    startsOn = date
    if returnsOn != nil { reconcileRoute() }
  }
  public mutating func setReturn(_ date: String) {
    returnsOn = min(max(date, minimumReturnDate), maximumReturnDate)
    reconcileRoute()
  }
  public mutating func reconcileRoute() {
    guard !stops.isEmpty else { return }
    if let returnsOn {
      self.returnsOn = min(max(returnsOn, minimumReturnDate), maximumReturnDate)
      let minimum = stops.count > 1 ? 1 : 0
      for index in stops.indices { stops[index].nights = max(minimum, stops[index].nights) }
      var remaining = totalNights - nights
      // Preserve existing allocations where possible, adjusting from the final stop backwards.
      for index in stops.indices.reversed() where remaining != 0 {
        let change =
          remaining > 0
          ? min(remaining, 365 - stops[index].nights)
          : max(remaining, minimum - stops[index].nights)
        stops[index].nights += change
        remaining -= change
      }
    }
    if !flowSteps.contains(step) { step = 7 }
  }
  public func maximumNights(at index: Int) -> Int {
    guard stops.indices.contains(index) else { return 0 }
    return max(stops.count > 1 ? 1 : 0, min(365, stops[index].nights + unallocatedNights))
  }
  public mutating func setNights(_ value: Int, at index: Int) {
    guard stops.indices.contains(index) else { return }
    stops[index].nights = min(max(value, stops.count > 1 ? 1 : 0), maximumNights(at: index))
  }
  public mutating func advanceStep() {
    guard canAdvance else { return }
    if step == 7 { setReturn(returnDate) }
    guard let index = flowSteps.firstIndex(of: step), index + 1 < flowSteps.count else { return }
    step = flowSteps[index + 1]
  }
  public mutating func previousStep() {
    guard let index = flowSteps.firstIndex(of: step), index > 0, step != 6 else { return }
    step = flowSteps[index - 1]
  }
  public var tripName: String {
    name.trimmingCharacters(in: .whitespaces).isEmpty
      ? Array(NSOrderedSet(array: stops.map(\.place))).compactMap { $0 as? String }.joined(
        separator: ", ") : name
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
      returnsOn == nil
        || (returnDate >= minimumReturnDate && returnDate <= maximumReturnDate
          && unallocatedNights == 0)
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
