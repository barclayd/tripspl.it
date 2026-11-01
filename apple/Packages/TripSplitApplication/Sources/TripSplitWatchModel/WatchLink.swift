import Foundation
import Observation

/// Where a complication, Smart Stack button or notification opens the watch app, as a
/// `tripsplit://` URL so WidgetKit can hand it over.
public enum WatchLink: Hashable, Sendable {
  /// The trips list.
  case trips
  /// A trip, on a page when it has one, e.g. Budget (D2) or Who owes who (D3).
  case trip(String, page: TripPages.Page? = nil)
  /// Quick convert (C1).
  case convert
  /// Quick convert set back to the trip's local currency, from the Landed notification (H1).
  case localConvert(trip: String)
  /// Logging a spend (F1), on a trip when known.
  case log(trip: String? = nil)
  /// One day of a trip, from the Evening wrap (H2).
  case day(trip: String, day: String)

  public static let scheme = "tripsplit"

  public var url: URL {
    var components = URLComponents()
    components.scheme = Self.scheme
    switch self {
    case .trips:
      components.host = "trips"
    case .trip(let id, let page):
      components.host = "trip"
      components.path = "/" + id
      if let page { components.queryItems = [.init(name: "page", value: page.rawValue)] }
    case .convert:
      components.host = "convert"
    case .localConvert(let trip):
      components.host = "convert"
      components.queryItems = [.init(name: "trip", value: trip)]
    case .log(let trip):
      components.host = "log"
      if let trip { components.queryItems = [.init(name: "trip", value: trip)] }
    case .day(let trip, let day):
      components.host = "day"
      components.path = "/\(trip)/\(day)"
    }
    return components.url ?? URL(string: "\(Self.scheme)://trips")!
  }

  public init?(url: URL) {
    guard url.scheme == Self.scheme,
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { return nil }
    let query = { (name: String) in
      components.queryItems?.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
    }
    switch components.host {
    case "trips": self = .trips
    case "convert": self = query("trip").map { .localConvert(trip: $0) } ?? .convert
    case "log": self = .log(trip: query("trip"))
    case "trip":
      let id = components.path.split(separator: "/").first.map(String.init)
      guard let id, !id.isEmpty else { return nil }
      self = .trip(id, page: query("page").flatMap(TripPages.Page.init(rawValue:)))
    case "day":
      let parts = components.path.split(separator: "/").map(String.init)
      guard parts.count == 2 else { return nil }
      self = .day(trip: parts[0], day: parts[1])
    default: return nil
    }
  }
}

/// Links waiting for the app to open, from Smart Stack buttons that run in the app's process.
@MainActor @Observable public final class WatchLinkInbox {
  public static let shared = WatchLinkInbox()

  public private(set) var pending: WatchLink?

  public init() {}

  public func open(_ link: WatchLink) { pending = link }

  /// Hands over the waiting link, once.
  public func take() -> WatchLink? {
    defer { pending = nil }
    return pending
  }
}
