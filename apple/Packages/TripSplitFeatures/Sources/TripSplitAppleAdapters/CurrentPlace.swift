import CoreLocation
import MapKit
import OSLog
import Observation
import TripSplitDomain

/// The city the person is in, looked up once and only when they ask, so the location prompt
/// never appears on its own.
@MainActor @Observable package final class CurrentPlace {
  package enum Outcome: Equatable, Sendable {
    case found(Destination)
    case denied
    case unavailable
  }

  package init() {}
  private nonisolated static let logger = Logger(
    subsystem: "it.tripspl.TripSplit", category: "CurrentPlace")
  package private(set) var isLocating = false
  @ObservationIgnored private var lookup: Task<Outcome, Never>?

  /// Asks for When-In-Use access the first time, then turns one fix into a city. Nil when a newer
  /// lookup or `cancel()` superseded this one.
  package func locate() async -> Outcome? {
    cancel()
    let task = Task { await Self.lookUp() }
    lookup = task
    isLocating = true
    let outcome = await task.value
    guard lookup == task, !task.isCancelled else { return nil }
    lookup = nil
    isLocating = false
    return outcome
  }

  package func cancel() {
    lookup?.cancel()
    lookup = nil
    isLocating = false
  }

  private enum Fix: Sendable {
    case at(CLLocationCoordinate2D)
    case denied
    case none
  }

  private static func lookUp() async -> Outcome {
    let status = CLLocationManager().authorizationStatus
    guard status != .denied, status != .restricted else { return .denied }
    let fix = await withTaskGroup(of: Fix.self) { group in
      group.addTask { await firstFix() }
      group.addTask {
        try? await Task.sleep(for: .seconds(15))
        return .none
      }
      let first = await group.next() ?? .none
      group.cancelAll()
      return first
    }
    switch fix {
    case .denied: return .denied
    case .none: return .unavailable
    case .at(let coordinate):
      let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
      guard let request = MKReverseGeocodingRequest(location: location) else { return .unavailable }
      do {
        let items = try await request.mapItems
        return items.lazy.compactMap(destination).first.map(Outcome.found) ?? .unavailable
      } catch {
        let failure = error as NSError
        logger.error(
          "Reverse geocoding failed: \(failure.domain, privacy: .public) (\(failure.code))")
        return .unavailable
      }
    }
  }

  private nonisolated static func firstFix() async -> Fix {
    let session = CLServiceSession(authorization: .whenInUse)
    defer { session.invalidate() }
    do {
      for try await update in CLLocationUpdate.liveUpdates() {
        if update.authorizationDenied || update.authorizationDeniedGlobally
          || update.authorizationRestricted
        {
          return .denied
        }
        if let location = update.location { return .at(location.coordinate) }
      }
    } catch {
      guard !(error is CancellationError) else { return .none }
      logger.error("Location updates failed: \((error as NSError).code)")
    }
    return .none
  }

  /// The catalogue's entry for the city when there is one, so popular chips and the pass agree;
  /// otherwise the city at about 10 km, since the trip origin is shared with everyone on it.
  ///
  /// Maps can name the district along with the city, e.g. "City of Westminster, London", so
  /// each part is tried against the catalogue and the city, which comes last, is kept otherwise.
  private static func destination(_ item: MKMapItem) -> Destination? {
    guard let code = item.addressRepresentations?.region?.identifier,
      let country = CountryMetadata.country(code),
      let named = item.addressRepresentations?.cityName
    else { return nil }
    let parts = named.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
    guard let city = parts.last else { return nil }
    let cities = Destination.all.filter { !$0.isCountry && $0.countryCode == country.code }
    for part in parts.reversed() {
      let name = Destination.normalise(part)
      if let known = cities.first(where: {
        ([$0.city] + $0.aliases).map(Destination.normalise).contains(name)
      }) {
        return known
      }
    }
    let coordinate = item.location.coordinate
    guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
    return Destination(
      countryCode: country.code, country: country.name, city: city,
      currency: country.defaultCurrency ?? "",
      latitude: (coordinate.latitude * 10).rounded() / 10,
      longitude: (coordinate.longitude * 10).rounded() / 10,
      catalogID: "here:\(country.code):\(city)")
  }
}
