import SwiftUI
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain
import TripSplitSharedUI

/// Step 2: the day you set off, then the day you're home, on one calendar. "Today" is the phone's
/// date, as you plan from where you are rather than where you're going.
struct DepartureStep: View {
  @Environment(AppModel.self) private var model
  @State private var timeZoneSelection: DestinationTimeZoneSelection?
  @State private var picking = End.leaving
  @Environment(\.onboardingWide) private var wide

  enum End { case leaving, home }

  private var draft: OnboardingDraft { model.onboarding }
  private var today: String { CivilDate.today(timeZone: TimeZone.current.identifier) }

  /// Stops in countries with several zones, or whose zone couldn't be worked out.
  private var ambiguousStops: [Stop] {
    draft.stops.filter {
      $0.resolvedTimeZone == nil
        || DestinationTimeZones.identifiers(countryCode: $0.countryCode).count > 1
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      StepTitle("How long is your trip?", "Pick the day you set off and return")
      DepartureCalendar(
        start: draft.startsOn, end: draft.returnDate, today: today, wide: wide,
        isSelectable: isSelectable, hint: picking == .leaving ? "Sets the day you set off" : "Sets the day you're home"
      ) { date in
        Haptics.selection()
        withAnimation(Motion.spring) { select(date) }
      }
      if !ambiguousStops.isEmpty {
        VStack(alignment: .leading, spacing: 10) {
          Kicker(title: "Time zones")
          ForEach(ambiguousStops) { stop in
            Button {
              timeZoneSelection = .init(id: stop.id)
            } label: {
              DestinationTimeZoneRow(
                place: stop.place, identifier: stop.resolvedTimeZone,
                date: CivilDate.date(draft.startsOn)
              )
              .padding(14)
              .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(PressStyle()).accessibilityIdentifier("onboarding.timezone.\(stop.id)")
          }
        }
      }
    }
    // A draft saved on an earlier day can't still leave in the past.
    .onAppear { if draft.startsOn < today { model.onboarding.setDeparture(today) } }
    .sheet(item: $timeZoneSelection) { selection in
      if let stop = draft.stops.first(where: { $0.id == selection.id }) {
        TimeZonePicker(
          selection: timeZoneBinding(for: stop.id),
          allowedIdentifiers: DestinationTimeZones.identifiers(countryCode: stop.countryCode),
          title: stop.place, referenceDate: CivilDate.date(draft.startsOn))
      }
    }
  }

  /// Any day from today. Picking home, it's also within a year of leaving, and leaves a night for
  /// each stop on a longer route; a day before leaving moves the start instead.
  private func isSelectable(_ date: String) -> Bool {
    guard date >= today else { return false }
    guard picking == .home, date >= draft.startsOn else { return true }
    let nights = CivilDate.days(from: draft.startsOn, to: date)
    return draft.tripNights.contains(nights)
  }

  /// The first tap moves the whole trip to leave that day, the next sets the day home, then it
  /// starts over. A day before leaving moves the start instead.
  private func select(_ date: String) {
    switch picking {
    case .leaving:
      model.onboarding.setDeparture(date)
      picking = .home
    case .home where date < draft.startsOn:
      model.onboarding.setDates(leaving: date, home: draft.returnDate)
    case .home:
      model.onboarding.setReturn(date)
      picking = .leaving
    }
  }

  private func timeZoneBinding(for stopID: String) -> Binding<String> {
    Binding(
      get: { model.onboarding.stops.first(where: { $0.id == stopID })?.resolvedTimeZone ?? "" },
      set: { zone in
        guard let index = model.onboarding.stops.firstIndex(where: { $0.id == stopID }) else {
          return
        }
        model.onboarding.stops[index].timeZone = zone
      })
  }
}
