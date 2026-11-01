import Foundation
import Observation
import SwiftData
import TripSplitDomain

@Model final class LocalDocument {
  @Attribute(.unique) var id: String
  var data: Data
  init(id: String, data: Data) {
    self.id = id
    self.data = data
  }
}
@MainActor @Observable public final class LocalStore {
  let container: ModelContainer
  private let context: ModelContext
  public let installationID: String
  public private(set) var envelopes: [String: TripEnvelope] = [:]
  public var storageError: String?
  public var activeAccountID: String?
  public var archivedTrips: [TripSnapshot] {
    envelopes.values.filter { $0.accountID == nil || $0.accountID == activeAccountID }.map(
      \.optimistic
    ).filter(\.archived).sorted { $0.startsOn < $1.startsOn }
  }
  public var trips: [TripSnapshot] {
    envelopes.values.filter { $0.accountID == nil || $0.accountID == activeAccountID }.map(
      \.optimistic
    ).filter { !$0.archived }.sorted { $0.startsOn < $1.startsOn }
  }
  public init(inMemory: Bool = false, installationID: String? = nil, storeURL: URL? = nil) throws {
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
  public func write<T: Encodable>(_ value: T, key: String) throws {
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
  public func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
    guard let doc = try? document(key) else { return nil }
    return try? JSONDecoder().decode(type, from: doc.data)
  }
  public func removeDocument(_ key: String) throws {
    if let doc = try document(key) {
      context.delete(doc)
      try context.save()
    }
  }
  public func persist(_ envelope: TripEnvelope) throws {
    try write(envelope, key: "trip:" + envelope.confirmed.id)
    envelopes[envelope.confirmed.id] = envelope
  }
  public func create(_ trip: TripSnapshot) throws {
    try persist(.init(confirmed: trip, installationID: installationID))
  }
  public func trip(_ id: String) -> TripSnapshot? {
    guard let e = envelopes[id], e.accountID == nil || e.accountID == activeAccountID else {
      return nil
    }
    return e.optimistic
  }
  public func enqueue(_ operation: TripSplitDomain.Operation, tripID: String) throws {
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
  public func saveExpense(_ expense: Expense, tripID: String) throws {
    guard let trip = trip(tripID) else { return }
    try enqueue(
      .init(
        syncEpoch: trip.syncEpoch, type: "expense.upsert", entityId: expense.id,
        expectedRevision: envelopes[tripID]?.confirmed.expenses.first(where: { $0.id == expense.id }
        )?.revision, payload: .expense(expense)), tripID: tripID)
  }
  public func deleteExpense(_ expense: Expense, tripID: String) throws {
    guard let trip = trip(tripID) else { return }
    try enqueue(
      .init(
        syncEpoch: trip.syncEpoch, type: "expense.delete", entityId: expense.id,
        expectedRevision: expense.revision, payload: .none), tripID: tripID)
  }
  public func discard(_ operationID: String, tripID: String) throws {
    guard var envelope = envelopes[tripID] else { return }
    envelope.pending.removeAll { $0.id == operationID }
    try persist(envelope)
  }
  public func clearAccount(_ accountID: String) throws {
    for (id, envelope) in envelopes where envelope.accountID == accountID {
      try removeDocument("trip:" + id)
      envelopes.removeValue(forKey: id)
      try removeDocument("expense:" + id)
    }
  }
}
