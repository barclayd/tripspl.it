#if DEBUG
  import Foundation
  import TripSplitApplication
  import TripSplitDomain
  import TripSplitNetworking
  import TripSplitPersistence
  import TripSplitSync

  /// An isolated, offline reproduction: no saved account, real trips, push or network access.
  @MainActor enum SyncRecoveryPreview {
    static func model() throws -> AppModel {
      let store = try LocalStore(inMemory: true, installationID: "sync-preview")
      var draft = OnboardingDraft()
      draft.name = "Lisbon weekend"
      draft.stops = [Destination.country("PT")!.stop(nights: 3)]
      var trip = try draft.makeTrip()
      trip.syncEpoch = "preview"
      trip.revision = 1
      try store.persist(
        .init(confirmed: trip, accountID: "preview", installationID: "sync-preview"))
      for title in ["Lunch by the river", "Tram tickets", "Coffee"] {
        try store.saveExpense(
          Expense(
            attachment: .init(kind: .day, id: trip.days[0].id), title: title, category: .food,
            amountMinor: "500", currency: trip.homeCurrency, status: .paid,
            paidBy: trip.ownerTravellerId, splitWith: [trip.ownerTravellerId]), tripID: trip.id)
      }
      let configuration = URLSessionConfiguration.ephemeral
      configuration.protocolClasses = [RejectedSessionProtocol.self]
      let sync = SyncCoordinator(
        store: store,
        api: APIClient(
          baseURL: URL(string: "https://example.invalid")!,
          transport: URLSession(configuration: configuration)), sessionWriter: { _ in },
        sessionReader: {
          Session(
            user: Account(id: "preview", displayName: "Alex"), accessToken: "preview",
            refreshToken: "preview", expiresAt: "2000-01-01T00:00:00Z")
        }, sessionDeleter: {})
      let model = AppModel(store: store, sync: sync)
      model.cacheReferenceRates(DemoData.referenceRates())
      model.showSettings = true
      return model
    }
  }

  private final class RejectedSessionProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
      let challenge = request.url?.path.hasSuffix("/auth/apple/challenge") == true
      let body =
        challenge
        ? #"{"id":"preview","nonce":"preview","expiresAt":"2099-01-01T00:00:00Z"}"#
        : #"{"error":{"code":"UNAUTHENTICATED","message":"Refresh token has expired or has already been used."}}"#
      client?.urlProtocol(
        self,
        didReceive: HTTPURLResponse(
          url: request.url!,
          statusCode: challenge ? 200 : 401, httpVersion: nil,
          headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: Data(body.utf8))
      client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
  }
#endif
