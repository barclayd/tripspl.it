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
  public var optimistic: TripSnapshot {
    var trip = confirmed
    for item in pending { item.operation.apply(to: &trip) }
    return trip
  }
}
public struct ExpenseDraft: Codable, Identifiable, Sendable {

  public var id: String = UUID().uuidString
  public var tripID: String
  public var attachment: Attachment
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
    if let e = expense {
      expenseID = e.id
      amount = Money.input(Money.minor(e.amountMinor) ?? 0, currency: e.currency)
      currency = e.currency
      title = e.title
      category = e.category
      status = e.status
      paidBy = e.paidBy
      splitWith = e.splitWith
      conversion = e.conversion
    }
  }
}
