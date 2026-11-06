import Foundation
import TripSplitWatchModel
import TripSplitWidgetModel
import TripSplitWidgetUI
import WidgetKit

/// The widget kinds, which the app also names when it reloads one.
enum WidgetKind {
  static let today = "today"
  static let convert = "quick-convert"
  static let whereYouAre = "where-you-are"
  static let countdown = "countdown"
  static let balances = "who-owes-who"
  static let daily = "daily-spend"
  static let departures = "departures"
}

/// What a widget is pointed at: a trip (nil follows the trip under way), Today's scope and
/// circle style, and Quick convert's pair (nil follows where you are).
struct EntryRequest: Sendable {
  var tripID: String?
  var scope: TodayFigures.Scope = .today
  var ringStyle: BudgetRingStyle = .code
  var from: String?
  var into: String?
}

/// Everything any widget shows at one instant, worked out on the main actor from the App Group
/// snapshot and handed to the views as plain values.
struct PhoneEntry: TimelineEntry, Sendable {
  let date: Date
  var today: TodayFigures?
  var progress: ProgressFigures?
  var countdown: CountdownFigures?
  var balances: BalanceFigures?
  var daily: DailyFigures?
  var convert: ConvertFigures?
  var departures: DeparturesFigures?
  var hasTrips = false
  var hidesAmounts = false
  var ringStyle: BudgetRingStyle = .code
  /// The gallery's loading state, drawn as track-coloured shapes.
  var isPlaceholder = false
  /// Smart Stack score and how long it holds; kept as plain values because
  /// `TimelineEntryRelevance` isn't Sendable.
  var score: (value: Float, duration: TimeInterval)?

  var relevance: TimelineEntryRelevance? {
    score.map { TimelineEntryRelevance(score: $0.value, duration: $0.duration) }
  }

  static var placeholder: PhoneEntry {
    PhoneEntry(date: Date(), hasTrips: true, isPlaceholder: true)
  }
}

@MainActor enum PhoneTimeline {
  /// The gallery shows the design's Porto example; the Home Screen shows real trips.
  static func widgets(preview: Bool, at date: Date) -> PhoneWidgets {
    if preview, let demo = try? WatchModel.demo(at: date) { return PhoneWidgets(model: demo) }
    return .shared(at: date)
  }

  static func entry(
    _ request: EntryRequest, kind: String, preview: Bool, at date: Date = Date()
  ) -> PhoneEntry {
    entry(request, kind: kind, widgets: widgets(preview: preview, at: date), at: date)
  }

  /// An entry now, on each hour for the next 12 so relevance follows mealtimes, and at local
  /// midnight when the day and the countdown move on. The app reloads timelines whenever trips,
  /// spending or rates change.
  /// Returned as entries because `Timeline` isn't Sendable; the provider wraps them, reloading at
  /// the end.
  static func entries(_ request: EntryRequest, kind: String, preview: Bool) -> [PhoneEntry] {
    let now = Date()
    let widgets = widgets(preview: preview, at: now)
    let calendar = Calendar.current
    let hour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
    var dates = [now] + (1...12).compactMap { calendar.date(byAdding: .hour, value: $0, to: hour) }
    let midnight = widgets.nextMidnight
    if !dates.contains(midnight) { dates.append(midnight) }
    dates.sort()
    var previous: PhoneEntry?
    return dates.map { date in
      widgets.model.now = date
      var entry = entry(request, kind: kind, widgets: widgets, at: date)
      entry.score = score(of: entry, kind: kind, widgets: widgets, after: previous)
      previous = entry
      return entry
    }
  }

  private static func entry(
    _ request: EntryRequest, kind: String, widgets: PhoneWidgets, at date: Date
  ) -> PhoneEntry {
    let id = request.tripID
    var entry = PhoneEntry(
      date: date, hasTrips: widgets.hasTrips,
      hidesAmounts: widgets.settings.hidesAmountsWhenLocked, ringStyle: request.ringStyle)
    switch kind {
    case WidgetKind.today:
      entry.today = widgets.today(tripID: id, scope: request.scope)
      if entry.today != nil {
        entry.progress = widgets.progress(tripID: id)
        entry.daily = widgets.daily(tripID: id)
        entry.balances = widgets.balances(tripID: id)
      } else {
        // Between trips Today counts down to the next one instead.
        entry.countdown = widgets.countdown(tripID: id)
        entry.departures = widgets.departures
      }
    case WidgetKind.convert:
      entry.convert = widgets.convert(pair: pair(request, widgets: widgets))
    case WidgetKind.whereYouAre:
      entry.progress = widgets.progress(tripID: id)
      if entry.progress == nil { entry.countdown = widgets.countdown(tripID: id) }
    case WidgetKind.countdown:
      entry.countdown = widgets.countdown(tripID: id)
    case WidgetKind.balances:
      entry.balances = widgets.balances(tripID: id)
    case WidgetKind.daily:
      entry.daily = widgets.daily(tripID: id)
      if entry.daily == nil { entry.countdown = widgets.countdown(tripID: id) }
    case WidgetKind.departures:
      entry.departures = widgets.departures
    default: break
    }
    return entry
  }

