import SwiftUI
import TripSplitWatchDesign
import TripSplitWatchModel
import WidgetKit

// G5 · Circular set. Rings are the system's gauges, so they match the weight and position of
// Apple's own; text stays within five characters.

/// The amount in a ring: 14.5 on the grid, 13 once it runs to five characters.
private func ringText(_ text: String, _ scale: CGFloat) -> some View {
  Text(text)
    .font(.glance((text.count > 4 ? 13 : 14.5) * scale))
    .foregroundStyle(.white)
    .lineLimit(1)
    .minimumScaleFactor(0.5)
    .frame(width: 34 * scale)
}

extension View {
  /// Colours a system gauge, dimmed while Always On hides amounts, and gives it the face's tint.
  fileprivate func gaugeTint(_ colour: Color, _ look: GlanceLook) -> some View {
    tint(colour.opacity(look.hidden ? 0.5 : 1)).widgetAccentable()
  }

  /// As above, for an open gauge whose marker, at `value` (0–1), is drawn in `Ink.marker` so it
  /// reads against the ring. The system paints the marker with the tint beneath it, so the
  /// marker's colour runs a short way either side of the value, which the marker covers.
  fileprivate func gaugeTint(_ colour: Color, marker value: Double, _ look: GlanceLook) -> some View {
    let fade = look.hidden ? 0.5 : 1
    let ring = colour.opacity(fade)
    let marker = Ink.marker.opacity(fade)
    let value = min(max(value, 0), 1)
    let from = max(value - markerReach, 0)
    let to = min(value + markerReach, 1)
    // At either end the marker overhangs the ring, so the marker's colour runs to that end
    // rather than starting with the ring's.
    var stops: [Gradient.Stop] = []
    if from > 0 { stops += [.init(color: ring, location: 0), .init(color: ring, location: from)] }
    stops += [.init(color: marker, location: from), .init(color: marker, location: to)]
    if to < 1 { stops += [.init(color: ring, location: to), .init(color: ring, location: 1)] }
    return tint(Gradient(stops: stops)).widgetAccentable()
  }
}

/// How far the system's marker reaches either side of its value, as a share of an open gauge.
private let markerReach = 0.025

/// Budget left · flag: today's flag, ring empties as you spend. Green, amber under 25%, red at 0.
struct BudgetFlagCircular: View {
  let remaining: WatchGlance.Remaining
  let place: WatchGlance.Place
  let look: GlanceLook

  var body: some View {
    Dial { scale in
      BudgetRing(remaining: remaining, look: look) {
        FlagMark(place: place, size: 19 * scale)
      }
    }
    .accessibilityElement()
    .accessibilityLabel("\(remaining.percent) of today's budget left")
  }
}

/// Budget left · %: the same ring with the share left, or "OVER" so it never relies on colour.
struct BudgetPercentCircular: View {
  let remaining: WatchGlance.Remaining
  let look: GlanceLook

  var body: some View {
    Dial { scale in
      BudgetRing(remaining: remaining, look: look) {
        ringText(remaining.percent, scale)
      }
    }
    .accessibilityElement()
    .accessibilityLabel(remaining.left < 0 ? "Over budget" : "\(remaining.percent) of budget left")
  }
}

/// A closed ring that empties as you spend, in the budget's level colour.
private struct BudgetRing<Centre: View>: View {
  let remaining: WatchGlance.Remaining
  let look: GlanceLook
  @ViewBuilder let centre: () -> Centre

  var body: some View {
    Gauge(value: remaining.fraction) {
      EmptyView()
    } currentValueLabel: {
      centre()
    }
    .gaugeStyle(.accessoryCircularCapacity)
    .gaugeTint(Ink.level(remaining.level), look)
  }
}

/// Budget left · £: open ring with the amount left and the flag in the gap.
struct BudgetAmountCircular: View {
  let remaining: WatchGlance.Remaining
  let place: WatchGlance.Place
  let glance: WatchGlance
  let look: GlanceLook

  var body: some View {
    Dial { scale in
      Gauge(value: remaining.fraction) {
        FlagMark(place: place, size: 10 * scale)
      } currentValueLabel: {
        ringText(look.amount(remaining.amount, glance), scale)
      }
      .gaugeStyle(.accessoryCircular)
      .gaugeTint(Ink.level(remaining.level), marker: remaining.fraction, look)
    }
    .accessibilityElement()
    .accessibilityLabel(look.hidden ? "Budget left" : "\(remaining.amount) left")
  }
}

/// Total spent: open range from 0 to the trip budget in pink, turning red once over.
struct TotalSpentCircular: View {
  let total: WatchGlance.Total
  let glance: WatchGlance
  let look: GlanceLook

