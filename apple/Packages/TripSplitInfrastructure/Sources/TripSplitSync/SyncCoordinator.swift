import Foundation
import Observation
import TripSplitDomain
import TripSplitNetworking
import TripSplitPersistence

@MainActor @Observable public final class SyncCoordinator {
  public let store: LocalStore
  public let api: APIClient
  public internal(set) var session: Session? {
    didSet {
      sessionVersion &+= 1
      store.activeAccountID = session?.user.id
    }
  }
  public private(set) var isSyncing = false
  public var message: String?
  public private(set) var challenge: AuthChallenge?
  public private(set) var deletionRequested = false
  public private(set) var lastSynced: Date?
  @ObservationIgnored private var sessionVersion = 0
  @ObservationIgnored private var refreshTask: Task<String, Error>?
  @ObservationIgnored private var endingSession = false
  @ObservationIgnored private let sessionWriter: @MainActor (Session) throws -> Void
  @ObservationIgnored private var liveTask: Task<Void, Never>?
  @ObservationIgnored private var liveSocket: URLSessionWebSocketTask?
  public init(
    store: LocalStore, api: APIClient = APIClient(),
    sessionWriter: (@MainActor (Session) throws -> Void)? = nil
  ) {
    self.sessionWriter =
      sessionWriter ?? { try SessionVault.write(JSONEncoder().encode($0), key: "session") }
    self.store = store
    self.api = api
    if let data = SessionVault.read("session") {
      session = try? JSONDecoder().decode(Session.self, from: data)
    }
    store.activeAccountID = session?.user.id
  }
  public var configured: Bool { api.baseURL != nil }
  public func stopLive() {
    liveTask?.cancel()
    liveTask = nil
    liveSocket?.cancel(with: .goingAway, reason: nil)
    liveSocket = nil
  }
  public func startLive(tripID: String?) {
    stopLive()
    guard let tripID, configured, session != nil, let envelope = store.envelopes[tripID],
      envelope.accountID == session?.user.id, envelope.confirmed.syncEpoch != "local"
    else { return }
    liveTask = Task { [weak self] in
      var delay = 1
      while !Task.isCancelled {
        guard let self else { return }
        do {
          let token = try await accessToken()
          guard var components = URLComponents(url: api.baseURL!, resolvingAgainstBaseURL: false)
          else { return }
          components.scheme = components.scheme == "https" ? "wss" : "ws"
          components.path =
            components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            + "/v1/trips/\(tripID)/live"
          var request = URLRequest(url: components.url!)
          request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
          let socket = api.transport.webSocketTask(with: request)
          liveSocket = socket
          socket.resume()
          delay = 1
          while !Task.isCancelled {
            let message = try await socket.receive()
            let data: Data
            switch message {
            case .data(let value): data = value
            case .string(let value): data = Data(value.utf8)
            @unknown default: continue
            }
            struct Hint: Decodable {
              var type: String
              var revision: Int
              var syncEpoch: String
            }
            if let hint = try? JSONDecoder().decode(Hint.self, from: data), hint.type == "changed",
              let cached = store.envelopes[tripID],
              hint.revision != cached.confirmed.revision
                || hint.syncEpoch != cached.confirmed.syncEpoch
            {
              await syncAll()
            }
          }
        } catch {
          if Task.isCancelled { return }
          try? await Task.sleep(for: .seconds(delay))
          delay = min(delay * 2, 30)
        }
      }
    }
  }
  public func prepareApple() async {
    do {
      challenge = try await api.request("/auth/apple/challenge", method: "POST", body: EmptyBody())
    } catch { message = error.localizedDescription }
  }
  public func completeApple(identityToken: String, authorizationCode: String, displayName: String?)
    async
  {
    do {
      guard let challenge else {
        throw ServiceError(
          code: "apple", message: "Apple didn’t return a complete sign-in response. Try again.")
      }
      struct Body: Encodable, Sendable {
        var challengeId: String
        var identityToken: String
        var authorizationCode: String
        var displayName: String?
      }
      let newSession: Session = try await api.request(
        "/auth/apple", method: "POST",
        body: Body(
          challengeId: challenge.id, identityToken: identityToken,
          authorizationCode: authorizationCode,
          displayName: displayName))
      try saveSession(newSession)
      self.challenge = nil
      message = nil
      await syncAll()
    } catch {
      message = error.localizedDescription
      await prepareApple()
    }
  }
  func saveSession(_ value: Session) throws {
    try sessionWriter(value)
    session = value
  }
  public func accessToken() async throws -> String {
    guard !endingSession else {
      throw ServiceError(code: "ending_session", message: "Sign-out is in progress.")
    }
    guard let session else {
      throw ServiceError(code: "sign_in", message: "Sign in with Apple to sync or share this trip.")
    }
    if let expiry = Self.expiry(session.expiresAt), expiry.timeIntervalSinceNow > 60 {
      return session.accessToken
    }
    if let refreshTask { return try await refreshTask.value }
    let version = sessionVersion
    let task = Task { @MainActor [weak self] () throws -> String in
      guard let self else { throw CancellationError() }
      defer { self.refreshTask = nil }
      struct Body: Encodable, Sendable { var refreshToken: String }
      let updated: Session = try await api.request(
        "/auth/refresh", method: "POST", body: Body(refreshToken: session.refreshToken))
      guard !Task.isCancelled, sessionVersion == version, self.session?.user.id == updated.user.id
      else { throw CancellationError() }
      try saveSession(updated)
      return updated.accessToken
    }
    refreshTask = task
    return try await task.value
  }
  static func expiry(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
  }
  public func syncAll() async {
    guard configured, session != nil, !isSyncing else { return }
    isSyncing = true
    defer { isSyncing = false }
    do {
      let token = try await accessToken()
      guard let account = session?.user.id else { return }
      var failures: [String] = []
      for id in Array(store.envelopes.keys) {
        guard let e = store.envelopes[id], e.accountID == nil || e.accountID == account else {
          continue
        }
        do { try await syncTrip(id, token: token, account: account) } catch let error
          as ServiceError where e.confirmed.syncEpoch != "local" && Self.revoked(error)
        {
          // The owner deleted the trip or took this traveller off it, so it leaves this device too.
          do { try store.removeTrip(id) } catch { failures.append(error.localizedDescription) }
        } catch {
          failures.append(error.localizedDescription)
        }
      }
      struct Listing: Decodable, Sendable {
        var trips: [TripSnapshot]
        var nextCursor: String?
      }
      var cursor: String?
      repeat {
        // Cursor is opaque and percent encoded as a query component.
        let suffix =
          cursor.map {
            "?cursor="
              + ($0.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed.subtracting(
                  CharacterSet(charactersIn: "+&=?#"))) ?? "")
          } ?? ""
        let listing: Listing = try await api.request("/trips" + suffix, token: token)
        guard session?.user.id == account, !endingSession else { return }
        for trip in listing.trips where store.envelopes[trip.id] == nil {
          try store.persist(
            .init(confirmed: trip, accountID: account, installationID: store.installationID))
        }
        for trip in listing.trips {
          guard var cached = store.envelopes[trip.id], cached.accountID == account else { continue }
          if trip.syncEpoch != cached.confirmed.syncEpoch {
            cached.restoreReview = true
            cached.restoreFetchedRevision = trip.revision
          }
          if trip.revision > cached.confirmed.revision
            || trip.syncEpoch != cached.confirmed.syncEpoch
          {
            cached.confirmed = trip
            try store.persist(cached)
          }
        }
        cursor = listing.nextCursor
      } while cursor != nil
      lastSynced = Date()
      message = failures.isEmpty ? nil : failures.joined(separator: "\n")
    } catch { message = error.localizedDescription }
  }
  func syncTrip(_ id: String, token: String, account: String) async throws {
    guard session?.user.id == account, !endingSession, var envelope = store.envelopes[id] else {
      return
    }
    if envelope.restoreReview {
      if envelope.confirmed.syncEpoch != "local" {
        let snapshot: TripSnapshot = try await api.request("/trips/" + id, token: token)
        guard session?.user.id == account, !endingSession, var current = store.envelopes[id] else {
          return
        }
        current.confirmed = snapshot
        current.restoreFetchedRevision = snapshot.revision
        try store.persist(current)
      }
      return
    }
    if envelope.confirmed.syncEpoch == "local" {
      if envelope.createSnapshot == nil {
        if let index = envelope.confirmed.travellers.firstIndex(where: {
          $0.id == envelope.confirmed.ownerTravellerId && $0.name == "You"
        }),
          let displayName = session?.user.displayName.trimmingCharacters(
            in: .whitespacesAndNewlines), !displayName.isEmpty
        {
          envelope.confirmed.travellers[index].name = displayName
        }
        for expense in envelope.confirmed.expenses
        where !envelope.pending.contains(where: { $0.operation.entityId == expense.id }) {
          envelope.pending.append(
            .init(
              operation: .init(
                syncEpoch: "local", type: "expense.upsert", entityId: expense.id,
                expectedRevision: nil, payload: .expense(expense))))
        }
        for repayment in envelope.confirmed.repayments
        where !envelope.pending.contains(where: { $0.operation.entityId == repayment.id }) {
          envelope.pending.append(
            .init(
              operation: .init(
                syncEpoch: "local", type: "repayment.upsert", entityId: repayment.id,
                expectedRevision: nil, payload: .repayment(repayment))))
        }
        var initial = envelope.confirmed
        initial.expenses = []
        initial.repayments = []
        envelope.createSnapshot = initial
        envelope.accountID = account
        try store.persist(envelope)
      }
      struct Create: Encodable, Sendable {
        var operationId: String
        var trip: TripSnapshot
      }
      let snapshot: TripSnapshot = try await api.request(
        "/trips", method: "POST",
        body: Create(operationId: envelope.createOperationID, trip: envelope.createSnapshot!),
        token: token)
      guard session?.user.id == account, !endingSession, var current = store.envelopes[id] else {
        return
      }
      current.confirmed = snapshot
      current.accountID = account
      current.createSnapshot = nil
      for index in current.pending.indices where !current.pending[index].attempted {
        current.pending[index].operation.syncEpoch = snapshot.syncEpoch
        if current.pending[index].operation.type.hasPrefix("trip.") {
          current.pending[index].operation.expectedRevision = snapshot.revision
        }
      }
      try store.persist(current)
      envelope = current
    }
    repeat {
      var operations: [TripSplitDomain.Operation] = []
      for index in envelope.pending.indices
      where envelope.pending[index].problem == nil && operations.count < 50 {
        envelope.pending[index].attempted = true
        operations.append(envelope.pending[index].operation)
      }
      try store.persist(envelope)
      let response: SyncResponse
      do {
        response = try await api.request(
          "/trips/\(id)/sync", method: "POST",
          body: SyncRequest(
            cursor: envelope.confirmed.revision, syncEpoch: envelope.confirmed.syncEpoch,
            operations: operations), token: token)
      } catch let error as ServiceError where error.status == 409 {
        guard session?.user.id == account, !endingSession, var current = store.envelopes[id] else {
          return
        }
        current.restoreReview = true
        try store.persist(current)
        throw error
      }
      guard session?.user.id == account, !endingSession, var current = store.envelopes[id] else {
        return
      }
      if response.syncEpoch != current.confirmed.syncEpoch { current.restoreReview = true }
      if let snapshot = response.snapshot { current.confirmed = snapshot }
      for result in response.results {
        if result.status == "accepted" || result.status == "duplicate" {
          current.pending.removeAll { $0.id == result.id }
        } else if let index = current.pending.firstIndex(where: { $0.id == result.id }) {
          current.pending[index].problem =
            result.message
            ?? "This change conflicts with the latest trip. Review it before continuing."
        }
      }
      try store.persist(current)
      if current.restoreReview || operations.isEmpty { break }
      let responded = Set(response.results.map(\.id))
      guard operations.allSatisfy({ responded.contains($0.id) }) else {
        throw ServiceError(
          code: "sync_response",
          message: "The server didn’t acknowledge every change. They remain saved for retry.")
      }
      envelope = current
    } while envelope.pending.contains(where: { $0.problem == nil })
  }
  static func revoked(_ error: ServiceError) -> Bool {
    error.code == "TRIP_NOT_FOUND" || error.code == "MEMBERSHIP"
  }
  /// Deletes a trip for every traveller on it, then forgets it here. A trip the server has
  /// never seen only leaves this device.
  public func deleteTrip(_ id: String) async throws {
    guard let envelope = store.envelopes[id] else { return }
    let local = envelope.confirmed.syncEpoch == "local"
    if !local || envelope.createSnapshot != nil {
      let token = try await accessToken()
      struct Done: Decodable, Sendable { var ok: Bool }
      do {
        let _: Done = try await api.request("/trips/\(id)", method: "DELETE", token: token)
      } catch let error as ServiceError
        where error.code == "TRIP_NOT_FOUND" || local && error.code == "MEMBERSHIP"
      {
        // Already gone, or a create that never reached the server.
      }
    }
    try store.removeTrip(id)
  }
  public func approveRestore(_ id: String) throws {
    guard var e = store.envelopes[id] else { return }
    guard e.confirmed.syncEpoch == "local" || e.restoreFetchedRevision != nil else {
      throw ServiceError(
        code: "restore_review",
        message: "Fetch the latest server version before approving restored changes.")
    }
    // Unknown-epoch commands need explicit conflict resolution, never automatic rebase.
    for i in e.pending.indices where e.pending[i].operation.syncEpoch != e.confirmed.syncEpoch {
      e.pending[i].problem =
        "The server’s recovery version changed. Keep the server version or apply this draft again after reviewing it."
    }
    e.restoreReview = false
    e.installationID = store.installationID
    try store.persist(e)
  }
  public func resolveByReapplying(_ operationID: String, tripID: String) throws {
    guard var e = store.envelopes[tripID],
      let old = e.pending.first(where: { $0.id == operationID })
    else { return }
    var operation = old.operation
    operation.id = UUID().uuidString
    operation.syncEpoch = e.confirmed.syncEpoch
    switch operation.payload {
    case .expense:
      operation.expectedRevision =
        e.confirmed.expenses.first(where: { $0.id == operation.entityId })?.revision
    case .repayment:
      operation.expectedRevision =
        e.confirmed.repayments.first(where: { $0.id == operation.entityId })?.revision
    case .traveller:
      operation.expectedRevision =
        e.confirmed.travellers.first(where: { $0.id == operation.entityId })?.revision
    default: operation.expectedRevision = e.confirmed.revision
    }
    e.pending.removeAll { $0.id == operationID }
    e.pending.append(.init(operation: operation))
    try store.persist(e)
  }
  public func signOut() async throws {
    guard session != nil else { return }
    let token: String
    do { token = try await accessToken() } catch {
      endLocalSession()
      message =
        "Signed out on this device. The service couldn’t confirm revocation of the previous session."
      return
    }
    guard let session else { return }
    endingSession = true
    sessionVersion &+= 1
    defer { endingSession = false }
    struct Body: Encodable, Sendable { var refreshToken: String }
    struct OK: Decodable, Sendable { var ok: Bool }
    do {
      let _: OK = try await api.request(
        "/auth/logout", method: "POST", body: Body(refreshToken: session.refreshToken), token: token
      )
      message = nil
    } catch {
      message =
        "Signed out on this device. The service couldn’t confirm revocation of the previous session."
    }
    endLocalSession()
  }
  private func endLocalSession() {
    stopLive()
    refreshTask?.cancel()
    refreshTask = nil
    SessionVault.delete("session")
    session = nil
  }
  public func deleteAccount() async throws {
    let token = try await accessToken()
    guard let accountID = session?.user.id else { return }
    endingSession = true
    sessionVersion &+= 1
    defer { endingSession = false }
    struct Result: Decodable, Sendable { var status: String }
    let response: Result = try await api.request(
      "/me", method: "DELETE", body: EmptyBody(), token: token)
    guard ["pending", "deleted"].contains(response.status) else {
      throw URLError(.badServerResponse)
    }
    stopLive()
    SessionVault.delete("session")
    session = nil
    deletionRequested = response.status == "pending"
    try store.clearAccount(accountID)
  }
  public func createInvite(tripID: String, travellerID: String) async throws -> Invite {
    let token = try await accessToken()
    let accountID = session?.user.id
    struct Body: Encodable, Sendable { var travellerId: String }
    let invite: Invite = try await api.request(
      "/trips/\(tripID)/invites", method: "POST", body: Body(travellerId: travellerID), token: token
    )
    guard accountID == session?.user.id, !endingSession else { throw CancellationError() }
    return invite
  }
  public func acceptInvite(tripID: String, inviteID: String, token secret: String) async throws
    -> TripSnapshot
  {
    let access = try await accessToken()
    let accountID = session?.user.id
    struct Body: Encodable, Sendable { var token: String }
    let trip: TripSnapshot = try await api.request(
      "/trips/\(tripID)/invites/\(inviteID)/accept", method: "POST", body: Body(token: secret),
      token: access)
    guard accountID == session?.user.id, !endingSession else { throw CancellationError() }
    try store.persist(
      .init(confirmed: trip, accountID: accountID, installationID: store.installationID))
    return trip
  }
}
