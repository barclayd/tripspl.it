import SwiftUI
import TripSplitAppleAdapters
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain

/// Step 2: where the trip sets off from and comes home to, from the current location or a search.
struct LeavingFromStep: View {
  let focus: FocusState<Bool>.Binding
  /// Whether the origin came from the current location, which ticks the location card rather
  /// than a chip. Held by the flow so it survives stepping forward and back.
  @Binding var nearby: Bool
  @Environment(AppModel.self) private var model
  @Environment(\.openURL) private var openURL
  @State private var query = ""
  @State private var here = CurrentPlace()
  @State private var failure: CurrentPlace.Outcome?
  @State private var mapSearch = DestinationSearch()
  @State private var searchedMapQuery: String?

  private let popular = Destination.origins(region: Locale.current.region?.identifier)
  private var origin: TripOrigin? { model.onboarding.origin }
  private var searchQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

  /// The popular places, led by a searched-for origin that isn't one of them, so coming back here
  /// still shows what you picked.
  private var shown: [Destination] {
    guard let origin, !nearby, !popular.contains(where: { isOrigin($0) }) else { return popular }
    return [Destination(origin: origin)] + popular
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      StepTitle("Where are you leaving from?", "So we can plan getting there and back.")
      locationCard
      PlaceSearchField(
        text: $query, focus: focus,
        hint: "Search cities and countries, or Apple Maps for anywhere else")
      VStack(alignment: .leading, spacing: 8) {
        Text(searchQuery.isEmpty ? "POPULAR" : "RESULTS")
          .typeface(12, .black, tracking: 0.1, relativeTo: .caption, maximum: 1.4)
          .foregroundStyle(Theme.tertiary).accessibilityAddTraits(.isHeader)
        if searchQuery.isEmpty {
          chips(shown, searching: false)
        } else {
          let results = Destination.search(searchQuery, limit: 14)
          if results.isEmpty {
            Text("No matching countries or cities.")
              .typeface(14, .semibold, relativeTo: .subheadline).foregroundStyle(Theme.secondary)
          } else {
            chips(results, searching: true)
          }
        }
      }
      if !searchQuery.isEmpty {
        MapsSearchResults(
          query: searchQuery, search: mapSearch, searched: searchedMapQuery == searchQuery,
          onSearch: searchMaps
        ) { chip($0, searching: true) }
      }
    }
    .onChange(of: query) { _, _ in
      mapSearch.cancel()
      searchedMapQuery = nil
    }
    .onDisappear {
      here.cancel()
      mapSearch.cancel()
    }
    #if DEBUG
      .task {
        if ProcessInfo.processInfo.arguments.contains("--onboarding-locate"), !nearby { locate() }
      }
    #endif
  }

  // MARK: Current location

  private var locationCard: some View {
    let highlighted = nearby && origin != nil
    let found = highlighted && !here.isLocating
    return Button(action: locate) {
      HStack(spacing: 12) {
        LocationTile(pulsing: here.isLocating)
        VStack(alignment: .leading, spacing: 1) {
          Text(cardTitle).typeface(16, .heavy, tracking: -0.01, relativeTo: .headline, maximum: 1.4)
          Text(cardSubtitle).typeface(13, .semibold, relativeTo: .footnote, maximum: 1.4)
            .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if found {
          Image(systemName: "checkmark").font(.system(size: 12, weight: .black))
            .foregroundStyle(Theme.accentInk).frame(width: 24, height: 24)
            .background(Theme.accent, in: Circle())
            .transition(.scale(scale: 0.3).combined(with: .opacity))
        }
      }
      .foregroundStyle(highlighted ? Theme.accentText : Theme.ink)
      .padding(.top, 12).padding(.trailing, 14).padding(.bottom, 12).padding(.leading, 12)
      .background(
        highlighted ? Theme.accentSoft : Theme.surface, in: RoundedRectangle(cornerRadius: 18)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 18)
          .strokeBorder(Theme.accent, lineWidth: highlighted ? 2 : 0)
      }
      .contentShape(RoundedRectangle(cornerRadius: 18))
      .animation(Motion.popIn, value: found)
    }
    .buttonStyle(PressStyle(scale: 0.97))
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(highlighted ? .isSelected : [])
    .accessibilityHint(highlighted ? "Looks up your location again" : "")
    .accessibilityIdentifier("onboarding.currentLocation")
  }

  private var cardTitle: String {
    if here.isLocating { return "Finding you…" }
    if nearby, let origin { return "\(origin.flag) \(origin.place)" }
    return "Use my current location"
  }

  private var cardSubtitle: String {
    if here.isLocating { return "Checking your location" }
    if nearby, origin != nil { return "Near you · tap to refresh" }
    switch failure {
    case .denied: return "Location is off · tap for Settings"
    case .unavailable: return "Couldn’t find you · tap to try again"
    default: return "Quickest way to fill this in"
    }
  }

  private func locate() {
    guard !here.isLocating else { return }
    if failure == .denied, let settings = URL(string: UIApplication.openSettingsURLString) {
      openURL(settings)
      return
    }
    focus.wrappedValue = false
    Haptics.selection()
    Task {
      switch await here.locate() {
      case .found(let destination)?:
        failure = nil
        pick(destination, nearby: true)
      case let outcome?:
        failure = outcome
        Haptics.error()
      case nil:
        return
      }
    }
  }

  // MARK: Places

  private func chips(_ destinations: [Destination], searching: Bool) -> some View {
    FlowLayout(spacing: 8) {
      ForEach(destinations) { chip($0, searching: searching) }
    }
  }

  private func chip(_ destination: Destination, searching: Bool) -> some View {
    let selected = !nearby && isOrigin(destination)
    return Button {
      pick(destination, nearby: false)
    } label: {
      PlaceChip(destination: destination, selected: selected, showsCountry: searching)
    }
    .buttonStyle(PressStyle(scale: 0.93))
    .animation(Motion.popIn, value: selected)
    .accessibilityLabel("\(destination.city), \(destination.secondaryLabel)")
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier("onboarding.origin.\(destination.id)")
  }

  private func isOrigin(_ destination: Destination) -> Bool {
    guard let origin else { return false }
    return origin.countryCode == destination.countryCode
      && origin.place.compare(destination.city, options: [.caseInsensitive, .diacriticInsensitive])
        == .orderedSame
  }

  private func pick(_ destination: Destination, nearby: Bool) {
    here.cancel()
    mapSearch.cancel()
    focus.wrappedValue = false
    Haptics.lightImpact()
    withAnimation(Motion.spring) {
      model.onboarding.setOrigin(destination.origin)
      self.nearby = nearby
      query = ""
    }
  }

  private func searchMaps() {
    let requested = searchQuery
    guard !requested.isEmpty, !mapSearch.isSearching else { return }
    focus.wrappedValue = false
    searchedMapQuery = requested
    Task { await mapSearch.searchMaps(requested) }
  }
}

/// The accent tile with the location arrow, which pulses while the location is found.
private struct LocationTile: View {
  let pulsing: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    arrow
      .foregroundStyle(Theme.accentInk).frame(width: 42, height: 42)
      .background(Theme.accent, in: RoundedRectangle(cornerRadius: 13))
      .accessibilityHidden(true)
  }

  @ViewBuilder private var arrow: some View {
    let symbol = Image(systemName: "location.fill").font(.system(size: 19, weight: .semibold))
    if pulsing, !reduceMotion {
      symbol.phaseAnimator([1, 0.72]) { content, scale in
        content.scaleEffect(scale)
      } animation: { _ in
        .easeInOut(duration: 0.4)
      }
    } else {
      symbol
    }
  }
}
