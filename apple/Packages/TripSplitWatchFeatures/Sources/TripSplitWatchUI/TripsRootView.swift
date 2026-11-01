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
  @Environment(WatchModel.self) private var model

  var body: some View {
    let timeline = model.timeline
    let today = CivilDate.string(model.now, timeZone: TimeZone.current.identifier)
    ScrollView {
      VStack(alignment: .leading, spacing: 6) {
        if let trip = timeline.now.first, let conversion = model.quickConversion(for: trip) {
          ConvertCapsule(conversion: conversion)
        }
        ForEach(timeline.now) { trip in
          NowCard(trip: trip, now: model.now)
        }
        if !timeline.upcoming.isEmpty {
          SectionLabel("Departures", symbol: "airplane", colour: WatchTheme.amber)
          ForEach(timeline.upcoming) { trip in
            DepartureRow(trip: trip, today: today)
          }
        }
        if !timeline.past.isEmpty {
          SectionLabel("Been there", colour: WatchTheme.ink2)
          PassportPage(trips: timeline.past, total: timeline.pastTotal)
        }
      }
      .padding(.horizontal, 7)
    }
  }
}