  /// A fixed pair, else nil to follow where you are. A lone "from" converts into home.
  private static func pair(_ request: EntryRequest, widgets: PhoneWidgets) -> CurrencyPair? {
    guard let from = request.from else { return nil }
    let home = widgets.trip(nil)?.homeCurrency ?? widgets.trips.first?.homeCurrency ?? "GBP"
    let into = request.into ?? home
    return from == into ? nil : CurrencyPair(from: from, to: into)
  }

  /// Smart Stack relevance (brief › Interactions): Today and Quick convert high while abroad,
  /// higher at mealtimes and highest on landing somewhere new; Countdown in its final week.
  private static func score(
    of entry: PhoneEntry, kind: String, widgets: PhoneWidgets, after previous: PhoneEntry?
  ) -> (value: Float, duration: TimeInterval)? {
    switch kind {
    case WidgetKind.today, WidgetKind.convert:
      guard let today = widgets.today(tripID: nil) else {
        return (0, 3600)
      }
      if let previous = previous?.today, previous.place != today.place {
        return (100, 3 * 3600)
      }
      guard widgets.isAbroad else { return (20, 3600) }
      let hour = Calendar.current.component(.hour, from: entry.date)
      let mealtime = [7, 8, 12, 13, 18, 19, 20].contains(hour)
      return (mealtime ? 80 : 50, 3600)
    case WidgetKind.countdown:
      guard let countdown = entry.countdown else { return (0, 3600) }
      if countdown.isDepartureDay { return (100, 3600) }
      return (countdown.days <= 7 ? 70 : 5, 3600)
    default:
      return nil
    }
  }
}

// MARK: Providers

struct TodayProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> PhoneEntry { .placeholder }

  func snapshot(for configuration: TodayIntent, in context: Context) async -> PhoneEntry {
    await PhoneTimeline.entry(
      Self.request(configuration), kind: WidgetKind.today, preview: context.isPreview)
  }

  func timeline(for configuration: TodayIntent, in context: Context) async -> Timeline<PhoneEntry> {
    let entries = await PhoneTimeline.entries(
      Self.request(configuration), kind: WidgetKind.today, preview: context.isPreview)
    return Timeline(entries: entries, policy: .atEnd)
  }

  private static func request(_ configuration: TodayIntent) -> EntryRequest {
    EntryRequest(
      tripID: configuration.trip?.tripID, scope: configuration.show.scope,
      ringStyle: configuration.circle.style)
  }
}

/// For the widgets configured with a trip alone.
struct TripProvider: AppIntentTimelineProvider {
  var kind: String

  func placeholder(in context: Context) -> PhoneEntry { .placeholder }

  func snapshot(for configuration: TripIntent, in context: Context) async -> PhoneEntry {
    await PhoneTimeline.entry(
      EntryRequest(tripID: configuration.trip?.tripID), kind: kind, preview: context.isPreview)
  }

  func timeline(for configuration: TripIntent, in context: Context) async -> Timeline<PhoneEntry> {
    let entries = await PhoneTimeline.entries(
      EntryRequest(tripID: configuration.trip?.tripID), kind: kind, preview: context.isPreview)
    return Timeline(entries: entries, policy: .atEnd)
  }
}

struct ConvertProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> PhoneEntry { .placeholder }

  func snapshot(for configuration: ConvertIntent, in context: Context) async -> PhoneEntry {
    await PhoneTimeline.entry(
      Self.request(configuration), kind: WidgetKind.convert, preview: context.isPreview)
  }

  func timeline(for configuration: ConvertIntent, in context: Context) async -> Timeline<PhoneEntry> {
    let entries = await PhoneTimeline.entries(
      Self.request(configuration), kind: WidgetKind.convert, preview: context.isPreview)
    return Timeline(entries: entries, policy: .atEnd)
  }

  private static func request(_ configuration: ConvertIntent) -> EntryRequest {
    EntryRequest(from: configuration.from?.id, into: configuration.into?.id)
  }
}

/// Departures has nothing to configure.
struct DeparturesProvider: TimelineProvider {
  func placeholder(in context: Context) -> PhoneEntry { .placeholder }

  func getSnapshot(in context: Context, completion: @escaping @Sendable (PhoneEntry) -> Void) {
    let preview = context.isPreview
    Task { @MainActor in
      completion(PhoneTimeline.entry(EntryRequest(), kind: WidgetKind.departures, preview: preview))
    }
  }

  func getTimeline(
    in context: Context, completion: @escaping @Sendable (Timeline<PhoneEntry>) -> Void
  ) {
    let preview = context.isPreview
    Task { @MainActor in
      let entries = PhoneTimeline.entries(EntryRequest(), kind: WidgetKind.departures, preview: preview)
      completion(Timeline(entries: entries, policy: .atEnd))
    }
  }
}
