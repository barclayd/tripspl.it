import SwiftUI
import TripSplitDomain
import TripSplitWatchDesign

/// Past trips as stamps on a ruled passport page, with the total spent across them.
struct PassportPage: View {
  let trips: [TripSnapshot]
  let total: (amount: Int64, currency: String)?

  /// Each pair of stamps adds a band of page; two stamps fill the first.
  private static let band: CGFloat = 112

  private var height: CGFloat {
    150 + CGFloat(max(0, (trips.count + 1) / 2 - 1)) * Self.band
  }

  private var footer: String {
    let stamps = trips.count == 1 ? "1 stamp" : "\(trips.count) stamps"
    guard let total else { return stamps }
    return "\(stamps) · \(Money.format(total.amount, total.currency, compact: true)) all in"
  }

  var body: some View {
    VStack(spacing: 6) {
      ZStack {
        RuledPaper()
        ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
          let isCircle = index.isMultiple(of: 2)
          let band = CGFloat(index / 2) * Self.band
          PassportStamp(
            trip: trip, isCircle: isCircle,
            ink: WatchTheme.stampInks[index % WatchTheme.stampInks.count],
            angle: isCircle ? (index / 2).isMultiple(of: 2) ? -12 : -7 : 9
          )
          .padding(isCircle ? .leading : .trailing, isCircle ? 12 : 10)
          .padding(.top, band + (isCircle ? 14 : 56))
          .frame(
            maxWidth: .infinity, maxHeight: .infinity,
            alignment: isCircle ? .topLeading : .topTrailing)
        }
      }
      .frame(height: height)
      .background(WatchTheme.paper)
      .clipShape(.rect(cornerRadius: 20))
      Text(footer)
        .watchFont(11, .heavy)
        .foregroundStyle(WatchTheme.ink2)
        .frame(maxWidth: .infinity)
    }
  }
}

/// Faint horizontal rules every 22pt, like a passport visa page.
struct RuledPaper: View {
  var body: some View {
    Canvas { context, size in
      var y: CGFloat = 22
      while y < size.height {
        context.fill(
          Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(WatchTheme.paperRule))
        y += 22
      }
    }
    .accessibilityHidden(true)
  }
}

struct PassportStamp: View {
  let trip: TripSnapshot
  let isCircle: Bool
  let ink: Color
  let angle: Double

  var body: some View {
    let city = trip.destination.uppercased()
    let date = CivilDate.display(trip.startsOn, format: "MMM yyyy").uppercased()
    VStack(spacing: 2) {
      Text(trip.stops.first?.flag ?? "✈️").font(.system(size: 18))
      Text(city)
        .font(.system(size: 10, weight: .black, design: .monospaced))
        .tracking(0.8)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
      Text(date).font(.system(size: 8, weight: .heavy, design: .monospaced))
    }
    .foregroundStyle(ink)
    .padding(.horizontal, 10)
    .frame(width: isCircle ? 86 : 92, height: isCircle ? 86 : 70)
    .overlay { outline(inset: 0, width: 2.5) }
    .overlay { outline(inset: 5.5, width: 1.5) }
    .rotationEffect(.degrees(angle))
    .opacity(0.9)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(trip.name), \(CivilDate.display(trip.startsOn, format: "MMMM yyyy"))")
  }

  @ViewBuilder private func outline(inset: CGFloat, width: CGFloat) -> some View {
    if isCircle {
      Circle().inset(by: inset).strokeBorder(ink, lineWidth: width)
    } else {
      RoundedRectangle(cornerRadius: 12).inset(by: inset).strokeBorder(ink, lineWidth: width)
    }
  }
}
