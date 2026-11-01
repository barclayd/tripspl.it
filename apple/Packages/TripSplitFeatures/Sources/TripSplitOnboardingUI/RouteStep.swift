import SwiftUI
import TripSplitAppleAdapters
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain

/// A step's heading: 28/800 with a quieter line of help beneath.
struct StepTitle: View {
  init(_ title: String, _ subtitle: String) {
    self.title = title
    self.subtitle = subtitle
  }
  let title: String
  let subtitle: String
  @Environment(\.onboardingWide) private var wide
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .typeface(wide ? 32 : 28, .heavy, tracking: -0.03, relativeTo: .largeTitle, maximum: 1.3)
        .foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
      Text(subtitle).typeface(wide ? 16 : 15, .semibold, relativeTo: .subheadline, maximum: 1.4)
        .foregroundStyle(Theme.secondary)
    }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
  }
}

/// Step 1: pick countries in visiting order. Tapping a chip again visits it again.
struct RouteStep: View {
  let focus: FocusState<Bool>.Binding
  @Environment(AppModel.self) private var model
  @State private var query = ""
  @State private var mapSearch = DestinationSearch()
  @State private var searchedMapQuery: String?
  @State private var addingCustom = false
  @State private var currencyDestination: Destination?

  private static let suggested = [
    "PT", "ES", "FR", "IT", "GR", "HR", "CH", "IS", "JP", "TH", "VN", "ID", "US", "MX", "MA", "AU",
  ].compactMap(Destination.country)

  /// Places in the route that aren't suggestions, such as a city found by searching, so coming
  /// back here still shows everything you picked.
  private var picked: [Destination] {
    var seen = Set(Self.suggested.map(\.id))
    return model.onboarding.stops.map(Destination.init(stop:)).filter { seen.insert($0.id).inserted }
  }

