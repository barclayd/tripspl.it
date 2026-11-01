import SwiftUI
import TripSplitWatchModel
import TripSplitWatchGlances
import WidgetKit

@main struct TripSplitWidgets: WidgetBundle {
  var body: some Widget {
    BudgetLeftWidget()
    TodayWidget()
    QuickConvertWidget()
    WhoOwesWidget()
    TotalSpentWidget()
    WhereYouAreWidget()
    CountdownWidget()
    DailySpendWidget()
  }
}

/// Budget left (G1), in the flag, percent or amount style, for today or the whole trip.
struct BudgetLeftWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: "budget-left", intent: BudgetLeftIntent.self, provider: BudgetLeftProvider()
    ) { entry in
      GlanceView(entry.kind ?? .budget(.flag, wholeTrip: false), glance: entry.glance)
    }
    .configurationDisplayName("Budget left")
    .description("What's left to spend today, or on the whole trip.")
    .supportedFamilies(GlanceKind.budget(.flag, wholeTrip: false).families)
  }
}

/// Today (G2), with Convert and Log on the Smart Stack card.
struct TodayWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "today", provider: GlanceProvider()) { entry in
      GlanceView(.today, glance: entry.glance) {
        Button(intent: OpenWatchLinkIntent(.convert)) { Text("Convert") }
          .buttonStyle(CardButtonStyle(prominent: false))
        Button(intent: OpenWatchLinkIntent(.log(trip: entry.glance.today?.tripID))) {
          Text("+ Log")
        }
        .buttonStyle(CardButtonStyle(prominent: true))
      }
    }
    .configurationDisplayName("Today")
    .description("Where you are, what's left today and what you've spent.")
    .supportedFamilies(GlanceKind.today.families)
  }
}

struct QuickConvertWidget: Widget {
  var body: some WidgetConfiguration {
    glance(.convert, kind: "quick-convert")
      .configurationDisplayName("Quick convert")
      .description("A local amount in your home currency, at today's rate.")
  }
}

struct WhoOwesWidget: Widget {
  var body: some WidgetConfiguration {
    glance(.owed, kind: "who-owes")
      .configurationDisplayName("Who owes who")
      .description("What you're owed, or owe, on your current trip.")
  }
}

struct TotalSpentWidget: Widget {
  var body: some WidgetConfiguration {
    glance(.totalSpent, kind: "total-spent")
      .configurationDisplayName("Total spent")
      .description("The trip's spend against its budget.")
  }
}

struct WhereYouAreWidget: Widget {
  var body: some WidgetConfiguration {
    glance(.whereYouAre, kind: "where-you-are")
      .configurationDisplayName("Where you are")
      .description("Today's stop and how far into the trip you are.")
  }
}

struct CountdownWidget: Widget {
  var body: some WidgetConfiguration {
    glance(.countdown, kind: "countdown")
      .configurationDisplayName("Countdown")
      .description("Days until your next trip.")
  }
}

struct DailySpendWidget: Widget {
  var body: some WidgetConfiguration {
    glance(.dailySpend, kind: "daily-spend")
      .configurationDisplayName("Daily spend")
      .description("Each day's spend against the daily budget.")
  }
}

/// A complication that reads the shared glance, offered in every family its kind supports.
@MainActor private func glance(_ glance: GlanceKind, kind: String) -> some WidgetConfiguration {
  StaticConfiguration(kind: kind, provider: GlanceProvider()) { entry in
    GlanceView(glance, glance: entry.glance)
  }
  .supportedFamilies(glance.families)
}
