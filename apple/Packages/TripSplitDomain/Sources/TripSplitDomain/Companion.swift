import Foundation

/// What the iPhone shares with its watch. The phone stays the source of truth;
/// the latest context replaces the previous one.
public struct CompanionContext: Codable, Hashable, Sendable {
  public init(
    trips: [TripSnapshot], rejected: [String: String] = [:], handled: [String] = [],
    sentAt: Date = Date()
  ) {
    self.trips = trips
    self.rejected = rejected
    self.handled = handled
    self.sentAt = sentAt
  }
  public var trips: [TripSnapshot]
  /// Watch commands the phone could not apply, keyed by command id, with a reason to show.
  public var rejected: [String: String]
  /// Watch commands the phone has carried out that leave no trace on a trip, such as a nudge.
  public var handled: [String]
  public var sentAt: Date

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    trips = try container.decode([TripSnapshot].self, forKey: .trips)
    rejected = try container.decode([String: String].self, forKey: .rejected)
    // Contexts mirrored before nudges carry no handled list.
    handled = try container.decodeIfPresent([String].self, forKey: .handled) ?? []
    sentAt = try container.decode(Date.self, forKey: .sentAt)
  }
}

/// The watch's copy of the phone's trips plus changes it has sent but not yet seen echoed.
public struct CompanionState: Codable, Hashable, Sendable {
  public init(context: CompanionContext? = nil, pending: [CompanionCommand] = []) {
    self.context = context
    self.pending = pending
  }
  public var context: CompanionContext?
  public var pending: [CompanionCommand]
  public var lastWriteClock: Int64?

  /// Trips as the watch should show them, with pending changes overlaid.
  public var trips: [TripSnapshot] {
    (context?.trips ?? []).map { trip in
      pending.reduce(into: trip) { $1.apply(to: &$0) }
    }
  }

  public var hasSynced: Bool { context != nil }

  /// Takes a newer phone context and returns the reasons for any commands it rejected.
  /// Commands it reflects, handles, rejects, or whose trip has gone are no longer pending.
  @discardableResult
  public mutating func receive(_ incoming: CompanionContext) -> [String] {
    if let context, context.sentAt > incoming.sentAt { return [] }
    context = incoming
    let trips = Dictionary(incoming.trips.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    let rejected = pending.compactMap { incoming.rejected[$0.id] }
    pending.removeAll { command in
      guard let trip = trips[command.tripID] else { return true }
      return incoming.rejected[command.id] != nil || incoming.handled.contains(command.id)
        || command.isReflected(in: trip)
    }
    return rejected
  }

  public mutating func queue(_ command: CompanionCommand) {
    pending.removeAll { $0.recordKey == command.recordKey }
    pending.append(command)
  }
}

/// A change made on the watch, applied by the phone through its normal sync path.
public enum CompanionCommand: Codable, Hashable, Sendable, Identifiable {
  case saveExpense(tripID: String, expense: Expense, editedAt: Int64? = nil)
  case saveRepayment(tripID: String, repayment: Repayment, editedAt: Int64? = nil)
  case deleteExpense(tripID: String, expenseID: String, editedAt: Int64? = nil)
  /// Asks the phone to buzz a traveller who owes you, once per trip day (`on`, yyyy-MM-dd).
  case nudge(tripID: String, travellerID: String, on: String)

  /// Saving and deleting the same expense share an id, so a delete replaces a pending save.
  public var id: String { recordKey + (editedAt.map { ":\($0)" } ?? "") }
  public var editedAt: Int64? {
    switch self {
    case .saveExpense(_, _, let clock), .saveRepayment(_, _, let clock),
      .deleteExpense(_, _, let clock):
      clock
    case .nudge: nil
    }
  }
  public func stamped(_ clock: Int64) -> Self {
    switch self {
    case .saveExpense(let trip, let expense, _):
      .saveExpense(tripID: trip, expense: expense, editedAt: clock)
    case .saveRepayment(let trip, let repayment, _):
      .saveRepayment(tripID: trip, repayment: repayment, editedAt: clock)
    case .deleteExpense(let trip, let id, _):
      .deleteExpense(tripID: trip, expenseID: id, editedAt: clock)
    case .nudge: self
    }
  }
  public var recordKey: String {
    switch self {
    case .saveExpense(_, let expense, _): "expense:" + expense.id
    case .deleteExpense(_, let id, _): "expense:" + id
    case .saveRepayment(_, let repayment, _): "repayment:" + repayment.id
    case .nudge(let trip, let traveller, let day): "nudge:\(trip):\(traveller):\(day)"
    }
  }

  public var tripID: String {
    switch self {
    case .saveExpense(let id, _, _), .saveRepayment(let id, _, _), .deleteExpense(let id, _, _),
      .nudge(let id, _, _):
      id
    }
  }

  /// Shows the change on the watch before the phone echoes it back.
  public func apply(to trip: inout TripSnapshot) {
    guard trip.id == tripID else { return }
    switch self {
    case .saveExpense(_, let expense, _):
      trip.expenses.removeAll { $0.id == expense.id }
      trip.expenses.append(expense)
    case .deleteExpense(_, let id, _):
      trip.expenses.removeAll { $0.id == id }
    case .saveRepayment(_, let repayment, _):
      trip.repayments.removeAll { $0.id == repayment.id }
      trip.repayments.append(repayment)
    case .nudge: break
    }
  }

  /// True once a phone snapshot carries this change.
  public func isReflected(in trip: TripSnapshot) -> Bool {
    switch self {
    case .saveExpense(_, let expense, _):
      trip.expenses.contains { $0.matches(expense) }
    case .deleteExpense(_, let id, _):
      !trip.expenses.contains { $0.id == id }
    case .saveRepayment(_, let repayment, _):
      trip.repayments.contains {
        $0.id == repayment.id && $0.amountMinor == repayment.amountMinor
          && $0.currency == repayment.currency
      }
    // A nudge never shows on the trip: the phone lists it as handled instead.
    case .nudge: false
    }
  }
}

extension Expense {
  /// Same user-visible content, ignoring server revision and conversion enrichment.
  public func matches(_ other: Expense) -> Bool {
    id == other.id && attachment == other.attachment && title == other.title
      && category == other.category && amountMinor == other.amountMinor
      && currency == other.currency && status == other.status && paidBy == other.paidBy
      && splitWith.sorted() == other.splitWith.sorted() && returnPairId == other.returnPairId
      && dayIds == other.dayIds
  }
}

/// Compact wire format for WatchConnectivity payloads: LZFSE-compressed JSON.
public enum CompanionCodec {
  public static let contextKey = "context"
  public static let commandKey = "command"

  public static func encode<T: Encodable>(_ value: T) throws -> Data {
    let json = try JSONEncoder().encode(value)
    return try (json as NSData).compressed(using: .lzfse) as Data
  }

  public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    let json = try (data as NSData).decompressed(using: .lzfse) as Data
    return try JSONDecoder().decode(type, from: json)
  }
}

/// Handoff activity the watch advertises to continue on the iPhone.
public enum CompanionActivity {
  public static let newTrip = "it.tripspl.TripSplit.new-trip"
}