  private var searchQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var full: Bool { model.onboarding.stops.count >= OnboardingDraft.maximumStops }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      StepTitle("Where are you off to?", "Add each country in the order you’ll visit.")
      searchField
      if searchQuery.isEmpty {
        chips(picked + Self.suggested)
      } else {
        let results = Destination.search(searchQuery, limit: 40)
        if results.isEmpty {
          Text("No matching countries or cities.")
            .typeface(14, .semibold, relativeTo: .subheadline).foregroundStyle(Theme.secondary)
        } else {
          chips(results)
        }
        mapsResults
      }
      Button {
        focus.wrappedValue = false
        addingCustom = true
      } label: {
        Label("Can’t find your destination?", systemImage: "mappin.and.ellipse")
          .typeface(14, .heavy, relativeTo: .subheadline, maximum: 1.4)
          .foregroundStyle(Theme.accentText).frame(minHeight: 44)
      }.buttonStyle(.plain).disabled(full).opacity(full ? 0.4 : 1)
        .accessibilityIdentifier("onboarding.addCustom")
    }
    .onChange(of: query) { _, _ in
      mapSearch.cancel()
      searchedMapQuery = nil
    }
    .onDisappear { mapSearch.cancel() }
    .sheet(isPresented: $addingCustom) {
      CustomDestinationSheet(isSelected: { visits($0) > 0 }, onSelect: add)
    }
    .sheet(item: $currencyDestination) { destination in
      DestinationCurrencySheet(destination: destination) { currency in
        var confirmed = destination
        confirmed.currency = currency
        add(confirmed)
      }
    }
  }

  private var searchField: some View {
    HStack(spacing: 10) {
      Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .bold))
        .foregroundStyle(Theme.tertiary).accessibilityHidden(true)
      TextField("Search cities or countries", text: $query)
        .typeface(16, .bold, relativeTo: .body, maximum: 1.4).foregroundStyle(Theme.ink)
        .focused(focus).textInputAutocapitalization(.words).autocorrectionDisabled()
        .submitLabel(.search).onSubmit { focus.wrappedValue = false }
        .accessibilityIdentifier("onboarding.search")
        .accessibilityHint("Search countries and cities, or Apple Maps for anywhere else")
      if !query.isEmpty {
        Button {
          query = ""
        } label: {
          Image(systemName: "xmark.circle.fill").font(.system(size: 17))
            .foregroundStyle(Theme.tertiary).frame(width: 32, height: 44)
        }.buttonStyle(.plain).accessibilityLabel("Clear search")
      }
    }
    .padding(.horizontal, 16).frame(minHeight: 50)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.key))
  }

  private func chips(_ destinations: [Destination]) -> some View {
    FlowLayout(spacing: 8) {
      ForEach(destinations) { destination in
        chip(destination)
      }
    }
  }

  private func chip(_ destination: Destination) -> some View {
    let count = visits(destination)
    let selected = count > 0
    return Button {
      select(destination)
    } label: {
      HStack(spacing: 7) {
        Text(destination.flag).font(.system(size: 20))
        Text(destination.city).typeface(14.5, .heavy, relativeTo: .subheadline, maximum: 1.4)
          .lineLimit(1)
        if !destination.isCountry {
          Text(destination.country).typeface(12.5, .bold, relativeTo: .caption, maximum: 1.4)
            .foregroundStyle(Theme.tertiary).lineLimit(1)
        }
        if selected {
          Text("\(count)").typeface(11, .black, relativeTo: .caption2, maximum: 1.3)
            .monospacedDigit().foregroundStyle(Theme.accentInk)
            .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
            .background(Theme.accent, in: Capsule())
            .bump(on: count).transition(.scale.combined(with: .opacity))
        }
      }
      .foregroundStyle(selected ? Theme.accentText : Theme.ink)
      .padding(.top, 9).padding(.trailing, 13).padding(.bottom, 9).padding(.leading, 10)
      .background(selected ? Theme.accentSoft : Theme.surface, in: Capsule())
      .overlay { Capsule().strokeBorder(Theme.accent, lineWidth: selected ? 2 : 0) }
      .contentShape(Capsule())
      .opacity(full && !selected ? 0.45 : 1)
    }
    .buttonStyle(PressStyle(scale: 0.93))
    .animation(Motion.popIn, value: count)
    .contextMenu {
      if selected {
        Button("Remove one", systemImage: "minus.circle", role: .destructive) {
          removeOne(destination)
        }
      }
    }
    .accessibilityLabel("\(destination.city), \(destination.secondaryLabel)")
    .accessibilityValue(
      selected ? (count == 1 ? "In your route" : "In your route \(count) times") : "")
    .accessibilityHint(full ? "Your route is full" : "Adds a stop to your route")
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityActions {
      if selected {
        Button("Remove one") { removeOne(destination) }
      }
    }
    .accessibilityIdentifier("onboarding.destination.\(destination.id)")
  }

  @ViewBuilder private var mapsResults: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button(action: searchMaps) {
        Label("Search Apple Maps for “\(searchQuery)”", systemImage: "map")
          .typeface(14, .heavy, relativeTo: .subheadline, maximum: 1.4)
          .foregroundStyle(Theme.accentText).lineLimit(1).frame(minHeight: 44)
      }.buttonStyle(.plain)
        .disabled(mapSearch.isSearching || full).opacity(full ? 0.4 : 1)
        .accessibilityIdentifier("onboarding.searchMaps")
      if searchedMapQuery == searchQuery {
        if mapSearch.isSearching {
          ProgressView("Searching Apple Maps…").tint(Theme.secondary)
        } else if let error = mapSearch.error {
          Text(error).typeface(13, .semibold, relativeTo: .footnote).foregroundStyle(Theme.bad)
        } else if mapSearch.matches.isEmpty {
          Text("No places found. Try adding the country to your search.")
            .typeface(13, .semibold, relativeTo: .footnote).foregroundStyle(Theme.secondary)
        } else {
          chips(mapSearch.matches)
        }
      }
    }
  }

  // MARK: Route changes

  private func visits(_ destination: Destination) -> Int {
    model.onboarding.stops.filter(destination.matches).count
  }

  private func select(_ destination: Destination) {
    guard !full else {
      Haptics.error()
      return
    }
    if destination.requiresCurrencySelection {
      focus.wrappedValue = false
      currencyDestination = destination
    } else {
      add(destination)
    }
  }

  private func add(_ destination: Destination) {
    guard !full, CurrencyMetadata.codes.contains(destination.currency) else {
      Haptics.error()
      return
    }
    Haptics.lightImpact()
    withAnimation(Motion.spring) {
      model.onboarding.stops.append(destination.stop())
      reconcile()
    }
  }

  private func removeOne(_ destination: Destination) {
    guard let index = model.onboarding.stops.lastIndex(where: destination.matches)
    else { return }
    Haptics.lightImpact()
    withAnimation(Motion.spring) {
      model.onboarding.stops.remove(at: index)
      reconcile()
    }
  }

  private func reconcile() {
    model.onboarding.reconcileRoute()
  }

  private func searchMaps() {
    let requested = searchQuery
    guard !requested.isEmpty, !mapSearch.isSearching, !full else { return }
    focus.wrappedValue = false
    searchedMapQuery = requested
    Task { await mapSearch.searchMaps(requested) }
  }
}
