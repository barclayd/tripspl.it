import SwiftUI
import TripSplitWatchDesign
import TripSplitWatchModel
import WidgetKit

/// Which complication to draw. Each one picks its layout from the widget family, falls back to
/// the next trip's countdown between trips and to the placeholder with no trips at all.
public enum GlanceKind: Hashable, Sendable {
  public enum BudgetStyle: String, Hashable, Sendable {
    case flag, percent, amount
  }

  case budget(BudgetStyle, wholeTrip: Bool)
  case totalSpent
  case whereYouAre
  case convert
  case countdown
  case owed
  case today
  case dailySpend

  /// The families each complication offers, per the G section of the design.
  public var families: [WidgetFamily] {
    switch self {
    case .budget: [.accessoryCircular, .accessoryCorner]
    case .totalSpent, .whereYouAre, .countdown: [.accessoryCircular]
    case .convert: [.accessoryCircular, .accessoryCorner, .accessoryInline]
    case .owed: [.accessoryCircular, .accessoryCorner, .accessoryRectangular]
    case .today: [.accessoryRectangular, .accessoryCorner, .accessoryInline]
    case .dailySpend: [.accessoryRectangular]
    }
  }

  /// Where a tap lands in the app.
  public func link(for glance: WatchGlance) -> WatchLink {
    let next = glance.countdown.map { WatchLink.trip($0.tripID) } ?? .trips
    switch self {
    case .budget, .totalSpent:
      return glance.today.map { .trip($0.tripID, page: .budget) } ?? next
    case .whereYouAre, .today:
      return glance.today.map { .trip($0.tripID, page: .today) } ?? next
    case .convert:
      return .convert
    case .countdown:
      return next
    case .owed:
      return glance.owed.map { .trip($0.tripID, page: .balances) } ?? .trips
    case .dailySpend:
      return glance.daily.map { .trip($0.tripID, page: .days) } ?? next
    }
  }
}

/// A complication for any family, drawn from a `WatchGlance`. The Smart Stack card's buttons are
/// passed in, since their intents live with the app and the widget extension.
public struct GlanceView<Actions: View>: View {
  let kind: GlanceKind
  let glance: WatchGlance
  let actions: Actions
  private let layout: (family: WidgetFamily, stacked: Bool)?
  @Environment(\.widgetFamily) private var environmentFamily
  @Environment(\.showsWidgetContainerBackground) private var environmentStacked

  /// - Parameter layout: Draws a family outside WidgetKit, e.g. in a gallery, where the
  ///   environment can't say which one it is.
  public init(
    _ kind: GlanceKind, glance: WatchGlance,
    layout: (family: WidgetFamily, stacked: Bool)? = nil,
    @ViewBuilder actions: () -> Actions
  ) {
    self.kind = kind
    self.glance = glance
    self.layout = layout
    self.actions = actions()
  }

  private var family: WidgetFamily { layout?.family ?? environmentFamily }
  private var stacked: Bool { layout?.stacked ?? environmentStacked }

  public var body: some View {
    glance.look { look in
      let look = GlanceLook(accented: look.accented, hidden: look.hidden, stacked: stacked)
      switch family {
      case .accessoryCorner: corner(look)
      case .accessoryRectangular: rectangular(look)
      case .accessoryInline: inline(look)
      default: circular(look)
      }
    }
    .widgetURL(kind.link(for: glance).url)
    .containerBackground(for: .widget) { background }
  }

  /// Only the Smart Stack shows a container: the accent card for Today, dark for the rest.
  private var background: Color {
    guard stacked, family == .accessoryRectangular else { return .clear }
    switch kind {
    case .owed, .dailySpend: return Ink.well
    default: return glance.today == nil ? Ink.well : WatchTheme.accent
    }
  }

