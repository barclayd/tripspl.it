import Foundation
import Testing
import TripSplitCompanionHost
import TripSplitDomain
import TripSplitNetworking

@testable import TripSplitApplication
@testable import TripSplitConversion
@testable import TripSplitPersistence
@testable import TripSplitSync

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
  var batches: [[TripSplitDomain.Operation]] = []
  var creates: [TripSnapshot] = []
  var createIDs: [String] = []
  var refreshCount = 0
  var refreshReply: (Int, String)?
  var loseRefreshResponse = false
  var signInAccount = "account"
  var failCreateFirst = false
  var failFirst = false
  var conflict = false
  var omitResults = false
  /// Set once the owner deletes the trip: every trip route then answers 404.
  var deleted = false
  var deletes = 0
  /// How the API answers a nudge: a status code and its JSON.
  var nudgeReply = (200, #"{"status":"sent","nudgedOn":"2026-11-01"}"#)
  /// Nudges and device changes, with their bodies.
  var calls: [(method: String, path: String, body: Data)] = []
  init(snapshot: TripSnapshot) { self.snapshot = snapshot }
  func handle(_ request: URLRequest) throws -> (Int, Data) {
    lock.lock()
    defer { lock.unlock() }
    requests.append(request)
    if request.url!.path.hasSuffix("/auth/refresh") {
      refreshCount += 1
      Thread.sleep(forTimeInterval: 0.05)
      if loseRefreshResponse { throw URLError(.networkConnectionLost) }
      if let refreshReply { return (refreshReply.0, Data(refreshReply.1.utf8)) }
      let session = Session(
        user: Account(id: "account", displayName: "Test"), accessToken: "rotated-access",
        refreshToken: "rotated-refresh", expiresAt: "2099-01-01T00:00:00.000Z")
      return (200, try JSONEncoder().encode(session))
    }
    if request.url!.path.hasSuffix("/auth/apple/challenge") {
      return (
        200, Data(#"{"id":"challenge","nonce":"nonce","expiresAt":"2099-01-01T00:00:00Z"}"#.utf8)
      )
    }
    if request.url!.path.hasSuffix("/auth/apple") {
      return (
        200,
        try JSONEncoder().encode(
          Session(
            user: Account(id: signInAccount, displayName: "Test"), accessToken: "signed-in-access",
            refreshToken: "signed-in-refresh", expiresAt: "2099-01-01T00:00:00.000Z"))
      )
    }
    if request.url!.path.hasSuffix("/auth/logout") { return (200, Data("{\"ok\":true}".utf8)) }
    if request.url!.path.hasSuffix("/nudges") || request.url!.path.hasSuffix("/me/devices") {
      calls.append((request.httpMethod ?? "GET", request.url!.path, body(request)))
      if request.url!.path.hasSuffix("/nudges") { return (nudgeReply.0, Data(nudgeReply.1.utf8)) }
      return (200, Data("{\"ok\":true}".utf8))
    }
    if request.httpMethod == "DELETE", request.url!.path.hasSuffix("/trips/\(snapshot.id)") {
      deletes += 1
      deleted = true
      return (200, Data("{\"ok\":true}".utf8))
    }
    if deleted, request.url!.path.contains("/trips/") {
      return (404, Data("{\"error\":{\"code\":\"TRIP_NOT_FOUND\",\"message\":\"Gone\"}}".utf8))
    }
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
  func fixture(
    count: Int = 1, sessionWriter: @escaping @MainActor (Session) throws -> Void = { _ in }
  ) throws -> (LocalStore, SyncCoordinator, SyncServer, TripSnapshot) {
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
        transport: URLSession(configuration: config)), sessionWriter: sessionWriter,
      sessionReader: { nil }, sessionDeleter: {})
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
  @Test(arguments: ["UNAUTHENTICATED", "APPLE_REVOKED"])
  func rejectedRefreshKeepsThreeEditsAndStopsRetrying(code: String) async throws {
    let (store, sync, server, trip) = try fixture(count: 3)
    let pending = store.envelopes[trip.id]?.pending
    sync.session?.expiresAt = "2000-01-01T00:00:00.000Z"
    server.refreshReply = (
      401, "{\"error\":{\"code\":\"\(code)\",\"message\":\"Refresh rejected\"}}"
    )
    await sync.syncAll()
    #expect(sync.requiresSignIn)
    #expect(sync.needsAppleSignIn)
    #expect(store.activeAccountID == "account")
    #expect(store.trips.contains { $0.id == trip.id })
    #expect(store.envelopes[trip.id]?.pending.map(\.operation) == pending?.map(\.operation))
    await sync.syncAll()
    await #expect { _ = try await sync.accessToken() } throws: {
      ($0 as? ServiceError)?.code == "sign_in_again"
    }
    #expect(server.refreshCount == 1)
    #expect(server.batches.isEmpty)

    await sync.prepareApple()
    await sync.completeApple(identityToken: "test", authorizationCode: "test", displayName: nil)
    #expect(!sync.requiresSignIn)
    #expect(sync.message == nil)
    #expect(server.batches.flatMap { $0 }.map(\.id) == pending?.map { $0.operation.id })
    #expect(store.envelopes[trip.id]?.pending.isEmpty == true)
    #expect(store.trip(trip.id)?.expenses.count == 3)
  }
  @Test func signOutAndBackInPreservesThreePendingEdits() async throws {
    let (store, sync, server, trip) = try fixture(count: 3)
    let pending = store.envelopes[trip.id]?.pending
    sync.session?.expiresAt = "2000-01-01T00:00:00.000Z"
    server.refreshReply = (
      401, #"{"error":{"code":"UNAUTHENTICATED","message":"Refresh rejected"}}"#
    )
    try await sync.signOut()
    #expect(sync.session == nil)
    #expect(store.trips.isEmpty)
    #expect(store.envelopes[trip.id]?.pending.map(\.operation) == pending?.map(\.operation))
    await sync.prepareApple()
    await sync.completeApple(identityToken: "test", authorizationCode: "test", displayName: nil)
    #expect(store.trip(trip.id)?.expenses.count == 3)
    #expect(store.envelopes[trip.id]?.pending.isEmpty == true)
  }
  @Test func reauthenticationNeverUploadsAnotherAccountsEdits() async throws {
    let (store, sync, server, trip) = try fixture(count: 3)
    let pending = store.envelopes[trip.id]?.pending
    sync.session?.expiresAt = "2000-01-01T00:00:00.000Z"
    server.refreshReply = (
      401, #"{"error":{"code":"UNAUTHENTICATED","message":"Refresh rejected"}}"#
    )
    await sync.syncAll()
    server.signInAccount = "other-account"
    await sync.prepareApple()
    await sync.completeApple(identityToken: "test", authorizationCode: "test", displayName: nil)
    #expect(server.batches.isEmpty)
    #expect(store.envelopes[trip.id]?.pending.map(\.operation) == pending?.map(\.operation))
    #expect(store.trips.isEmpty)
  }
  @Test func temporaryRefreshFailuresRemainRetryable() async throws {
    let (_, sync, server, _) = try fixture(count: 0)
    sync.session?.expiresAt = "2000-01-01T00:00:00.000Z"
    server.refreshReply = (503, #"{"error":{"code":"APPLE_UNAVAILABLE","message":"Try later"}}"#)
    await sync.syncAll()
    #expect(!sync.requiresSignIn)
    server.refreshReply = nil
    #expect(try await sync.accessToken() == "rotated-access")
    #expect(server.refreshCount == 2)
  }
  @Test func lostRefreshResponseEventuallyOffersSignInWithoutDroppingEdits() async throws {
    let (store, sync, server, trip) = try fixture(count: 3)
    let pending = store.envelopes[trip.id]?.pending
    sync.session?.expiresAt = "2000-01-01T00:00:00.000Z"
    server.loseRefreshResponse = true
    await sync.syncAll()
    #expect(!sync.requiresSignIn)
    server.loseRefreshResponse = false
    server.refreshReply = (401, #"{"error":{"code":"UNAUTHENTICATED","message":"Already used"}}"#)
    await sync.syncAll()
    #expect(sync.requiresSignIn)
    #expect(store.envelopes[trip.id]?.pending.map(\.operation) == pending?.map(\.operation))
  }
  @Test func failedSecureSaveRetriesTheRotatedCredentialWithoutRefreshingAgain() async throws {
    var writes = 0
    var saved: Session?
    let (store, sync, server, trip) = try fixture(count: 3) { value in
      writes += 1
      if writes == 1 { throw ServiceError(code: "keychain", message: "Secure storage unavailable") }
      saved = value
    }
    sync.session?.expiresAt = "2000-01-01T00:00:00.000Z"
    await sync.syncAll()
    #expect(sync.session?.refreshToken == "test-refresh")
    #expect(!sync.requiresSignIn)
    #expect(store.envelopes[trip.id]?.pending.count == 3)
    await sync.syncAll()
    #expect(saved?.refreshToken == "rotated-refresh")
    #expect(sync.session?.refreshToken == "rotated-refresh")
    #expect(server.refreshCount == 1)
    #expect(writes == 2)
    #expect(store.envelopes[trip.id]?.pending.isEmpty == true)
  }
  @Test func staleRefreshRejectionCannotInvalidateANewSession() async throws {
    let (_, sync, server, _) = try fixture(count: 0)
    sync.session?.expiresAt = "2000-01-01T00:00:00.000Z"
    server.refreshReply = (
      401, #"{"error":{"code":"UNAUTHENTICATED","message":"Refresh rejected"}}"#
    )
    let token = Task { try await sync.accessToken() }
    try await Task.sleep(for: .milliseconds(10))
    try sync.saveSession(
      Session(
        user: Account(id: "account", displayName: "Test"), accessToken: "new-access",
        refreshToken: "new-refresh", expiresAt: "2099-01-01T00:00:00.000Z"))
    _ = try? await token.value
    #expect(!sync.requiresSignIn)
    #expect(try await sync.accessToken() == "new-access")
  }
  @Test func unsavedRotatedCredentialCannotReplaceAnotherAccount() async throws {
    var writes = 0
    let (_, sync, server, _) = try fixture(count: 0) { _ in
      writes += 1
      throw ServiceError(code: "keychain", message: "Secure storage unavailable")
    }
    sync.session?.expiresAt = "2000-01-01T00:00:00.000Z"
    _ = try? await sync.accessToken()
    sync.session = Session(
      user: Account(id: "other", displayName: "Other"), accessToken: "other-access",
      refreshToken: "other-refresh", expiresAt: "2099-01-01T00:00:00.000Z")
    #expect(try await sync.accessToken() == "other-access")
    #expect(writes == 1)
    #expect(server.refreshCount == 1)
  }
  @Test func pushTokenWaitsForSignInAndGoesWithSignOut() async throws {
    let (_, sync, server, _) = try fixture(count: 0)
    let device = PushDevice(token: String(repeating: "ab", count: 32), environment: .sandbox)
    let session = sync.session
    sync.session = nil
    try await sync.registerDevice(device)
    #expect(server.calls.isEmpty)
    sync.session = session
    try await sync.registerDevice(device)
    let registered = try #require(server.calls.last)
    #expect(registered.method == "POST")
    #expect(registered.path == "/v1/me/devices")
    #expect(try JSONDecoder().decode(PushDevice.self, from: registered.body) == device)
    try await sync.signOut()
    let removed = try #require(server.calls.last)
    #expect(removed.method == "DELETE")
    #expect(removed.path == "/v1/me/devices")
    #expect(
      try JSONDecoder().decode([String: String].self, from: removed.body) == ["token": device.token]
    )
    #expect(server.requests.last?.url?.path == "/v1/auth/logout")
  }
  @Test func nudgesGoThroughTheAPI() async throws {
    let (_, sync, server, trip) = try fixture(count: 0)
    let result = try await sync.nudge(tripID: trip.id, travellerID: "b")
    #expect(result == NudgeResult(status: .sent, nudgedOn: "2026-11-01"))
    let call = try #require(server.calls.last)
    #expect(call.method == "POST")
    #expect(call.path == "/v1/trips/\(trip.id)/nudges")
    #expect(
      try JSONDecoder().decode([String: String].self, from: call.body) == ["travellerId": "b"])
    server.nudgeReply = (
      429, #"{"error":{"code":"NUDGE_LIMIT","message":"Already nudged today."}}"#
    )
    await #expect {
      _ = try await sync.nudge(tripID: trip.id, travellerID: "b")
    } throws: { ($0 as? ServiceError)?.code == "NUDGE_LIMIT" }
  }
  /// The phone relays a watch nudge, and tells the watch whether it went.
  @Test func hostRelaysWatchNudges() async throws {
    let (store, sync, server, trip) = try fixture(count: 0)
    let traveller = trip.ownerTravellerId
    var published: [CompanionContext] = []
    let host = WatchCompanionHost(model: AppModel(store: store, sync: sync)) {
      published.append($0)
    }
    func nudge(_ day: String) -> CompanionCommand {
      .nudge(tripID: trip.id, travellerID: traveller, on: day)
    }

    await host.receive(nudge("2026-11-01"))
    #expect(published.last?.handled == [nudge("2026-11-01").id])
    #expect(server.calls.count == 1)
    // A redelivered transfer isn't sent twice.
    await host.receive(nudge("2026-11-01"))
    #expect(server.calls.count == 1)

    // The server's daily limit counts as done: the watch already showed it as sent.
    server.nudgeReply = (
      429, #"{"error":{"code":"NUDGE_LIMIT","message":"Already nudged today."}}"#
    )
    await host.receive(nudge("2026-11-02"))
    #expect(published.last?.handled.contains(nudge("2026-11-02").id) == true)

    server.nudgeReply = (200, #"{"status":"notJoined","nudgedOn":"2026-11-03"}"#)
    await host.receive(nudge("2026-11-03"))
    #expect(
      published.last?.rejected[nudge("2026-11-03").id]?.contains("hasn’t joined TripSplit") == true)

    server.nudgeReply = (409, #"{"error":{"code":"NOTHING_OWED","message":"Nothing owed."}}"#)
    await host.receive(nudge("2026-11-04"))
    #expect(published.last?.rejected[nudge("2026-11-04").id]?.contains("doesn’t owe you") == true)

    // Retried once it can go: the old reason is dropped so it can't cancel the retry.
    server.nudgeReply = (200, #"{"status":"sent","nudgedOn":"2026-11-04"}"#)
    await host.receive(nudge("2026-11-04"))
    #expect(published.last?.rejected[nudge("2026-11-04").id] == nil)
    #expect(published.last?.handled.contains(nudge("2026-11-04").id) == true)

    // Signed out with the trip still on the phone, e.g. one not yet shared.
    sync.session = nil
    store.activeAccountID = "account"
    await host.receive(nudge("2026-11-05"))
    #expect(
      published.last?.rejected[nudge("2026-11-05").id] == "Sign in on your iPhone to nudge people.")
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
  @Test func deletingACloudTripRemovesItEverywhereThenLocally() async throws {
    let (store, sync, server, trip) = try fixture()
    try await sync.deleteTrip(trip.id)
    #expect(server.deletes == 1)
    #expect(store.envelopes[trip.id] == nil)
    #expect(store.trip(trip.id) == nil)
  }
  @Test func deletingATripTheServerNeverSawStaysOffline() async throws {
    let (store, sync, server, trip) = try fixture()
    var local = trip
    local.syncEpoch = "local"
    try store.persist(.init(confirmed: local, accountID: "account", installationID: "test"))
    try await sync.deleteTrip(trip.id)
    #expect(server.requests.isEmpty)
    #expect(store.trip(trip.id) == nil)
  }
  @Test func deletingAnAlreadyDeletedTripStillForgetsIt() async throws {
    let (store, sync, server, trip) = try fixture()
    server.deleted = true
    server.snapshot.id = "another"
    try await sync.deleteTrip(trip.id)
    #expect(store.trip(trip.id) == nil)
  }
  @Test func syncDropsTripsTheOwnerDeleted() async throws {
    let (store, sync, server, trip) = try fixture()
    server.deleted = true
    await sync.syncAll()
    #expect(store.trip(trip.id) == nil)
    #expect(sync.message == nil)
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
