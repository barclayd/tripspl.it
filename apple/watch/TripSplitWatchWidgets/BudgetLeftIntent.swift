import AppIntents
import TripSplitWatchGlances
import WidgetKit

/// How the Budget left complication shows what's left (G1).
enum BudgetStyleOption: String, AppEnum {
  case flag, percent, amount

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Style"
  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .flag: "Flag",
    .percent: "Percent",
    .amount: "Amount",
  ]

  var style: GlanceKind.BudgetStyle {
    switch self {
    case .flag: .flag
    case .percent: .percent
    case .amount: .amount
    }
  }
}

/// Whether the Budget left complication tracks today's allowance or the whole trip.
enum BudgetScope: String, AppEnum {
  case today, trip

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Budget"
  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .today: "Today",
    .trip: "Whole trip",
  ]
}

struct BudgetLeftIntent: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "Budget left"
  static let description = IntentDescription("What's left to spend today or on the whole trip.")

  @Parameter(title: "Style", default: .flag) var style: BudgetStyleOption
  @Parameter(title: "Budget", default: .today) var scope: BudgetScope

  init() {}

  init(style: BudgetStyleOption, scope: BudgetScope) {
    self.style = style
    self.scope = scope
  }

  var kind: GlanceKind { .budget(style.style, wholeTrip: scope == .trip) }
}
