import Foundation
import TripSplitWatchGlances
import TripSplitWatchModel
import WidgetKit

struct GlanceEntry: TimelineEntry, Sendable {
  /// How much the Smart Stack should want this entry, and for how long.
  struct Importance: Hashable, Sendable {
    var score: Float
    var duration: TimeInterval
  }

  let date: Date
  let glance: WatchGlance
  var importance: Importance?
  /// The configured style, for complications that have one.
  var kind: GlanceKind?

  var relevance: TimelineEntryRelevance? {
    importance.map { TimelineEntryRelevance(score: $0.score, duration: $0.duration) }
  }

  /// Nothing to show yet, without touching the App Group.
  static var placeholder: GlanceEntry {
    GlanceEntry(date: Date(), glance: WatchGlance(date: Date()))
  }
}

/// Builds complication entries from what the watch app mirrored to the App Group.
@MainActor enum GlanceTimeline {
  /// The gallery shows the design's Porto example; the face shows real trips.
  static func model(preview: Bool) -> WatchModel {
    if preview, let demo = try? WatchModel.demo() { return demo }
    return .mirrored()
  }

  static func entry(preview: Bool, at date: Date = Date()) -> GlanceEntry {
    let model = model(preview: preview)
    model.now = date
    return GlanceEntry(date: date, glance: WatchGlance(model: model))
  }

  /// An entry now and on every hour for the next 12, so the day rolls over at local midnight and
  /// relevance follows mealtimes. The app reloads timelines whenever something is logged or synced.
  static func entries(preview: Bool, from now: Date = Date()) -> [GlanceEntry] {
    let model = model(preview: preview)
    let calendar = Calendar.current
    let hour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
    let dates = [now] + (1...12).compactMap { calendar.date(byAdding: .hour, value: $0, to: hour) }
    var previous: WatchGlance?
    return dates.map { date in
      model.now = date
      let glance = WatchGlance(model: model)
      defer { previous = glance }
      return GlanceEntry(
        date: date, glance: glance,
        importance: importance(of: glance, at: date, after: previous, calendar: calendar))
    }
  }

  /// Smart Stack relevance: highest on a new stop's first morning, high at mealtimes on a trip,
  /// low between trips and nothing without one.
  static func importance(
    of glance: WatchGlance, at date: Date, after previous: WatchGlance?, calendar: Calendar
  ) -> GlanceEntry.Importance {
    guard let today = glance.today else {
      return .init(score: glance.countdown == nil ? 0 : 5, duration: 3600)
    }
    if let previous, previous.today?.place != today.place {
      return .init(score: 100, duration: 3 * 3600)
    }
    let hour = calendar.component(.hour, from: date)
    let mealtime = [7, 8, 12, 13, 18, 19, 20].contains(hour)
    return .init(score: mealtime ? 80 : 40, duration: 3600)
  }
}

struct GlanceProvider: TimelineProvider {
  func placeholder(in context: Context) -> GlanceEntry { .placeholder }

  func getSnapshot(in context: Context, completion: @escaping @Sendable (GlanceEntry) -> Void) {
    let preview = context.isPreview
    Task { @MainActor in completion(GlanceTimeline.entry(preview: preview)) }
  }

  func getTimeline(
    in context: Context, completion: @escaping @Sendable (Timeline<GlanceEntry>) -> Void
  ) {
    let preview = context.isPreview
    Task { @MainActor in
      completion(Timeline(entries: GlanceTimeline.entries(preview: preview), policy: .atEnd))
    }
  }
}

struct BudgetLeftProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> GlanceEntry { .placeholder }

  func snapshot(for configuration: BudgetLeftIntent, in context: Context) async -> GlanceEntry {
    var entry = await GlanceTimeline.entry(preview: context.isPreview)
    entry.kind = configuration.kind
    return entry
  }

  func timeline(
    for configuration: BudgetLeftIntent, in context: Context
  ) async -> Timeline<GlanceEntry> {
    let kind = configuration.kind
    let entries = await GlanceTimeline.entries(preview: context.isPreview).map { entry in
      var entry = entry
      entry.kind = kind
      return entry
    }
    return Timeline(entries: entries, policy: .atEnd)
  }

  func recommendations() -> [AppIntentRecommendation<BudgetLeftIntent>] {
    [
      .init(intent: .init(style: .flag, scope: .today), description: "Budget left · flag"),
      .init(intent: .init(style: .percent, scope: .today), description: "Budget left · %"),
      .init(intent: .init(style: .amount, scope: .today), description: "Budget left today"),
      .init(intent: .init(style: .amount, scope: .trip), description: "Budget left on the trip"),
    ]
  }
}
