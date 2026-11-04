import SwiftUI
import TripSplitDomain
import TripSplitWatchDesign

/// An upcoming trip as a row on a departures board. The countdown turns green inside a week.
struct DepartureRow: View {
  let trip: TripSnapshot
  let today: String

  var body: some View {
    let days = trip.daysUntilStart(from: today)
    let date = CivilDate.display(trip.startsOn).uppercased()
    let people = trip.activeTravellers.count
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text(trip.stops.first?.flag ?? "✈️").font(.system(size: 17))
        SplitFlapText(trip.destination.uppercased())
      }
      HStack(spacing: 4) {
        Text("\(date)\(trip.hasCompanions ? " · \(people) PPL" : " · SOLO")").foregroundStyle(WatchTheme.ink2)
        Spacer(minLength: 4)
        Text("IN \(days)D").foregroundStyle(days <= 7 ? WatchTheme.good : WatchTheme.amber)
      }
      .boardFont(11, .heavy)
      .tracking(em: 0.04, size: 11)
      .lineLimit(1)
      .minimumScaleFactor(0.8)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(WatchTheme.board, in: .rect(cornerRadius: 18))
    .overlay {
      RoundedRectangle(cornerRadius: 18).strokeBorder(WatchTheme.boardEdge, lineWidth: 1)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "\(trip.name), \(CivilDate.display(trip.startsOn, format: "d MMMM")), "
        + "\(trip.hasCompanions ? "\(people) people" : "Solo trip"), "
        + "\(days == 1 ? "tomorrow" : "in \(days) days")")
  }
}
