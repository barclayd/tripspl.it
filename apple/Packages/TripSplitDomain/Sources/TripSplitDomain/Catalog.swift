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
  /// Leaving from here, as the trip saves it.
  public var origin: TripOrigin {
    .init(place: city, countryCode: countryCode, latitude: latitude, longitude: longitude)
  }

  /// The destination a stop was picked from: its catalogue entry, or one rebuilt from the stop
  /// for a place found on Apple Maps.
  public init(stop: Stop) {
    if let match = Self.all.first(where: { $0.matches(stop) }) {
      self = match
      return
    }
    self.init(
      countryCode: stop.countryCode,
      country: CountryMetadata.country(stop.countryCode)?.name ?? stop.countryCode,
      city: stop.place, currency: stop.currency, latitude: stop.latitude,
      longitude: stop.longitude, timeZone: stop.timeZone)
  }

  /// The place an origin was picked from: its catalogue entry, or one rebuilt from the origin for
  /// a place found on Apple Maps or from the current location.
  public init(origin: TripOrigin) {
    if let match = Self.all.first(where: { $0.origin == origin }) {
      self = match
      return
    }
    self.init(
      countryCode: origin.countryCode,
      country: CountryMetadata.country(origin.countryCode)?.name ?? origin.countryCode,
      city: origin.place, currency: origin.currency ?? "", latitude: origin.latitude,
      longitude: origin.longitude)
  }

  /// Whether the stop is a visit here: the same place, ignoring case and accents, at the same spot.
  public func matches(_ stop: Stop) -> Bool {
    stop.countryCode == countryCode
      && stop.place.compare(city, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
      && abs(stop.latitude - latitude) <= 0.0001 && abs(stop.longitude - longitude) <= 0.0001
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
  /// Where to start before anything's typed: the world's most visited cities and countries, taking
  /// turns down each ranking. Cities follow Euromonitor's Top 100 City Destinations 2025 by
  /// international arrivals, and countries UN Tourism's international arrivals for 2024.
  public static let popular: [Destination] = {
    let cities = [
      "geonames-1609350",  // Bangkok
      "geonames-1819729",  // Hong Kong
      "geonames-2643743",  // London
      "geonames-1821274",  // Macau
      "geonames-745044",  // Istanbul
      "geonames-292223",  // Dubai
      "geonames-104515",  // Makkah
      "geonames-323777",  // Antalya
      "geonames-2988507",  // Paris
      "geonames-1735161",  // Kuala Lumpur
    ].compactMap { id in all.first { $0.catalogID == id } }
    let countries = ["FR", "ES", "US", "TR", "IT", "MX", "GB", "DE", "JP", "GR"].compactMap(country)
    return zip(cities, countries).flatMap { [$0, $1] }
  }()
  /// The catalogue's city by one of its names in a country, so a place found through Maps and the
  /// chips agree on it.
  public static func catalogued(city name: String, countryCode: String) -> Destination? {
    let name = normalise(name)
    return index.first {
      !$0.destination.isCountry && $0.destination.countryCode == countryCode
        && $0.names.contains(name)
    }?.destination
  }
  public static func country(_ code: String) -> Destination? {
    CountryMetadata.country(code).map(makeCountry)
  }
  /// The catalogue's leading city for a region, standing in for home until people set one.
  public static func home(region: String?) -> Destination? {
    guard let region = region?.uppercased() else { return nil }
    return all.first { $0.countryCode == region && !$0.isCountry }
  }
  /// Where people in a region usually leave from: its own cities, then the nearest neighbours'
  /// leading cities, so the UK lists London, Edinburgh and Manchester before Dublin. Neighbours
  /// need a few catalogue cities, which passes over small islands such as the Isle of Man.
  public static func origins(region: String?, limit: Int = 7) -> [Destination] {
    let cities = all.filter { !$0.isCountry }
    guard let code = region?.uppercased(), let country = CountryMetadata.country(code) else {
      return Array(cities.prefix(limit))
    }
    let centre = GeoPoint(latitude: country.latitude, longitude: country.longitude)
    let sizes = Dictionary(grouping: cities, by: \.countryCode).mapValues(\.count)
    var seen: Set = [code]
    let neighbours = cities.filter { sizes[$0.countryCode, default: 0] > 1 }
      .filter { seen.insert($0.countryCode).inserted }
      .sorted { $0.point.distance(to: centre) < $1.point.distance(to: centre) }
    let local = cities.filter { $0.countryCode == code }.prefix(max(limit - 1, 0))
    return Array((local + neighbours).prefix(limit))
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
    origin: TripOrigin? = nil,
    datesPicked: DatesPicked? = nil
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
    self.origin = origin
    self.datesPicked = datesPicked
  }
  /// A fresh draft for the new-trip flow, with the budget left for the flow to suggest and the
  /// dates left for you to pick.
  public static func newTrip() -> OnboardingDraft {
    OnboardingDraft(budget: "", datesPicked: .neither)
  }

  public static let maximumStops = 6
  public static let maximumTravellers = 8
  /// The longest trip the itinerary and the API accept, in nights.
  public static let maximumNights = Itinerary.maximumNights
  /// The budget suggested per person per day, in pounds, before converting to the home currency.
  public static let suggestedDailySpendGBP = 75

  public var createdTripID: String?
  public var step = 0
  public var stops: [Stop] = []
  public var startsOn = CivilDate.today(timeZone: TimeZone.current.identifier)
  /// Where the planner is, not where they're going: "today" while planning is the phone's date.
  public var timeZone = TimeZone.current.identifier
  public var travellers = [Traveller(name: "You")]
  public var currency = "GBP"
  public var budget = "2400"
  public var name = ""
  /// Where the trip leaves from and returns to; drafts saved before the step have none.
  public var origin: TripOrigin?
  /// How far picking the dates has got. A new trip starts with neither, so the calendar shows only
  /// today until you tap; drafts saved before you picked them have none and keep their dates.
  public var datesPicked: DatesPicked?
  public enum DatesPicked: String, Codable, Sendable { case neither, leaving, both }
  /// The day you leave, once picked.
  public var pickedStart: String? { datesPicked == .neither ? nil : startsOn }
  /// The day you're home, once picked.
  public var pickedEnd: String? { hasDates ? returnDate : nil }
  public var hasDates: Bool { (datesPicked ?? .both) == .both }
  /// The next tap on the calendar sets the day you're home.
  public var isPickingHome: Bool { datesPicked == .leaving }
  public var nights: Int { stops.reduce(0) { $0 + $1.nights } }
  public var days: Int { nights + 1 }
  public var returnDate: String { CivilDate.adding(nights, to: startsOn) }
  /// A lone stop can be a day trip; every stop on a longer route needs at least a night.
  public var nightRange: ClosedRange<Int> { Itinerary.nightRange(stops: stops.count) }
  /// The shortest and longest trip the route allows: a night per stop on a longer route.
  public var tripNights: ClosedRange<Int> { Itinerary.tripNights(stops: stops.count) }
  /// Every step in the order they're asked. Drafts are saved by step number, so leaving from (8)
  /// slots in after where without renumbering, and step 7 (a since-removed return date step) is
  /// gone: where, leaving from, when, how long, who, home currency, budget, then done.
  public static let stepOrder = [0, 8, 1, 2, 3, 4, 5, 6]
  /// How long only splits the dates between stops, so a single destination skips it.
  public var flowSteps: [Int] { Self.stepOrder.filter { $0 != 2 || stops.count > 1 } }
  public var totalSteps: Int { flowSteps.count - 1 }
  public var stepPosition: Int { min((flowSteps.firstIndex(of: step) ?? 0) + 1, totalSteps) }
  /// Whether the flow has got as far as `target`, by the order the steps are asked in.
  public func reached(_ target: Int) -> Bool { Self.rank(step) >= Self.rank(target) }
  private static func rank(_ step: Int) -> Int { stepOrder.firstIndex(of: step) ?? stepOrder.count }
  /// The progress bar's fill. Leaving from is quick, so it counts as half a step.
  public var progress: Double {
    let questions = flowSteps.filter { $0 != 8 }
    let done = step == 8 ? 0.5 : Double(questions.firstIndex(of: step) ?? 0)
    return max(0.05, done / Double(max(questions.count - 1, 1)))
  }
  public var canAdvance: Bool {
    switch step {
    case 0: return !stops.isEmpty
    case 8: return origin != nil
    case 1:
      return hasDates && stops.allSatisfy { $0.resolvedTimeZone != nil } && tripNights.contains(nights)
    case 2: return !stops.isEmpty && stops.allSatisfy { nightRange.contains($0.nights) }
    case 5: return ((try? Money.parse(budget, currency: currency)) ?? 0) > 0
    default: return true
    }
  }
  /// Moves the whole trip, keeping its length.
  public mutating func setDeparture(_ date: String) { startsOn = date }
  /// Any day from today. Picking home, a day on or after leaving also has to leave a night for
  /// each stop on a longer route; a day before leaving moves leaving instead.
  public func canPick(_ date: String, today: String) -> Bool {
    guard date >= today else { return false }
    guard isPickingHome, date >= startsOn else { return true }
    return tripNights.contains(CivilDate.days(from: startsOn, to: date))
  }
  /// A tap on the calendar: the first picks the day you leave and the next the day you're home,
  /// unless it's before leaving, which moves leaving instead. Once both are picked, a tap starts
  /// over from that day.
  public mutating func pick(_ date: String) {
    if isPickingHome, date >= startsOn {
      setReturn(date)
      datesPicked = .both
    } else {
      startsOn = date
      datesPicked = .leaving
    }
  }
  /// Forgets both dates, as a draft left until after the day it leaves has to.
  public mutating func clearDates(today: String) {
    startsOn = today
    datesPicked = .neither
  }
  /// Adds or removes stops, keeping the dates you picked: the trip's nights are shared out across
  /// the new route, or the day home is cleared to pick again when it's too short for every stop.
  public mutating func changeRoute(_ change: (inout [Stop]) -> Void) {
    let home = returnDate
    change(&stops)
    reconcileRoute()
    guard hasDates else { return }
    if !stops.isEmpty, tripNights.contains(CivilDate.days(from: startsOn, to: home)) {
      setReturn(home)
    } else {
      datesPicked = .leaving
    }
  }
  /// Sets the day you're home, sharing the nights between stops in their current proportions.
  public mutating func setReturn(_ date: String) {
    let total = min(
      max(CivilDate.days(from: startsOn, to: date), tripNights.lowerBound), tripNights.upperBound)
    let split = Itinerary.split(total, across: stops.map(\.nights), floor: nightRange.lowerBound)
    for index in stops.indices { stops[index].nights = split[index] }
  }
  /// Sets both ends of the trip at once, as tapping a day before the start while picking home does.
  public mutating func setDates(leaving: String, home: String) {
    startsOn = leaving
    setReturn(home)
  }
  /// Moves nights between stops so the dates you picked stay put. A stop takes a night from the
  /// nearest later stop that can spare one (then the nearest earlier), and gives one to the next
  /// stop (or the one before, for the last).
  public mutating func shiftNight(at index: Int, by delta: Int) {
    for _ in 0..<abs(delta) {
      guard canShiftNight(at: index, by: delta),
        let other = delta > 0 ? donor(for: index) : recipient(for: index)
      else { return }
      stops[index].nights += delta > 0 ? 1 : -1
      stops[other].nights += delta > 0 ? -1 : 1
    }
  }
  public func canShiftNight(at index: Int, by delta: Int) -> Bool {
    guard stops.count > 1, stops.indices.contains(index), delta != 0 else { return false }
    return delta > 0 ? donor(for: index) != nil : stops[index].nights > nightRange.lowerBound
  }
  private func donor(for index: Int) -> Int? {
    let nearest = Array(stops.indices.dropFirst(index + 1)) + stops.indices.prefix(index).reversed()
    return nearest.first { stops[$0].nights > nightRange.lowerBound }
  }
  private func recipient(for index: Int) -> Int? {
    index + 1 < stops.count ? index + 1 : index > 0 ? index - 1 : nil
  }
  /// Keeps nights within range after the route changes and moves a stale step back into the flow.
  public mutating func reconcileRoute() {
    for index in stops.indices {
      stops[index].nights = min(max(stops[index].nights, nightRange.lowerBound), nightRange.upperBound)
    }
    if !flowSteps.contains(step) { step = flowSteps.contains(2) ? 2 : 1 }
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
    guard step != 6, flowSteps.contains(target), Self.rank(target) < Self.rank(step) else { return }
    step = target
  }
  /// Leaves from `origin`, making its currency home; the currency step can still change it.
  public mutating func setOrigin(_ origin: TripOrigin) {
    self.origin = origin
    if let currency = origin.currency, CurrencyMetadata.codes.contains(currency) {
      self.currency = currency
    }
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
      stops.allSatisfy({ (0...Self.maximumNights).contains($0.nights) }), nights <= Self.maximumNights,
      stops.count == 1 || stops.allSatisfy({ $0.nights > 0 })
    else { throw MoneyError.invalid }
    let layout = ItineraryLayout(startsOn: startsOn, stops: stops)
    return TripSnapshot(
      name: tripName, startsOn: startsOn, timeZone: stops.first?.resolvedTimeZone ?? timeZone,
      homeCurrency: currency,
      budgetMinor: String(try Money.parse(budget, currency: currency)), origin: origin,
      ownerTravellerId: owner.id, currentTravellerId: owner.id, travellers: travellers,
      stops: stops, days: layout.days, legs: layout.legs())
  }
}
