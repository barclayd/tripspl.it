import AppIntents
import TripSplitCompanion
import TripSplitDomain
import TripSplitWatchModel
import TripSplitWidgetModel
import TripSplitWidgetUI
import WidgetKit

// MARK: Trip

/// A trip to point a widget at, or Automatic: the trip under way, else the next departure.
struct TripEntity: AppEntity {
  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Trip"
  static let defaultQuery = TripQuery()
  static let automaticID = "automatic"

  let id: String
  let name: String
  let detail: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(name)", subtitle: "\(detail)")
  }

  /// Nil for Automatic.
  var tripID: String? { id == Self.automaticID ? nil : id }

  static let automatic = TripEntity(
    id: automaticID, name: "Automatic", detail: "The trip under way, else the next")

  init(id: String, name: String, detail: String) {
    self.id = id
    self.name = name
    self.detail = detail
  }

  init(_ trip: TripSnapshot) {
    let place = trip.stops.first.map { "\($0.flag) \($0.place)" } ?? trip.name
    self.init(id: trip.id, name: trip.name, detail: "\(place) · \(CivilDate.display(trip.startsOn))")
  }
}

struct TripQuery: EntityQuery {
  func entities(for identifiers: [String]) async throws -> [TripEntity] {
    let trips = await Self.trips()
    return identifiers.compactMap { id in trips.first { $0.id == id } }
  }

  func suggestedEntities() async throws -> [TripEntity] { await Self.trips() }

  func defaultResult() async -> TripEntity? { .automatic }

  @MainActor private static func trips() -> [TripEntity] {
    [.automatic] + PhoneWidgets.shared().trips.filter { !$0.archived }.map(TripEntity.init)
  }
}

// MARK: Options

/// Whether Today tracks today's allowance or the whole trip's budget (E4).
enum ShowOption: String, AppEnum {
  case today, trip

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Show"
  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .today: "Today",
    .trip: "Whole trip",
  ]

  var scope: TodayFigures.Scope { self == .trip ? .trip : .today }
}

/// How the Lock Screen's circular Today shows the budget (C3).
enum RingStyleOption: String, AppEnum {
  case code, percent, amount, totalSpent

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Circle"
  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .code: "Country code",
    .percent: "Percent left",
    .amount: "Amount left",
    .totalSpent: "Total spent",
  ]

  var style: BudgetRingStyle {
    switch self {
    case .code: .code
    case .percent: .percent
    case .amount: .amount
    case .totalSpent: .totalSpent
    }
  }
}

/// A currency for Quick convert's fixed pair.
struct CurrencyEntity: AppEntity {
  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Currency"
  static let defaultQuery = CurrencyQuery()

  let id: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: "\(id)", subtitle: "\(Locale.current.localizedString(forCurrencyCode: id) ?? id)")
  }
}

struct CurrencyQuery: EntityStringQuery {
  func entities(for identifiers: [String]) async throws -> [CurrencyEntity] {
    identifiers.map(CurrencyEntity.init)
  }

  func entities(matching string: String) async throws -> [CurrencyEntity] {
    let query = string.lowercased()
    return await Self.codes().filter { code in
      code.lowercased().contains(query)
        || (Locale.current.localizedString(forCurrencyCode: code)?.lowercased().contains(query)
          ?? false)
    }
    .map(CurrencyEntity.init)
  }

  func suggestedEntities() async throws -> [CurrencyEntity] {
    await Self.codes().map(CurrencyEntity.init)
  }

  /// Currencies the cached reference rates cover, so every pair picked can convert offline.
  @MainActor private static func codes() -> [String] {
    let tables = PhoneWidgets.shared().model.tables.values
    let codes = Set(tables.flatMap { [$0.base] + $0.rates.keys })
    return codes.isEmpty ? ["EUR", "GBP", "USD"] : codes.sorted()
  }
}

// MARK: Configuration intents

struct TodayIntent: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "Today"
  static let description = IntentDescription("See what's left to spend today and log an expense in a tap.")

  @Parameter(title: "Trip") var trip: TripEntity?
  @Parameter(title: "Show", default: .today) var show: ShowOption
  @Parameter(title: "Circle", default: .code) var circle: RingStyleOption

  init() {}

  static var parameterSummary: some ParameterSummary {
    When(widgetFamily: .equalTo, .accessoryCircular) {
      Summary {
        \.$trip
        \.$show
        \.$circle
      }
    } otherwise: {
      Summary {
        \.$trip
        \.$show
      }
    }
  }
}

struct TripIntent: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "Trip"
  static let description = IntentDescription("Choose a trip, or follow the one under way.")

  @Parameter(title: "Trip") var trip: TripEntity?

  init() {}
}

struct ConvertIntent: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "Quick convert"
  static let description = IntentDescription("Convert prices into your home currency at a glance.")

  /// Empty follows where you are: today's local currency into home.
  @Parameter(title: "Convert from") var from: CurrencyEntity?
  /// Empty is your home currency.
  @Parameter(title: "Into") var into: CurrencyEntity?

  init() {}
}

// MARK: Swap

/// Quick convert's Swap (B2): turns the pair around in place, e.g. £ to € rather than € to £.
/// Runs in the widget extension and saves the direction where the widgets read it.
struct SwapDirectionIntent: AppIntent {
  static let title: LocalizedStringResource = "Swap currencies"
  static let description = IntentDescription("Turns Quick convert's currencies around.")
  static let isDiscoverable = false

  init() {}

  @MainActor func perform() async throws -> some IntentResult {
    let mirror = CompanionMirror.shared()
    let model = WatchModel(state: mirror.load(), mirror: mirror)
    model.convertMemory.flipped.toggle()
    WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.convert)
    return .result()
  }
}
