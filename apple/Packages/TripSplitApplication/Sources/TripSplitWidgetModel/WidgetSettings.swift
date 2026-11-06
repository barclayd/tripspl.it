import Foundation
import TripSplitCompanion
import TripSplitDomain

/// What the phone writes beside its trips for the widgets: the privacy setting, when the rates
/// were fetched, and when each upcoming trip was first seen, for the countdown bar.
public struct WidgetSettings: Codable, Hashable, Sendable {
  public static let key = "widgets"

  /// Marks amounts privacy sensitive, so the system redacts them while the phone is locked.
  public var hidesAmountsWhenLocked: Bool
  /// When the reference rates were fetched, for "€1 = £0.862 · 08:00".
  public var ratesFetchedAt: Date?
  /// The day each trip was first seen on this phone, keyed by trip id, e.g. "2026-09-12".
  public var firstSeen: [String: String]

  public init(
    hidesAmountsWhenLocked: Bool = false, ratesFetchedAt: Date? = nil,
    firstSeen: [String: String] = [:]
  ) {
    self.hidesAmountsWhenLocked = hidesAmountsWhenLocked
    self.ratesFetchedAt = ratesFetchedAt
    self.firstSeen = firstSeen
  }

  // Settings saved before a key existed keep their defaults for it.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    hidesAmountsWhenLocked =
      try container.decodeIfPresent(Bool.self, forKey: .hidesAmountsWhenLocked) ?? false
    ratesFetchedAt = try container.decodeIfPresent(Date.self, forKey: .ratesFetchedAt)
    firstSeen = try container.decodeIfPresent([String: String].self, forKey: .firstSeen) ?? [:]
  }
}

/// The phone's side of the widgets' App Group snapshot.
public enum WidgetSnapshot {
  /// Writes the phone's trips, rates and settings where the widget extension reads them, and
  /// returns the settings saved. Trips seen for the first time are stamped with today.
  @discardableResult public static func write(
    trips: [TripSnapshot], rates: FXTable?, ratesFetchedAt: Date?, hidesAmountsWhenLocked: Bool,
    to mirror: CompanionMirror, at instant: Date = Date()
  ) throws -> WidgetSettings {
    var settings = mirror.read(WidgetSettings.self, key: WidgetSettings.key) ?? .init()
    let today = CivilDate.string(instant, timeZone: TimeZone.current.identifier)
    let live = trips.filter { !$0.archived }
    for trip in live where settings.firstSeen[trip.id] == nil {
      settings.firstSeen[trip.id] = today
    }
    let ids = Set(live.map(\.id))
    settings.firstSeen = settings.firstSeen.filter { ids.contains($0.key) }
    settings.hidesAmountsWhenLocked = hidesAmountsWhenLocked
    if let ratesFetchedAt { settings.ratesFetchedAt = ratesFetchedAt }

    try mirror.save(CompanionState(context: .init(trips: live, sentAt: instant)))
    if let rates { try mirror.write([rates.base: rates], key: "tables") }
    try mirror.write(settings, key: WidgetSettings.key)
    return settings
  }

  /// The settings the phone last wrote.
  public static func settings(in mirror: CompanionMirror) -> WidgetSettings {
    mirror.read(WidgetSettings.self, key: WidgetSettings.key) ?? .init()
  }
}
