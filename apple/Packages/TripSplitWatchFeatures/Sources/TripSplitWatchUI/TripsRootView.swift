import SwiftUI
import TripSplitDomain
import TripSplitWatchDesign
import TripSplitWatchModel

/// The watch's launch screen: the trip you're on, upcoming departures and a passport page
/// of past trips. Shows the empty state until the phone has shared a trip. Complications,
/// Smart Stack buttons and notifications open it at a `WatchLink`.
public struct TripsRootView: View {
  @Environment(WatchModel.self) private var model
  @Environment(\.isLuminanceReduced) private var dimmed
  @State private var path: [TripRoute] = []
  @State private var sheet: TripsSheet?
  private let links: WatchLinkInbox

  public init(links: WatchLinkInbox = .shared) {
    self.links = links
  }

  public var body: some View {
    NavigationStack(path: $path) {
      Group {
        if let moment = model.moment {
          MomentView(moment: moment)
            .transition(.opacity)
        } else if model.timeline.isEmpty {
          NoTripsView()
        } else {
          TripsList(sheet: $sheet)
        }
      }
      .navigationDestination(for: TripRoute.self) { TripDestination(route: $0) }
      // The wordmark, in the accent, as in the design. It's the title rather than a leading
      // item so the time, which the profile button moves to the left, stays above it. The
      // passport stamp and Always On leave the time on its own.
      .navigationTitle {
        if !dimmed, !(model.moment?.isStamp ?? false) {
          Text("TripSplit")
            .watchFont(15, .black)
            .foregroundStyle(WatchTheme.accentText)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .toolbar {
        // Settings sit behind the profile button, top right, as on the phone.
        if !dimmed, model.moment == nil {
          ToolbarItem(placement: .topBarTrailing) {
            ProfileButton { sheet = .settings }
          }
        }
      }
    }
    .tint(WatchTheme.accentText)
    // H3 · Always On: everything dims to about half, values stay readable.
    .opacity(dimmed ? 0.55 : 1)
    .sheet(item: $sheet) { sheet in
      switch sheet {
      case .convert: QuickConvertView(model: model)
      case .log(let trip): LogExpenseView(model: model, trip: trip.flatMap(model.trip))
      case .settings: WatchSettingsView(model: model)
      }
    }
    .onOpenURL { url in
      if let link = WatchLink(url: url) { open(link) }
    }
    .onChange(of: links.pending, initial: true) {
      if let link = links.take() { open(link) }
    }
  }

  private func open(_ link: WatchLink) {
    switch link {
    case .trips:
      sheet = nil
      path = []
    case .trip(let id, let page):
      sheet = nil
      path = model.trip(id) == nil ? [] : [.trip(id, page: page)]
    case .convert:
      sheet = .convert
    case .localConvert:
      // Just landed: convert from the new local currency, not a pair picked earlier.
      model.followTripCurrency()
      sheet = .convert
    case .log(let trip):
      sheet = .log(trip: trip)
    case .day(let trip, let day):
      sheet = nil
      path = model.trip(trip) == nil ? [] : [.trip(trip, page: .days), .day(trip: trip, day: day)]
    }
  }
}

/// The sheets the trips list opens, also opened by links.
enum TripsSheet: Hashable, Identifiable {
  case convert
  case log(trip: String?)
  case settings
  var id: Self { self }
}

struct TripsList: View {
  @Environment(WatchModel.self) private var model
  @Environment(\.isLuminanceReduced) private var dimmed
  @Binding var sheet: TripsSheet?

  var body: some View {
    let timeline = model.timeline
    let today = CivilDate.string(model.now, timeZone: TimeZone.current.identifier)
    ScrollView {
      VStack(alignment: .leading, spacing: 6) {
        if let trip = timeline.now.first, let conversion = model.quickConversion(for: trip) {
          Button {
            sheet = .convert
          } label: {
            ConvertCapsule(conversion: conversion)
          }
          .buttonStyle(.plain)
          .accessibilityHint("Opens quick convert")
        }
        ForEach(timeline.now) { trip in
          NavigationLink(value: TripRoute.trip(trip.id)) {
            NowCard(trip: trip, now: model.now)
          }
          .buttonStyle(.plain)
        }
        if !timeline.upcoming.isEmpty {
          SectionLabel("Departures", symbol: "airplane", colour: WatchTheme.amber)
          ForEach(timeline.upcoming) { trip in
            NavigationLink(value: TripRoute.trip(trip.id)) {
              DepartureRow(trip: trip, today: today)
            }
            .buttonStyle(.plain)
          }
        }
        if !timeline.past.isEmpty {
          SectionLabel("Been there", colour: WatchTheme.ink2)
          PassportPage(trips: timeline.past, total: timeline.pastTotal)
        }
      }
      .padding(.horizontal, 7)
    }
    .toolbar {
      if !dimmed, !timeline.now.isEmpty || !timeline.upcoming.isEmpty {
        ToolbarItemGroup(placement: .bottomBar) {
          Spacer()
          LogButton { sheet = .log(trip: nil) }
        }
      }
    }
  }
}

/// The accent "+" that opens Log expense, from Trips or inside a trip.
struct LogButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "plus")
        .font(.system(size: 17, weight: .bold))
        .foregroundStyle(.white)
    }
    .buttonStyle(.glassProminent)
    .buttonBorderShape(.circle)
    .tint(WatchTheme.accent)
    .accessibilityLabel("Log expense")
  }
}

/// The profile button on Trips, top right, that opens Settings.
struct ProfileButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "person.fill")
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(.white)
    }
    .buttonBorderShape(.circle)
    // Neutral glass, so it doesn't compete with the accent "+".
    .tint(WatchTheme.card2)
    .accessibilityLabel("Settings")
  }
}

/// Watch-only settings, from the profile button on Trips.
struct WatchSettingsView: View {
  @Bindable var model: WatchModel

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 6) {
          StepTitle("Settings")
          toggles
            .padding(.horizontal, 6)
        }
      }
      .containerBackground(.black, for: .navigation)
    }
    // Toolbar buttons sit on the card fill rather than the accent, as in the design.
    .tint(WatchTheme.card2)
  }

  @ViewBuilder private var toggles: some View {
    Toggle(isOn: $model.preferences.hidesAmountsWhenWristDown) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Hide amounts")
          .watchFont(14, .semibold)
        Text("On the watch face when your wrist is down")
          .watchFont(11, .semibold)
          .foregroundStyle(WatchTheme.ink2)
      }
    }
    .tint(WatchTheme.accent)
    .padding(.vertical, 4)
    Toggle(isOn: $model.preferences.eveningWrap) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Evening wrap")
          .watchFont(14, .semibold)
        Text("At 21:30, what the day came to and anything to add")
          .watchFont(11, .semibold)
          .foregroundStyle(WatchTheme.ink2)
      }
    }
    .tint(WatchTheme.accent)
    .padding(.vertical, 4)
  }
}
