import SwiftUI
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain
import TripSplitNetworking
import TripSplitSync

/// A one-line converter for today's local currency into home, opening the full converter on tap.
struct QuickConvertCard: View {
  var trip: TripSnapshot
  @Environment(AppModel.self) private var model
  @State private var quoted: String?

  private var pair: (from: ConversionCurrency, to: ConversionCurrency) { trip.conversionDefaults }

  var body: some View {
    let (from, to) = pair
    let stop = trip.stop(for: trip.currentAttachment)
    // Zero-decimal currencies read better in thousands: ¥1,000 rather than ¥1.
    let unit = Money.factor(from.code) * (Money.precision(from.code) == 0 ? 1000 : 1)
    let rate = quoted ?? knownRate(from: from.code, to: to.code)
    let place = stop.map { " · \($0.place) \($0.flag)" } ?? ""
    Button {
      model.open(trip)
      model.showConverter = true
    } label: {
      HStack(spacing: 12) {
        ZStack {
          Text(from.flag).font(.system(size: 20)).frame(width: 36, height: 36)
            .background(Theme.inset, in: Circle())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          Text(to.flag).font(.system(size: 16)).frame(width: 30, height: 30)
            .background(Theme.inset, in: Circle())
            .background(Circle().fill(Theme.surface).padding(-3))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(width: 52, height: 40)
        .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 1) {
          Text("Quick convert").typeface(15.5, .heavy, relativeTo: .headline)
            .foregroundStyle(Theme.ink)
          Text(
            rate.flatMap { converted(unit, from: from.code, to: to.code, rate: $0) }
              .map { "\(Money.format(unit, from.code, compact: true)) = \($0)\(place)" }
              ?? "\(from.code) → \(to.code)\(place)"
          )
          .typeface(12.5, .semibold, relativeTo: .caption)
          .foregroundStyle(Theme.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if let rate, let value = converted(unit * 10, from: from.code, to: to.code, rate: rate) {
          HStack(spacing: 4) {
            Text(Money.format(unit * 10, from.code, compact: true))
              .foregroundStyle(Theme.secondary)
            Text(value).foregroundStyle(Theme.accentInk)
              .padding(.vertical, 4).padding(.horizontal, 10)
              .background(Theme.accent, in: Capsule())
          }
          .typeface(13.5, .heavy, relativeTo: .subheadline, maximum: 1.3).monospacedDigit()
          .padding(3).padding(.leading, 8)
          .background(Theme.inset, in: Capsule())
          .fixedSize()
        }
      }
      .padding(12).padding(.trailing, 2)
      .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
      .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle(scale: 0.98))
    .accessibilityIdentifier("home.quickConvert")
    .accessibilityHint("Opens the converter")
    .task(id: "\(from.code)|\(to.code)") {
      guard model.sync.configured else { return }
      let api = model.sync.api
      let date = CivilDate.today(timeZone: trip.timeZone(for: trip.currentAttachment))
      quoted = try? await api.quote(from: from.code, to: to.code, date: date, token: nil).rate
    }
  }

  private func converted(_ minor: Int64, from: String, to: String, rate: String) -> String? {
    (try? Money.convert(minor, from: from, to: to, rate: rate)).map { Money.format($0, to) }
  }

  /// The latest rate an expense already locked in for this pair, so the card works offline.
  private func knownRate(from: String, to: String) -> String? {
    model.store.trips.lazy.filter { $0.homeCurrency == to }
      .flatMap(\.expenses)
      .filter { $0.currency == from }
      .compactMap(\.conversion)
      .max { $0.rateDate < $1.rateDate }?.rate
  }
}