  var body: some View {
    Dial { scale in
      Gauge(value: min(total.fraction, 1)) {
        EmptyView()
      } currentValueLabel: {
        ringText(look.amount(total.amount, glance), scale)
      } minimumValueLabel: {
        bound("0", scale)
      } maximumValueLabel: {
        bound(look.hidden ? "•••" : total.budgetLabel, scale)
      }
      .gaugeStyle(.accessoryCircular)
      .gaugeTint(
        total.isOver ? WatchTheme.bad : WatchTheme.accentText, marker: total.fraction, look)
    }
    .accessibilityElement()
    .accessibilityLabel(
      look.hidden ? "Total spent" : "\(total.amount) spent of \(total.budgetLabel), \(total.percent)")
  }

  private func bound(_ text: String, _ scale: CGFloat) -> some View {
    Text(text)
      .font(.glance(6.5 * scale))
      .foregroundStyle(WatchTheme.ink2)
  }
}

/// Where you are: today's flag, the ring marking the day of the trip and "4/8" in the gap.
struct WhereYouAreCircular: View {
  let today: WatchGlance.Today
  let look: GlanceLook

  var body: some View {
    Dial { scale in
      Gauge(value: Double(min(today.day, today.days)), in: 0...Double(max(today.days, 1))) {
        Text(today.progress)
          .font(.glance(8 * scale, .heavy))
          .foregroundStyle(.white)
      } currentValueLabel: {
        FlagMark(place: today.place, size: 17 * scale)
      }
      .gaugeStyle(.accessoryCircular)
      .gaugeTint(WatchTheme.accentText, marker: Double(today.day) / Double(max(today.days, 1)), look)
    }
    .accessibilityElement()
    .accessibilityLabel("\(today.place.name), day \(today.day) of \(today.days)")
  }
}

/// Quick convert: the last amount over its result, always in the trip's pair.
struct ConvertCircular: View {
  let conversion: WatchGlance.Conversion

  var body: some View {
    Dial { scale in
      VStack(spacing: -1 * scale) {
        Text(conversion.from)
          .font(.glance(10 * scale))
          .foregroundStyle(WatchTheme.ink2)
        Text(conversion.to)
          .font(.glance((conversion.to.count > 5 ? 12.5 : 14.5) * scale))
          .foregroundStyle(WatchTheme.accentText)
          .widgetAccentable()
      }
      .lineLimit(1)
      .minimumScaleFactor(0.5)
      .frame(width: 40 * scale)
    }
    .accessibilityElement()
    .accessibilityLabel(conversion.line)
  }
}

/// Countdown: the next trip's flag, large, over the days to go. No ring, as days away has nothing
/// to fill towards.
struct CountdownCircular: View {
  let countdown: WatchGlance.Countdown

  var body: some View {
    Dial { scale in
      FlagMark(place: countdown.place, size: 21 * scale).at(25, 17, scale)
      Text(countdown.days, format: .number)
        .font(.glance(13 * scale))
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(width: 30 * scale)
        .at(25, 32, scale)
      Text(countdown.unit)
        .font(.glance(5.5 * scale, .heavy))
        .foregroundStyle(WatchTheme.amber)
        .widgetAccentable()
        .at(25, 40, scale)
    }
    .accessibilityElement()
    .accessibilityLabel(countdown.line)
  }
}

/// Owed to you: your net balance on the trip, green when it's coming to you.
struct OwedCircular: View {
  let owed: WatchGlance.Owed
  let glance: WatchGlance
  let look: GlanceLook

  var body: some View {
    Dial { scale in
      VStack(spacing: -1 * scale) {
        Text(owed.label)
          .font(.glance(7.5 * scale))
          .foregroundStyle(WatchTheme.ink2)
        Text(look.amount(owed.amount, glance))
          .font(.glance((owed.amount.count > 4 ? 13 : 14.5) * scale))
          .foregroundStyle(OwedCircular.colour(owed))
          .widgetAccentable()
      }
      .lineLimit(1)
      .minimumScaleFactor(0.5)
      .frame(width: 36 * scale)
    }
    .accessibilityElement()
    .accessibilityLabel(look.hidden ? "Balance" : "\(owed.corner.capitalized) \(owed.amount)")
  }

  static func colour(_ owed: WatchGlance.Owed) -> Color {
    owed.balance > 0 ? WatchTheme.good : owed.balance < 0 ? WatchTheme.bad : .white
  }
}

/// Placeholder: shown on first install, with no trips, and in the gallery.
struct PlaceholderCircular: View {
  var body: some View {
    GeometryReader { proxy in
      let side = min(proxy.size.width, proxy.size.height)
      ZStack {
        Circle().fill(WatchTheme.accent).widgetAccentable()
        Image(systemName: "airplane")
          .font(.system(size: side * 0.42, weight: .bold))
          .foregroundStyle(.white)
      }
      .frame(width: side, height: side)
      .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
    }
    .accessibilityElement()
    .accessibilityLabel("TripSplit")
  }
}