  @ViewBuilder private func circular(_ look: GlanceLook) -> some View {
    switch kind {
    case .budget(let style, let wholeTrip):
      if let today = glance.today {
        let remaining = wholeTrip ? today.trip : today.daily
        switch style {
        case .flag: BudgetFlagCircular(remaining: remaining, place: today.place, look: look)
        case .percent: BudgetPercentCircular(remaining: remaining, look: look)
        case .amount:
          BudgetAmountCircular(remaining: remaining, place: today.place, glance: glance, look: look)
        }
      } else {
        fallbackCircular
      }
    case .totalSpent:
      if let total = glance.total {
        TotalSpentCircular(total: total, glance: glance, look: look)
      } else {
        fallbackCircular
      }
    case .whereYouAre, .today, .dailySpend:
      if let today = glance.today {
        WhereYouAreCircular(today: today, look: look)
          .widgetLabel(today.bezel)
      } else {
        fallbackCircular
      }
    case .convert:
      if let conversion = glance.conversion {
        ConvertCircular(conversion: conversion)
      } else {
        PlaceholderCircular()
      }
    case .countdown:
      fallbackCircular
    case .owed:
      if let owed = glance.owed {
        OwedCircular(owed: owed, glance: glance, look: look)
      } else {
        PlaceholderCircular()
      }
    }
  }

  @ViewBuilder private var fallbackCircular: some View {
    if let countdown = glance.countdown {
      CountdownCircular(countdown: countdown)
    } else {
      PlaceholderCircular()
    }
  }

  @ViewBuilder private func corner(_ look: GlanceLook) -> some View {
    switch kind {
    case .convert:
      if let conversion = glance.conversion { ConvertCorner(conversion: conversion) } else {
        PlaceholderCorner()
      }
    case .owed:
      if let owed = glance.owed { OwedCorner(owed: owed, glance: glance, look: look) } else {
        PlaceholderCorner()
      }
    case .today:
      if let today = glance.today {
        TodayCorner(today: today, glance: glance, look: look)
      } else {
        fallbackCorner
      }
    case .budget(_, let wholeTrip):
      if let today = glance.today {
        BudgetCorner(remaining: wholeTrip ? today.trip : today.daily, place: today.place)
      } else {
        fallbackCorner
      }
    default:
      fallbackCorner
    }
  }

  @ViewBuilder private var fallbackCorner: some View {
    if let countdown = glance.countdown {
      CountdownCorner(countdown: countdown)
    } else {
      PlaceholderCorner()
    }
  }

  @ViewBuilder private func rectangular(_ look: GlanceLook) -> some View {
    switch kind {
    case .owed:
      if let balances = glance.balances {
        WhoOwesRectangular(balances: balances, glance: glance, look: look)
      } else {
        PlaceholderRectangular(look: look)
      }
    case .dailySpend:
      if let daily = glance.daily {
        DailySpendRectangular(daily: daily, glance: glance, look: look)
      } else {
        fallbackRectangular(look)
      }
    default:
      if let today = glance.today {
        if stacked {
          TodayCard(today: today, conversion: glance.conversion, glance: glance) { actions }
        } else {
          TodayRectangular(today: today, glance: glance, look: look)
        }
      } else {
        fallbackRectangular(look)
      }
    }
  }

  @ViewBuilder private func fallbackRectangular(_ look: GlanceLook) -> some View {
    if let countdown = glance.countdown {
      CountdownRectangular(countdown: countdown, look: look)
    } else {
      PlaceholderRectangular(look: look)
    }
  }

  @ViewBuilder private func inline(_ look: GlanceLook) -> some View {
    switch kind {
    case .convert:
      if let conversion = glance.conversion {
        InlineGlance(place: conversion.place, text: conversion.line)
      } else {
        InlineGlance(place: nil, text: "TripSplit")
      }
    default:
      if let today = glance.today {
        InlineGlance(
          place: today.place,
          text: look.hidden ? today.title : today.leftLine)
      } else if let countdown = glance.countdown {
        InlineGlance(place: countdown.place, text: countdown.line)
      } else {
        InlineGlance(place: nil, text: "TripSplit")
      }
    }
  }
}

extension GlanceView where Actions == EmptyView {
  public init(
    _ kind: GlanceKind, glance: WatchGlance, layout: (family: WidgetFamily, stacked: Bool)? = nil
  ) {
    self.init(kind, glance: glance, layout: layout) { EmptyView() }
  }
}
