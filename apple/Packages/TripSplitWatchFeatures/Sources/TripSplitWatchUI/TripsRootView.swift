import SwiftUI
import TripSplitDomain
import TripSplitWatchDesign
import TripSplitWatchModel

/// The watch's launch screen: the trip you're on, upcoming departures and a passport page
/// of past trips. Shows the empty state until the phone has shared a trip. Complications,
/// Smart Stack buttons and notifications open it at a `WatchLink`.
public struct TripsRootView: View {
  @Environment(WatchModel.self) private var model
  @State private var path: [TripRoute] = []
  @State private var sheet: TripsSheet?
  private let links: WatchLinkInbox

  public init(links: WatchLinkInbox = .shared) {
    self.links = links
  }

  public var body: some View {
    NavigationStack(path: $path) {
      Group {
        if model.timeline.isEmpty {
          NoTripsView()
        } else {
          TripsList(sheet: $sheet)
        }
      }
      .navigationDestination(for: TripRoute.self) { TripDestination(route: $0) }
      .toolbar {
        // The wordmark sits level with the time, in the accent, as in the design.
        ToolbarItem(placement: .topBarLeading) {
          Text("TripSplit")
            .watchFont(15, .black)
            .foregroundStyle(WatchTheme.accentText)
            .fixedSize()
            .accessibilityAddTraits(.isHeader)
        }
      }
    }
    .tint(WatchTheme.accentText)
    .sheet(item: $sheet) { sheet in
      switch sheet {
      case .convert: QuickConvertView(model: model)
      case .log(let trip): LogExpenseView(model: model, trip: trip.flatMap(model.trip))
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
    case .log(let trip):
      sheet = .log(trip: trip)
    }
  }
}

/// The sheets the trips list opens, also opened by links.
enum TripsSheet: Hashable, Identifiable {
  case convert
  case log(trip: String?)
  var id: Self { self }
}

struct TripsList: View {
  @Environment(WatchModel.self) private var model
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
        WatchSettings()
      }
      .padding(.horizontal, 7)
    }
    .toolbar {
      if !timeline.now.isEmpty || !timeline.upcoming.isEmpty {
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

/// Watch-only settings, at the foot of the trips list.
struct WatchSettings: View {
  @Environment(WatchModel.self) private var model

  var body: some View {
    @Bindable var model = model
    SectionLabel("Settings", symbol: "gearshape", colour: WatchTheme.ink2)
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
  }
}
