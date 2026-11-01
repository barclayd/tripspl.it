import SwiftUI
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain
import TripSplitSharedUI

/// New dates for a trip that hasn't started, picked on the same calendar as planning it: the
/// first tap moves the whole trip, the next sets the day home. The stops stay, sharing the nights
/// as before, and expenses on days that leave move to the last day left in their place.
struct ChangeDatesView: View {
  init(trip: TripSnapshot) {
    tripID = trip.id
    _start = State(initialValue: trip.startsOn)
    _end = State(initialValue: trip.endsOn)
  }

  let tripID: String
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var start: String
  @State private var end: String
  @State private var picking = End.leaving

  enum End { case leaving, home }

  private var today: String { CivilDate.today(timeZone: TimeZone.current.identifier) }

  var body: some View {
    NavigationStack {
      if let trip = model.store.trip(tripID) {
        let reschedule = trip.rescheduled(leaving: start, home: end)
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            ends(trip)
            DepartureCalendar(
              start: start, end: end, today: today, identifier: "dates.calendar",
              isSelectable: { isSelectable($0, in: trip) },
              hint: picking == .leaving ? "Moves the whole trip to leave this day" : "Sets the day you're home"
            ) { date in
              Haptics.selection()
              withAnimation(Motion.spring) { select(date, in: trip) }
            }
            stays(trip, reschedule)
            moved(trip, reschedule)
          }
          .pagePadding().padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.background)
        .navigationTitle("Change dates").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", systemImage: "xmark") { dismiss() }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save", systemImage: "checkmark") { save(reschedule, to: trip) }
              .disabled(start == trip.startsOn && end == trip.endsOn)
              .accessibilityIdentifier("dates.save")
          }
        }
      }
    }
  }

  // MARK: Ends

  /// Leaving and home side by side; the one the next tap sets is ringed, and tapping either
  /// picks it instead.
  private func ends(_ trip: TripSnapshot) -> some View {
    let nights = CivilDate.days(from: start, to: end)
    return VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        endButton(.leaving, title: "Leaving", date: start)
        endButton(.home, title: "Home", date: end)
      }
      Text(
        "\(Text(trip.name).foregroundStyle(Theme.ink).fontWeight(.heavy)) · \(nights == 0 ? "A day trip" : nights == 1 ? "1 night" : "\(nights) nights")"
      )
      .foregroundStyle(Theme.secondary)
    }
    .typeface(14, .bold, relativeTo: .subheadline, maximum: 1.5)
  }

  private func endButton(_ end: End, title: String, date: String) -> some View {
    let selected = picking == end
    return Button {
      Haptics.selection()
      withAnimation(Motion.spring) { picking = end }
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        Text(title.uppercased()).typeface(11, .heavy, tracking: 0.06, relativeTo: .caption2, maximum: 1.3)
          .foregroundStyle(selected ? Theme.accentText : Theme.tertiary)
        Text(CivilDate.display(date, format: "EEE d MMM"))
          .typeface(17, .heavy, tracking: -0.02, relativeTo: .headline, maximum: 1.4)
          .foregroundStyle(Theme.ink).contentTransition(.numericText())
      }
      .padding(.horizontal, 14).padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .strokeBorder(selected ? Theme.accent : .clear, lineWidth: 2)
      }
    }
    .buttonStyle(PressStyle())
    .accessibilityLabel("\(title), \(CivilDate.display(date, format: "EEEE d MMMM yyyy"))")
    .accessibilityHint(end == .leaving ? "Pick the day you set off" : "Pick the day you're home")
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier(end == .leaving ? "dates.leaving" : "dates.home")
  }

  // MARK: Stays

  /// Each place and its share of the new nights, on a route with more than one.
  @ViewBuilder private func stays(_ trip: TripSnapshot, _ reschedule: TripReschedule) -> some View {
    if trip.stops.count > 1 {
      VStack(alignment: .leading, spacing: 10) {
        Kicker(title: "Nights in each place")
        VStack(spacing: 0) {
          ForEach(Array(zip(trip.stops, reschedule.stops)), id: \.0.id) { stop, stay in
            HStack(spacing: 10) {
              Text(stop.flag).font(.system(size: 20)).accessibilityHidden(true)
              Text(stop.place).typeface(15, .bold, relativeTo: .body, maximum: 1.5)
                .foregroundStyle(Theme.ink)
              Spacer(minLength: 8)
              Text(stay.nights == 1 ? "1 night" : "\(stay.nights) nights")
                .typeface(15, .heavy, relativeTo: .body, maximum: 1.5).monospacedDigit()
                .foregroundStyle(stay.nights == stop.nights ? Theme.secondary : Theme.accentText)
                .contentTransition(.numericText())
            }
            .padding(.horizontal, 14).frame(minHeight: 48)
            .accessibilityElement(children: .combine)
            if stop.id != trip.stops.last?.id {
              Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 44)
            }
          }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        Text("Nights are shared between places as they are now. Fine-tune them once the dates are set.")
          .typeface(12.5, relativeTo: .caption, maximum: 1.5).foregroundStyle(Theme.secondary)
      }
    }
  }

  /// What happens to expenses on days the trip no longer has.
  @ViewBuilder private func moved(_ trip: TripSnapshot, _ reschedule: TripReschedule) -> some View {
    let leaving = Set(reschedule.moves.map(\.fromDayId))
    let count = trip.expenses.filter { $0.attachment.kind == .day && leaving.contains($0.attachment.id) }
      .count
    if count > 0 {
      Label {
        Text(
          count == 1
            ? "1 expense is on a day the trip no longer has. It moves to the last day left in its place."
            : "\(count) expenses are on days the trip no longer has. They move to the last day left in each place."
        )
      } icon: {
        Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(Theme.accentText)
      }
      .typeface(13, .semibold, relativeTo: .footnote, maximum: 1.5).foregroundStyle(Theme.ink)
      .padding(14).frame(maxWidth: .infinity, alignment: .leading)
      .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      .transition(.opacity.combined(with: .move(edge: .top)))
    }
  }

  // MARK: Picking

  /// Any day from today. Picking home, it's also within a year of leaving, and leaves a night for
  /// each stop on a longer route; a day before leaving moves the start instead.
  private func isSelectable(_ date: String, in trip: TripSnapshot) -> Bool {
    guard date >= today else { return false }
    guard picking == .home, date >= start else { return true }
    return Itinerary.tripNights(stops: trip.stops.count).contains(CivilDate.days(from: start, to: date))
  }

  /// The first tap moves the whole trip to leave that day, the next sets the day home, then it
  /// starts over. A day before leaving moves the start instead.
  private func select(_ date: String, in trip: TripSnapshot) {
    let range = Itinerary.tripNights(stops: trip.stops.count)
    switch picking {
    case .leaving:
      end = CivilDate.adding(CivilDate.days(from: start, to: end), to: date)
      start = date
      picking = .home
    case .home where date < start:
      start = date
      end = CivilDate.adding(min(CivilDate.days(from: date, to: end), range.upperBound), to: date)
    case .home:
      end = date
      picking = .leaving
    }
  }

  private func save(_ reschedule: TripReschedule, to trip: TripSnapshot) {
    model.perform {
      try model.store.enqueue(
        .init(
          syncEpoch: trip.syncEpoch, type: "trip.reschedule", entityId: trip.id,
          expectedRevision: model.store.envelopes[trip.id]?.confirmed.revision ?? trip.revision,
          payload: .reschedule(reschedule)), tripID: trip.id)
      Haptics.success()
      model.changed()
      dismiss()
    }
  }
}
