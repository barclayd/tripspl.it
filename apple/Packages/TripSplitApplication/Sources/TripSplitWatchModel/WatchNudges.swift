import Foundation
import TripSplitDomain

/// The nudges sent from this watch, so each person gets at most one a trip day, as the server
/// allows. Kept in the App Group as `nudgesSentToday`.
public struct NudgeMemory: Codable, Hashable, Sendable {
  public init(sent: Set<String> = []) { self.sent = sent }
  /// Nudge command ids, which end with the trip day, e.g. "nudge:trip:tom:2026-11-01".
  public var sent: Set<String>

  /// Forgets nudges from before yesterday: no trip's today is further behind UTC than that.
  mutating func prune(before day: String) {
    sent = sent.filter { String($0.suffix(10)) >= day }
  }
}

extension WatchModel {
  /// The day a nudge counts against: today in the trip's time zone, as on the server.
  func nudgeCommand(_ travellerID: String, in trip: TripSnapshot) -> CompanionCommand {
    .nudge(
      tripID: trip.id, travellerID: travellerID, on: CivilDate.string(now, timeZone: trip.timeZone))
  }

  /// Whether this person has already had today's nudge from this watch.
  public func hasNudged(_ travellerID: String, in trip: TripSnapshot) -> Bool {
    nudges.sent.contains(nudgeCommand(travellerID, in: trip).id)
  }

  /// Asks the phone to buzz someone who owes you. The phone sends it through the API, which
  /// pushes it to their iPhone; a refusal comes back as a message and frees the day again.
  public func nudge(_ travellerID: String, in trip: TripSnapshot) {
    let command = nudgeCommand(travellerID, in: trip)
    guard !nudges.sent.contains(command.id) else { return }
    nudges.prune(before: CivilDate.adding(-1, to: CivilDate.string(now)))
    nudges.sent.insert(command.id)
    send(command)
  }

  /// Frees the day for nudges the phone couldn't send, so the button comes back.
  func forgetNudges(_ ids: some Sequence<String>) {
    let refused = nudges.sent.intersection(ids)
    guard !refused.isEmpty else { return }
    nudges.sent.subtract(refused)
  }
}
