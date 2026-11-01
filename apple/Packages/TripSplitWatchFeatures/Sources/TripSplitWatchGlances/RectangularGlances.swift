import SwiftUI
import TripSplitWatchDesign
import TripSplitWatchModel
import WidgetKit

// G7 · Rectangular and inline set.

/// The backplate behind a rectangular complication: filled on a full-colour face, an outline when
/// Always On is hiding amounts, and left to the system on a tinted face or in the Smart Stack.
private struct Backplate: ViewModifier {
  let look: GlanceLook

  func body(content: Content) -> some View {
    if look.stacked {
      content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    } else {
      content
        .padding(.init(top: 7, leading: 10, bottom: 8, trailing: 10))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
          let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
          if look.accented {
            EmptyView()
          } else if look.hidden {
            shape.strokeBorder(Ink.rule, lineWidth: 1)
          } else {
            shape.fill(Ink.well)
          }
        }
    }
  }
}

/// A pink title with a flag, e.g. "🇵🇹 Porto · Day 4".
private struct GlanceTitle: View {
  let place: WatchGlance.Place?
  let text: String
  var trailing: String?

  var body: some View {
    HStack(spacing: 4) {
      if let place { FlagMark(place: place, size: 11) }
      Text(text)
        .foregroundStyle(WatchTheme.accentText)
        .widgetAccentable()
      if let trailing {
        Spacer(minLength: 4)
        Text(trailing).foregroundStyle(WatchTheme.ink2)
      }
    }
    .font(.glance(12, .heavy))
    .lineLimit(1)
    .minimumScaleFactor(0.7)
  }
}

/// A 4pt linear gauge.
private struct LinearGauge: View {
  let value: Double
  let fill: Color
  let outlined: Bool

  var body: some View {
    Capsule()
      .fill(Ink.track)
      .frame(height: 4)
      .overlay(alignment: .leading) {
        GeometryReader { proxy in
          Capsule()
            .fill(fill.opacity(outlined ? 0.45 : 1))
            .frame(width: proxy.size.width * min(1, max(0, value)))
            .widgetAccentable()
        }
      }
  }
}

/// Today: where you are, what's left today and a gauge.
struct TodayRectangular: View {
  let today: WatchGlance.Today
  let glance: WatchGlance
  let look: GlanceLook

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      GlanceTitle(place: today.place, text: today.title)
      Text(look.hidden ? glance.masked + " left today" : today.leftLine)
        .font(.glance(19.5))
        .foregroundStyle(look.hidden ? WatchTheme.ink2 : .white)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
      Spacer(minLength: 0)
      LinearGauge(
        value: today.daily.fraction, fill: Ink.level(today.daily.level), outlined: look.hidden)
    }
    .modifier(Backplate(look: look))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(look.hidden ? today.title : "\(today.title), \(today.leftLine)")
  }
}

/// Between trips the Today slot counts down to the next one instead.
struct CountdownRectangular: View {
  let countdown: WatchGlance.Countdown
  let look: GlanceLook

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      GlanceTitle(place: countdown.place, text: "Next trip")
      Text(countdown.line)
        .font(.glance(17))
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
      Spacer(minLength: 0)
      LinearGauge(value: countdown.fraction, fill: WatchTheme.amber, outlined: look.hidden)
    }
    .modifier(Backplate(look: look))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(countdown.line)
  }
}

/// Daily spend: a bar per day against the dashed daily budget. Past days white, today pink,
/// days still to come as grey stubs.
struct DailySpendRectangular: View {
  let daily: WatchGlance.DailySpend
  let glance: WatchGlance
  let look: GlanceLook

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      GlanceTitle(
        place: daily.place, text: "Daily spend",
        trailing: look.hidden ? nil : daily.budgetLabel)
      GeometryReader { proxy in
        let height = proxy.size.height
        ZStack(alignment: .bottom) {
          HStack(alignment: .bottom, spacing: 4) {
            ForEach(daily.bars) { bar in
              Group {
                if bar.kind == .future {
                  Capsule().fill(Ink.stub).frame(height: 2)
                } else {
                  RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(colour(bar.kind).opacity(look.hidden ? 0.4 : 1))
                    .frame(height: max(4, height * bar.height))
                    .widgetAccentable(bar.kind == .today)
                }
              }
              .frame(maxWidth: .infinity)
            }
          }
          Line()
            .stroke(Ink.rule, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
            .frame(height: 1.5)
            .offset(y: -height * daily.budgetLine)
        }
      }
      HStack(spacing: 4) {
        ForEach(daily.bars) { bar in
          Text("D\(bar.number)")
            .foregroundStyle(bar.kind == .future ? WatchTheme.ink3 : .white)
            .frame(maxWidth: .infinity)
        }
      }
      .font(.glance(9))
      .lineLimit(1)
      .minimumScaleFactor(0.5)
    }
    .modifier(Backplate(look: look))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
  }

  private func colour(_ kind: WatchGlance.DailySpend.Kind) -> Color {
    kind == .today ? WatchTheme.accentText : .white
  }

  private var label: String {
    let today = daily.bars.first { $0.kind == .today }
    guard let today, !look.hidden else { return "Daily spend" }
    return "Daily spend, day \(today.number) \(WatchCurrency.whole(today.amount, daily.currency)) "
      + "of \(daily.budgetLabel)"
  }
}

