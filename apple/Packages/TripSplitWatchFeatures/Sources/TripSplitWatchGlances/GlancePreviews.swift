import SwiftUI
import TripSplitWatchModel
import WidgetKit

// The circular set beside Apple's own gauge, at the 46mm slot size. Tinted swaps in the
// tinted-face layout; the face itself does the tinting, so colours still show here.

private struct CircularSet: View {
  let glance: WatchGlance = {
    var glance = try! WatchGlance(model: .demo())
    glance.countdown = .init(
      tripID: "", place: .init(flag: "🇹🇼", code: "TW", name: "Taipei"), days: 3)
    return glance
  }()
  let kinds: [GlanceKind] = [
    .budget(.flag, wholeTrip: false), .budget(.percent, wholeTrip: false),
    .budget(.amount, wholeTrip: false), .totalSpent, .whereYouAre, .countdown,
  ]

  var body: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.fixed(50), spacing: 6), count: 3), spacing: 6) {
      ForEach(kinds, id: \.self) { kind in
        GlanceView(kind, glance: glance, layout: (.accessoryCircular, false))
          .frame(width: 50, height: 50)
      }
      Gauge(value: 9, in: 0...10) {
        EmptyView()
      } currentValueLabel: {
        Text("9")
      } minimumValueLabel: {
        Text("9")
      } maximumValueLabel: {
        Text("10")
      }
      .gaugeStyle(.accessoryCircular)
      .frame(width: 50, height: 50)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.black)
  }
}

#Preview("Circular") {
  CircularSet()
}

#Preview("Circular, tinted") {
  CircularSet().environment(\.widgetRenderingMode, .accented)
}
