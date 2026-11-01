import SwiftUI
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain

/// Past trips as rubber stamps on a ruled passport page, stamped in as they scroll into view.
struct PassportStamps: View {
  var trips: [TripSnapshot]
  @Environment(AppModel.self) private var model
  @State private var visible = false

  /// Most recent first.
  private var past: [TripSnapshot] {
    trips.filter { $0.phase == .past }.sorted { $0.startsOn > $1.startsOn }
  }

  var body: some View {
    let past = past
    VStack(alignment: .leading, spacing: 10) {
      Kicker(title: "Been there")
      VStack(spacing: 18) {
        HStack {
          Text("PASSPORT · VISAS")
          Spacer()
          Text("\(past.count) STAMP\(past.count == 1 ? "" : "S")")
        }
        .typeface(10, .black, tracking: 0.18, relativeTo: .caption2, maximum: 1.2)
        .foregroundStyle(Theme.paperInk)
        .accessibilityElement(children: .combine)
        VStack(spacing: 18) {
          ForEach(Array(stride(from: 0, to: past.count, by: 2)), id: \.self) { start in
            HStack(spacing: 0) {
              ForEach(start..<min(start + 2, past.count), id: \.self) { index in
                Spacer(minLength: 0)
                Button {
                  model.open(past[index])
                } label: {
                  Stamp(trip: past[index], index: index)
                }
                .buttonStyle(PressStyle(scale: 0.95))
                .tripActions(past[index], swipes: false)
                .stampIn(delay: 0.15 + Double(index) * 0.18, visible: visible)
              }
              Spacer(minLength: 0)
            }
          }
        }
      }
      .padding(.horizontal, 14).padding(.top, 16).padding(.bottom, 22)
      .background { RuledPaper() }
      .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
      .onScrollVisibilityChange(threshold: 0.2) { if $0 { visible = true } }
    }
  }
}

private struct RuledPaper: View {
  var body: some View {
    Canvas { context, size in
      var y: CGFloat = 0
      while y < size.height {
        context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(Theme.paperLine))
        y += 22
      }
    }
    .background(Theme.paper)
  }
}

private struct Stamp: View {
  var trip: TripSnapshot
  var index: Int
  @Environment(\.colorScheme) private var scheme

  private static let hues: [Double] = [25, 255, 150, 300]
  private static let tilts: [Double] = [-7, 6, -3, 9]

  var body: some View {
    let round = index.isMultiple(of: 2)
    let hue = Self.hues[index % 4]
    let colour = Color(light: OKLCH(0.5, 0.17, hue), dark: OKLCH(0.76, 0.13, hue))
    let ledger = Ledger(trip)
    let budget = Money.minor(trip.budgetMinor) ?? 0
    let over = ledger.total > budget
    let shape = RoundedRectangle(cornerRadius: round ? 69 : 16, style: .continuous)
    let country =
      trip.stops.first.flatMap { CountryMetadata.country($0.countryCode)?.name }
      ?? trip.stops.first?.place ?? trip.name
    VStack(spacing: 1) {
      Text(round ? "ARRIVED" : "ENTRY").typeface(8.5, .black, tracking: 0.2, maximum: 1)
      Text(country.uppercased()).typeface(15, .black, tracking: 0.06, maximum: 1)
        .lineLimit(1).minimumScaleFactor(0.6)
      Text(trip.uniqueFlags.joined()).font(.system(size: 19)).lineLimit(1)
        .minimumScaleFactor(0.6)
      Text(CivilDate.display(trip.startsOn, format: "MMM yyyy").uppercased())
        .typeface(10, .heavy, tracking: 0.12, maximum: 1)
      Text(Money.whole(ledger.total, trip.homeCurrency)).typeface(12.5, .black, maximum: 1)
        .padding(.top, 1)
      Text(
        "\(over ? "OVER" : "UNDER") BY \(Money.whole(abs(ledger.total - budget), trip.homeCurrency))"
      )
      .typeface(8.5, .black, tracking: 0.1, maximum: 1).lineLimit(1).minimumScaleFactor(0.6)
      // The last line sits where the circle narrows, so it gets less room than the centre lines.
      .frame(maxWidth: round ? 80 : nil)
    }
    .multilineTextAlignment(.center)
    .padding(.horizontal, round ? 16 : 10)
    .frame(width: round ? 138 : 158, height: round ? 138 : 118)
    .foregroundStyle(colour)
    .overlay { shape.strokeBorder(colour, lineWidth: 2.5) }
    .overlay {
      RoundedRectangle(cornerRadius: round ? 63.5 : 10.5, style: .continuous)
        .strokeBorder(colour, lineWidth: 1.5).padding(5.5)
    }
    .contentShape(shape)
    .blendMode(scheme == .dark ? .normal : .multiply)
    .rotationEffect(.degrees(Self.tilts[index % 4]))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "\(trip.name), \(CivilDate.display(trip.startsOn, format: "MMMM yyyy")), \(Money.whole(ledger.total, trip.homeCurrency)), \(over ? "over" : "under") budget by \(Money.whole(abs(ledger.total - budget), trip.homeCurrency))"
    )
  }
}
