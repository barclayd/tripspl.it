import SwiftUI
import TripSplitWatchDesign
import TripSplitWatchModel
import WidgetKit

// G6 · Corners and bezel: a figure in the circle, a short label or gauge curved along the bezel.

/// A figure in the corner's circle.
private struct CornerFigure: View {
  let text: String
  let colour: Color

  var body: some View {
    ZStack {
      Well()
      Text(text)
        .font(.glance(text.count > 4 ? 12 : 13))
        .foregroundStyle(colour)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .padding(2)
        .widgetAccentable()
    }
  }
}

/// Convert: the result in the circle, "€10 =" along the bezel.
struct ConvertCorner: View {
  let conversion: WatchGlance.Conversion

  var body: some View {
    CornerFigure(text: conversion.to, colour: WatchTheme.accentText)
      .widgetLabel { Text(conversion.from + " =") }
      .accessibilityElement()
      .accessibilityLabel(conversion.line)
  }
}

/// Budget: the flag in the circle, budget left as a curved gauge.
struct BudgetCorner: View {
  let remaining: WatchGlance.Remaining
  let place: WatchGlance.Place

  var body: some View {
    ZStack {
      Well()
      FlagMark(place: place, size: 15)
    }
    .widgetLabel {
      Gauge(value: remaining.fraction) {
        Text("Budget left")
      }
      .tint(Ink.level(remaining.level))
    }
    .accessibilityElement()
    .accessibilityLabel("\(remaining.percent) of budget left")
  }
}

/// Owed: your balance in the circle, which way it runs along the bezel.
struct OwedCorner: View {
  let owed: WatchGlance.Owed
  let glance: WatchGlance
  let look: GlanceLook

  var body: some View {
    CornerFigure(text: look.amount(owed.amount, glance), colour: OwedCircular.colour(owed))
      .widgetLabel { Text(owed.corner) }
      .accessibilityElement()
      .accessibilityLabel(look.hidden ? "Balance" : "\(owed.corner.capitalized) \(owed.amount)")
  }
}

/// Today: spent so far today in the circle, "TODAY" along the bezel.
struct TodayCorner: View {
  let today: WatchGlance.Today
  let glance: WatchGlance
  let look: GlanceLook

  var body: some View {
    CornerFigure(text: look.amount(today.spent, glance), colour: .white)
      .widgetLabel { Text("TODAY") }
      .accessibilityElement()
      .accessibilityLabel(look.hidden ? "Spent today" : "\(today.spent) spent today")
  }
}

/// Between trips: days to go in the circle, where to along the bezel.
struct CountdownCorner: View {
  let countdown: WatchGlance.Countdown

  var body: some View {
    CornerFigure(text: "\(countdown.days)", colour: WatchTheme.amber)
      .widgetLabel { Text("\(countdown.unit) · \(countdown.place.name.uppercased())") }
      .accessibilityElement()
      .accessibilityLabel(countdown.line)
  }
}

/// No trips yet.
struct PlaceholderCorner: View {
  var body: some View {
    PlaceholderCircular()
      .widgetLabel { Text("TRIPSPLIT") }
  }
}

/// One short line above the time.
struct InlineGlance: View {
  let place: WatchGlance.Place?
  let text: String
  @Environment(\.widgetRenderingMode) private var mode

  var body: some View {
    if let place {
      let mark = mode == .accented || place.flag.isEmpty ? place.code : place.flag
      Text("\(mark) \(text)")
    } else {
      Text(text)
    }
  }
}
