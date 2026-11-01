import SwiftUI
import TripSplitApplication
import TripSplitDesignSystem
import TripSplitDomain

extension View {
  /// A trip's own actions, a swipe away on iOS 27 and a long press away before it, or always a
  /// long press when it isn't a row. Only the owner can change or delete a trip, so a member's
  /// don't offer them, and only a trip that hasn't started can move. A row drawn in a forced
  /// scheme, like the dark departures board, passes the page's so its sheet matches the page.
  func tripActions(
    _ trip: TripSnapshot, swipes: Bool = true, colorScheme: ColorScheme? = nil
  ) -> some View {
    modifier(TripActions(trip: trip, swipes: swipes, colorScheme: colorScheme))
  }

  /// Gathers the swipe actions of the rows inside, so only one row is open at a time.
  @ViewBuilder func tripActionsContainer() -> some View {
    if #available(iOS 27.0, *) { swipeActionsContainer() } else { self }
  }

  /// Asks before deleting a trip, since it goes for everyone on it and can't be undone.
  public func confirmsDeleting(_ trip: Binding<TripSnapshot?>) -> some View {
    modifier(DeleteTripDialog(trip: trip))
  }
}

private struct TripActions: ViewModifier {
  let trip: TripSnapshot
  let swipes: Bool
  let colorScheme: ColorScheme?
  /// Set while the dialog asks, which then points at this row.
  @State private var deleting: TripSnapshot?
  @State private var changing: TripSnapshot?

  /// A trip that's under way or over keeps its dates: its days have happened.
  private var canChangeDates: Bool {
    trip.startsOn >= CivilDate.today(timeZone: TimeZone.current.identifier)
  }

  func body(content: Content) -> some View {
    Group {
      if trip.role != "owner" {
        content
      } else if swipes, #available(iOS 27.0, *) {
        // The first is outermost, and what a full swipe picks.
        content.swipeActions(edge: .trailing, allowsFullSwipe: true) {
          delete
          if canChangeDates { changeDates }
        }
      } else {
        content.contextMenu {
          if canChangeDates { changeDates }
          delete
        }
      }
    }
    .confirmsDeleting($deleting)
    .sheet(item: $changing) { trip in
      ChangeDatesView(trip: trip)
        .transformEnvironment(\.colorScheme) { if let colorScheme { $0 = colorScheme } }
    }
  }

  // Not `.destructive`, which would animate the row away before the dialog asks.
  private var delete: some View {
    Button("Delete", systemImage: "trash") { deleting = trip }
      .tint(.red).accessibilityLabel("Delete")
  }

  private var changeDates: some View {
    Button("Change dates", systemImage: "calendar") { changing = trip }
      .tint(.indigo).accessibilityLabel("Change dates")
  }
}

private struct DeleteTripDialog: ViewModifier {
  @Binding var trip: TripSnapshot?
  @Environment(AppModel.self) private var model

  func body(content: Content) -> some View {
    content.confirmationDialog(
      "Delete \(trip?.name ?? "this trip")?",
      isPresented: Binding(get: { trip != nil }, set: { if !$0 { trip = nil } }),
      titleVisibility: .visible, presenting: trip
    ) { trip in
      Button("Delete trip", role: .destructive) { Task { await model.deleteTrip(trip) } }
    } message: { trip in
      Text(
        trip.travellers.count > 1
          ? "Its days and expenses go for all \(trip.travellers.count) travellers. This can’t be undone."
          : "Its days and expenses go too. This can’t be undone.")
    }
  }
}
