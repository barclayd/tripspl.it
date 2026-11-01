import Foundation
import Testing
import TripSplitDomain

@testable import TripSplitPersistence

private final class LegacyFixtureBundleMarker: NSObject {}

/// Opens an actual old-module SwiftData store. A new-store round trip cannot prove this migration.
@MainActor struct LegacyStoreCompatibilityTests {
  private struct Expected: Decodable {
    let primaryTripID: String
    let accountID: String
    let installationID: String
    let pendingOperationIDs: [String]
    let attemptedExpenseID: String
    let createOperationID: String
    let frozenCreateTripID: String
    let frozenCreateOperationID: String
    let expenseDraftID: String
    let onboardingStep: Int
  }

  private var bundle: Bundle {
    #if SWIFT_PACKAGE
      Bundle.module
    #else
      Bundle(for: LegacyFixtureBundleMarker.self)
    #endif
  }

  private func fixture(_ name: String, extension suffix: String) throws -> URL {
    try #require(bundle.url(forResource: name, withExtension: suffix, subdirectory: "Fixtures"))
  }

  @Test func oldAppModuleStorePreservesDocumentsOutboxAndAccountIsolation() throws {
    let expected = try JSONDecoder().decode(
      Expected.self, from: Data(contentsOf: fixture("expected", extension: "json")))
    let documents = try JSONDecoder().decode(
      [String: Data].self, from: Data(contentsOf: fixture("documents", extension: "json")))
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "legacy.store")
    try FileManager.default.copyItem(
      at: fixture("TripSplit-build5", extension: "store"), to: url)
    let store = try LocalStore(installationID: expected.installationID, storeURL: url)
    for (key, data) in documents {
      #expect(try store.document(key)?.data == data)
    }
    let envelope = try #require(store.envelopes[expected.primaryTripID])
    #expect(envelope.accountID == expected.accountID)
    #expect(envelope.pending.map(\.id) == expected.pendingOperationIDs)
    #expect(envelope.pending[0].attempted)
    #expect(envelope.pending[1].problem != nil)
    #expect(envelope.restoreReview)
    #expect(envelope.restoreFetchedRevision == 17)
    #expect(envelope.createOperationID == expected.createOperationID)
    #expect(store.trip(expected.primaryTripID) == nil)
    store.activeAccountID = expected.accountID
    #expect(store.trip(expected.primaryTripID) == envelope.optimistic)
    let pendingExpense = try #require(
      envelope.optimistic.expenses.first { $0.id == expected.attemptedExpenseID })
    #expect(throws: ServiceError.self) {
      try store.saveExpense(pendingExpense, tripID: expected.primaryTripID)
    }
    store.activeAccountID = "another-account"
    #expect(store.trip(expected.primaryTripID) == nil)
    let local = try #require(store.envelopes[expected.frozenCreateTripID])
    #expect(local.accountID == expected.accountID)
    #expect(local.confirmed.syncEpoch == "local")
    #expect(local.createOperationID == expected.frozenCreateOperationID)
    #expect(local.createSnapshot != nil)
    #expect(store.trip(local.confirmed.id) == nil)
    store.activeAccountID = expected.accountID
    #expect(store.trip(local.confirmed.id) == local.optimistic)
    let draft = store.read(ExpenseDraft.self, key: "expense:" + expected.primaryTripID)
    #expect(draft?.id == expected.expenseDraftID)
    #expect(store.read(OnboardingDraft.self, key: "onboarding")?.step == expected.onboardingStep)

    // A restored installation still requires review, with the original operation identity intact.
    let restored = try LocalStore(installationID: "replacement-device", storeURL: url)
    #expect(restored.envelopes.values.allSatisfy { $0.restoreReview })
    #expect(
      restored.envelopes[expected.primaryTripID]?.pending.map(\.id) == expected.pendingOperationIDs)
  }
}
