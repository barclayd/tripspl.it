import Foundation

public struct PendingOperation: Codable, Identifiable, Sendable {
  public init(
    operation: Operation,
    attempted: Bool = false,
    problem: String? = nil
  ) {
    self.operation = operation
    self.attempted = attempted
    self.problem = problem
  }
  public var operation: Operation
  public var attempted = false
  public var problem: String?
  public var id: String { operation.id }
}
public struct TripEnvelope: Codable, Sendable {
  public init(
    confirmed: TripSnapshot,
    pending: [PendingOperation] = [],
    accountID: String? = nil,
    installationID: String,
    createOperationID: String = UUID().uuidString,
    createSnapshot: TripSnapshot? = nil,
    restoreReview: Bool = false,
    restoreFetchedRevision: Int? = nil
  ) {
    self.confirmed = confirmed
    self.pending = pending
    self.accountID = accountID
    self.installationID = installationID
    self.createOperationID = createOperationID
    self.createSnapshot = createSnapshot
    self.restoreReview = restoreReview
    self.restoreFetchedRevision = restoreFetchedRevision
  }
  public var confirmed: TripSnapshot
  public var pending: [PendingOperation] = []
  public var accountID: String?
  public var installationID: String
  public var createOperationID = UUID().uuidString
  public var createSnapshot: TripSnapshot?
  public var restoreReview = false
  public var restoreFetchedRevision: Int?
  public var recordEdits: [String: EditVersion]?
  public var lastWriteClock: Int64?
  public var deletionPending: Bool?
  public var pendingRateChanges: [RateChange]?

  /// Store notices with the snapshot/acknowledgements, including syncs while the app is asleep.
  public mutating func recordRateChanges(from previous: TripSnapshot, ignoring: Set<String> = []) {
    guard !restoreReview, previous.syncEpoch == confirmed.syncEpoch,
      previous.homeCurrency == confirmed.homeCurrency
    else {
      pendingRateChanges = nil
      return
    }
    let current = optimistic
    pendingRateChanges?.removeAll { notice in
      !current.expenses.contains {
        $0.id == notice.expenseID && $0.conversion?.estimateDate == nil
          && Money.minor($0.conversion?.homeAmountMinor) == notice.afterMinor
      }
    }
    let before = Dictionary(
      previous.expenses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    for expense in current.expenses where !ignoring.contains(expense.id) {
      guard let old = before[expense.id], old.amountMinor == expense.amountMinor,
        old.currency == expense.currency, old.conversion?.estimateDate != nil,
        let conversion = expense.conversion, conversion.estimateDate == nil,
        conversion.kind == "reference", conversion.quoteId != nil,
        let oldAmount = Money.minor(old.conversion?.homeAmountMinor),
        let newAmount = Money.minor(conversion.homeAmountMinor), abs(newAmount - oldAmount) > 1
      else { continue }
      if pendingRateChanges == nil { pendingRateChanges = [] }
      pendingRateChanges?.removeAll { $0.expenseID == expense.id }
      pendingRateChanges?.append(
        .init(
          id: "\(current.id):\(expense.id):\(expense.revision)", expenseID: expense.id,
          title: expense.title, currency: current.homeCurrency,
          beforeMinor: oldAmount, afterMinor: newAmount))
    }
  }
  public mutating func nextWriteClock(now: Date = Date()) -> Int64 {
    let next = max(
      Int64(now.timeIntervalSince1970 * 1_000),
      max(lastWriteClock ?? 0, confirmed.writeClock ?? 0) + 1)
    lastWriteClock = next
    return next
  }
  public var optimistic: TripSnapshot {
    var trip = confirmed
    for item in pending { item.operation.apply(to: &trip) }
    return trip
  }
}

public struct RateChange: Codable, Identifiable, Sendable, Equatable {
  public var id: String
  public var expenseID: String
  public var title: String
  public var currency: String
  public var beforeMinor: Int64
  public var afterMinor: Int64
  public var message: String {
    "Rate updated · \(title.prefix(24))\n\(Money.format(beforeMinor, currency)) → \(Money.format(afterMinor, currency))"
  }
}
public struct ExpenseDraft: Codable, Identifiable, Sendable {

  public var id: String = UUID().uuidString
  public var tripID: String
  public var attachment: Attachment
  public var dayIds: [String]?
  public var expenseID: String?
  public var amount = ""
  public var currency: String
  public var title = ""
  public var category: ExpenseCategory = .food
  public var status: Expense.Status
  public var paidBy: String
  public var splitWith: [String]
  public var actualHomeAmount = ""
  public var conversion: Conversion?
  /// Whether travel booked before you go is a return ticket, saved half getting there and half
  /// getting home. Nil in a new draft, or one saved before returns were asked, which is a return.
  public var coversReturn: Bool?
  public var isReturn: Bool { coversReturn ?? true }
  /// Opens a return ticket whole, from either half, on getting there.
  public init(trip: TripSnapshot, attachment: Attachment, expense: Expense? = nil) {
    tripID = trip.id
    self.attachment = attachment
    currency = trip.stop(for: attachment)?.currency ?? trip.homeCurrency
    status = trip.phase == .upcoming ? .planned : .paid
    paidBy = trip.currentTravellerId
    splitWith = trip.activeTravellers.map(\.id)
    if attachment.kind == .leg {
      category = .flight
      currency = trip.homeCurrency
    }
    if let e = expense.map(trip.wholeTicket) {
      self.attachment = e.attachment
      dayIds = e.dayIds
      expenseID = e.id
      amount = Money.input(Money.minor(e.amountMinor) ?? 0, currency: e.currency)
      currency = e.currency
      title = e.title
      category = e.category
      status = e.status
      paidBy = e.paidBy
      splitWith = e.splitWith
      conversion = e.conversion
      if let conversion = e.conversion, conversion.isBankCharge,
        let home = Money.minor(conversion.homeAmountMinor)
      {
        actualHomeAmount = Money.input(home, currency: trip.homeCurrency)
      }
      coversReturn = trip.returnHalves(of: e) != nil || e.title == e.category.returnTitle
    }
  }

  public var selectedDayIDs: Set<String> {
    attachment.kind == .day ? Set(dayIds ?? [attachment.id]) : []
  }

  /// Day pills toggle independently; one day always stays selected. Travel remains exclusive.
  public mutating func select(_ option: Attachment, in trip: TripSnapshot) {
    guard option.kind == .day, attachment.kind == .day else {
      attachment = option
      dayIds = nil
      return
    }
    var selected = selectedDayIDs
    if selected.contains(option.id) {
      if selected.count > 1 { selected.remove(option.id) }
    } else {
      selected.insert(option.id)
    }
    let ordered = trip.days.map(\.id).filter { selected.contains($0) }
    guard let first = ordered.first else { return }
    attachment = .init(kind: .day, id: first)
    dayIds = ordered.count > 1 ? ordered : nil
  }
}

/// A stable ordering for edits received from the watch as well as this phone.
public struct EditVersion: Codable, Sendable, Comparable {
  public var clock: Int64
  public var id: String
  public init(clock: Int64, id: String) { self.clock = clock; self.id = id }
  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.clock == rhs.clock ? lhs.id < rhs.id : lhs.clock < rhs.clock
  }
}
