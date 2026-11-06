import Foundation
import TripSplitApplication
import TripSplitDomain
import TripSplitWatchModel

extension AppModel {
  /// Opens where a Home Screen or Lock Screen widget, or a Control Centre control, points.
  func open(_ link: WatchLink) async {
    // A sheet already up would stop the next one showing, so it closes first. A half-typed
    // expense is kept, as it is when the app goes to the background.
    let covered =
      showSettings || showTripSettings || showConverter || showOnboarding || expenseDraft != nil
    if expenseDraft != nil {
      persistDraft()
      expenseDraft = nil
    }
    showSettings = false
    showTripSettings = false
    showConverter = false
    if link != .newTrip { showOnboarding = false }
    if covered { try? await Task.sleep(for: .milliseconds(450)) }

    switch link {
    case .trips:
      showTrips()
    case .trip(let id, let page):
      guard let trip = store.trip(id) else { return showTrips() }
      open(trip)
      // Today opens the day under way; the trip's own page already leads with budget,
      // balances and days.
      if page == .today, trip.phase == .now { openDay(trip.currentAttachment) }
    case .day(let id, let day):
      guard let trip = store.trip(id) else { return showTrips() }
      open(trip)
      openDay(.init(kind: .day, id: day))
    case .convert:
      if selectedTrip == nil, !store.trips.contains(where: \.showsHomeConverter) {
        guard let trip = widgetTrip else { return showTrips() }
        open(trip)
      }
      showConverter = true
    case .localConvert(let id):
      guard let trip = store.trip(id) else { return showTrips() }
      open(trip)
      showConverter = true
    case .log(let id):
      guard let trip = id.flatMap(store.trip) ?? widgetTrip else {
        showOnboarding = true
        return
      }
      selectedTab = 0
      editExpense(trip: trip, attachment: trip.currentAttachment)
    case .newTrip:
      showOnboarding = true
    }
  }

  private func showTrips() {
    selectedTab = 0
    selectedTripID = nil
  }

  /// The trip under way, else the next to leave: what Automatic widgets follow.
  private var widgetTrip: TripSnapshot? {
    let trips = store.trips.filter { !$0.archived }
    return trips.first { $0.phase == .now }
      ?? trips.filter { $0.phase == .upcoming }.min { $0.startsOn < $1.startsOn }
  }
}
