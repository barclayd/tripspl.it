import Foundation
import Testing
import TripSplitCompanion
import TripSplitDomain

struct CompanionMirrorTests {
  @Test func stateSurvivesARelaunch() throws {
    let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let mirror = CompanionMirror(directory: directory)
    #expect(mirror.load() == CompanionState())
    var draft = OnboardingDraft()
    draft.stops = [try #require(Destination.search("Rome").first).stop(nights: 1)]
    let trip = try draft.makeTrip()
    let state = CompanionState(
      context: .init(trips: [trip], sentAt: Date(timeIntervalSince1970: 1_800_000_000)))
    try mirror.save(state)
    #expect(CompanionMirror(directory: directory).load() == state)
  }
}
