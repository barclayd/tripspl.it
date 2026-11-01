import SwiftUI
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain
import TripSplitSharedUI

/// Step 2: the day you set off, then the day you're home, on one calendar that starts with neither
/// picked. "Today" is the phone's date, as you plan from where you are rather than where you're
/// going.
struct DepartureStep: View {
  @Environment(AppModel.self) private var model
  @State private var timeZoneSelection: DestinationTimeZoneSelection?
  @Environment(\.onboardingWide) private var wide

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
        start: draft.pickedStart, end: draft.pickedEnd, today: today, wide: wide,
        isSelectable: { draft.canPick($0, today: today) },
        hint: draft.isPickingHome ? "Sets the day you're home" : "Sets the day you set off"
      ) { date in
        Haptics.selection()
        withAnimation(Motion.spring) { model.onboarding.pick(date) }
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
    // A draft saved on an earlier day can't still leave in the past, so its dates are picked again.
    .onAppear { if draft.startsOn < today { model.onboarding.clearDates(today: today) } }
    .sheet(item: $timeZoneSelection) { selection in
      if let stop = draft.stops.first(where: { $0.id == selection.id }) {
        TimeZonePicker(
          selection: timeZoneBinding(for: stop.id),
          allowedIdentifiers: DestinationTimeZones.identifiers(countryCode: stop.countryCode),
          title: stop.place, referenceDate: CivilDate.date(draft.startsOn))
      }
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
