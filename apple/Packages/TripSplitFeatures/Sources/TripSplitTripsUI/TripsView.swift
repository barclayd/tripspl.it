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
  var compact = false
  private var trips: [TripSnapshot] { model.store.trips }
  public var body: some View {
    if trips.isEmpty {
      content
    } else {
      content.refreshable { await model.sync.syncAll() }
    }
  }
  private var content: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        if !compact { header }
        if trips.isEmpty {
          empty
        } else if compact {
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
      }.pagePadding().padding(.bottom, 28)
    }
    .scrollBounceBehavior(.basedOnSize)
    .background(Theme.background)
    .toolbar {
      if compact {
        ToolbarItem(placement: .primaryAction) {
          Button("New trip", systemImage: "plus") { model.showOnboarding = true }
        }
        ToolbarItem {
          Button("Account & sync", systemImage: "person.crop.circle") { model.showSettings = true }
        }
      }
    }
  }
  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Trips").screenTitle(34).accessibilityAddTraits(.isHeader)
        Spacer()
        Button {
          model.showSettings = true
        } label: {
          if let me = trips.first.flatMap({ trip in
            trip.travellers.first { $0.id == trip.currentTravellerId }
          }) {
            Avatar(traveller: me, size: 36)
          } else {
            Image(systemName: "person.crop.circle.fill").font(.system(size: 34))
              .foregroundStyle(Theme.secondary)
          }
        }
        .buttonStyle(PressStyle(scale: 0.9))
        .accessibilityLabel("Account & sync")
      }
      if !trips.isEmpty {
        let flags = Self.flags(trips)
        let countries = Set(trips.flatMap { $0.stops.map(\.countryCode) }).count
        HStack(spacing: 8) {
          HStack(spacing: 3) {
            ForEach(Array(flags.enumerated()), id: \.offset) { index, flag in
              Text(flag).font(.system(size: 16)).popIn(delay: Double(index) * 0.06)
            }
          }
          .accessibilityHidden(true)
          Text(
            "\(trips.count) \(trips.count == 1 ? "trip" : "trips") · \(countries) \(countries == 1 ? "country" : "countries")"
          )
          .typeface(14, relativeTo: .subheadline).foregroundStyle(Theme.secondary)
          .lineLimit(1)
        }
      }
    }
    .padding(.top, 6)
  }
  /// Every flag across every trip once, in the order they were first visited.
  private static func flags(_ trips: [TripSnapshot]) -> [String] {
    var seen = Set<String>()
    return trips.flatMap(\.stops).map(\.flag).filter { seen.insert($0).inserted }
  }
  private var empty: some View {
    VStack(alignment: .leading, spacing: 28) {
      ZStack(alignment: .bottomTrailing) {
        VStack(alignment: .leading, spacing: 15) {
          Text("Your next trip").font(
            .system(size: 43, weight: .heavy, design: .default)
          ).tracking(-2)
        }.padding(26).frame(maxWidth: .infinity, alignment: .leading).background(
          Theme.surface, in: RoundedRectangle(cornerRadius: 28))
        Text("✈️").font(.system(size: 56)).rotationEffect(.degrees(-12)).offset(x: -10, y: 28)
      }.padding(.top, 12).padding(.bottom, 20)
      PrimaryButton(title: "Plan your first trip", symbol: "plus") { model.showOnboarding = true }
    }
  }
  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 24) {
      ForEach(TripSnapshot.Phase.allCases, id: \.self) { phase in
        let group = trips.filter { $0.phase == phase }
        if !group.isEmpty {
          VStack(alignment: .leading, spacing: 10) {
            Kicker(title: phase == .now ? "Now" : phase == .upcoming ? "Coming up" : "Been there")
            ForEach(group) { trip in
              Button {
                model.open(trip)
              } label: {
                HStack(spacing: 12) {
                  Text(trip.stops.first?.flag ?? "🌍").font(.title2).frame(width: 40, height: 44)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                  VStack(alignment: .leading, spacing: 4) {
                    Text(trip.name).font(.subheadline.weight(.heavy))
                    Text(
                      "\(CivilDate.display(trip.startsOn)) · \(trip.activeTravellers.count) \(trip.activeTravellers.count == 1 ? "person" : "people")"
                    ).font(.caption).foregroundStyle(Theme.secondary)
                  }
                  Spacer()
                  Text(Money.format(Ledger(trip).total, trip.homeCurrency, compact: true)).font(
                    .subheadline.weight(.bold))
                }.padding(12).background(
                  model.selectedTripID == trip.id ? Theme.accentSoft : .clear,
                  in: RoundedRectangle(cornerRadius: 16))
              }.buttonStyle(.plain)
            }
          }
        }
      }
    }
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
