import Foundation
import Observation
import SwiftData

@Model final class LocalDocument {
  @Attribute(.unique) var id: String
  var data: Data
  init(id: String, data: Data) {
    self.id = id
    self.data = data
  }
}
struct PendingOperation: Codable, Identifiable, Sendable {
  var operation: Operation
  var attempted = false
  var problem: String?
  var id: String { operation.id }
}
struct TripEnvelope: Codable, Sendable {
  var confirmed: TripSnapshot
  var pending: [PendingOperation] = []
  var accountID: String?
  var installationID: String
  var createOperationID = UUID().uuidString
  var createSnapshot: TripSnapshot?
  var restoreReview = false
  var restoreFetchedRevision: Int?
  var optimistic: TripSnapshot {
    var trip = confirmed
    for item in pending { item.operation.apply(to: &trip) }
    return trip
  }
}
struct ExpenseDraft: Codable, Identifiable, Sendable {
  var id: String = UUID().uuidString
  var tripID: String
  var attachment: Attachment
  var expenseID: String?
  var amount = ""
  var currency: String
  var title = ""
  var category: ExpenseCategory = .food
  var status: Expense.Status
  var paidBy: String
  var splitWith: [String]
  var actualHomeAmount = ""
  var conversion: Conversion?
  init(trip: TripSnapshot, attachment: Attachment, expense: Expense? = nil) {
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
@MainActor @Observable final class LocalStore {
  let container: ModelContainer
  private let context: ModelContext
  let installationID: String
  private(set) var envelopes: [String: TripEnvelope] = [:]
  var storageError: String?
  var activeAccountID: String?
  var archivedTrips: [TripSnapshot] {
    envelopes.values.filter { $0.accountID == nil || $0.accountID == activeAccountID }.map(
      \.optimistic
    ).filter(\.archived).sorted { $0.startsOn < $1.startsOn }
  }
  var trips: [TripSnapshot] {
    envelopes.values.filter { $0.accountID == nil || $0.accountID == activeAccountID }.map(
      \.optimistic
    ).filter { !$0.archived }.sorted { $0.startsOn < $1.startsOn }
  }
  init(inMemory: Bool = false, installationID: String? = nil, storeURL: URL? = nil) throws {
    if !inMemory {
      let directory =
        storeURL?.deletingLastPathComponent()
        ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    let configuration =
      storeURL.map { ModelConfiguration(url: $0, cloudKitDatabase: .none) }
      ?? ModelConfiguration(isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
    container = try ModelContainer(for: LocalDocument.self, configurations: configuration)
    context = ModelContext(container)
    context.autosaveEnabled = false
    self.installationID = try installationID ?? InstallationIdentity.current()
    for document in try context.fetch(FetchDescriptor<LocalDocument>())
    where document.id.hasPrefix("trip:") {
      var envelope = try JSONDecoder().decode(TripEnvelope.self, from: document.data)
      if envelope.installationID != self.installationID { envelope.restoreReview = true }
      envelopes[envelope.confirmed.id] = envelope
    }
  }
  func document(_ id: String) throws -> LocalDocument? {
    try context.fetch(FetchDescriptor<LocalDocument>(predicate: #Predicate { $0.id == id })).first
  }
  func write<T: Encodable>(_ value: T, key: String) throws {
    let data = try JSONEncoder().encode(value)
    do {
      if let doc = try document(key) {
        doc.data = data
      } else {
        context.insert(LocalDocument(id: key, data: data))
      }
      try context.save()
    } catch {
      context.rollback()
      throw error
    }
  }
  func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
    guard let doc = try? document(key) else { return nil }
    return try? JSONDecoder().decode(type, from: doc.data)
  }
  func removeDocument(_ key: String) throws {
    if let doc = try document(key) {
      context.delete(doc)
      try context.save()
    }
  }
  func persist(_ envelope: TripEnvelope) throws {
    try write(envelope, key: "trip:" + envelope.confirmed.id)
    envelopes[envelope.confirmed.id] = envelope
  }
  func create(_ trip: TripSnapshot) throws {
    try persist(.init(confirmed: trip, installationID: installationID))
  }
  func trip(_ id: String) -> TripSnapshot? {
    guard let e = envelopes[id], e.accountID == nil || e.accountID == activeAccountID else {
      return nil
    }
    return e.optimistic
  }
  func enqueue(_ operation: Operation, tripID: String) throws {
    guard var envelope = envelopes[tripID] else { return }
    // A never-sent change can be amended. Attempted operations remain immutable across retries.
    if envelope.pending.contains(where: {
      $0.operation.entityId == operation.entityId && $0.attempted
    }) {
      throw ServiceError(
        code: "pending",
        message:
          "This item is waiting for sync. Your new draft is saved. Sync or review the earlier change, then reopen this draft to save it."
      )
    }
    if let index = envelope.pending.firstIndex(where: {
      $0.operation.entityId == operation.entityId && !$0.attempted
    }) {
      let previous = envelope.pending[index].operation
      if operation.type.hasSuffix(".delete"), previous.expectedRevision == nil {
        envelope.pending.remove(at: index)
      } else {
        var merged = operation
        merged.expectedRevision = previous.expectedRevision
        envelope.pending[index] = .init(operation: merged)
      }
    } else {
      envelope.pending.append(.init(operation: operation))
    }
    try persist(envelope)
  }
  func saveExpense(_ expense: Expense, tripID: String) throws {
    guard let trip = trip(tripID) else { return }
    try enqueue(
      .init(
        syncEpoch: trip.syncEpoch, type: "expense.upsert", entityId: expense.id,
        expectedRevision: envelopes[tripID]?.confirmed.expenses.first(where: { $0.id == expense.id }
        )?.revision, payload: .expense(expense)), tripID: tripID)
  }
  func deleteExpense(_ expense: Expense, tripID: String) throws {
    guard let trip = trip(tripID) else { return }
    try enqueue(
      .init(
        syncEpoch: trip.syncEpoch, type: "expense.delete", entityId: expense.id,
        expectedRevision: expense.revision, payload: .none), tripID: tripID)
  }
  func discard(_ operationID: String, tripID: String) throws {
    guard var envelope = envelopes[tripID] else { return }
    envelope.pending.removeAll { $0.id == operationID }
    try persist(envelope)
  }
  func clearAccount(_ accountID: String) throws {
    for (id, envelope) in envelopes where envelope.accountID == accountID {
      try removeDocument("trip:" + id)
      envelopes.removeValue(forKey: id)
      try removeDocument("expense:" + id)
    }
  }
}
