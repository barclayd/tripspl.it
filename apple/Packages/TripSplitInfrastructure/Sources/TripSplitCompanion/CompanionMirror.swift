import Foundation
import TripSplitDomain

/// Keeps the watch's companion state on disk so trips open instantly and offline.
/// Lives in the App Group so complications read the same figures as the app.
public struct CompanionMirror: Sendable {
  public static let appGroup = "group.it.tripspl.TripSplit"

  public let directory: URL

  public init(directory: URL) {
    self.directory = directory
  }

  /// The shared App Group container, falling back to Application Support when the
  /// entitlement is missing (unsigned simulator builds).
  public static func shared(appGroup: String = appGroup) -> CompanionMirror {
    let directory =
      FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
      ?? URL.applicationSupportDirectory.appending(path: "TripSplit")
    return CompanionMirror(directory: directory)
  }

  public func load() -> CompanionState {
    read(CompanionState.self, key: "companion") ?? CompanionState()
  }

  public func save(_ state: CompanionState) throws {
    try write(state, key: "companion")
  }

  /// Watch-local documents such as cached rates and preferences.
  public func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
    guard let data = try? Data(contentsOf: directory.appending(path: key + ".json")) else {
      return nil
    }
    return try? JSONDecoder().decode(type, from: data)
  }

  public func write<T: Encodable>(_ value: T, key: String) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONEncoder().encode(value).write(
      to: directory.appending(path: key + ".json"), options: [.atomic])
  }
}
