import Foundation
import Testing

@testable import TripSplit

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      let (status, body) = try Self.handler!(request)
      client?.urlProtocol(
        self,
        didReceive: HTTPURLResponse(
          url: request.url!, statusCode: status, httpVersion: nil,
          headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: body)
      client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}
final class SyncServer: @unchecked Sendable {
  let lock = NSLock()
  var snapshot: TripSnapshot
  var requests: [URLRequest] = []
  var batches: [[TripSplit.Operation]] = []
  var creates: [TripSnapshot] = []
  var createIDs: [String] = []
  var refreshCount = 0
  var failCreateFirst = false
  var failFirst = false
  var conflict = false
  var omitResults = false
  init(snapshot: TripSnapshot) { self.snapshot = snapshot }
  func handle(_ request: URLRequest) throws -> (Int, Data) {
    lock.lock()
    defer { lock.unlock() }
    requests.append(request)
    if request.url!.path.hasSuffix("/auth/refresh") {
      refreshCount += 1
      Thread.sleep(forTimeInterval: 0.05)
      let session = Session(
        user: Account(id: "account", displayName: "Test"), accessToken: "rotated-access",
        refreshToken: "rotated-refresh", expiresAt: "2099-01-01T00:00:00.000Z")
      return (200, try JSONEncoder().encode(session))
    }
    if request.url!.path.hasSuffix("/auth/logout") { return (200, Data("{\"ok\":true}".utf8)) }
    if request.url!.path.hasSuffix("/trips"), request.httpMethod == "POST" {
      struct Create: Decodable {
        var operationId: String
        var trip: TripSnapshot
      }
      let value = try JSONDecoder().decode(Create.self, from: body(request))
      creates.append(value.trip)
      createIDs.append(value.operationId)
      if failCreateFirst && creates.count == 1 { throw URLError(.networkConnectionLost) }
      snapshot = value.trip
      snapshot.syncEpoch = "server-epoch"
      snapshot.revision = 1
      return (200, try JSONEncoder().encode(snapshot))
    }
    if request.url!.path.hasSuffix("/sync") {
      let input = try JSONDecoder().decode(SyncRequest.self, from: body(request))
      batches.append(input.operations)
      if failFirst && batches.count == 1 { throw URLError(.networkConnectionLost) }
      var results: [OperationResult] = []
      for operation in input.operations {
        if !conflict {
          operation.apply(to: &snapshot)
          snapshot.revision += 1
        }
        results.append(
          .init(
            id: operation.id, status: conflict ? "conflict" : failFirst ? "duplicate" : "accepted",
            revision: snapshot.revision, code: conflict ? "stale_revision" : nil,
            message: conflict ? "A friend changed this expense." : nil))
      }
      let response = SyncResponse(
        cursor: snapshot.revision, syncEpoch: snapshot.syncEpoch, snapshot: snapshot,
        results: omitResults ? [] : results)
      return (200, try JSONEncoder().encode(response))
    }
    if request.url!.path.hasSuffix("/trips") {
      return (200, Data("{\"trips\":[],\"nextCursor\":null}".utf8))
    }
    return (200, try JSONEncoder().encode(snapshot))
  }
  private func body(_ request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var body = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      if count <= 0 { break }
      body.append(buffer, count: count)
    }
    return body
  }
}
@Suite(.serialized) @MainActor struct SyncTests {
  func fixture(count: Int = 1) throws -> (LocalStore, SyncCoordinator, SyncServer, TripSnapshot) {
    let store = try LocalStore(inMemory: true, installationID: "test")
    var draft = OnboardingDraft()
    draft.stops = [Destination.all[0].stop()]
    var trip = try draft.makeTrip()
    trip.syncEpoch = "server-epoch"
    trip.revision = 1
    store.activeAccountID = "account"
    try store.persist(.init(confirmed: trip, accountID: "account", installationID: "test"))
    for i in 0..<count {
      let expense = Expense(
        attachment: .init(kind: .day, id: trip.days[0].id), title: "Expense \(i)", category: .food,
        amountMinor: "100", currency: "GBP", status: .paid, paidBy: trip.ownerTravellerId,
        splitWith: [trip.ownerTravellerId])
      try store.saveExpense(expense, tripID: trip.id)
    }
    let server = SyncServer(snapshot: trip)
    StubURLProtocol.handler = { try server.handle($0) }
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    let sync = SyncCoordinator(
      store: store,
      api: .init(
        baseURL: URL(string: "https://example.invalid")!,
        transport: URLSession(configuration: config)), sessionWriter: { _ in })
    sync.session = Session(
      user: Account(id: "account", displayName: "Test"), accessToken: "test-access",
      refreshToken: "test-refresh", expiresAt: "2099-01-01T00:00:00.000Z")
    return (store, sync, server, trip)
  }
  @Test func concurrentExpiredTokenRequestsShareOneRotation() async throws {
    let (_, sync, server, _) = try fixture(count: 0)
    sync.session?.expiresAt = "2000-01-01T00:00:00.000Z"
    async let first = sync.accessToken()
    async let second = sync.accessToken()
    let tokens = try await [first, second]
    #expect(tokens == ["rotated-access", "rotated-access"])
    #expect(server.refreshCount == 1)
  }
  @Test func expiredIdleSessionRefreshesBeforeLogout() async throws {
    let (_, sync, server, _) = try fixture(count: 0)
    sync.session?.expiresAt = "2000-01-01T00:00:00.000Z"
    try await sync.signOut()
    #expect(server.refreshCount == 1)
    #expect(server.requests.last?.url?.path == "/v1/auth/logout")
    #expect(
      server.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer rotated-access")
    #expect(sync.session == nil)
  }
  @Test func signOutDuringRefreshCannotResurrectSession() async throws {
    let (_, sync, server, _) = try fixture(count: 0)
    sync.session?.expiresAt = "2000-01-01T00:00:00.000Z"
    let tokenTask = Task { try await sync.accessToken() }
    await Task.yield()
    try await sync.signOut()
    _ = try? await tokenTask.value
    #expect(sync.session == nil)
    #expect(server.refreshCount <= 1)
  }
  @Test func accountChangeDiscardsInFlightRefreshResponse() async throws {
    let (_, sync, _, _) = try fixture(count: 0)
    sync.session?.expiresAt = "2000-01-01T00:00:00.000Z"
    let tokenTask = Task { try await sync.accessToken() }
    try await Task.sleep(for: .milliseconds(10))
    sync.session = Session(
      user: Account(id: "other", displayName: "Other"), accessToken: "other-access",
      refreshToken: "other-refresh", expiresAt: "2099-01-01T00:00:00.000Z")
    do {
      _ = try await tokenTask.value
      Issue.record("Old session should not replace a different account")
    } catch {}
    #expect(sync.session?.user.id == "other")
  }
  @Test func cloudCreationNormalizesOwnerOnceAndFreezesRetryPayload() async throws {
    let (store, sync, server, trip) = try fixture(count: 0)
    var local = trip
    local.syncEpoch = "local"
    local.revision = 0
    try store.persist(.init(confirmed: local, installationID: "test"))
    server.failCreateFirst = true
    do {
      try await sync.syncTrip(trip.id, token: "test", account: "account")
      Issue.record("Expected create acknowledgement loss")
    } catch {}
    sync.session?.user.displayName = "A later profile name"
    try await sync.syncTrip(trip.id, token: "test", account: "account")
    #expect(server.creates.count == 2)
    #expect(server.creates[0] == server.creates[1])
    #expect(server.createIDs[0] == server.createIDs[1])
    #expect(server.creates[0].travellers.first?.name == "Test")
  }
  @Test func uncertainAcknowledgementRetriesSameOperation() async throws {
    let (store, sync, server, trip) = try fixture()
    server.failFirst = true
    do {
      try await sync.syncTrip(trip.id, token: "test", account: "account")
      Issue.record("Expected network loss")
    } catch {}
    #expect(store.envelopes[trip.id]?.pending.first?.attempted == true)
    try await sync.syncTrip(trip.id, token: "test", account: "account")
    #expect(server.batches.count == 2)
    #expect(server.batches[0] == server.batches[1])
    #expect(store.envelopes[trip.id]?.pending.isEmpty == true)
  }
  @Test func drainsBoundedBatchesAndPreservesEveryExpense() async throws {
    let (store, sync, server, trip) = try fixture(count: 53)
    try await sync.syncTrip(trip.id, token: "test", account: "account")
    #expect(server.batches.map(\.count) == [50, 3])
    #expect(store.envelopes[trip.id]?.pending.isEmpty == true)
    #expect(store.trip(trip.id)?.expenses.count == 53)
  }
  @Test func conflictsKeepLocalDraftAndConfirmedServerVersion() async throws {
    let (store, sync, server, trip) = try fixture()
    server.conflict = true
    try await sync.syncTrip(trip.id, token: "test", account: "account")
    #expect(store.envelopes[trip.id]?.pending.first?.problem == "A friend changed this expense.")
    #expect(store.envelopes[trip.id]?.confirmed.expenses.isEmpty == true)
    #expect(store.trip(trip.id)?.expenses.count == 1)
  }
  @Test func restoredDataFetchesWithoutUploadingUntilReviewed() async throws {
    let (store, sync, server, trip) = try fixture()
    var e = try #require(store.envelopes[trip.id])
    e.restoreReview = true
    try store.persist(e)
    try await sync.syncTrip(trip.id, token: "test", account: "account")
    #expect(server.batches.isEmpty)
    #expect(store.envelopes[trip.id]?.restoreFetchedRevision == 1)
    #expect(store.envelopes[trip.id]?.pending.count == 1)
    try sync.approveRestore(trip.id)
    try await sync.syncTrip(trip.id, token: "test", account: "account")
    #expect(server.batches.count == 1)
  }
  @Test func malformedAcknowledgementNeverDropsPendingOperation() async throws {
    let (store, sync, server, trip) = try fixture()
    server.omitResults = true
    do {
      try await sync.syncTrip(trip.id, token: "test", account: "account")
      Issue.record("Expected malformed response error")
    } catch {}
    #expect(store.envelopes[trip.id]?.pending.count == 1)
  }
  @Test func paginationQueryIsAQueryNotEscapedPath() async throws {
    let (_, sync, server, _) = try fixture(count: 0)
    struct Listing: Decodable, Sendable {
      var trips: [TripSnapshot]
      var nextCursor: String?
    }
    let _: Listing = try await sync.api.request("/trips?cursor=a%2Bb%3Dc", token: "test")
    #expect(server.requests.last?.url?.path == "/v1/trips")
    #expect(
      URLComponents(url: server.requests.last!.url!, resolvingAgainstBaseURL: false)?.queryItems?
        .first?.value == "a+b=c")
  }
}
