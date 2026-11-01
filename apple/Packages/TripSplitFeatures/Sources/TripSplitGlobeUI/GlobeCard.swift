import SwiftUI
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain
import TripSplitPersistence

/// The globe's glass card: lifetime stats and trip chips, or the picked trip.
struct GlobeCard: View {
  @Environment(AppModel.self) private var model
  let trips: [TripSnapshot]
  let selected: TripSnapshot?

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      if let selected {
        TripSummary(trip: selected)
          .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
      } else {
        overview.transition(.opacity)
      }
    }
    .animation(Motion.rise, value: selected?.id)
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .foregroundStyle(.white)
    .glassEffect(
      .regular.tint(Color(hex: 0x181B21, opacity: 0.8)), in: RoundedRectangle(cornerRadius: 30))
    .shadow(color: .black.opacity(0.4), radius: 20, y: 20)
  }

  private var overview: some View {
    let all = model.store.trips
    let currency = model.displayCurrency
    return VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 8) {
        stat(
          "\(Set(all.flatMap { $0.stops.map(\.countryCode) }).count)", "Countries")
        stat("\(all.count)", "Trips")
        stat(model.spentSoFar(in: currency).map { Self.compact($0, currency) } ?? "—", "Spent so far")
      }
      ScrollView(.horizontal) {
        HStack(spacing: 8) {
          ForEach(trips) { trip in
            TripChip(trip: trip) { model.globeTripID = trip.id }
          }
          if trips.isEmpty {
            Text(emptyMessage).typeface(13.5, .semibold, relativeTo: .subheadline)
              .foregroundStyle(.white.opacity(0.6)).padding(.vertical, 9)
          }
        }
      }
      .scrollIndicators(.hidden)
      .contentMargins(.horizontal, 16, for: .scrollContent)
      .padding(.horizontal, -16)
    }
  }

  private var emptyMessage: String {
    switch model.globeFilter {
    case .all: "Trips you add land here"
    case .upcoming: "Nothing booked yet"
    case .past: "No trips behind you yet"
    }
  }

  private func stat(_ value: String, _ label: String) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(value).typeface(24, .heavy, tracking: -0.04, relativeTo: .title2)
        .contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.7)
      Text(label).typeface(12, .semibold, relativeTo: .caption).foregroundStyle(.white.opacity(0.6))
    }
    .padding(.horizontal, 4).padding(.vertical, 2)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  /// "Lisbon, Seville & Marrakesh" chips as "Lisbon".
  static func shortName(_ name: String) -> String {
    let cut = name.firstRange(of: ",").map(\.lowerBound) ?? name.firstRange(of: " &")?.lowerBound
    return cut.map { String(name[..<$0]) } ?? name
  }

  static func compact(_ minor: Int64, _ currency: String) -> String {
    let units = Double(minor) / Double(Money.factor(currency))
    return units.formatted(
      .currency(code: currency).notation(.compactName).precision(
        .fractionLength(units >= 1000 ? 1 : 0)))
  }
}

private struct TripChip: View {
  let trip: TripSnapshot
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack(spacing: 7) {
        Text(trip.uniqueFlags.joined()).font(.system(size: 18))
        Text(GlobeCard.shortName(trip.name)).typeface(13.5, .bold, relativeTo: .subheadline)
          .lineLimit(1)
      }
      .padding(.vertical, 9).padding(.leading, 10).padding(.trailing, 13)
      .background { Capsule().fill(Color.white.opacity(0.1)) }
    }
    .buttonStyle(PressStyle(scale: 0.94))
    .accessibilityLabel(trip.name)
  }
}

private struct TripSummary: View {
  @Environment(AppModel.self) private var model
  let trip: TripSnapshot

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 0) {
          Text(trip.uniqueFlags.joined(separator: " ")).font(.system(size: 22)).tracking(2)
            .accessibilityHidden(true)
          Text(trip.name).typeface(20, .heavy, tracking: -0.02, relativeTo: .title3)
            .padding(.top, 6)
          Text(subtitle).typeface(13.5, relativeTo: .subheadline)
            .foregroundStyle(.white.opacity(0.65)).padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Button {
          model.globeTripID = nil
        } label: {
          Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
            .frame(width: 32, height: 32)
            .background { Circle().fill(Color.white.opacity(0.12)) }
        }
        .buttonStyle(PressStyle(scale: 0.9))
        .accessibilityLabel("Show all trips")
      }
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 0) {
          Text(trip.phase == .upcoming ? "Planned so far" : "Total cost")
            .typeface(12, .semibold, relativeTo: .caption).foregroundStyle(.white.opacity(0.6))
          Text(total).typeface(28, .heavy, tracking: -0.04, relativeTo: .title)
            .lineLimit(1).minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, alignment: .leading)
        Button {
          model.open(trip)
        } label: {
          HStack(spacing: 6) {
            Text("Open trip")
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .heavy))
          }
          .typeface(15, .heavy, relativeTo: .headline)
          .foregroundStyle(Theme.accentInk)
          .frame(height: 46).padding(.horizontal, 20)
          .background { Capsule().fill(Theme.accent) }
        }
        .buttonStyle(PressStyle(scale: 0.95))
      }
    }
  }

  private var total: String {
    let factor = Money.factor(trip.homeCurrency)
    let whole = (Ledger(trip).total + factor / 2) / factor * factor
    return Money.format(whole, trip.homeCurrency, compact: true)
  }

  private var subtitle: String {
    let dates = "\(CivilDate.display(trip.startsOn)) – \(CivilDate.display(trip.endsOn))"
    switch trip.phase {
    case .now:
      return trip.dayProgress().map { "Happening now · Day \($0.day) of \($0.of)" }
        ?? "Happening now · \(dates)"
    case .upcoming:
      let days = CivilDate.days(from: trip.today, to: trip.startsOn)
      return "\(days == 1 ? "Tomorrow" : "In \(days) days") · \(dates)"
    case .past:
      return "\(dates) \(CivilDate.display(trip.endsOn, format: "yyyy"))"
    }
  }
}
