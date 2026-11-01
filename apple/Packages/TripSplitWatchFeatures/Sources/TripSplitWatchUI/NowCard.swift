import SwiftUI
import TripSplitDomain
import TripSplitWatchDesign

/// The trip happening now: name, where you are today and how far through the trip you are.
struct NowCard: View {
  let trip: TripSnapshot
  let now: Date

  private var flags: String {
    trip.stops.map(\.flag).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
      .joined()
  }

  var body: some View {
    let day = trip.currentDay(at: now)
    VStack(alignment: .leading, spacing: 3) {
      HStack(alignment: .center) {
        Text("NOW")
          .watchFont(10, .black)
          .tracking(em: 0.08, size: 10)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(.white.opacity(0.22), in: .rect(cornerRadius: 6))
        Spacer(minLength: 4)
        Text(flags).font(.system(size: 15)).tracking(2).accessibilityHidden(true)
      }
      Text(trip.name)
        .watchFont(16, .black)
        .lineLimit(3)
        .padding(.top, 3)
      if let day {
        let place = trip.stop(for: .init(kind: .day, id: day.id))?.place
        Text(
          ["Day \(trip.dayNumber(of: day)) of \(trip.days.count)", place]
            .compactMap(\.self).joined(separator: " · ")
        )
        .watchFont(12, .heavy)
        .foregroundStyle(.white.opacity(0.88))
        .lineLimit(1)
        Meter(value: trip.progress(through: day), track: .white.opacity(0.28))
          .padding(.top, 5)
      }
    }
    .foregroundStyle(.white)
    .padding(.top, 11)
    .padding(.horizontal, 13)
    .padding(.bottom, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(WatchTheme.accent, in: .rect(cornerRadius: 22))
    .accessibilityElement(children: .combine)
  }
}
