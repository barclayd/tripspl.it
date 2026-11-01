import SwiftUI
import TripSplitDomain
import TripSplitWatchDesign
import TripSplitWatchModel

/// A glanceable rate for today's stop, e.g. €10 → £8.62. Only shown abroad.
struct ConvertCapsule: View {
  let conversion: QuickConversion

  var body: some View {
    let local = Money.format(conversion.amount, conversion.currency, compact: true)
    let home = Money.format(conversion.converted, conversion.homeCurrency, compact: true)
    HStack(spacing: 7) {
      Text(conversion.flag).font(.system(size: 16))
      Text(local).watchFont(17, .black)
      Image(systemName: "arrow.right")
        .font(.system(size: 12, weight: .heavy))
        .foregroundStyle(WatchTheme.ink2)
      Text(home).watchFont(17, .black).foregroundStyle(WatchTheme.accentText)
      Spacer(minLength: 0)
    }
    .lineLimit(1)
    .minimumScaleFactor(0.7)
    .padding(.horizontal, 14)
    .frame(minHeight: 40)
    .background(WatchTheme.card, in: .capsule)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(local) is about \(home)")
  }
}
