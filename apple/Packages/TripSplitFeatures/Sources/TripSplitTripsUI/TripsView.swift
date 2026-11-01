import SwiftUI
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain
import TripSplitPersistence
import TripSplitSharedUI
import TripSplitSync

public struct TripsView: View {
  public init(compact: Bool = false) {
    self.compact = compact
  }
  @Environment(AppModel.self) private var model
  /// The open Duo's leading pane: a plain sidebar of every trip, with the trip beside it.
  var compact = false
  private var trips: [TripSnapshot] { model.store.trips }
  public var body: some View {
    if trips.isEmpty {
      FirstTripView(sidebar: compact) {
        if compact { sidebarHeader } else { header }
      }
    } else {
      content.refreshable { await model.sync.syncAll() }
    }
  }
  private var content: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        if compact { sidebarHeader } else { header }
        if compact {
          sidebar
        } else {
          if let now = trips.first(where: { $0.phase == .now }) {
            VStack(alignment: .leading, spacing: 14) {
              VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                  LiveDot()
                  Kicker(title: "Happening now")
                }
                CurrentTripCard(trip: now)
              }
              if now.showsHomeConverter { QuickConvertCard(trip: now) }
            }
          }
          DeparturesBoard(trips: trips)
          if trips.contains(where: { $0.phase == .past }) { PassportStamps(trips: trips) }
        }
      }
      .pagePadding().padding(.bottom, 28)
      .tripActionsContainer()
    }
    .scrollBounceBehavior(.basedOnSize)
    .scrollEdgeEffectHidden(compact, for: .top)
    .background(Theme.background)
  }
  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Trips").screenTitle(34).accessibilityAddTraits(.isHeader)
        Spacer()
        account(size: 36)
      }
      if !trips.isEmpty {
        let flags = Self.flags(trips)
        HStack(spacing: 8) {
          HStack(spacing: 3) {
            ForEach(Array(flags.enumerated()), id: \.offset) { index, flag in
              Text(flag).font(.system(size: 16)).popIn(delay: Double(index) * 0.06)
            }
          }
          .accessibilityHidden(true)
          Text(tally).typeface(14, relativeTo: .subheadline).foregroundStyle(Theme.secondary)
            .lineLimit(1)
        }
      }
    }
    .padding(.top, 6)
  }
  /// The sidebar's quieter header: title and tally, with the account tucked beside them.
  private var sidebarHeader: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Trips").screenTitle(26).accessibilityAddTraits(.isHeader)
        if !trips.isEmpty {
          Text(tally).typeface(12.5, .semibold, relativeTo: .caption).foregroundStyle(Theme.secondary)
            .lineLimit(1)
        }
      }
      Spacer()
      account(size: 30)
    }
    .padding(.top, 6).padding(.bottom, -6)
  }
  private var tally: String {
    let countries = Set(trips.flatMap { $0.stops.map(\.countryCode) }).count
    return
      "\(trips.count) \(trips.count == 1 ? "trip" : "trips") · \(countries) \(countries == 1 ? "country" : "countries")"
  }
  private func account(size: CGFloat) -> some View {
    Button {
      model.showSettings = true
    } label: {
      if let me = trips.first.flatMap({ trip in
        trip.travellers.first { $0.id == trip.currentTravellerId }
      }) {
        Avatar(traveller: me, size: size)
      } else {
        Image(systemName: "person.crop.circle.fill").font(.system(size: size - 2))
          .foregroundStyle(Theme.secondary)
      }
    }
    .buttonStyle(PressStyle(scale: 0.9))
    .accessibilityLabel("Account & sync")
  }
  /// Every flag across every trip once, in the order they were first visited.
  private static func flags(_ trips: [TripSnapshot]) -> [String] {
    var seen = Set<String>()
    return trips.flatMap(\.stops).map(\.flag).filter { seen.insert($0).inserted }
  }
  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 22) {
      ForEach(TripSnapshot.Phase.allCases, id: \.self) { phase in
        let group = trips.filter { $0.phase == phase }
        if !group.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            Text(phase == .now ? "NOW" : phase == .upcoming ? "COMING UP" : "BEEN THERE")
              .typeface(11.5, .heavy, tracking: 0.06, relativeTo: .caption, maximum: 1.4)
              .foregroundStyle(Theme.secondary).accessibilityAddTraits(.isHeader)
              .padding(.horizontal, 10).padding(.bottom, 4)
            ForEach(group) { trip in
              SidebarRow(trip: trip, selected: model.selectedTripID == trip.id) { model.open(trip) }
                .tripActions(trip)
            }
          }
        }
      }
    }
    .padding(.horizontal, -10)
    // A row swiped open for its actions slides under the column's edge rather than into the gutter.
    .clipped()
  }
}

/// One trip in the open Duo's sidebar: flag, name, dates and people, total.
private struct SidebarRow: View {
  let trip: TripSnapshot
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Text(trip.stops.first?.flag ?? "🌍").font(.system(size: 20))
          .frame(width: 40, height: 40)
          .background(
            selected ? Theme.surface : Theme.inset,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        VStack(alignment: .leading, spacing: 2) {
          Text(trip.name).typeface(15, .heavy, relativeTo: .subheadline, maximum: 1.4)
            .foregroundStyle(Theme.ink).lineLimit(1)
          Text(subtitle).typeface(12.5, relativeTo: .caption, maximum: 1.4)
            .foregroundStyle(Theme.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Text(Money.whole(Ledger(trip).total, trip.homeCurrency))
          .typeface(14, .heavy, relativeTo: .subheadline, maximum: 1.4).monospacedDigit()
          .foregroundStyle(Theme.ink).fixedSize()
      }
      .padding(10)
      .background(
        selected ? Theme.accentSoft : .clear,
        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(alignment: .topTrailing) {
        if trip.phase == .now {
          Text("NOW").typeface(10, .black, tracking: 0.06, relativeTo: .caption2, maximum: 1.3)
            .foregroundStyle(Theme.accentInk)
            .padding(.vertical, 3).padding(.horizontal, 8)
            .background(Theme.accent, in: Capsule())
            .offset(x: -8, y: -9)
            .accessibilityHidden(true)
        }
      }
      .contentShape(RoundedRectangle(cornerRadius: 16))
    }
    .buttonStyle(PressStyle(scale: 0.98))
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private var subtitle: String {
    let year = trip.phase == .past ? " \(CivilDate.display(trip.endsOn, format: "yyyy"))" : ""
    let people = trip.activeTravellers.count
    return
      "\(CivilDate.display(trip.startsOn)) – \(CivilDate.display(trip.endsOn))\(year) · \(people) \(people == 1 ? "person" : "people")"
  }
}

/// The "happening now" marker: a solid dot with a ring pulsing out of it.
private struct LiveDot: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var pulsing = false
  var body: some View {
    ZStack {
      if !reduceMotion {
        Circle().fill(Theme.accent)
          .scaleEffect(pulsing ? 2.6 : 1).opacity(pulsing ? 0 : 0.9)
      }
      Circle().fill(Theme.accent)
    }
    .frame(width: 8, height: 8)
    .accessibilityHidden(true)
    .onAppear {
      withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { pulsing = true }
    }
  }
}
