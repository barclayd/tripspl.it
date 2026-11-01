import MapKit
import OSLog
import Observation
import TripSplitDomain

/// Cities, regions and countries from Apple Maps as you type, for places the catalogue doesn't
/// know.
/// Suggestions are transient and only looked up in full once one is tapped.
@MainActor @Observable package final class PlaceCompleter {
  /// Leans towards places near the region's country without hiding anywhere else.
  ///
  /// Regions are kept as well as cities and countries, since Maps files some places, like Bath
  /// and Cardiff, as areas rather than towns, and somewhere like Tuscany or Bali is a fine stop.
  package init(region: String? = Locale.current.region?.identifier) {
    completer.resultTypes = .address
    completer.addressFilter = MKAddressFilter(
      including: [.locality, .subAdministrativeArea, .administrativeArea, .country])
    if let home = region.flatMap(CountryMetadata.country) {
      completer.region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: home.latitude, longitude: home.longitude),
        span: MKCoordinateSpan(latitudeDelta: 12, longitudeDelta: 12))
    }
    relay.owner = self
    completer.delegate = relay
  }

  private nonisolated static let logger = Logger(
    subsystem: "it.tripspl.TripSplit", category: "PlaceCompleter")
  private static let limit = 8

  /// What Maps suggests for the latest query, best first.
  package private(set) var suggestions: [PlaceSuggestion] = []
  /// Suggestions already looked up, so tapping one again doesn't ask Maps twice.
  package private(set) var resolved: [PlaceSuggestion.ID: Destination] = [:]
  /// Whether Maps has yet to answer the latest query.
  package private(set) var isPending = false
  /// The suggestion being looked up.
  package private(set) var resolving: PlaceSuggestion.ID?
  package private(set) var error: String?
  @ObservationIgnored private let completer = MKLocalSearchCompleter()
  @ObservationIgnored private let relay = Relay()
  @ObservationIgnored private var completions: [PlaceSuggestion.ID: MKLocalSearchCompletion] = [:]
  @ObservationIgnored private var lookup: MKLocalSearch?
  @ObservationIgnored private var generation = UUID()

  /// Asks Maps about what's typed so far; under two letters clears the suggestions instead.
  package func update(_ query: String) {
    let query = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
    guard query.count >= 2 else {
      cancel()
      return
    }
    cancelLookup()
    error = nil
    guard query != completer.queryFragment else { return }
    isPending = true
    completer.queryFragment = query
  }

  package func cancel() {
    cancelLookup()
    completer.cancel()
    completer.queryFragment = ""
    suggestions = []
    completions = [:]
    isPending = false
    error = nil
  }

  /// The suggestion as a place to visit, preferring the catalogue's own entry. Nil when the
  /// lookup failed, which sets `error`, or a newer query or `cancel()` superseded it.
  package func resolve(_ suggestion: PlaceSuggestion) async -> Destination? {
    if let known = resolved[suggestion.id] { return known }
    if suggestion.isCountry, let code = suggestion.countryCode,
      let country = Destination.country(code)
    {
      return country
    }
    guard let completion = completions[suggestion.id] else { return nil }
    cancelLookup()
    let token = generation
    let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
    lookup = search
    resolving = suggestion.id
    error = nil
    let timeout = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(10)) } catch { return }
      guard let self, self.generation == token else { return }
      self.lookup?.cancel()
    }
    defer { timeout.cancel() }
    var destination: Destination?
    do {
      let response = try await search.start()
      guard generation == token else { return nil }
      destination = response.mapItems.lazy.compactMap(Self.destination).first
    } catch {
      guard generation == token else { return nil }
      let failure = error as NSError
      Self.logger.error(
        "Place lookup failed: \(failure.domain, privacy: .public) (\(failure.code))")
    }
    lookup = nil
    resolving = nil
    guard let destination else {
      error = "Couldn’t find \(suggestion.name) on Apple Maps. Try again."
      return nil
    }
    resolved[suggestion.id] = destination
    return destination
  }

  private func cancelLookup() {
    generation = UUID()
    lookup?.cancel()
    lookup = nil
    resolving = nil
  }

  private static func destination(_ item: MKMapItem) -> Destination? {
    guard let place = Destination(mapItem: item) else { return nil }
    if place.isCountry { return Destination.country(place.countryCode) ?? place }
    return Destination.catalogued(city: place.city, countryCode: place.countryCode) ?? place
  }

  fileprivate func receive(_ results: [MKLocalSearchCompletion]) {
    var completions: [PlaceSuggestion.ID: MKLocalSearchCompletion] = [:]
    var shown: [PlaceSuggestion] = []
    var keys = Set<String>()
    for completion in results where shown.count < Self.limit {
      let suggestion = PlaceSuggestion(title: completion.title, subtitle: completion.subtitle)
      guard !suggestion.title.isEmpty, keys.insert(suggestion.key).inserted else { continue }
      completions[suggestion.id] = completion
      shown.append(suggestion)
    }
    self.completions = completions
    suggestions = shown
    isPending = false
  }

  fileprivate func fail(_ error: any Error) {
    let failure = error as NSError
    Self.logger.error(
      "Place suggestions failed: \(failure.domain, privacy: .public) (\(failure.code))")
    completions = [:]
    suggestions = []
    isPending = false
  }

  /// The completer's delegate, which MapKit calls on the main thread it was made on.
  @MainActor private final class Relay: NSObject, @preconcurrency MKLocalSearchCompleterDelegate {
    weak var owner: PlaceCompleter?

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
      owner?.receive(completer.results)
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
      owner?.fail(error)
    }
  }
}

extension PlaceCompleter {
  /// The suggestions that aren't already among the catalogue's results.
  package func suggestions(beyond shown: [Destination]) -> [PlaceSuggestion] {
    let ids = Set(shown.map(\.id))
    return suggestions.filter { suggestion in
      if let place = resolved[suggestion.id], ids.contains(place.id) { return false }
      return !shown.contains(where: suggestion.duplicates)
    }
  }
}
