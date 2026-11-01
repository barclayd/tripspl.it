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

/// Step 1: pick cities and countries in visiting order. Tapping a chip again visits it again.
struct RouteStep: View {
  let focus: FocusState<Bool>.Binding
  @Environment(AppModel.self) private var model
  @State private var query = ""
  @State private var completer = PlaceCompleter()
  @State private var addingCustom = false
  @State private var currencyDestination: Destination?

  /// Places in the route that aren't suggestions, such as a city found by searching, so coming
  /// back here still shows everything you picked.
  private var picked: [Destination] {
    var seen = Set(Destination.popular.map(\.id))
    return model.onboarding.stops.map(Destination.init(stop:)).filter { seen.insert($0.id).inserted }
  }

  private var searchQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var full: Bool { model.onboarding.stops.count >= OnboardingDraft.maximumStops }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      StepTitle("Where are you off to?", "Add each city or country in the order you’ll visit.")
      PlaceSearchField(
        text: $query, focus: focus,
        hint: "Suggests countries and cities anywhere as you type")
      if searchQuery.isEmpty {
        chips(picked + Destination.popular)
      } else {
        PlaceResults(
          results: Destination.search(searchQuery, limit: 40), completer: completer,
          hint: full ? "Your route is full" : "Adds a stop to your route", disabled: full,
          chip: chip, onSuggestion: choose)
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
    .onChange(of: query) { _, query in completer.update(query) }
    .onDisappear { completer.cancel() }
    #if DEBUG
      .task {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--onboarding-query"),
          arguments.indices.contains(index + 1)
        {
          query = arguments[index + 1]
        }
      }
      // `--onboarding-choose` taps the first suggestion Apple Maps gives for the query.
      .onChange(of: completer.suggestions.first) { _, first in
        guard let first, ProcessInfo.processInfo.arguments.contains("--onboarding-choose"),
          completer.resolved.isEmpty
        else { return }
        choose(first)
      }
    #endif
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
      PlaceChip(destination: destination, selected: selected, count: count)
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
      model.onboarding.changeRoute { $0.append(destination.stop()) }
    }
  }

  private func removeOne(_ destination: Destination) {
    guard let index = model.onboarding.stops.lastIndex(where: destination.matches)
    else { return }
    Haptics.lightImpact()
    withAnimation(Motion.spring) {
      model.onboarding.changeRoute { $0.remove(at: index) }
    }
  }

  /// Looks a suggested place up, then adds it like any other chip.
  private func choose(_ suggestion: PlaceSuggestion) {
    guard !full else {
      Haptics.error()
      return
    }
    guard completer.resolving != suggestion.id else { return }
    Task {
      if let place = await completer.resolve(suggestion) {
        select(place)
      } else if completer.error != nil {
        Haptics.error()
      }
    }
  }
}
