import Foundation
import TripSplitDomain
import TripSplitPersistence

extension AppModel {
  public func setDayLocation(_ location: TripOrigin?, dayID: String, tripID: String) throws {
    guard let trip = store.trip(tripID), let day = trip.days.first(where: { $0.id == dayID }) else {
      throw ServiceError(code: "day_missing", message: "This day is no longer in the trip.")
    }
    guard trip.role == "owner" else {
      throw ServiceError(code: "owner_required", message: "Only the trip organiser can change its locations.")
    }
    if let location {
      guard !location.place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        location.place.count <= 120, CountryMetadata.country(location.countryCode) != nil,
        (-90...90).contains(location.latitude), (-180...180).contains(location.longitude)
      else { throw ServiceError(code: "location", message: "Choose a valid city or place.") }
    }
    guard location != day.location else { return }
    try store.enqueue(
      .init(syncEpoch: trip.syncEpoch, type: "day.location", entityId: dayID,
            expectedRevision: day.locationRevision ?? 0, payload: .dayLocation(.init(location: location))),
      tripID: tripID)
    changed()
  }
}
