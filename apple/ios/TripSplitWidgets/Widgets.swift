import SwiftUI
import TripSplitWatchModel
import TripSplitWidgetModel
import TripSplitWidgetUI
import WidgetKit

@main struct TripSplitWidgets: WidgetBundle {
  var body: some Widget {
    TodayWidget()
    QuickConvertWidget()
    WhereYouAreWidget()
    CountdownWidget()
    WhoOwesWidget()
    DailySpendWidget()
    DeparturesWidget()
    QuickConvertControl()
    LogExpenseControl()
  }
}

// MARK: Today

/// Today (B1, B6, B9, C1, C3, C4): what's left to spend, with Convert and Log on the medium.
struct TodayWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: WidgetKind.today, intent: TodayIntent.self, provider: TodayProvider()) {
      entry in
      TodayEntryView(entry: entry)
    }
    .configurationDisplayName("Today")
    .description("See what's left to spend today and log an expense in a tap.")
    .supportedFamilies([
      .systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular,
      .accessoryInline,
    ])
  }
}

struct TodayEntryView: View {
  var entry: PhoneEntry
  @Environment(\.widgetFamily) private var family

  var body: some View {
    Group {
      if entry.isPlaceholder {
        PlaceholderContent()
      } else if let today = entry.today {
        switch family {
        case .systemMedium: TodayMediumView(figures: today)
        case .systemLarge:
          TodayLargeView(
            today: today, progress: entry.progress, daily: entry.daily, balances: entry.balances)
        case .accessoryRectangular: TodayRectangularView(figures: today)
        case .accessoryCircular: BudgetCircularView(figures: today, style: entry.ringStyle)
        case .accessoryInline: InlineView.today(today)
        default: TodaySmallView(figures: today)
        }
      } else if let countdown = entry.countdown {
        // Between trips: the countdown, or the board on the wider sizes.
        switch family {
        case .systemMedium, .systemLarge:
          if let departures = entry.departures {
            DeparturesMediumView(figures: departures)
          } else {
            CountdownSmallView(figures: countdown)
          }
        case .accessoryCircular: CountdownCircularView(figures: countdown)
        case .accessoryInline: InlineView.countdown(countdown)
        case .accessoryRectangular: InlineView.countdown(countdown)
        default: CountdownSmallView(figures: countdown)
        }
      } else {
        NoTripsContent(hasTrips: entry.hasTrips)
      }
    }
    .modifier(EntryLook(entry: entry, board: entry.today == nil && entry.countdown != nil))
  }
}

// MARK: Quick convert

/// Quick convert (B2, C1, C3, D2): a local price in home currency, with Swap in place.
struct QuickConvertWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: WidgetKind.convert, intent: ConvertIntent.self, provider: ConvertProvider()
    ) { entry in
      ConvertEntryView(entry: entry)
    }
    .configurationDisplayName("Quick convert")
    .description("Convert prices into your home currency at a glance.")
    .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
  }
}

struct ConvertEntryView: View {
  var entry: PhoneEntry
  @Environment(\.widgetFamily) private var family

  var body: some View {
    Group {
      if entry.isPlaceholder {
        PlaceholderContent()
      } else if let convert = entry.convert {
        switch family {
        case .accessoryCircular: ConvertCircularView(figures: convert)
        case .accessoryInline: InlineView.convert(convert)
        default:
          ConvertSmallView(figures: convert) {
            Button(intent: SwapDirectionIntent()) { SwapBadge() }
              .buttonStyle(.plain)
              .accessibilityLabel("Swap currencies")
          }
        }
      } else {
        NoTripsContent(hasTrips: entry.hasTrips)
      }
    }
    .modifier(EntryLook(entry: entry))
  }
}

// MARK: Trip widgets

/// Where you are (B3): the trip's days grouped by stop, today picked out.
struct WhereYouAreWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: WidgetKind.whereYouAre, intent: TripIntent.self,
      provider: TripProvider(kind: WidgetKind.whereYouAre)
    ) { entry in
      TripEntryView(entry: entry, kind: WidgetKind.whereYouAre)
    }
    .configurationDisplayName("Where you are")
    .description("Follow where you are in your trip, day by day.")
    .supportedFamilies([.systemSmall, .accessoryCircular])
  }
}

/// Countdown (B4): days to the next trip, or departure day.
struct CountdownWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: WidgetKind.countdown, intent: TripIntent.self,
      provider: TripProvider(kind: WidgetKind.countdown)
    ) { entry in
      TripEntryView(entry: entry, kind: WidgetKind.countdown)
    }
    .configurationDisplayName("Countdown")
    .description("Count down the days to your next trip.")
    .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
  }
}

/// Who owes who (B5): your balance and the biggest transfer between others.
struct WhoOwesWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: WidgetKind.balances, intent: TripIntent.self,
      provider: TripProvider(kind: WidgetKind.balances)
    ) { entry in
      TripEntryView(entry: entry, kind: WidgetKind.balances)
    }
    .configurationDisplayName("Who owes who")
    .description("Check who owes whom on your trip.")
    .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
  }
}

