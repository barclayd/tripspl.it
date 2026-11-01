import MapKit
import OSLog
import Observation
import TripSplitDomain
import TripSplitSync

/// Online results are transient and only fetched after an explicit Apple Maps search.
@MainActor @Observable package final class DestinationSearch {
  package init() {}
  private static let logger = Logger(
    subsystem: "it.tripspl.TripSplit", category: "DestinationSearch")
  package private(set) var matches: [Destination] = []
  package private(set) var isSearching = false
  package private(set) var error: String?
  @ObservationIgnored private var request: MKLocalSearch?
  @ObservationIgnored private var timeout: Task<Void, Never>?
  @ObservationIgnored private var generation = UUID()

  package func cancel() {
    generation = UUID()
    timeout?.cancel()
    timeout = nil
    request?.cancel()
    request = nil
    isSearching = false
    matches = []
    error = nil
  }

  package func searchMaps(_ text: String) async {
    cancel()
    let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard query.count >= 2 else { return }
    let token = generation
    let configuration = MKLocalSearch.Request()
    configuration.naturalLanguageQuery = String(query.prefix(200))
    configuration.resultTypes = [.address, .physicalFeature]
    let search = MKLocalSearch(request: configuration)
    request = search
    isSearching = true
    timeout = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(12)) } catch { return }
      guard let self, self.generation == token else { return }
      self.cancel()
      self.error = "Apple Maps took too long. Try again, or choose a saved destination."
    }
    do {
      let response = try await withTaskCancellationHandler {
        try await search.start()
      } onCancel: { [weak self] in
        Task { @MainActor in
          guard let self, self.generation == token else { return }
          self.cancel()
        }
      }
      guard generation == token, !Task.isCancelled else { return }
      var identifiers = Set<String>()
      matches = response.mapItems.compactMap { item in
        guard let code = item.addressRepresentations?.region?.identifier,
          let country = CountryMetadata.country(code),
          let name = item.name, !name.isEmpty
        else { return nil }
        let coordinate = item.location.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        let isCountry = country.searchNames.map(Destination.normalise).contains(
          Destination.normalise(name))
        let id =
          isCountry
          ? "country:" + country.code
          : "maps:\(country.code):\(name):\(coordinate.latitude):\(coordinate.longitude)"
        guard identifiers.insert(id).inserted else { return nil }
        return Destination(
          countryCode: country.code, country: country.name, city: name,
          currency: country.defaultCurrency ?? "", latitude: coordinate.latitude,
          longitude: coordinate.longitude, catalogID: id, isCountry: isCountry,
          detail: item.addressRepresentations?.cityWithContext(.full) ?? country.name,
          timeZone: item.timeZone?.identifier)
      }
      if matches.isEmpty {
        error =
          "No matching places found. Try a city with its country, or choose the country itself."
      }
    } catch {
      guard generation == token, !Task.isCancelled else { return }
      let failure = error as NSError
      Self.logger.error("Maps search failed: \(failure.domain, privacy: .public) (\(failure.code))")
      if failure.domain == MKErrorDomain, failure.code == MKError.Code.placemarkNotFound.rawValue {
        self.error =
          "No matching places found. Try a city with its country, or choose the country itself."
      } else {
        self.error =
          "Apple Maps isn’t available right now. Your saved countries and cities still work offline."
      }
    }
    guard generation == token else { return }
    timeout?.cancel()
    timeout = nil
    request = nil
    isSearching = false
  }
}
