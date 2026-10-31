import Foundation

struct Destination: Identifiable, Hashable, Sendable {
  var countryCode: String
  var country: String
  var city: String
  var currency: String
  var latitude: Double
  var longitude: Double
  var id: String { countryCode + city }
  var flag: String { countryCode.flag }
  func stop(nights: Int = 3) -> Stop {
    .init(
      countryCode: countryCode, place: city, nights: nights, currency: currency, latitude: latitude,
      longitude: longitude)
  }
  static let all: [Destination] = [
    .init(
      countryCode: "PT", country: "Portugal", city: "Lisbon", currency: "EUR", latitude: 38.7223,
      longitude: -9.1393),
    .init(
      countryCode: "PT", country: "Portugal", city: "Porto", currency: "EUR", latitude: 41.1579,
      longitude: -8.6291),
    .init(
      countryCode: "ES", country: "Spain", city: "Seville", currency: "EUR", latitude: 37.3891,
      longitude: -5.9845),
    .init(
      countryCode: "ES", country: "Spain", city: "Barcelona", currency: "EUR", latitude: 41.3874,
      longitude: 2.1686),
    .init(
      countryCode: "FR", country: "France", city: "Paris", currency: "EUR", latitude: 48.8566,
      longitude: 2.3522),
    .init(
      countryCode: "IT", country: "Italy", city: "Rome", currency: "EUR", latitude: 41.9028,
      longitude: 12.4964),
    .init(
      countryCode: "JP", country: "Japan", city: "Tokyo", currency: "JPY", latitude: 35.6762,
      longitude: 139.6503),
    .init(
      countryCode: "JP", country: "Japan", city: "Kyoto", currency: "JPY", latitude: 35.0116,
      longitude: 135.7681),
    .init(
      countryCode: "GB", country: "United Kingdom", city: "London", currency: "GBP",
      latitude: 51.5074, longitude: -0.1278),
    .init(
      countryCode: "US", country: "United States", city: "New York", currency: "USD",
      latitude: 40.7128, longitude: -74.006),
    .init(
      countryCode: "AU", country: "Australia", city: "Sydney", currency: "AUD", latitude: -33.8688,
      longitude: 151.2093),
    .init(
      countryCode: "TH", country: "Thailand", city: "Bangkok", currency: "THB", latitude: 13.7563,
      longitude: 100.5018),
    .init(
      countryCode: "ID", country: "Indonesia", city: "Bali", currency: "IDR", latitude: -8.4095,
      longitude: 115.1889),
    .init(
      countryCode: "VN", country: "Vietnam", city: "Hanoi", currency: "VND", latitude: 21.0278,
      longitude: 105.8342),
    .init(
      countryCode: "MA", country: "Morocco", city: "Marrakesh", currency: "MAD", latitude: 31.6295,
      longitude: -7.9811),
    .init(
      countryCode: "GR", country: "Greece", city: "Athens", currency: "EUR", latitude: 37.9838,
      longitude: 23.7275),
    .init(
      countryCode: "CH", country: "Switzerland", city: "Zermatt", currency: "CHF",
      latitude: 46.0207, longitude: 7.7491),
    .init(
      countryCode: "CA", country: "Canada", city: "Vancouver", currency: "CAD", latitude: 49.2827,
      longitude: -123.1207),
    .init(
      countryCode: "MX", country: "Mexico", city: "Mexico City", currency: "MXN", latitude: 19.4326,
      longitude: -99.1332),
    .init(
      countryCode: "KR", country: "South Korea", city: "Seoul", currency: "KRW", latitude: 37.5665,
      longitude: 126.978),
    .init(
      countryCode: "AE", country: "United Arab Emirates", city: "Dubai", currency: "AED",
      latitude: 25.2048, longitude: 55.2708),
    .init(
      countryCode: "NZ", country: "New Zealand", city: "Auckland", currency: "NZD",
      latitude: -36.8509, longitude: 174.7645),
  ]
}
struct OnboardingDraft: Codable, Equatable, Sendable {
  var createdTripID: String?
  var step = 0
  var stops: [Stop] = []
  var startsOn = CivilDate.today(timeZone: TimeZone.current.identifier)
  var timeZone = TimeZone.current.identifier
  var travellers = [Traveller(name: "You")]
  var currency = "GBP"
  var budget = "2400"
  var name = ""
  var nights: Int { stops.reduce(0) { $0 + $1.nights } }
  var tripName: String {
    name.trimmingCharacters(in: .whitespaces).isEmpty
      ? Array(NSOrderedSet(array: stops.map(\.place))).compactMap { $0 as? String }.joined(
        separator: ", ") : name
  }
  func makeTrip() throws -> TripSnapshot {
    guard let owner = travellers.first, !stops.isEmpty else { throw MoneyError.invalid }
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
      name: tripName, startsOn: startsOn, timeZone: timeZone, homeCurrency: currency,
      budgetMinor: String(try Money.parse(budget, currency: currency)), ownerTravellerId: owner.id,
      currentTravellerId: owner.id, travellers: travellers, stops: stops, days: days, legs: legs)
  }
}