private struct Line: Shape {
  func path(in rect: CGRect) -> Path {
    Path {
      $0.move(to: .init(x: rect.minX, y: rect.midY))
      $0.addLine(to: .init(x: rect.maxX, y: rect.midY))
    }
  }
}

/// Who owes who: your balance first, then the biggest other one.
struct WhoOwesRectangular: View {
  let balances: WatchGlance.Balances
  let glance: WatchGlance
  let look: GlanceLook

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      GlanceTitle(place: balances.place, text: "Who owes who")
      ForEach(Array(balances.lines.enumerated()), id: \.offset) { index, line in
        let amount = look.hidden && !line.amount.isEmpty ? glance.masked : line.amount
        Group {
          if index == 0 {
            Text("\(line.text) \(Text(amount).foregroundStyle(colour(line.tone)))")
              .font(.glance(16.5))
              .foregroundStyle(.white)
          } else {
            Text("\(line.text) \(amount)")
              .font(.glance(12.5))
              .foregroundStyle(WatchTheme.ink2)
          }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
      }
      Spacer(minLength: 0)
    }
    .modifier(Backplate(look: look))
    .accessibilityElement(children: .combine)
  }

  private func colour(_ tone: WatchGlance.Balances.Tone) -> Color {
    switch tone {
    case .owedToYou: WatchTheme.good
    case .youOwe: WatchTheme.bad
    case .others: WatchTheme.ink2
    }
  }
}

/// No trips yet: the rectangular placeholder.
struct PlaceholderRectangular: View {
  let look: GlanceLook

  var body: some View {
    HStack(spacing: 8) {
      PlaceholderCircular().frame(width: 30, height: 30)
      VStack(alignment: .leading, spacing: 0) {
        Text("TripSplit")
          .font(.glance(12, .heavy))
          .foregroundStyle(WatchTheme.accentText)
          .widgetAccentable()
        Text("No trips yet")
          .font(.glance(16))
          .foregroundStyle(.white)
      }
      .lineLimit(1)
      .minimumScaleFactor(0.7)
    }
    .modifier(Backplate(look: look))
  }
}

/// G2 · Smart Stack: the accent card, with where you are, today's rate and two buttons that open
/// Convert or Log straight away. The buttons come from the widget extension, which owns the intents.
public struct TodayCard<Actions: View>: View {
  let today: WatchGlance.Today
  let conversion: WatchGlance.Conversion?
  let glance: WatchGlance
  @ViewBuilder let actions: () -> Actions
  @Environment(\.isLuminanceReduced) private var dimmed

  public var body: some View {
    let hidden = glance.hidesAmounts && dimmed
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 4) {
        FlagMark(place: today.place, size: 10.5)
        Text(today.title)
          .font(.glance(11, .black))
          .foregroundStyle(.white.opacity(0.88))
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        Spacer(minLength: 4)
        if let rate = conversion?.rate {
          Text(rate)
            .font(.glance(10, .black))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.white.opacity(0.22), in: .rect(cornerRadius: 6))
            .layoutPriority(1)
        }
      }
      Text(hidden ? glance.masked + " left today" : today.leftLine)
        .font(.glance(22, .black))
        .foregroundStyle(.white)
        .lineLimit(2)
        .minimumScaleFactor(0.6)
      Spacer(minLength: 0)
      HStack(spacing: 6) { actions() }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

/// The two pills on the Smart Stack card: Convert on frosted white, Log on solid white.
public struct CardButtonStyle: ButtonStyle {
  let prominent: Bool

  public init(prominent: Bool) {
    self.prominent = prominent
  }

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.glance(12, .black))
      .lineLimit(1)
      .foregroundStyle(prominent ? Ink.logText : .white)
      .frame(maxWidth: .infinity)
      .frame(height: 28)
      .background(prominent ? .white : .white.opacity(0.22), in: .capsule)
      .opacity(configuration.isPressed ? 0.7 : 1)
  }
}
