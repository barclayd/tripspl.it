import SwiftUI
import TripSplitWatchDesign
import TripSplitWatchModel
import WidgetKit

// G5 · Circular set. Every gauge is segmented; text stays within five characters.

/// The amount in a ring: 14.5 on the grid, 13 once it runs to five characters.
private func ringText(_ text: String, _ scale: CGFloat) -> some View {
  Text(text)
    .font(.glance((text.count > 4 ? 13 : 14.5) * scale))
    .foregroundStyle(.white)
    .lineLimit(1)
    .minimumScaleFactor(0.5)
    .frame(width: 34 * scale)
}

/// Budget left · flag: today's flag, ring empties as you spend. Green, amber under 25%, red at 0.
struct BudgetFlagCircular: View {
  let remaining: WatchGlance.Remaining
  let place: WatchGlance.Place
  let look: GlanceLook

  var body: some View {
    Dial { scale in
      BudgetRing(remaining: remaining, look: look)
      FlagMark(place: place, size: 19 * scale)
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
      BudgetRing(remaining: remaining, look: look)
      ringText(remaining.percent, scale)
    }
    .accessibilityElement()
    .accessibilityLabel(remaining.left < 0 ? "Over budget" : "\(remaining.percent) of budget left")
  }
}

private struct BudgetRing: View {
  let remaining: WatchGlance.Remaining
  let look: GlanceLook

  var body: some View {
    let colour = Ink.level(remaining.level)
    Ring(
      layout: .closed, count: 12, filled: SegmentedArc.filled(remaining.fraction, of: 12),
      fill: colour, track: remaining.level == .out ? colour.opacity(0.35) : Ink.track,
      outlined: look.hidden)
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
      let colour = Ink.level(remaining.level)
      Ring(
        layout: .open, count: 10, filled: SegmentedArc.filled(remaining.fraction, of: 10),
        fill: colour, track: remaining.level == .out ? colour.opacity(0.35) : Ink.track,
        outlined: look.hidden)
      ringText(look.amount(remaining.amount, glance), scale)
      FlagMark(place: place, size: 9 * scale).at(25, 44.5, scale)
    }
    .accessibilityElement()
    .accessibilityLabel(look.hidden ? "Budget left" : "\(remaining.amount) left")
  }
}

/// Total spent: open range from 0 to the trip budget in pink, with a red end cap once over.
struct TotalSpentCircular: View {
  let total: WatchGlance.Total
  let glance: WatchGlance
  let look: GlanceLook

  var body: some View {
    Dial { scale in
      Ring(
        layout: .open, count: 10, filled: SegmentedArc.filled(min(total.fraction, 1), of: 10),
        fill: WatchTheme.accentText, outlined: look.hidden)
      ringText(look.amount(total.amount, glance), scale)
      Group {
        Text("0").at(17, 44.2, scale)
        Text(look.hidden ? "•••" : total.budgetLabel).at(33, 44.2, scale)
      }
      .font(.glance(6.5 * scale))
      .foregroundStyle(WatchTheme.ink2)
      if total.isOver {
        Circle()
          .fill(WatchTheme.bad)
          .frame(width: 5.2 * scale, height: 5.2 * scale)
          .widgetAccentable()
          .at(39.1, 39.1, scale)
      }
    }
    .accessibilityElement()
    .accessibilityLabel(
      look.hidden ? "Total spent" : "\(total.amount) spent of \(total.budgetLabel), \(total.percent)")
  }
}

/// Where you are: one segment per trip day, the days so far in pink and "4/8" in the gap.
struct WhereYouAreCircular: View {
  let today: WatchGlance.Today
  let look: GlanceLook

  var body: some View {
    Dial { scale in
      Ring(
        layout: .open, count: today.days, filled: today.day, fill: WatchTheme.accentText,
        outlined: look.hidden)
      FlagMark(place: today.place, size: 19 * scale)
      Text(today.progress)
        .font(.glance(8 * scale, .heavy))
        .foregroundStyle(.white)
        .at(25, 44.7, scale)
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

/// Countdown: amber open ring that fills as departure nears, destination flag in the gap.
struct CountdownCircular: View {
  let countdown: WatchGlance.Countdown

  var body: some View {
    Dial { scale in
      Ring(
        layout: .open, count: 10, filled: SegmentedArc.filled(countdown.fraction, of: 10),
        fill: WatchTheme.amber)
      VStack(spacing: -1 * scale) {
        Text(countdown.days, format: .number)
          .font(.glance(14.5 * scale))
          .foregroundStyle(.white)
        Text(countdown.unit)
          .font(.glance(6.5 * scale))
          .foregroundStyle(WatchTheme.ink2)
      }
      .lineLimit(1)
      .minimumScaleFactor(0.5)
      .padding(.top, 1 * scale)
      FlagMark(place: countdown.place, size: 9 * scale).at(25, 44.5, scale)
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
