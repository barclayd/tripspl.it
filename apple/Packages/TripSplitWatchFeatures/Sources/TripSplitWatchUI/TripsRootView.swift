import SwiftUI
import TripSplitDomain
import TripSplitWatchDesign
import TripSplitWatchModel

/// The watch's launch screen: the trip you're on, upcoming departures and a passport page
/// of past trips. Shows the empty state until the phone has shared a trip.
public struct TripsRootView: View {
  @Environment(WatchModel.self) private var model

  public init() {}

  public var body: some View {
    NavigationStack {
      Group {
        if model.timeline.isEmpty {
          NoTripsView()
        } else {
          TripsList()
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
  }
}

struct TripsList: View {
  enum Sheet: Identifiable {
    case convert, log
    var id: Self { self }
  }

  @Environment(WatchModel.self) private var model
  @State private var sheet: Sheet?

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
      if !timeline.now.isEmpty || !timeline.upcoming.isEmpty {
        ToolbarItemGroup(placement: .bottomBar) {
          Spacer()
          LogButton { sheet = .log }
        }
      }
    }
    .sheet(item: $sheet) { sheet in
      switch sheet {
      case .convert: QuickConvertView(model: model)
      case .log: LogExpenseView(model: model)
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