/// Daily spend (B7): each day's spending against the daily budget.
struct DailySpendWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: WidgetKind.daily, intent: TripIntent.self, provider: TripProvider(kind: WidgetKind.daily)
    ) { entry in
      TripEntryView(entry: entry, kind: WidgetKind.daily)
    }
    .configurationDisplayName("Daily spend")
    .description("Compare each day's spending with your daily budget.")
    .supportedFamilies([.systemMedium, .accessoryRectangular])
  }
}

struct TripEntryView: View {
  var entry: PhoneEntry
  var kind: String
  @Environment(\.widgetFamily) private var family

  var body: some View {
    Group {
      if entry.isPlaceholder {
        PlaceholderContent()
      } else {
        switch kind {
        case WidgetKind.whereYouAre: whereYouAre
        case WidgetKind.countdown: countdown
        case WidgetKind.balances: balances
        default: daily
        }
      }
    }
    .modifier(EntryLook(entry: entry))
  }

  @ViewBuilder private var whereYouAre: some View {
    if let progress = entry.progress {
      if family == .accessoryCircular {
        WhereCircularView(figures: progress)
      } else {
        WhereSmallView(figures: progress)
      }
    } else {
      fallback
    }
  }

  @ViewBuilder private var countdown: some View {
    if let countdown = entry.countdown {
      switch family {
      case .accessoryCircular: CountdownCircularView(figures: countdown)
      case .accessoryInline: InlineView.countdown(countdown)
      default: CountdownSmallView(figures: countdown)
      }
    } else {
      NoTripsContent(hasTrips: entry.hasTrips)
    }
  }

  @ViewBuilder private var balances: some View {
    if let balances = entry.balances {
      switch family {
      case .accessoryCircular: OwedCircularView(figures: balances)
      case .accessoryRectangular: BalanceRectangularView(figures: balances)
      default: BalanceSmallView(figures: balances)
      }
    } else {
      NoTripsContent(hasTrips: entry.hasTrips)
    }
  }

  @ViewBuilder private var daily: some View {
    if let daily = entry.daily {
      if family == .accessoryRectangular {
        DailyRectangularView(figures: daily)
      } else {
        DailyMediumView(figures: daily)
      }
    } else {
      fallback
    }
  }

  /// Before the trip starts, a trip widget counts down to it.
  @ViewBuilder private var fallback: some View {
    if let countdown = entry.countdown {
      switch family {
      case .accessoryCircular: CountdownCircularView(figures: countdown)
      case .accessoryRectangular, .accessoryInline: InlineView.countdown(countdown)
      default: CountdownSmallView(figures: countdown)
      }
    } else {
      NoTripsContent(hasTrips: entry.hasTrips)
    }
  }
}

// MARK: Departures

/// Departures (B8): the trip under way and the next departures as a split-flap board.
struct DeparturesWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: WidgetKind.departures, provider: DeparturesProvider()) { entry in
      Group {
        if entry.isPlaceholder {
          Color.clear
        } else if let departures = entry.departures, !departures.rows.isEmpty || departures.addTrip {
          DeparturesMediumView(figures: departures)
        } else {
          NoTripsView().padding()
        }
      }
      .widgetLook(hidesAmounts: entry.hidesAmounts, background: DeparturesBoard.background)
    }
    .configurationDisplayName("Departures")
    .description("See your upcoming trips on the departures board.")
    .supportedFamilies([.systemMedium])
    .contentMarginsDisabled()
  }
}

// MARK: Shared

/// Placeholder shapes on the Home Screen, the plane on the Lock Screen.
struct PlaceholderContent: View {
  @Environment(\.widgetFamily) private var family

  var body: some View {
    switch family {
    case .accessoryCircular: PlaceholderCircularView()
    case .accessoryRectangular: NoTripsRectangularView().redacted(reason: .placeholder)
    case .accessoryInline: Text("TripSplit")
    default: PlaceholderView()
    }
  }
}

/// No trips (E2), in each family's shape.
struct NoTripsContent: View {
  var hasTrips: Bool
  @Environment(\.widgetFamily) private var family

  var body: some View {
    switch family {
    case .accessoryCircular: PlaceholderCircularView(hasTrips: hasTrips)
    case .accessoryRectangular: NoTripsRectangularView()
    case .accessoryInline: InlineView.noTrips
    default: NoTripsView()
    }
  }
}

/// Resolves the look and paints the container. The board between trips brings its own dark
/// background and padding, so it takes the margins away.
struct EntryLook: ViewModifier {
  var entry: PhoneEntry
  var board = false
  @Environment(\.widgetFamily) private var family
  @Environment(\.widgetContentMargins) private var margins

  func body(content: Content) -> some View {
    if board, family == .systemMedium || family == .systemLarge, entry.departures != nil {
      content.padding(margins.negated)
        .widgetLook(hidesAmounts: entry.hidesAmounts, background: DeparturesBoard.background)
    } else {
      content.widgetLook(hidesAmounts: entry.hidesAmounts)
    }
  }
}

extension EdgeInsets {
  fileprivate var negated: EdgeInsets {
    EdgeInsets(top: -top, leading: -leading, bottom: -bottom, trailing: -trailing)
  }
}
