import TripSplitDomain

public enum GlobeFilter: String, CaseIterable, Identifiable, Sendable {
  case all = "All"
  case upcoming = "Upcoming"
  case past = "Past"
  public var id: Self { self }
  /// Upcoming keeps trips in progress, so only finished trips drop out of it.
  public func includes(_ trip: TripSnapshot) -> Bool {
    switch self {
    case .all: true
    case .upcoming: trip.phase != .past
    case .past: trip.phase == .past
    }
  }
}
