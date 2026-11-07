import Foundation
import Testing
import TripSplitApplication
import TripSplitDomain
import TripSplitNetworking
import TripSplitPersistence
import TripSplitSync

@MainActor struct ApplicationDayLocationTests {
  private let location = TripOrigin(place: "Kamakura", countryCode: "JP", latitude: 35.319, longitude: 139.55)
  private func trip() throws -> TripSnapshot {
    var draft = OnboardingDraft()
    draft.stops = [try #require(Destination.country("JP")).stop(nights: 3)]
    return try draft.makeTrip()
  }

  @Test func offlineDayEditsSurviveRestartAndCoalesceOnlyTheirOwnDay() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".store")
    let store = try LocalStore(installationID: "day-location", storeURL: url)
    let trip = try trip()
    try store.create(trip)
    let app = AppModel(store: store, sync: SyncCoordinator(store: store, api: APIClient(baseURL: nil)))
    try app.setDayLocation(location, dayID: trip.days[0].id, tripID: trip.id)
    try app.setDayLocation(location, dayID: trip.days[1].id, tripID: trip.id)
    try app.setDayLocation(nil, dayID: trip.days[0].id, tripID: trip.id)
    #expect(store.envelopes[trip.id]?.pending.count == 2)
    let reopened = try LocalStore(installationID: "day-location", storeURL: url)
    let restored = try #require(reopened.trip(trip.id))
    #expect(restored.days[0].location == nil)
    #expect(restored.days[1].location == location)
    #expect(restored.days[2].location == nil)
    #expect(restored.stops == trip.stops)
  }

  @Test func attemptedEditStaysImmutableAndReapplyUsesTheDayRevision() throws {
    let store = try LocalStore(inMemory: true, installationID: "day-location")
    let trip = try trip()
    try store.create(trip)
    let app = AppModel(store: store, sync: SyncCoordinator(store: store, api: APIClient(baseURL: nil)))
    try app.setDayLocation(location, dayID: trip.days[0].id, tripID: trip.id)
    var envelope = try #require(store.envelopes[trip.id])
    envelope.pending[0].attempted = true
    envelope.confirmed.days[0].locationRevision = 4
    try store.persist(envelope)
    let original = envelope.pending[0].operation
    #expect(throws: ServiceError.self) { try app.setDayLocation(nil, dayID: trip.days[0].id, tripID: trip.id) }
    #expect(store.envelopes[trip.id]?.pending[0].operation == original)
    try app.sync.resolveByReapplying(original.id, tripID: trip.id)
    let replacement = try #require(store.envelopes[trip.id]?.pending[0].operation)
    #expect(replacement.id != original.id)
    #expect(replacement.expectedRevision == 4)
    #expect(replacement.payload == original.payload)
  }

  @Test func membersAndMissingDaysCannotBeEdited() throws {
    let store = try LocalStore(inMemory: true, installationID: "day-location")
    var trip = try trip()
    trip.role = "member"
    try store.create(trip)
    let app = AppModel(store: store)
    #expect(throws: ServiceError.self) { try app.setDayLocation(location, dayID: trip.days[0].id, tripID: trip.id) }
    #expect(throws: ServiceError.self) { try app.setDayLocation(location, dayID: "missing", tripID: trip.id) }
    #expect(store.envelopes[trip.id]?.pending.isEmpty == true)
  }
}
